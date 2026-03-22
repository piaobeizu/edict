from __future__ import annotations

from datetime import datetime, timezone

import pytest

from kernel.graph_entities import NodeEntity, RevisionEntity, WorkflowEntity, WorkflowSnapshot

from backend.app.models.task import Task, TaskState
from backend.app.services.task_projection_service import apply_workflow_snapshot_to_task
from backend.app.services.task_service import TaskService


def build_snapshot() -> WorkflowSnapshot:
    now = datetime.now(timezone.utc)
    workflow = WorkflowEntity(
        id="wf-1",
        task_id="JJC-1",
        type="generic",
        title="Spike",
        goal="Projection",
        state="executing",
        owner="shangshu",
        current_revision_id="rev-1",
        summary_output="workflow summary",
        created_at=now,
        updated_at=now,
    )
    revision = RevisionEntity(
        id="rev-1",
        workflow_id="wf-1",
        number=1,
        status="approved",
        created_by="zhongshu",
        created_at=now,
        updated_at=now,
    )
    nodes = [
        NodeEntity(
            id="node-1",
            workflow_id="wf-1",
            revision_id="rev-1",
            kind="work_item",
            state="approved",
            title="步骤一",
            sequence=1,
            assignee="gongbu",
            created_at=now,
            updated_at=now,
        ),
        NodeEntity(
            id="node-2",
            workflow_id="wf-1",
            revision_id="rev-1",
            kind="work_item",
            state="running",
            title="步骤二",
            sequence=2,
            assignee="hubu",
            created_at=now,
            updated_at=now,
        ),
    ]
    return WorkflowSnapshot(workflow=workflow, revisions=[revision], nodes=nodes)


def build_done_snapshot_with_produced_node() -> WorkflowSnapshot:
    now = datetime.now(timezone.utc)
    workflow = WorkflowEntity(
        id="wf-done",
        task_id="JJC-done",
        type="generic",
        title="Done flow",
        goal="Projection",
        state="done",
        owner="shangshu",
        current_revision_id="rev-done",
        summary_output="done summary",
        created_at=now,
        updated_at=now,
    )
    nodes = [
        NodeEntity(
            id="node-done-1",
            workflow_id="wf-done",
            revision_id="rev-done",
            kind="work_item",
            state="produced",
            title="步骤一",
            sequence=1,
            assignee="gongbu",
            created_at=now,
            updated_at=now,
        )
    ]
    return WorkflowSnapshot(workflow=workflow, revisions=[], nodes=nodes)


def test_apply_workflow_snapshot_to_task():
    task = Task(
        id="JJC-1",
        title="旧任务",
        state=TaskState.Taizi.value,
        org="太子",
        official="皇上",
    )
    projected = apply_workflow_snapshot_to_task(task, build_snapshot())
    assert projected.workflow_id == "wf-1"
    assert projected.workflow_type == "generic"
    assert projected.state == "Doing"
    assert projected.org == "hubu"
    assert projected.current_revision_id == "rev-1"
    assert projected.running_node_count == 1
    assert projected.pending_review_count == 0
    assert len(projected.todos) == 2
    assert projected.todos[0]["status"] == "completed"
    assert projected.todos[1]["status"] == "in-progress"
    assert len(projected.flow_log) == 1
    assert projected.flow_log[0]["to"] == "Doing"


def test_apply_workflow_snapshot_to_task_appends_flow_log_on_state_change_only():
    task = Task(
        id="JJC-1",
        title="旧任务",
        state=TaskState.Taizi.value,
        org="太子",
        official="皇上",
        flow_log=[{"from": None, "to": "Taizi", "agent": "system", "reason": "init", "ts": "t1"}],
    )
    projected = apply_workflow_snapshot_to_task(task, build_snapshot())
    assert len(projected.flow_log) == 2
    assert projected.flow_log[-1]["from"] == "Taizi"
    assert projected.flow_log[-1]["to"] == "Doing"

    projected_again = apply_workflow_snapshot_to_task(projected, build_snapshot())
    assert len(projected_again.flow_log) == 2
    assert projected_again.flow_log[-1]["to"] == "Doing"


def test_task_service_rejects_non_legacy_mutation():
    task = Task(
        id="JJC-2",
        title="V2 任务",
        state=TaskState.Taizi.value,
        workflow_type="generic",
    )
    with pytest.raises(ValueError):
        TaskService._assert_legacy_mutation(task, "transition_state")


def test_terminal_workflow_forces_pending_review_count_to_zero():
    task = Task(
        id="JJC-done",
        title="已完成任务",
        state=TaskState.Review.value,
        org="工部",
        official="中书",
    )
    projected = apply_workflow_snapshot_to_task(task, build_done_snapshot_with_produced_node())
    assert projected.state == "Done"
    assert projected.pending_review_count == 0
    assert projected.scheduler.get("pendingReviewCount") == 0
