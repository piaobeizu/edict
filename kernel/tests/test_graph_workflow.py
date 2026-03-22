"""Kernel v2 graph workflow spike tests."""

from __future__ import annotations

import pytest

from kernel.graph_workflow import GraphWorkflowEngine
from kernel.graph_entities import (
    AssemblyEntity,
    AssemblyItemRef,
    CandidateEntity,
    NodeEntity,
    RevisionEntity,
)
from kernel.workflow_types import CandidateState, NodeState, WorkflowState
from kernel.workflow_actions import (
    CreateRevisionAction,
    RecordDecisionAction,
    RollbackWorkflowAction,
    SelectCandidateAction,
    SpawnNodeAction,
    TransitionCandidateAction,
    TransitionNodeAction,
    TransitionRevisionAction,
    TransitionWorkflowAction,
)
from kernel.workflow_events import WorkflowEvent
from kernel.state_machine import InvalidTransitionError
from backend.app.services.workflow_guards import EVENT_REJECT_ASSEMBLY, EVENT_ROLLBACK_WORKFLOW
from backend.app.services.workflow_policy import MinimalWorkflowPolicy
from tests.helpers import InMemoryWorkflowRepo


class InMemoryBus:
    def __init__(self):
        self.events = []

    async def publish(self, topic, trace_id, event_type, producer, payload=None):
        self.events.append(
            {
                "topic": topic,
                "trace_id": trace_id,
                "event_type": event_type,
                "producer": producer,
                "payload": payload or {},
            }
        )
        return f"evt-{len(self.events)}"

    async def consume(self, topic, group, consumer, count=10, block_ms=5000):
        return []

    async def ack(self, topic, group, entry_id):
        return None

    async def claim_stale(self, topic, group, consumer, min_idle_ms=60000, count=10):
        return []


class InMemoryProjection:
    def __init__(self):
        self.refreshed = []

    async def refresh_task_projection(self, workflow_id: str) -> None:
        self.refreshed.append(workflow_id)


class FakePolicy:
    def plan_actions(self, snapshot, event):
        if event.event_type == "spike.start_planning":
            return [
                CreateRevisionAction(
                    workflow_id=snapshot.workflow.id,
                    created_by="zhongshu",
                    source="agent",
                    content="最小 spike 方案",
                ),
                TransitionWorkflowAction(
                    workflow_id=snapshot.workflow.id,
                    to_state="planning",
                    reason="进入规划阶段",
                ),

            ]
        if event.event_type == "spike.plan_submitted":
            return [
                TransitionRevisionAction(
                    workflow_id=snapshot.workflow.id,
                    revision_id=snapshot.workflow.current_revision_id,
                    to_status="awaiting_review",
                    reason="规划完成，等待审议",
                ),
                TransitionWorkflowAction(
                    workflow_id=snapshot.workflow.id,
                    to_state="awaiting_plan_review",
                    reason="规划完成，等待审议",
                ),

            ]
        if event.event_type == "spike.plan_approved":
            return [
                TransitionRevisionAction(
                    workflow_id=snapshot.workflow.id,
                    revision_id=snapshot.workflow.current_revision_id,
                    to_status="approved",
                    reason="方案批准",
                ),
                SpawnNodeAction(
                    workflow_id=snapshot.workflow.id,
                    revision_id=snapshot.workflow.current_revision_id,
                    kind="work_item",
                    title="步骤一",
                    assignee="gongbu",
                    sequence=1,
                    state="ready",
                ),
                TransitionWorkflowAction(
                    workflow_id=snapshot.workflow.id,
                    to_state="executing",
                    reason="方案已批准，开始执行",
                ),

            ]
        return []


@pytest.fixture
def graph_engine():
    repo = InMemoryWorkflowRepo()
    bus = InMemoryBus()
    projection = InMemoryProjection()
    policy = FakePolicy()
    return GraphWorkflowEngine(repo=repo, bus=bus, policy=policy, projection=projection), repo, bus, projection


class TestGraphWorkflowEngineSpike:
    @pytest.mark.asyncio
    async def test_create_workflow_publishes_created_event(self, graph_engine):
        engine, repo, bus, _ = graph_engine
        workflow = await engine.create_workflow("最小 spike", goal="验证 v2 骨架")
        assert workflow.state == "draft"
        assert workflow.id in repo.workflows
        assert bus.events[-1]["topic"] == "workflow.v2.created"
        assert bus.events[-1]["payload"]["workflow_version"] == 2

    @pytest.mark.asyncio
    async def test_apply_event_creates_revision_and_projection(self, graph_engine):
        engine, repo, bus, projection = graph_engine
        workflow = await engine.create_workflow("最小 spike", goal="验证 v2 骨架")
        actions = await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.start_planning",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        stored = await repo.get_workflow(workflow.id)
        revisions = await repo.list_revisions(workflow.id)
        assert len(actions) == 2
        assert stored is not None and stored.state == "planning"
        assert len(revisions) == 1
        assert stored.current_revision_id == revisions[0].id
        assert projection.refreshed == [workflow.id]
        topics = [e["topic"] for e in bus.events]
        assert "workflow.v2.revision.created" in topics
        assert "workflow.v2.state.changed" in topics

    @pytest.mark.asyncio
    async def test_create_revision_fills_fallback_content_when_empty(self):
        class EmptyContentPolicy:
            def plan_actions(self, snapshot, event):
                if event.event_type != "spike.start_planning_empty":
                    return []
                return [
                    CreateRevisionAction(
                        workflow_id=snapshot.workflow.id,
                        created_by="zhongshu",
                        source="agent",
                        content="",
                    ),
                    TransitionWorkflowAction(
                        workflow_id=snapshot.workflow.id,
                        to_state="planning",
                        reason="进入规划阶段",
                    ),
                ]

        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=EmptyContentPolicy(), projection=None)
        workflow = await engine.create_workflow("长期修复校验", goal="验证空正文兜底")
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.start_planning_empty",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        revisions = await repo.list_revisions(workflow.id)
        assert len(revisions) == 1
        assert revisions[0].content
        assert "任务主题：" in revisions[0].content
        assert revisions[0].change_summary

    @pytest.mark.asyncio
    async def test_apply_event_spawns_node_and_transitions_workflow(self, graph_engine):
        engine, repo, _, projection = graph_engine
        workflow = await engine.create_workflow("最小 spike", goal="验证 v2 骨架")
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.start_planning",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.plan_submitted",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        revisions = await repo.list_revisions(workflow.id)
        assert revisions and revisions[-1].status == "awaiting_review"
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.plan_approved",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        stored = await repo.get_workflow(workflow.id)
        nodes = await repo.list_nodes(workflow.id)
        revisions = await repo.list_revisions(workflow.id)
        assert stored is not None and stored.state == "executing"
        assert len(nodes) == 1
        assert nodes[0].revision_id == stored.current_revision_id
        assert nodes[0].state == "ready"
        assert revisions and revisions[-1].status == "approved"
        assert projection.refreshed == [workflow.id, workflow.id, workflow.id]

    @pytest.mark.asyncio
    async def test_phase3_methods_cover_progress_candidate_assembly_and_rollback(self, graph_engine):
        engine, repo, bus, _ = graph_engine
        workflow = await engine.create_workflow("phase3", goal="补齐缺失引擎方法")
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.start_planning",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.plan_submitted",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.plan_approved",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        nodes = await repo.list_nodes(workflow.id)
        assert len(nodes) == 1
        node = nodes[0]

        node = await engine.add_node_progress(
            workflow_id=workflow.id,
            node_id=node.id,
            to_state=NodeState.RUNNING.value,
            reason="开始执行",
            executor_id="gongbu",
        )
        assert node.state == NodeState.RUNNING.value

        candidate = CandidateEntity(
            id="cand-1",
            workflow_id=workflow.id,
            node_id=node.id,
            status=CandidateState.QUEUED.value,
            provider="unit-test",
        )
        await repo.create_candidate(candidate)

        candidate = await engine.complete_candidate(
            workflow_id=workflow.id,
            candidate_id=candidate.id,
            status=CandidateState.RUNNING.value,
        )
        assert candidate.status == CandidateState.RUNNING.value
        candidate = await engine.complete_candidate(
            workflow_id=workflow.id,
            candidate_id=candidate.id,
            status=CandidateState.PRODUCED.value,
            summary="候选方案已产出",
        )
        assert candidate.status == CandidateState.PRODUCED.value

        assembly = AssemblyEntity(
            id="asm-1",
            workflow_id=workflow.id,
            status=WorkflowState.DRAFT.value,
            items=[
                AssemblyItemRef(
                    order=1,
                    node_id=node.id,
                    candidate_id=candidate.id,
                    role="primary",
                )
            ],
        )
        await repo.create_assembly(assembly)
        wf = await repo.get_workflow(workflow.id)
        assert wf is not None
        wf.current_assembly_id = assembly.id
        await repo.save_workflow(wf)

        assembly = await engine.complete_assembly(
            workflow_id=workflow.id,
            status=WorkflowState.DONE.value,
        )
        assert assembly.status == WorkflowState.DONE.value
        assert assembly.summary == "候选方案已产出"
        wf = await repo.get_workflow(workflow.id)
        assert wf is not None
        assert wf.summary_output == "候选方案已产出"

        decision = await engine.submit_decision(
            workflow_id=workflow.id,
            target_type="assembly",
            target_id=assembly.id,
            action="approve",
            actor="zhongshu",
            comment="同意进入下一阶段",
        )
        assert decision.action == "approve"

        rolled = await engine.rollback(
            workflow_id=workflow.id,
            actor="zhongshu",
            reason="回滚验证",
        )
        assert rolled.state == WorkflowState.PLANNING.value
        assert any(item["event_type"] == "workflow.v2.rollback" for item in bus.events)

    @pytest.mark.asyncio
    async def test_apply_event_can_supersede_ready_node_and_queued_candidate(self):
        class SupersedePolicy:
            def plan_actions(self, snapshot, event):
                if event.event_type != "spike.supersede":
                    return []
                return [
                    TransitionNodeAction(
                        node_id="node-1",
                        to_state=NodeState.SUPERSEDED.value,
                        reason="revision rejected",
                    ),
                    TransitionCandidateAction(
                        candidate_id="cand-1",
                        to_state=CandidateState.SUPERSEDED.value,
                        reason="revision rejected",
                    ),
                ]

        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=SupersedePolicy(), projection=None)
        workflow = await engine.create_workflow("supersede", goal="覆盖 reject 级联")
        node = await repo.create_node(
            NodeEntity(
                id="node-1",
                workflow_id=workflow.id,
                revision_id="rev-1",
                kind="work_item",
                state=NodeState.READY.value,
                title="待废弃节点",
            )
        )
        await repo.create_candidate(
            CandidateEntity(
                id="cand-1",
                workflow_id=workflow.id,
                node_id=node.id,
                status=CandidateState.QUEUED.value,
                provider="unit-test",
            )
        )
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.supersede",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        updated_node = await repo.get_node(node.id)
        updated_candidate = await repo.get_candidate("cand-1")
        assert updated_node is not None and updated_node.state == NodeState.SUPERSEDED.value
        assert updated_candidate is not None and updated_candidate.status == CandidateState.SUPERSEDED.value

    @pytest.mark.asyncio
    async def test_upsert_assembly_for_selected_candidate_checks_current_revision(self, graph_engine):
        engine, repo, _, _ = graph_engine
        workflow = await engine.create_workflow("assembly-check", goal="revision guard")
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.start_planning",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        current = await repo.get_workflow(workflow.id)
        assert current is not None and current.current_revision_id
        current.state = WorkflowState.EXECUTING.value
        await repo.save_workflow(current)
        await repo.create_node(
            NodeEntity(
                id="node-ok",
                workflow_id=workflow.id,
                revision_id=current.current_revision_id,
                kind="work_item",
                state=NodeState.APPROVED.value,
                title="ok",
            )
        )
        await repo.create_candidate(
            CandidateEntity(
                id="cand-ok",
                workflow_id=workflow.id,
                node_id="node-ok",
                status=CandidateState.APPROVED.value,
                provider="unit-test",
            )
        )
        assembly = await engine.upsert_assembly_for_selected_candidate(
            workflow_id=workflow.id,
            node_id="node-ok",
            candidate_id="cand-ok",
            summary="s",
        )
        assert assembly.workflow_id == workflow.id
        await repo.create_node(
            NodeEntity(
                id="node-stale",
                workflow_id=workflow.id,
                revision_id="rev-old",
                kind="work_item",
                state=NodeState.APPROVED.value,
                title="stale",
            )
        )
        await repo.create_candidate(
            CandidateEntity(
                id="cand-stale",
                workflow_id=workflow.id,
                node_id="node-stale",
                status=CandidateState.APPROVED.value,
                provider="unit-test",
            )
        )
        with pytest.raises(ValueError, match="current revision"):
            await engine.upsert_assembly_for_selected_candidate(
                workflow_id=workflow.id,
                node_id="node-stale",
                candidate_id="cand-stale",
            )

    @pytest.mark.asyncio
    async def test_terminal_workflow_rejects_rollback_command(self):
        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=MinimalWorkflowPolicy(), projection=None)
        workflow = await engine.create_workflow("terminal", goal="guard")
        stored = await repo.get_workflow(workflow.id)
        assert stored is not None
        stored.state = WorkflowState.DONE.value
        await repo.save_workflow(stored)
        with pytest.raises(ValueError, match="terminal"):
            await engine.apply_event(
                WorkflowEvent(
                    topic="workflow.v2.command",
                    event_type=EVENT_ROLLBACK_WORKFLOW,
                    trace_id=workflow.id,
                    producer="tester",
                    payload={"workflow_id": workflow.id, "workflow_version": 2, "actor": "zhongshu"},
                )
            )

    @pytest.mark.asyncio
    async def test_terminal_workflow_rejects_reject_assembly_command(self):
        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=MinimalWorkflowPolicy(), projection=None)
        workflow = await engine.create_workflow("terminal-assembly", goal="guard")
        await repo.create_assembly(
            AssemblyEntity(
                id="asm-terminal",
                workflow_id=workflow.id,
                status=WorkflowState.DRAFT.value,
                items=[],
            )
        )
        stored = await repo.get_workflow(workflow.id)
        assert stored is not None
        stored.current_assembly_id = "asm-terminal"
        stored.state = WorkflowState.CANCELLED.value
        await repo.save_workflow(stored)
        with pytest.raises(InvalidTransitionError):
            await engine.apply_event(
                WorkflowEvent(
                    topic="workflow.v2.command",
                    event_type=EVENT_REJECT_ASSEMBLY,
                    trace_id=workflow.id,
                    producer="tester",
                    payload={
                        "workflow_id": workflow.id,
                        "workflow_version": 2,
                        "assembly_id": "asm-terminal",
                        "actor": "zhongshu",
                    },
                )
            )

    @pytest.mark.asyncio
    async def test_rollback_from_assembling_is_allowed_by_explicit_rule(self):
        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=MinimalWorkflowPolicy(), projection=None)
        workflow = await engine.create_workflow("rollback-assembling", goal="guard")
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.start_planning",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.plan_submitted",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type="spike.plan_approved",
                trace_id=workflow.id,
                producer="tester",
                payload={"workflow_id": workflow.id, "workflow_version": 2},
            )
        )
        current = await repo.get_workflow(workflow.id)
        assert current is not None
        current.state = WorkflowState.ASSEMBLING.value
        current.current_revision_id = "rev-target"
        await repo.save_workflow(current)
        rolled = await engine.rollback(
            workflow_id=workflow.id,
            actor="zhongshu",
            target_revision_id="rev-target",
            reason="assemble rollback",
        )
        assert rolled.state == WorkflowState.PLANNING.value

    @pytest.mark.asyncio
    async def test_rollback_from_blocked_is_allowed(self):
        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=MinimalWorkflowPolicy(), projection=None)
        workflow = await engine.create_workflow("rollback-blocked", goal="blocked rollback guard")

        await repo.create_revision(
            RevisionEntity(
                id="rev-1",
                workflow_id=workflow.id,
                number=1,
                status="approved",
                created_by="zhongshu",
                content="r1",
                change_summary="r1",
            )
        )
        current = await repo.get_workflow(workflow.id)
        assert current is not None
        current.state = WorkflowState.BLOCKED.value
        current.current_revision_id = "rev-1"
        await repo.save_workflow(current)

        rolled = await engine.rollback(
            workflow_id=workflow.id,
            actor="zhongshu",
            target_revision_id="rev-1",
            reason="blocked rollback",
        )

        assert rolled.state == WorkflowState.PLANNING.value
        assert rolled.current_revision_id == "rev-1"

    @pytest.mark.asyncio
    async def test_rollback_with_explicit_target_revision_in_multi_revision_workflow(self):
        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=MinimalWorkflowPolicy(), projection=None)
        workflow = await engine.create_workflow("rollback-target", goal="explicit target revision")

        await repo.create_revision(
            RevisionEntity(
                id="rev-1",
                workflow_id=workflow.id,
                number=1,
                status="approved",
                created_by="zhongshu",
                content="r1",
                change_summary="r1",
            )
        )
        await repo.create_revision(
            RevisionEntity(
                id="rev-2",
                workflow_id=workflow.id,
                number=2,
                status="approved",
                created_by="zhongshu",
                content="r2",
                change_summary="r2",
                parent_revision_id="rev-1",
            )
        )
        await repo.create_revision(
            RevisionEntity(
                id="rev-3",
                workflow_id=workflow.id,
                number=3,
                status="approved",
                created_by="zhongshu",
                content="r3",
                change_summary="r3",
                parent_revision_id="rev-2",
            )
        )
        current = await repo.get_workflow(workflow.id)
        assert current is not None
        current.state = WorkflowState.EXECUTING.value
        current.current_revision_id = "rev-3"
        await repo.save_workflow(current)

        rolled = await engine.rollback(
            workflow_id=workflow.id,
            actor="zhongshu",
            target_revision_id="rev-1",
            reason="explicit target rollback",
        )

        assert rolled.state == WorkflowState.PLANNING.value
        assert rolled.current_revision_id == "rev-1"
        decisions = await repo.list_decisions(workflow.id)
        assert decisions
        assert decisions[-1].action == "rollback"
        assert decisions[-1].payload["target_revision_id"] == "rev-1"

    @pytest.mark.asyncio
    async def test_reject_assembly_then_reselect_creates_new_assembly(self):
        repo = InMemoryWorkflowRepo()
        bus = InMemoryBus()
        engine = GraphWorkflowEngine(repo=repo, bus=bus, policy=MinimalWorkflowPolicy(), projection=None)
        workflow = await engine.create_workflow("reject-reselect", goal="assembly recoverability")

        current = await repo.get_workflow(workflow.id)
        assert current is not None
        current.state = WorkflowState.EXECUTING.value
        current.current_revision_id = "rev-1"
        await repo.save_workflow(current)

        await repo.create_node(
            NodeEntity(
                id="node-1",
                workflow_id=workflow.id,
                revision_id="rev-1",
                kind="work_item",
                state=NodeState.APPROVED.value,
                title="node",
            )
        )
        await repo.create_candidate(
            CandidateEntity(
                id="cand-1",
                workflow_id=workflow.id,
                node_id="node-1",
                status=CandidateState.APPROVED.value,
                provider="unit-test",
            )
        )
        await repo.create_candidate(
            CandidateEntity(
                id="cand-2",
                workflow_id=workflow.id,
                node_id="node-1",
                status=CandidateState.APPROVED.value,
                provider="unit-test",
            )
        )

        first = await engine.upsert_assembly_for_selected_candidate(
            workflow_id=workflow.id,
            node_id="node-1",
            candidate_id="cand-1",
            summary="first",
        )

        await engine.apply_event(
            WorkflowEvent(
                topic="workflow.v2.command",
                event_type=EVENT_REJECT_ASSEMBLY,
                trace_id=workflow.id,
                producer="tester",
                payload={
                    "workflow_id": workflow.id,
                    "workflow_version": 2,
                    "assembly_id": first.id,
                    "actor": "zhongshu",
                    "reason": "need better output",
                },
            )
        )

        second = await engine.upsert_assembly_for_selected_candidate(
            workflow_id=workflow.id,
            node_id="node-1",
            candidate_id="cand-2",
            summary="second",
        )

        assert second.id != first.id
        rejected = await repo.get_assembly(first.id)
        assert rejected is not None and rejected.status == "rejected"
        assert [item.candidate_id for item in rejected.items] == ["cand-1"]
        assert [item.candidate_id for item in second.items] == ["cand-2"]
