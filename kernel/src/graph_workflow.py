"""Graph workflow engine for kernel v2."""

from __future__ import annotations

import logging
from datetime import datetime

from .graph_entities import (
    WorkflowEntity,
    RevisionEntity,
    NodeEntity,
    CandidateEntity,
    DecisionEntity,
    AssemblyEntity,
    AssemblyItemRef,
    utcnow,
    snapshot_to_working_copy,
    WorkflowSnapshot,
)
from .state_machine import StateMachine
from .ports import EventBusPort
from .workflow_actions import (
    WorkflowAction,
    CreateRevisionAction,
    SpawnNodeAction,
    TransitionWorkflowAction,
    TransitionRevisionAction,
    TransitionNodeAction,
    TransitionCandidateAction,
    DispatchNodeAction,
    CreateCandidateAction,
    SelectCandidateAction,
    UpsertAssemblyFromSelectionAction,
    CompleteAssemblyAction,
    RejectAssemblyAction,
    RollbackWorkflowAction,
    BuildAssemblyAction,
    RecordDecisionAction,
    RefreshProjectionAction,
)
from .workflow_events import (
    WorkflowEvent,
    TOPIC_WORKFLOW_CREATED,
    TOPIC_WORKFLOW_STATE_CHANGED,
    TOPIC_WORKFLOW_REVISION_CREATED,
    TOPIC_WORKFLOW_NODE_CREATED,
    TOPIC_WORKFLOW_NODE_STATE_CHANGED,
    TOPIC_WORKFLOW_NODE_DISPATCHED,
    TOPIC_WORKFLOW_CANDIDATE_CREATED,
    TOPIC_WORKFLOW_CANDIDATE_UPDATED,
    TOPIC_WORKFLOW_CANDIDATE_SELECTED,
    TOPIC_WORKFLOW_ASSEMBLY_CREATED,
    TOPIC_WORKFLOW_DECISION,
)
from .workflow_ports import NodeExecutorPort, ProjectionPort, WorkflowPolicy, WorkflowRepoPort
from .workflow_types import CandidateState, NodeState, WorkflowState


log = logging.getLogger("kernel.graph_workflow")

WORKFLOW_TRANSITIONS: dict[str, set[str]] = {
    WorkflowState.DRAFT.value: {WorkflowState.PLANNING.value, WorkflowState.CANCELLED.value},
    WorkflowState.PLANNING.value: {
        WorkflowState.AWAITING_PLAN_REVIEW.value,
        WorkflowState.BLOCKED.value,
        WorkflowState.CANCELLED.value,
    },
    WorkflowState.AWAITING_PLAN_REVIEW.value: {
        WorkflowState.PLANNING.value,
        WorkflowState.EXECUTING.value,
        WorkflowState.BLOCKED.value,
        WorkflowState.CANCELLED.value,
    },
    WorkflowState.EXECUTING.value: {
        WorkflowState.AWAITING_SELECTION.value,
        WorkflowState.ASSEMBLING.value,
        WorkflowState.BLOCKED.value,
        WorkflowState.CANCELLED.value,
    },
    WorkflowState.AWAITING_SELECTION.value: {
        WorkflowState.EXECUTING.value,
        WorkflowState.ASSEMBLING.value,
        WorkflowState.BLOCKED.value,
        WorkflowState.CANCELLED.value,
    },
    WorkflowState.ASSEMBLING.value: {
        WorkflowState.AWAITING_FINAL_REVIEW.value,
        WorkflowState.BLOCKED.value,
        WorkflowState.CANCELLED.value,
    },
    WorkflowState.AWAITING_FINAL_REVIEW.value: {
        WorkflowState.EXECUTING.value,
        WorkflowState.DONE.value,
        WorkflowState.BLOCKED.value,
        WorkflowState.CANCELLED.value,
    },
    WorkflowState.BLOCKED.value: {
        WorkflowState.PLANNING.value,
        WorkflowState.EXECUTING.value,
        WorkflowState.ASSEMBLING.value,
        WorkflowState.CANCELLED.value,
    },
}
WORKFLOW_TERMINAL = {WorkflowState.DONE.value, WorkflowState.CANCELLED.value}
WORKFLOW_ROLLBACK_ALLOWED = {
    WorkflowState.DRAFT.value,
    WorkflowState.PLANNING.value,
    WorkflowState.AWAITING_PLAN_REVIEW.value,
    WorkflowState.EXECUTING.value,
    WorkflowState.AWAITING_SELECTION.value,
    WorkflowState.ASSEMBLING.value,
    WorkflowState.AWAITING_FINAL_REVIEW.value,
    WorkflowState.BLOCKED.value,
}

NODE_TRANSITIONS: dict[str, set[str]] = {
    NodeState.PENDING.value: {NodeState.READY.value, NodeState.CANCELLED.value, NodeState.SUPERSEDED.value},
    NodeState.READY.value: {NodeState.RUNNING.value, NodeState.CANCELLED.value, NodeState.SUPERSEDED.value},
    NodeState.RUNNING.value: {
        NodeState.PRODUCED.value,
        NodeState.FAILED.value,
        NodeState.CANCELLED.value,
        NodeState.SUPERSEDED.value,
    },
    NodeState.PRODUCED.value: {
        NodeState.AWAITING_REVIEW.value,
        NodeState.APPROVED.value,
        NodeState.REJECTED.value,
        NodeState.SUPERSEDED.value,
    },
    NodeState.AWAITING_REVIEW.value: {
        NodeState.APPROVED.value,
        NodeState.REJECTED.value,
        NodeState.SUPERSEDED.value,
    },
    NodeState.REJECTED.value: {NodeState.READY.value, NodeState.SUPERSEDED.value, NodeState.CANCELLED.value},
    NodeState.FAILED.value: {NodeState.READY.value, NodeState.SUPERSEDED.value, NodeState.CANCELLED.value},
    NodeState.APPROVED.value: {NodeState.SUPERSEDED.value},
}
NODE_TERMINAL = {NodeState.CANCELLED.value, NodeState.SUPERSEDED.value}

CANDIDATE_TRANSITIONS: dict[str, set[str]] = {
    CandidateState.QUEUED.value: {
        CandidateState.RUNNING.value,
        CandidateState.FAILED.value,
        CandidateState.CANCELLED.value,
        CandidateState.SUPERSEDED.value,
    },
    CandidateState.RUNNING.value: {
        CandidateState.PRODUCED.value,
        CandidateState.FAILED.value,
        CandidateState.CANCELLED.value,
        CandidateState.SUPERSEDED.value,
    },
    CandidateState.PRODUCED.value: {
        CandidateState.APPROVED.value,
        CandidateState.REJECTED.value,
        CandidateState.SUPERSEDED.value,
    },
    CandidateState.REJECTED.value: {
        CandidateState.QUEUED.value,
        CandidateState.SUPERSEDED.value,
        CandidateState.CANCELLED.value,
    },
    CandidateState.FAILED.value: {
        CandidateState.QUEUED.value,
        CandidateState.SUPERSEDED.value,
        CandidateState.CANCELLED.value,
    },
    CandidateState.APPROVED.value: {CandidateState.SUPERSEDED.value},
}
CANDIDATE_TERMINAL = {
    CandidateState.APPROVED.value,
    CandidateState.SUPERSEDED.value,
    CandidateState.CANCELLED.value,
}


class GraphWorkflowEngine:
    """Minimal kernel v2 workflow engine spike."""

    def __init__(
        self,
        repo: WorkflowRepoPort,
        bus: EventBusPort,
        policy: WorkflowPolicy,
        projection: ProjectionPort | None = None,
        node_executor: NodeExecutorPort | None = None,
    ):
        self.repo = repo
        self.bus = bus
        self.policy = policy
        self.projection = projection
        self.node_executor = node_executor
        self.workflow_sm = StateMachine(
            transitions=WORKFLOW_TRANSITIONS,
            terminal_states=WORKFLOW_TERMINAL,
            initial_state="draft",
        )
        self.node_sm = StateMachine(
            transitions=NODE_TRANSITIONS,
            terminal_states=NODE_TERMINAL,
            initial_state=NodeState.PENDING.value,
        )
        self.candidate_sm = StateMachine(
            transitions=CANDIDATE_TRANSITIONS,
            terminal_states=CANDIDATE_TERMINAL,
            initial_state=CandidateState.QUEUED.value,
        )
        self._action_handlers = {
            CreateRevisionAction: self._handle_create_revision,
            SpawnNodeAction: self._handle_spawn_node,
            TransitionWorkflowAction: self._handle_transition_workflow,
            TransitionRevisionAction: self._handle_transition_revision,
            TransitionNodeAction: self._handle_transition_node,
            TransitionCandidateAction: self._handle_transition_candidate,
            DispatchNodeAction: self._handle_dispatch_node,
            CreateCandidateAction: self._handle_create_candidate,
            SelectCandidateAction: self._handle_select_candidate,
            UpsertAssemblyFromSelectionAction: self._handle_upsert_assembly_from_selection,
            CompleteAssemblyAction: self._handle_complete_assembly,
            RejectAssemblyAction: self._handle_reject_assembly,
            RollbackWorkflowAction: self._handle_rollback_workflow,
            BuildAssemblyAction: self._handle_build_assembly,
            RecordDecisionAction: self._handle_record_decision,
        }

    async def create_workflow(
        self,
        title: str,
        *,
        goal: str = "",
        workflow_type: str = "generic",
        owner: str = "",
        task_id: str | None = None,
        meta: dict | None = None,
    ) -> WorkflowEntity:
        now = utcnow()
        workflow = WorkflowEntity(
            id=self._generate_id("wf", now),
            task_id=task_id or self._generate_id("task", now),
            type=workflow_type,
            title=title,
            goal=goal,
            state=self.workflow_sm.initial_state,
            owner=owner,
            meta=meta or {},
            created_at=now,
            updated_at=now,
        )
        workflow = await self.repo.create_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_CREATED,
            trace_id=workflow.id,
            event_type="workflow.v2.created",
            producer="graph_workflow",
            payload={
                "workflow_id": workflow.id,
                "task_id": workflow.task_id,
                "workflow_version": 2,
                "title": workflow.title,
                "state": workflow.state,
                "type": workflow.type,
            },
        )
        return workflow

    async def get_snapshot(self, workflow_id: str) -> WorkflowSnapshot:
        return await self.repo.load_snapshot(workflow_id)

    async def submit_decision(
        self,
        *,
        workflow_id: str,
        target_type: str,
        target_id: str,
        action: str,
        actor: str,
        comment: str = "",
        payload: dict | None = None,
        producer: str = "graph_workflow",
    ) -> DecisionEntity:
        snapshot = await self.repo.load_snapshot(workflow_id, include_decisions=False)
        working = snapshot_to_working_copy(snapshot)
        workflow = working.workflow
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_DECISION,
            event_type="workflow.v2.command.record_decision",
            trace_id=workflow_id,
            producer=producer,
            payload={"workflow_id": workflow_id, "workflow_version": 2, **(payload or {})},
        )
        await self._handle_record_decision(
            working,
            event,
            RecordDecisionAction(
                workflow_id=workflow_id,
                target_type=target_type,
                target_id=target_id,
                action=action,
                actor=actor,
                comment=comment,
                payload=payload or {},
            ),
        )
        workflow.touch()
        await self.repo.save_workflow(workflow)
        return working.decisions[-1]

    async def add_node_progress(
        self,
        *,
        workflow_id: str,
        node_id: str,
        to_state: str,
        reason: str = "",
        executor_id: str = "",
        message: str = "",
        producer: str = "graph_workflow",
    ) -> NodeEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_NODE_STATE_CHANGED,
            event_type="workflow.v2.command.node_progress",
            trace_id=workflow_id,
            producer=producer,
            payload={"workflow_id": workflow_id, "workflow_version": 2, "node_id": node_id},
        )
        await self._handle_transition_node(
            working,
            event,
            TransitionNodeAction(node_id=node_id, to_state=to_state, reason=reason),
        )
        if to_state == NodeState.RUNNING.value:
            # Use a dispatch-stage default message; downstream worker may convert
            # generic placeholders into a produced-stage candidate summary.
            dispatch_message = message or "node dispatched"
            await self._handle_dispatch_node(
                working,
                event,
                DispatchNodeAction(
                    node_id=node_id,
                    executor_id=executor_id or "node_executor",
                    message=dispatch_message,
                ),
            )
            if self.node_executor:
                await self.node_executor.execute_node(
                    workflow_id=workflow_id,
                    node_id=node_id,
                    executor_id=executor_id or "node_executor",
                    payload={"message": dispatch_message},
                )
        node = self._get_node(working, node_id)
        return node

    async def select_candidate(
        self,
        *,
        workflow_id: str,
        node_id: str,
        candidate_id: str,
        producer: str = "graph_workflow",
    ) -> tuple[NodeEntity, CandidateEntity]:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_CANDIDATE_SELECTED,
            event_type="workflow.v2.command.select_candidate",
            trace_id=workflow_id,
            producer=producer,
            payload={
                "workflow_id": workflow_id,
                "workflow_version": 2,
                "node_id": node_id,
                "candidate_id": candidate_id,
            },
        )
        await self._handle_select_candidate(
            working,
            event,
            SelectCandidateAction(node_id=node_id, candidate_id=candidate_id),
        )
        return self._get_node(working, node_id), self._get_candidate(working, candidate_id)

    async def transition_workflow(
        self,
        *,
        workflow_id: str,
        to_state: str,
        reason: str = "",
        producer: str = "graph_workflow",
    ) -> WorkflowEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_STATE_CHANGED,
            event_type="workflow.v2.command.transition_workflow",
            trace_id=workflow_id,
            producer=producer,
            payload={
                "workflow_id": workflow_id,
                "workflow_version": 2,
                "to_state": to_state,
            },
        )
        await self._handle_transition_workflow(
            working,
            event,
            TransitionWorkflowAction(
                workflow_id=workflow_id,
                to_state=to_state,
                reason=reason,
            ),
        )
        return working.workflow

    async def complete_candidate(
        self,
        *,
        workflow_id: str,
        candidate_id: str,
        status: str = CandidateState.PRODUCED.value,
        summary: str = "",
        score: float | None = None,
        metrics: dict | None = None,
        artifacts: list | None = None,
        meta: dict | None = None,
        producer: str = "graph_workflow",
    ) -> CandidateEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        candidate = self._get_candidate(working, candidate_id)
        self.candidate_sm.validate(candidate.status, status)
        candidate.status = status
        if summary:
            candidate.summary = summary
        if score is not None:
            candidate.score = score
        if metrics:
            candidate.metrics.update(metrics)
        if artifacts is not None:
            candidate.artifacts = artifacts
        if meta:
            candidate.meta.update(meta)
        candidate.touch()
        candidate = await self.repo.save_candidate(candidate)
        working.upsert_candidate(candidate)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_CANDIDATE_UPDATED,
            trace_id=workflow_id,
            event_type="workflow.v2.candidate.updated",
            producer=producer,
            payload={
                "workflow_id": workflow_id,
                "workflow_version": 2,
                "candidate_id": candidate.id,
                "node_id": candidate.node_id,
                "status": candidate.status,
            },
        )
        return candidate

    async def create_candidate(
        self,
        *,
        workflow_id: str,
        node_id: str,
        provider: str,
        prompt_snapshot: dict | None = None,
        producer: str = "graph_workflow",
    ) -> CandidateEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        before_ids = {item.id for item in working.candidates}
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_CANDIDATE_CREATED,
            event_type="workflow.v2.command.create_candidate",
            trace_id=workflow_id,
            producer=producer,
            payload={
                "workflow_id": workflow_id,
                "workflow_version": 2,
                "node_id": node_id,
            },
        )
        await self._handle_create_candidate(
            working,
            event,
            CreateCandidateAction(
                workflow_id=workflow_id,
                node_id=node_id,
                provider=provider,
                prompt_snapshot=dict(prompt_snapshot or {}),
            ),
        )
        created = next((item for item in working.candidates if item.id not in before_ids), None)
        if created is None:
            raise ValueError("failed to create candidate")
        return created

    async def complete_assembly(
        self,
        *,
        workflow_id: str,
        assembly_id: str | None = None,
        status: str = WorkflowState.DONE.value,
        summary: str = "",
        artifacts: list | None = None,
        meta: dict | None = None,
        producer: str = "graph_workflow",
    ) -> AssemblyEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_ASSEMBLY_CREATED,
            event_type="workflow.v2.command.complete_assembly",
            trace_id=workflow_id,
            producer=producer,
            payload={"workflow_id": workflow_id, "workflow_version": 2},
        )
        await self._handle_complete_assembly(
            working,
            event,
            CompleteAssemblyAction(
                workflow_id=workflow_id,
                assembly_id=assembly_id or "",
                status=status,
                summary=summary,
                artifacts=artifacts,
                meta=meta,
            ),
        )
        resolved_assembly_id = assembly_id or working.workflow.current_assembly_id
        return self._get_assembly(working, resolved_assembly_id)

    async def upsert_assembly_for_selected_candidate(
        self,
        *,
        workflow_id: str,
        node_id: str,
        candidate_id: str,
        summary: str = "",
    ) -> AssemblyEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_ASSEMBLY_CREATED,
            event_type="workflow.v2.command.upsert_assembly_from_selection",
            trace_id=workflow_id,
            producer="graph_workflow",
            payload={"workflow_id": workflow_id, "workflow_version": 2},
        )
        await self._handle_upsert_assembly_from_selection(
            working,
            event,
            UpsertAssemblyFromSelectionAction(
                workflow_id=workflow_id,
                node_id=node_id,
                candidate_id=candidate_id,
                summary=summary,
            ),
        )
        return self._get_assembly(working, working.workflow.current_assembly_id)

    async def rollback(
        self,
        *,
        workflow_id: str,
        actor: str,
        target_revision_id: str | None = None,
        reason: str = "",
        producer: str = "graph_workflow",
    ) -> WorkflowEntity:
        snapshot = await self.repo.load_snapshot(workflow_id)
        working = snapshot_to_working_copy(snapshot)
        event = WorkflowEvent(
            topic=TOPIC_WORKFLOW_STATE_CHANGED,
            event_type="workflow.v2.command.rollback",
            trace_id=workflow_id,
            producer=producer,
            payload={"workflow_id": workflow_id, "workflow_version": 2},
        )
        await self._handle_rollback_workflow(
            working,
            event,
            RollbackWorkflowAction(
                workflow_id=workflow_id,
                actor=actor,
                target_revision_id=target_revision_id or "",
                reason=reason,
            ),
        )
        return working.workflow

    async def apply_event(self, event: WorkflowEvent) -> list[WorkflowAction]:
        workflow_id = str(event.payload.get("workflow_id") or "")
        if not workflow_id:
            raise ValueError("workflow_id is required in event payload")
        snapshot = await self.repo.load_snapshot(workflow_id)
        actions = self.policy.plan_actions(snapshot, event)
        working = snapshot_to_working_copy(snapshot)
        for action in actions:
            if isinstance(action, RefreshProjectionAction):
                continue
            await self._apply_action(working, event, action)
        # Always refresh projection after applying actions (if projection is configured)
        if actions and self.projection:
            await self.projection.refresh_task_projection(workflow_id)
        return actions

    async def _apply_action(
        self,
        working,
        event: WorkflowEvent,
        action: WorkflowAction,
    ) -> None:
        handler = self._action_handlers.get(type(action))
        if handler is None:
            raise NotImplementedError(type(action).__name__)
        await handler(working, event, action)

    async def _handle_create_revision(self, working, event: WorkflowEvent, action: CreateRevisionAction) -> None:
        number = len(working.revisions) + 1
        workflow = working.workflow
        content = self._normalize_revision_content(
            workflow_title=workflow.title,
            workflow_goal=workflow.goal,
            raw_content=action.content,
        )
        change_summary = self._derive_revision_summary(content)
        revision = RevisionEntity(
            id=self._generate_id("rev", utcnow()),
            workflow_id=action.workflow_id,
            number=number,
            status=WorkflowState.DRAFT.value,
            created_by=action.created_by,
            source=action.source,
            content=content,
            change_summary=change_summary,
            parent_revision_id=action.parent_revision_id,
        )
        revision = await self.repo.create_revision(revision)
        working.upsert_revision(revision)
        workflow.current_revision_id = revision.id
        workflow.touch()
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_REVISION_CREATED,
            trace_id=workflow.id,
            event_type="workflow.v2.revision.created",
            producer=event.producer,
            payload={
                "workflow_id": workflow.id,
                "workflow_version": 2,
                "revision_id": revision.id,
                "revision_number": revision.number,
            },
        )

    async def _handle_spawn_node(self, working, event: WorkflowEvent, action: SpawnNodeAction) -> None:
        node = NodeEntity(
            id=self._generate_id("node", utcnow()),
            workflow_id=action.workflow_id,
            revision_id=action.revision_id,
            kind=action.kind,
            state=action.state,
            title=action.title,
            description=action.description,
            parent_node_id=action.parent_node_id,
            assignee=action.assignee,
            sequence=action.sequence,
            spec=action.spec,
        )
        node = await self.repo.create_node(node)
        working.upsert_node(node)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_NODE_CREATED,
            trace_id=node.workflow_id,
            event_type="workflow.v2.node.created",
            producer=event.producer,
            payload={
                "workflow_id": node.workflow_id,
                "workflow_version": 2,
                "node_id": node.id,
                "revision_id": node.revision_id,
                "state": node.state,
                "kind": node.kind,
            },
        )

    async def _handle_transition_workflow(self, working, event: WorkflowEvent, action: TransitionWorkflowAction) -> None:
        workflow = working.workflow
        previous_state = workflow.state
        self.workflow_sm.validate(workflow.state, action.to_state)
        # 进入 blocked 时记住之前的状态，以便 resume 恢复
        if action.to_state == WorkflowState.BLOCKED.value:
            workflow.meta = dict(workflow.meta or {})
            workflow.meta["pre_block_state"] = previous_state
        workflow.state = action.to_state
        workflow.touch()
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_STATE_CHANGED,
            trace_id=workflow.id,
            event_type="workflow.v2.state.changed",
            producer=event.producer,
            payload={
                "workflow_id": workflow.id,
                "workflow_version": 2,
                "state": workflow.state,
                "reason": action.reason,
            },
        )

    async def _handle_transition_revision(self, working, event: WorkflowEvent, action: TransitionRevisionAction) -> None:
        revision_id = action.revision_id or working.workflow.current_revision_id
        if not revision_id and working.revisions:
            revision_id = max(working.revisions, key=lambda item: item.number).id
        if not revision_id:
            raise ValueError(f"No revision found to transition for workflow: {action.workflow_id}")
        revision = self._get_revision(working, revision_id)
        revision.status = action.to_status
        revision.touch()
        revision = await self.repo.save_revision(revision)
        working.upsert_revision(revision)

    async def _handle_transition_node(self, working, event: WorkflowEvent, action: TransitionNodeAction) -> None:
        node = next((n for n in working.nodes if n.id == action.node_id), None)
        if node is None:
            raise ValueError(f"Node not found in working snapshot: {action.node_id}")
        self.node_sm.validate(node.state, action.to_state)
        node.state = action.to_state
        node.touch()
        node = await self.repo.save_node(node)
        working.upsert_node(node)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_NODE_STATE_CHANGED,
            trace_id=node.workflow_id,
            event_type="workflow.v2.node.state.changed",
            producer=event.producer,
            payload={
                "workflow_id": node.workflow_id,
                "workflow_version": 2,
                "node_id": node.id,
                "state": node.state,
                "reason": action.reason,
            },
        )

    async def _handle_dispatch_node(self, working, event: WorkflowEvent, action: DispatchNodeAction) -> None:
        node = next((n for n in working.nodes if n.id == action.node_id), None)
        if node is None:
            raise ValueError(f"Node not found in working snapshot: {action.node_id}")
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_NODE_DISPATCHED,
            trace_id=node.workflow_id,
            event_type="workflow.v2.node.dispatched",
            producer=event.producer,
            payload={
                "workflow_id": node.workflow_id,
                "workflow_version": 2,
                "node_id": node.id,
                "executor_id": action.executor_id,
                "message": action.message,
            },
        )

    async def _handle_transition_candidate(
        self,
        working,
        event: WorkflowEvent,
        action: TransitionCandidateAction,
    ) -> None:
        candidate = self._get_candidate(working, action.candidate_id)
        self.candidate_sm.validate(candidate.status, action.to_state)
        candidate.status = action.to_state
        candidate.touch()
        candidate = await self.repo.save_candidate(candidate)
        working.upsert_candidate(candidate)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_CANDIDATE_UPDATED,
            trace_id=candidate.workflow_id,
            event_type="workflow.v2.candidate.updated",
            producer=event.producer,
            payload={
                "workflow_id": candidate.workflow_id,
                "workflow_version": 2,
                "candidate_id": candidate.id,
                "node_id": candidate.node_id,
                "status": candidate.status,
                "reason": action.reason,
            },
        )

    async def _handle_create_candidate(self, working, event: WorkflowEvent, action: CreateCandidateAction) -> None:
        candidate = CandidateEntity(
            id=self._generate_id("cand", utcnow()),
            workflow_id=action.workflow_id,
            node_id=action.node_id,
            status=CandidateState.QUEUED.value,
            provider=action.provider,
            prompt_snapshot=action.prompt_snapshot,
        )
        candidate = await self.repo.create_candidate(candidate)
        working.upsert_candidate(candidate)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_CANDIDATE_CREATED,
            trace_id=candidate.workflow_id,
            event_type="workflow.v2.candidate.created",
            producer=event.producer,
            payload={
                "workflow_id": candidate.workflow_id,
                "workflow_version": 2,
                "candidate_id": candidate.id,
                "node_id": candidate.node_id,
                "provider": candidate.provider,
            },
        )

    async def _handle_select_candidate(self, working, event: WorkflowEvent, action: SelectCandidateAction) -> None:
        node = next((n for n in working.nodes if n.id == action.node_id), None)
        candidate = next((c for c in working.candidates if c.id == action.candidate_id), None)
        if node is None or candidate is None:
            raise ValueError("Node or candidate not found in working snapshot")
        node.selected_candidate_id = candidate.id
        node.touch()
        self.candidate_sm.validate(candidate.status, CandidateState.APPROVED.value)
        candidate.status = CandidateState.APPROVED.value
        candidate.touch()
        node = await self.repo.save_node(node)
        candidate = await self.repo.save_candidate(candidate)
        working.upsert_node(node)
        working.upsert_candidate(candidate)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_CANDIDATE_SELECTED,
            trace_id=node.workflow_id,
            event_type="workflow.v2.candidate.selected",
            producer=event.producer,
            payload={
                "workflow_id": node.workflow_id,
                "workflow_version": 2,
                "node_id": node.id,
                "candidate_id": candidate.id,
            },
        )

    async def _handle_upsert_assembly_from_selection(
        self,
        working,
        event: WorkflowEvent,
        action: UpsertAssemblyFromSelectionAction,
    ) -> None:
        workflow = working.workflow
        current_revision_id = str(workflow.current_revision_id or "")
        node = self._get_node(working, action.node_id)
        candidate = self._get_candidate(working, action.candidate_id)
        if candidate.node_id != action.node_id:
            raise ValueError("Candidate does not belong to node")
        if current_revision_id and node.revision_id != current_revision_id:
            raise ValueError("Node is not in current revision")

        item_ref = AssemblyItemRef(
            order=1,
            node_id=action.node_id,
            candidate_id=action.candidate_id,
            role="primary",
            meta={},
        )
        assembly = None
        if workflow.current_assembly_id:
            assembly = next((item for item in working.assemblies if item.id == workflow.current_assembly_id), None)
            if assembly is not None and assembly.status in {
                "rejected",
                WorkflowState.DONE.value,
                WorkflowState.CANCELLED.value,
            }:
                # Rejected/terminal assembly should not be mutated by new selection.
                assembly = None
        if assembly is None and working.assemblies:
            assembly = working.assemblies[-1]
            if assembly is not None and assembly.status in {
                "rejected",
                WorkflowState.DONE.value,
                WorkflowState.CANCELLED.value,
            }:
                assembly = None
        if assembly is None:
            assembly = AssemblyEntity(
                id=self._generate_id("asm", utcnow()),
                workflow_id=action.workflow_id,
                status=WorkflowState.DRAFT.value,
                items=[item_ref],
                summary=action.summary or "",
            )
            assembly = await self.repo.create_assembly(assembly)
            working.upsert_assembly(assembly)
            workflow.current_assembly_id = assembly.id
        else:
            exists = any(
                item.node_id == action.node_id and item.candidate_id == action.candidate_id
                for item in assembly.items
            )
            if not exists:
                order = len(assembly.items) + 1
                assembly.items.append(
                    AssemblyItemRef(
                        order=order,
                        node_id=action.node_id,
                        candidate_id=action.candidate_id,
                        role="primary",
                        meta={},
                    )
                )
            if action.summary:
                assembly.summary = action.summary
            assembly.touch()
            assembly = await self.repo.save_assembly(assembly)
            working.upsert_assembly(assembly)

        if workflow.state != WorkflowState.AWAITING_FINAL_REVIEW.value:
            if workflow.state != WorkflowState.ASSEMBLING.value:
                self.workflow_sm.validate(workflow.state, WorkflowState.ASSEMBLING.value)
                workflow.state = WorkflowState.ASSEMBLING.value
                workflow.touch()
                workflow = await self.repo.save_workflow(workflow)
                working.upsert_workflow(workflow)
                await self.bus.publish(
                    topic=TOPIC_WORKFLOW_STATE_CHANGED,
                    trace_id=workflow.id,
                    event_type="workflow.v2.state.changed",
                    producer=event.producer,
                    payload={
                        "workflow_id": workflow.id,
                        "workflow_version": 2,
                        "state": workflow.state,
                        "reason": "assembly created from candidate selection",
                    },
                )
            self.workflow_sm.validate(workflow.state, WorkflowState.AWAITING_FINAL_REVIEW.value)
            workflow.state = WorkflowState.AWAITING_FINAL_REVIEW.value
        workflow.touch()
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_STATE_CHANGED,
            trace_id=workflow.id,
            event_type="workflow.v2.state.changed",
            producer=event.producer,
            payload={
                "workflow_id": workflow.id,
                "workflow_version": 2,
                "state": workflow.state,
                "reason": "awaiting final review",
            },
        )
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_ASSEMBLY_CREATED,
            trace_id=action.workflow_id,
            event_type="workflow.v2.assembly.created",
            producer=event.producer,
            payload={
                "workflow_id": action.workflow_id,
                "workflow_version": 2,
                "assembly_id": workflow.current_assembly_id,
            },
        )

    async def _handle_complete_assembly(
        self,
        working,
        event: WorkflowEvent,
        action: CompleteAssemblyAction,
    ) -> None:
        workflow = working.workflow
        resolved_assembly_id = action.assembly_id or workflow.current_assembly_id
        if not resolved_assembly_id:
            raise ValueError("assembly_id is required when workflow has no current assembly")
        assembly = self._get_assembly(working, resolved_assembly_id)
        assembly.status = action.status
        if action.summary:
            assembly.summary = action.summary
        effective_summary = (action.summary or assembly.summary or "").strip()
        if not effective_summary:
            effective_summary = self._derive_assembly_summary(working, assembly)
            if effective_summary:
                assembly.summary = effective_summary
        if effective_summary:
            workflow.summary_output = effective_summary
        if action.artifacts is not None:
            assembly.artifacts = action.artifacts
        if action.meta:
            assembly.meta.update(action.meta)
        assembly.touch()
        workflow.touch()
        assembly = await self.repo.save_assembly(assembly)
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_assembly(assembly)
        working.upsert_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_ASSEMBLY_CREATED,
            trace_id=action.workflow_id,
            event_type="workflow.v2.assembly.updated",
            producer=event.producer,
            payload={
                "workflow_id": action.workflow_id,
                "workflow_version": 2,
                "assembly_id": assembly.id,
                "status": assembly.status,
            },
        )

    async def _handle_reject_assembly(
        self,
        working,
        event: WorkflowEvent,
        action: RejectAssemblyAction,
    ) -> None:
        assembly = self._get_assembly(working, action.assembly_id)
        assembly.status = "rejected"
        assembly.touch()
        assembly = await self.repo.save_assembly(assembly)
        working.upsert_assembly(assembly)
        workflow = working.workflow
        self.workflow_sm.validate(workflow.state, WorkflowState.EXECUTING.value)
        workflow.state = WorkflowState.EXECUTING.value
        workflow.touch()
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_ASSEMBLY_CREATED,
            trace_id=action.workflow_id,
            event_type="workflow.v2.assembly.updated",
            producer=event.producer,
            payload={
                "workflow_id": action.workflow_id,
                "workflow_version": 2,
                "assembly_id": assembly.id,
                "status": assembly.status,
                "reason": action.reason,
            },
        )

    async def _handle_rollback_workflow(
        self,
        working,
        event: WorkflowEvent,
        action: RollbackWorkflowAction,
    ) -> None:
        workflow = working.workflow
        if workflow.state in WORKFLOW_TERMINAL:
            raise ValueError(f"workflow {action.workflow_id} is terminal: {workflow.state}")
        target = action.target_revision_id
        if not target and working.revisions:
            sorted_revisions = sorted(working.revisions, key=lambda item: item.number)
            target = sorted_revisions[-2].id if len(sorted_revisions) > 1 else sorted_revisions[0].id
        if not target:
            raise ValueError("rollback requires at least one revision")
        workflow.current_revision_id = target
        if workflow.state not in WORKFLOW_ROLLBACK_ALLOWED:
            raise ValueError(f"workflow {action.workflow_id} cannot rollback from state: {workflow.state}")
        allowed = self.workflow_sm.allowed_transitions(workflow.state)
        if WorkflowState.PLANNING.value in allowed:
            self.workflow_sm.validate(workflow.state, WorkflowState.PLANNING.value)
        workflow.state = WorkflowState.PLANNING.value
        workflow.touch()
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_workflow(workflow)
        await self._handle_record_decision(
            working,
            event,
            RecordDecisionAction(
                workflow_id=action.workflow_id,
                target_type="workflow",
                target_id=action.workflow_id,
                action="rollback",
                actor=action.actor,
                comment=action.reason or f"rollback to revision {target}",
                payload={"target_revision_id": target},
            ),
        )
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_STATE_CHANGED,
            trace_id=action.workflow_id,
            event_type="workflow.v2.rollback",
            producer=event.producer,
            payload={
                "workflow_id": action.workflow_id,
                "workflow_version": 2,
                "state": workflow.state,
                "target_revision_id": target,
                "reason": action.reason,
            },
        )

    async def _handle_build_assembly(self, working, event: WorkflowEvent, action: BuildAssemblyAction) -> None:
        assembly = AssemblyEntity(
            id=self._generate_id("asm", utcnow()),
            workflow_id=action.workflow_id,
            status=WorkflowState.DRAFT.value,
            items=action.item_refs,
        )
        assembly = await self.repo.create_assembly(assembly)
        working.upsert_assembly(assembly)
        workflow = working.workflow
        workflow.current_assembly_id = assembly.id
        workflow.touch()
        workflow = await self.repo.save_workflow(workflow)
        working.upsert_workflow(workflow)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_ASSEMBLY_CREATED,
            trace_id=assembly.workflow_id,
            event_type="workflow.v2.assembly.created",
            producer=event.producer,
            payload={
                "workflow_id": assembly.workflow_id,
                "workflow_version": 2,
                "assembly_id": assembly.id,
            },
        )

    async def _handle_record_decision(self, working, event: WorkflowEvent, action: RecordDecisionAction) -> None:
        decision = DecisionEntity(
            id=self._generate_id("dec", utcnow()),
            workflow_id=action.workflow_id,
            target_type=action.target_type,
            target_id=action.target_id,
            action=action.action,
            actor=action.actor,
            comment=action.comment,
            payload=action.payload,
        )
        decision = await self.repo.create_decision(decision)
        working.upsert_decision(decision)
        await self.bus.publish(
            topic=TOPIC_WORKFLOW_DECISION,
            trace_id=decision.workflow_id,
            event_type="workflow.v2.decision",
            producer=event.producer,
            payload={
                "workflow_id": decision.workflow_id,
                "workflow_version": 2,
                "decision_id": decision.id,
                "target_type": decision.target_type,
                "target_id": decision.target_id,
                "action": decision.action,
            },
        )

    @staticmethod
    def _get_node(working, node_id: str) -> NodeEntity:
        node = next((n for n in working.nodes if n.id == node_id), None)
        if node is None:
            raise ValueError(f"Node not found in working snapshot: {node_id}")
        return node

    @staticmethod
    def _get_candidate(working, candidate_id: str) -> CandidateEntity:
        candidate = next((c for c in working.candidates if c.id == candidate_id), None)
        if candidate is None:
            raise ValueError(f"Candidate not found in working snapshot: {candidate_id}")
        return candidate

    @staticmethod
    def _get_revision(working, revision_id: str) -> RevisionEntity:
        revision = next((r for r in working.revisions if r.id == revision_id), None)
        if revision is None:
            raise ValueError(f"Revision not found in working snapshot: {revision_id}")
        return revision

    @staticmethod
    def _get_assembly(working, assembly_id: str) -> AssemblyEntity:
        assembly = next((a for a in working.assemblies if a.id == assembly_id), None)
        if assembly is None:
            raise ValueError(f"Assembly not found in working snapshot: {assembly_id}")
        return assembly

    @staticmethod
    def _derive_assembly_summary(working, assembly: AssemblyEntity) -> str:
        candidate_ids = [
            str(getattr(item, "candidate_id", "") or "")
            for item in (assembly.items or [])
            if str(getattr(item, "candidate_id", "") or "")
        ]
        if not candidate_ids:
            return ""
        chunks: list[str] = []
        for candidate_id in candidate_ids:
            candidate = next((c for c in working.candidates if c.id == candidate_id), None)
            if candidate is None:
                continue
            text = str(getattr(candidate, "summary", "") or "").strip()
            if text:
                chunks.append(text)
        return "\n\n".join(chunks).strip()

    @staticmethod
    def _generate_id(prefix: str, now: datetime) -> str:
        import uuid

        return f"{prefix}-{now.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6]}"

    @staticmethod
    def _normalize_revision_content(
        *,
        workflow_title: str,
        workflow_goal: str,
        raw_content: str,
    ) -> str:
        content = (raw_content or "").strip()
        if content:
            return content
        title = (workflow_title or "").strip() or "未命名任务"
        goal = (workflow_goal or "").strip()
        lines = [f"任务主题：{title}"]
        if goal:
            lines.append(f"目标：{goal}")
        lines.append("说明：当前方案正文未提供，已自动生成基础草案，请在后续迭代中补充细节。")
        return "\n".join(lines)

    @staticmethod
    def _derive_revision_summary(content: str, max_len: int = 120) -> str:
        text = " ".join((content or "").split())
        if not text:
            return ""
        if len(text) <= max_len:
            return text
        return f"{text[:max_len].rstrip()}..."
