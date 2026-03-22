"""Minimal backend workflow policy for the v2 spike."""

from __future__ import annotations

from kernel.workflow_actions import (
    CompleteAssemblyAction,
    CreateRevisionAction,
    RecordDecisionAction,
    RejectAssemblyAction,
    RollbackWorkflowAction,
    SelectCandidateAction,
    SpawnNodeAction,
    TransitionCandidateAction,
    TransitionNodeAction,
    TransitionRevisionAction,
    TransitionWorkflowAction,
)
from .workflow_guards import (
    EVENT_APPROVE_ASSEMBLY,
    EVENT_APPROVE_PLAN,
    EVENT_CANCEL_WORKFLOW,
    EVENT_REGENERATE_NODE,
    EVENT_REJECT_PLAN,
    EVENT_REJECT_ASSEMBLY,
    EVENT_ROLLBACK_WORKFLOW,
    EVENT_RESUME_WORKFLOW,
    EVENT_SELECT_CANDIDATE,
    EVENT_START_PLANNING,
    EVENT_STOP_WORKFLOW,
    EVENT_SUBMIT_PLAN,
)


class MinimalWorkflowPolicy:
    """A tiny policy just to exercise the v2 workflow pipeline."""

    def plan_actions(self, snapshot, event):
        workflow_id = snapshot.workflow.id
        if event.event_type == EVENT_START_PLANNING:
            return [
                CreateRevisionAction(
                    workflow_id=workflow_id,
                    created_by=str(event.producer or "system"),
                    source="command",
                    content=str(event.payload.get("content") or ""),
                ),
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="planning",
                    reason="start planning",
                ),

            ]
        if event.event_type == EVENT_SUBMIT_PLAN:
            return [
                TransitionRevisionAction(
                    workflow_id=workflow_id,
                    to_status="awaiting_review",
                    revision_id=snapshot.workflow.current_revision_id,
                    reason="submit plan",
                ),
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="awaiting_plan_review",
                    reason="submit plan",
                ),

            ]
        if event.event_type == EVENT_APPROVE_PLAN:
            revision_id = snapshot.workflow.current_revision_id
            if not revision_id:
                return []
            return [
                TransitionRevisionAction(
                    workflow_id=workflow_id,
                    to_status="approved",
                    revision_id=revision_id,
                    reason="approve plan",
                ),
                SpawnNodeAction(
                    workflow_id=workflow_id,
                    revision_id=revision_id,
                    kind="work_item",
                    title=str(event.payload.get("node_title") or "默认执行节点"),
                    assignee=str(event.payload.get("assignee") or "gongbu"),
                    sequence=1,
                    state="ready",
                ),
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="executing",
                    reason="approve plan",
                ),

            ]
        if event.event_type == EVENT_REJECT_PLAN:
            revision_id = snapshot.workflow.current_revision_id
            cascade_actions = []
            if revision_id:
                current_nodes = [item for item in snapshot.nodes if item.revision_id == revision_id]
                current_node_ids = {item.id for item in current_nodes}
                for node in current_nodes:
                    if node.state != "superseded":
                        cascade_actions.append(
                            TransitionNodeAction(
                                node_id=node.id,
                                to_state="superseded",
                                reason="revision rejected",
                            )
                        )
                for candidate in snapshot.candidates:
                    if candidate.node_id in current_node_ids and candidate.status != "superseded":
                        cascade_actions.append(
                            TransitionCandidateAction(
                                candidate_id=candidate.id,
                                to_state="superseded",
                                reason="revision rejected",
                            )
                        )
            return [
                TransitionRevisionAction(
                    workflow_id=workflow_id,
                    to_status="rejected",
                    revision_id=revision_id,
                    reason="reject plan",
                ),
                *cascade_actions,
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="planning",
                    reason="reject plan",
                ),

            ]
        if event.event_type == EVENT_STOP_WORKFLOW:
            return [
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="blocked",
                    reason="stop workflow",
                ),

            ]
        if event.event_type == EVENT_CANCEL_WORKFLOW:
            return [
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="cancelled",
                    reason="cancel workflow",
                ),

            ]
        if event.event_type == EVENT_RESUME_WORKFLOW and snapshot.workflow.state == "blocked":
            # 从 meta 中恢复 stop 前状态；blocked 允许回到 planning / executing / assembling
            pre_block_state = str((snapshot.workflow.meta or {}).get("pre_block_state") or "")
            valid_resume_targets = {"planning", "executing", "assembling"}
            resume_target = pre_block_state if pre_block_state in valid_resume_targets else "planning"
            return [
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state=resume_target,
                    reason=f"resume workflow (restored to {resume_target})",
                ),

            ]
        if event.event_type == EVENT_SELECT_CANDIDATE:
            node_id = str(event.payload.get("node_id") or "")
            candidate_id = str(event.payload.get("candidate_id") or "")
            if not node_id or not candidate_id:
                return []
            return [
                SelectCandidateAction(node_id=node_id, candidate_id=candidate_id),
                RecordDecisionAction(
                    workflow_id=workflow_id,
                    target_type="candidate",
                    target_id=candidate_id,
                    action="select",
                    actor=str(event.payload.get("actor") or event.producer or "api"),
                    comment=str(event.payload.get("comment") or ""),
                    payload={"node_id": node_id},
                ),

            ]
        if event.event_type == EVENT_APPROVE_ASSEMBLY:
            assembly_id = str(event.payload.get("assembly_id") or "")
            return [
                CompleteAssemblyAction(
                    workflow_id=workflow_id,
                    assembly_id=assembly_id,
                    status="done",
                    summary=str(event.payload.get("summary") or ""),
                    artifacts=event.payload.get("artifacts"),
                    meta=event.payload.get("meta"),
                ),
                TransitionWorkflowAction(
                    workflow_id=workflow_id,
                    to_state="done",
                    reason="assembly approved",
                ),
                RecordDecisionAction(
                    workflow_id=workflow_id,
                    target_type="assembly",
                    target_id=assembly_id,
                    action="approve",
                    actor=str(event.payload.get("actor") or event.producer or "api"),
                    comment=str(event.payload.get("summary") or ""),
                    payload={},
                ),

            ]
        if event.event_type == EVENT_REJECT_ASSEMBLY:
            assembly_id = str(event.payload.get("assembly_id") or "")
            if not assembly_id:
                return []
            return [
                RejectAssemblyAction(
                    workflow_id=workflow_id,
                    assembly_id=assembly_id,
                    reason=str(event.payload.get("reason") or ""),
                ),
                RecordDecisionAction(
                    workflow_id=workflow_id,
                    target_type="assembly",
                    target_id=assembly_id,
                    action="reject",
                    actor=str(event.payload.get("actor") or event.producer or "api"),
                    comment=str(event.payload.get("reason") or ""),
                    payload={"reason": str(event.payload.get("reason") or "")},
                ),

            ]
        if event.event_type == EVENT_ROLLBACK_WORKFLOW:
            return [
                RollbackWorkflowAction(
                    workflow_id=workflow_id,
                    actor=str(event.payload.get("actor") or event.producer or "api"),
                    target_revision_id=str(event.payload.get("target_revision_id") or ""),
                    reason=str(event.payload.get("reason") or ""),
                ),

            ]
        if event.event_type == EVENT_REGENERATE_NODE:
            return []
        return []
