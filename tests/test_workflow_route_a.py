from __future__ import annotations

from datetime import datetime, timezone

import pytest

from kernel.graph_entities import (
    ArtifactRef,
    AssemblyEntity,
    CandidateEntity,
    DecisionEntity,
    NodeEntity,
    RevisionEntity,
    WorkflowEntity,
    WorkflowSnapshot,
)

from backend.app.api import compat as compat_api
from backend.app.models.task import Task
from backend.app.services.task_service import TaskService
from backend.app.services.workflow_policy import MinimalWorkflowPolicy
from backend.app.services.workflow_guards import (
    PolicyViolation,
    ensure_action_actor,
    ensure_command_actor,
    ensure_not_done,
    ensure_review_actor,
)
from backend.app.services.workflow_guards import (
    EVENT_APPROVE_ASSEMBLY,
    EVENT_APPROVE_PLAN,
    EVENT_CANCEL_WORKFLOW,
    EVENT_COMPLETE_CANDIDATE,
    EVENT_NODE_PROGRESS,
    EVENT_REGENERATE_NODE,
    EVENT_REJECT_PLAN,
    EVENT_REJECT_ASSEMBLY,
    EVENT_ROLLBACK_WORKFLOW,
    EVENT_RESUME_WORKFLOW,
    EVENT_SELECT_CANDIDATE,
    EVENT_START_PLANNING,
    EVENT_STOP_WORKFLOW,
    TOPIC_WORKFLOW_COMMAND,
    EVENT_SUBMIT_PLAN,
)
from backend.app.services.workflow_service import WorkflowService
from kernel.workflow_actions import TransitionRevisionAction, TransitionWorkflowAction
from kernel.workflow_actions import TransitionCandidateAction, TransitionNodeAction
from kernel.workflow_actions import (
    CompleteAssemblyAction,
    RejectAssemblyAction,
    RollbackWorkflowAction,
    SelectCandidateAction,
)
from kernel.workflow_types import WorkflowState


@pytest.mark.asyncio
async def test_workflow_service_timeline_includes_revisions_nodes_decisions_and_artifacts():
    now = datetime.now(timezone.utc)
    snapshot = WorkflowSnapshot(
        workflow=WorkflowEntity(
            id="wf-1",
            task_id="JJC-1",
            type="generic",
            title="测试",
            goal="timeline",
            state="executing",
            created_at=now,
            updated_at=now,
        ),
        revisions=[
            RevisionEntity(
                id="rev-1",
                workflow_id="wf-1",
                number=1,
                status="approved",
                created_by="zhongshu",
                change_summary="初版方案",
                created_at=now,
                updated_at=now,
            )
        ],
        nodes=[
            NodeEntity(
                id="node-1",
                workflow_id="wf-1",
                revision_id="rev-1",
                kind="work_item",
                state="ready",
                title="步骤一",
                assignee="gongbu",
                created_at=now,
                updated_at=now,
            )
        ],
        decisions=[
            DecisionEntity(
                id="dec-1",
                workflow_id="wf-1",
                target_type="revision",
                target_id="rev-1",
                action="approve",
                actor="emperor",
                comment="准奏",
                created_at=now,
            )
        ],
        assemblies=[
            AssemblyEntity(
                id="asm-1",
                workflow_id="wf-1",
                status="ready",
                summary="已生成成片",
                artifacts=[ArtifactRef(kind="video", path="/tmp/final.mp4", mime="video/mp4")],
                created_at=now,
                updated_at=now,
            )
        ],
    )

    class FakeRepo:
        async def load_snapshot(self, workflow_id: str, include_decisions: bool = True):
            return snapshot

    svc = object.__new__(WorkflowService)
    svc.repo = FakeRepo()
    timeline = await WorkflowService.get_timeline(svc, "wf-1")
    kinds = [item["kind"] for item in timeline]
    assert "revision" in kinds
    assert "node" in kinds
    assert "decision" in kinds
    assert "assembly" in kinds
    assembly = next(item for item in timeline if item["kind"] == "assembly")
    assert assembly["artifacts"][0]["kind"] == "video"


class FakeBus:
    def __init__(self):
        self.calls = []

    async def publish(self, topic, trace_id, event_type, producer, payload=None):
        self.calls.append(
            {
                "topic": topic,
                "trace_id": trace_id,
                "event_type": event_type,
                "producer": producer,
                "payload": payload or {},
            }
        )
        return "evt-1"


@pytest.mark.asyncio
async def test_compat_task_action_forwards_workflow_stop(monkeypatch):
    bus = FakeBus()

    async def fake_get_event_bus():
        return bus

    monkeypatch.setattr(compat_api, "get_event_bus", fake_get_event_bus)
    task = Task(id="JJC-2", title="v2", state="Doing", workflow_type="generic", workflow_id="wf-2")
    result = await compat_api._handle_workflow_task_action(task, "stop", "暂停")
    assert result["ok"] is True
    assert bus.calls[0]["topic"] == TOPIC_WORKFLOW_COMMAND
    assert bus.calls[0]["event_type"] == EVENT_STOP_WORKFLOW


@pytest.mark.asyncio
async def test_compat_review_action_forwards_approve(monkeypatch):
    bus = FakeBus()

    async def fake_get_event_bus():
        return bus

    monkeypatch.setattr(compat_api, "get_event_bus", fake_get_event_bus)
    task = Task(id="JJC-3", title="v2", state="YuLan", workflow_type="generic", workflow_id="wf-3")
    result = await compat_api._handle_workflow_review_action(task, "approve", "准奏")
    assert result["ok"] is True
    assert bus.calls[0]["event_type"] == EVENT_APPROVE_PLAN


@pytest.mark.asyncio
async def test_compat_advance_forwards_start_planning(monkeypatch):
    bus = FakeBus()

    async def fake_get_event_bus():
        return bus

    monkeypatch.setattr(compat_api, "get_event_bus", fake_get_event_bus)
    task = Task(id="JJC-4", title="v2", state="Pending", workflow_type="generic", workflow_id="wf-4")
    result = await compat_api._handle_workflow_advance(task, "开工")
    assert result["ok"] is True
    assert bus.calls[0]["event_type"] == EVENT_START_PLANNING


@pytest.mark.asyncio
async def test_compat_create_task_creates_workflow_v2(monkeypatch):
    class FakeWorkflow:
        id = "wf-compat-1"
        task_id = "task-compat-1"
        state = "draft"

    calls = {}

    class FakeWorkflowService:
        def __init__(self, db):
            self.db = db

        async def create_workflow(self, **kwargs):
            calls.update(kwargs)
            return FakeWorkflow()

    monkeypatch.setattr(compat_api, "WorkflowService", FakeWorkflowService)
    body = compat_api.CreateTaskBody(
        title="新任务",
        org="太子",
        targetDept="工部",
        priority="高",
        templateId="tpl-1",
        params={"k": "v"},
    )

    result = await compat_api.create_task_compat(body, db=None)
    assert result["ok"] is True
    assert result["workflowId"] == "wf-compat-1"
    assert result["taskId"] == "task-compat-1"
    assert result["state"] == "draft"
    assert calls["workflow_type"] == "generic"
    assert calls["meta"]["created_via"] == "compat.create-task"


@pytest.mark.asyncio
async def test_task_service_live_status_hides_rows_without_workflow_id():
    svc = object.__new__(TaskService)
    with_wf = Task(id="JJC-100", title="with", state="Doing", workflow_id="wf-100")
    no_wf = Task(id="JJC-101", title="legacy", state="Doing", workflow_id="")

    async def fake_list_tasks(limit: int = 200):
        assert limit == 200
        return [with_wf, no_wf]

    svc.list_tasks = fake_list_tasks
    payload = await TaskService.get_live_status(svc)
    assert "JJC-100" in payload["tasks"]
    assert "JJC-101" not in payload["tasks"]


def test_minimal_workflow_policy_covers_remaining_branches():
    now = datetime.now(timezone.utc)
    policy = MinimalWorkflowPolicy()
    snapshot = WorkflowSnapshot(
        workflow=WorkflowEntity(
            id="wf-9",
            task_id="JJC-9",
            type="generic",
            title="测试",
            goal="policy",
            state="blocked",
            current_revision_id="rev-9",
            created_at=now,
            updated_at=now,
        ),
        nodes=[
            NodeEntity(
                id="node-old",
                workflow_id="wf-9",
                revision_id="rev-9",
                kind="work_item",
                state="ready",
                title="旧节点",
                created_at=now,
                updated_at=now,
            )
        ],
        candidates=[
            CandidateEntity(
                id="cand-old",
                workflow_id="wf-9",
                node_id="node-old",
                status="queued",
                provider="gongbu",
                created_at=now,
                updated_at=now,
            )
        ],
    )
    event = type("Evt", (), {"producer": "api", "payload": {}, "event_type": EVENT_REJECT_PLAN})()
    reject_actions = policy.plan_actions(snapshot, event)
    reject_wf = [a for a in reject_actions if isinstance(a, TransitionWorkflowAction)]
    reject_rev = [a for a in reject_actions if isinstance(a, TransitionRevisionAction)]
    reject_nodes = [a for a in reject_actions if isinstance(a, TransitionNodeAction)]
    reject_candidates = [a for a in reject_actions if isinstance(a, TransitionCandidateAction)]
    assert reject_wf and reject_wf[0].to_state == "planning"
    assert reject_rev and reject_rev[0].to_status == "rejected"
    assert reject_nodes and reject_nodes[0].to_state == "superseded"
    assert reject_candidates and reject_candidates[0].to_state == "superseded"

    event.event_type = EVENT_STOP_WORKFLOW
    stop_actions = policy.plan_actions(snapshot, event)
    stop_wf = [a for a in stop_actions if isinstance(a, TransitionWorkflowAction)]
    assert stop_wf and stop_wf[0].to_state == "blocked"

    event.event_type = EVENT_CANCEL_WORKFLOW
    cancel_actions = policy.plan_actions(snapshot, event)
    cancel_wf = [a for a in cancel_actions if isinstance(a, TransitionWorkflowAction)]
    assert cancel_wf and cancel_wf[0].to_state == "cancelled"

    event.event_type = EVENT_RESUME_WORKFLOW
    resume_actions = policy.plan_actions(snapshot, event)
    resume_wf = [a for a in resume_actions if isinstance(a, TransitionWorkflowAction)]
    assert resume_wf and resume_wf[0].to_state == "planning"

    event.event_type = EVENT_SUBMIT_PLAN
    submit_actions = policy.plan_actions(snapshot, event)
    submit_wf = [a for a in submit_actions if isinstance(a, TransitionWorkflowAction)]
    submit_rev = [a for a in submit_actions if isinstance(a, TransitionRevisionAction)]
    assert submit_wf and submit_wf[0].to_state == "awaiting_plan_review"
    assert submit_rev and submit_rev[0].to_status == "awaiting_review"

    event.event_type = EVENT_SELECT_CANDIDATE
    event.payload = {"node_id": "node-old", "candidate_id": "cand-old", "actor": "zhongshu"}
    select_actions = policy.plan_actions(snapshot, event)
    assert any(isinstance(item, SelectCandidateAction) for item in select_actions)

    event.event_type = EVENT_APPROVE_ASSEMBLY
    event.payload = {"assembly_id": "asm-1", "actor": "zhongshu"}
    approve_assembly_actions = policy.plan_actions(snapshot, event)
    assert any(isinstance(item, CompleteAssemblyAction) for item in approve_assembly_actions)

    event.event_type = EVENT_REJECT_ASSEMBLY
    event.payload = {"assembly_id": "asm-1", "actor": "zhongshu"}
    reject_assembly_actions = policy.plan_actions(snapshot, event)
    assert any(isinstance(item, RejectAssemblyAction) for item in reject_assembly_actions)

    event.event_type = EVENT_ROLLBACK_WORKFLOW
    event.payload = {"actor": "zhongshu"}
    rollback_actions = policy.plan_actions(snapshot, event)
    assert any(isinstance(item, RollbackWorkflowAction) for item in rollback_actions)


@pytest.mark.asyncio
async def test_workflow_service_complete_candidate_maps_artifacts_and_commits():
    class FakeEngine:
        async def complete_candidate(self, **kwargs):
            self.kwargs = kwargs
            return type("Candidate", (), {"id": "cand-1", "status": kwargs["status"], "summary": kwargs["summary"]})()

    class FakeDb:
        def __init__(self):
            self.commits = 0

        async def commit(self):
            self.commits += 1

    svc = object.__new__(WorkflowService)
    svc.engine = FakeEngine()
    svc.db = FakeDb()
    result = await WorkflowService.complete_candidate(
        svc,
        workflow_id="wf-1",
        candidate_id="cand-1",
        status="produced",
        summary="ok",
        artifacts=[
            {
                "kind": "image",
                "path": "/tmp/a.png",
                "mime": "image/png",
                "previewUrl": "http://x/a.png",
                "metadata": {"w": 100},
            }
        ],
    )
    assert result.id == "cand-1"
    assert svc.db.commits == 1
    assert len(svc.engine.kwargs["artifacts"]) == 1
    mapped = svc.engine.kwargs["artifacts"][0]
    assert mapped.kind == "image"
    assert mapped.preview_url == "http://x/a.png"


@pytest.mark.asyncio
async def test_workflow_service_rollback_passes_params_and_commits():
    svc = object.__new__(WorkflowService)
    workflow = type("Workflow", (), {"id": "wf-9", "state": "planning"})()

    class FakeRepo:
        async def get_workflow(self, workflow_id: str):
            assert workflow_id == "wf-9"
            return workflow

    async def fake_submit_command(**kwargs):
        svc.command_kwargs = kwargs
        return []

    svc.repo = FakeRepo()
    svc.submit_command = fake_submit_command
    workflow = await WorkflowService.rollback(
        svc,
        workflow_id="wf-9",
        actor="zhongshu",
        target_revision_id="rev-1",
        reason="回滚测试",
    )
    assert workflow.id == "wf-9"
    assert workflow.state == "planning"
    assert svc.command_kwargs["event_type"] == EVENT_ROLLBACK_WORKFLOW
    assert svc.command_kwargs["payload"]["target_revision_id"] == "rev-1"


@pytest.mark.asyncio
async def test_workflow_service_create_candidate_for_node_runs_completion_flow():
    now = datetime.now(timezone.utc)

    class FakeRepo:
        async def load_snapshot(self, workflow_id: str):
            return WorkflowSnapshot(
                workflow=WorkflowEntity(
                    id=workflow_id,
                    task_id="JJC-1",
                    type="generic",
                    title="x",
                    goal="x",
                    state="executing",
                    created_at=now,
                    updated_at=now,
                ),
                candidates=[],
            )

    class FakeEngine:
        def __init__(self):
            self.calls = []
            self.created = []

        async def create_candidate(self, **kwargs):
            self.created.append(kwargs)
            return type(
                "Candidate",
                (),
                {
                    "id": "cand-created",
                    "status": "queued",
                    "summary": "",
                },
            )()

        async def complete_candidate(self, **kwargs):
            self.calls.append(kwargs)
            return type(
                "Candidate",
                (),
                {
                    "id": kwargs["candidate_id"],
                    "status": kwargs["status"],
                    "summary": kwargs.get("summary", ""),
                },
            )()

    class FakeDb:
        def __init__(self):
            self.commits = 0

        async def commit(self):
            self.commits += 1

    svc = object.__new__(WorkflowService)
    svc.repo = FakeRepo()
    svc.engine = FakeEngine()
    svc.db = FakeDb()
    candidate = await WorkflowService.create_candidate_for_node(
        svc,
        workflow_id="wf-1",
        node_id="node-1",
        provider="gongbu",
        summary="执行完成",
    )
    assert candidate.status == "produced"
    assert len(svc.engine.created) == 1
    assert svc.engine.created[0]["node_id"] == "node-1"
    assert len(svc.engine.calls) == 2
    assert svc.engine.calls[0]["status"] == "running"
    assert svc.engine.calls[1]["status"] == "produced"
    assert svc.db.commits == 1


@pytest.mark.asyncio
async def test_workflow_service_upsert_assembly_creates_and_links_current():
    class FakeEngine:
        async def upsert_assembly_for_selected_candidate(self, **kwargs):
            self.kwargs = kwargs
            return type(
                "Assembly",
                (),
                {
                    "id": "asm-1",
                    "workflow_id": kwargs["workflow_id"],
                    "items": [type("Item", (), {"candidate_id": kwargs["candidate_id"]})()],
                },
            )()

    class FakeDb:
        def __init__(self):
            self.commits = 0

        async def commit(self):
            self.commits += 1

    svc = object.__new__(WorkflowService)
    svc.engine = FakeEngine()
    svc.db = FakeDb()
    assembly = await WorkflowService.upsert_assembly_for_selected_candidate(
        svc,
        workflow_id="wf-2",
        node_id="node-1",
        candidate_id="cand-1",
        summary="汇总草稿",
    )
    assert assembly.workflow_id == "wf-2"
    assert len(assembly.items) == 1
    assert assembly.items[0].candidate_id == "cand-1"
    assert svc.engine.kwargs["node_id"] == "node-1"
    assert svc.db.commits == 1


@pytest.mark.asyncio
async def test_workflow_service_upsert_assembly_rejects_stale_revision_node():
    class FakeEngine:
        async def upsert_assembly_for_selected_candidate(self, **kwargs):
            raise ValueError("Node is not in current revision")

    class FakeDb:
        async def commit(self):
            raise AssertionError("should not commit when validation fails")

    svc = object.__new__(WorkflowService)
    svc.engine = FakeEngine()
    svc.db = FakeDb()

    with pytest.raises(ValueError, match="current revision"):
        await WorkflowService.upsert_assembly_for_selected_candidate(
            svc,
            workflow_id="wf-2",
            node_id="node-stale",
            candidate_id="cand-stale",
        )


@pytest.mark.asyncio
async def test_workflow_service_reject_assembly_moves_workflow_back_to_selection():
    class FakeRepo:
        async def get_assembly(self, assembly_id: str):
            return type("Assembly", (), {"id": assembly_id, "status": "rejected"})()

    svc = object.__new__(WorkflowService)
    svc.repo = FakeRepo()

    async def fake_submit_command(**kwargs):
        svc.command_kwargs = kwargs
        return []

    svc.submit_command = fake_submit_command
    result = await WorkflowService.reject_assembly(
        svc,
        workflow_id="wf-3",
        assembly_id="asm-1",
        actor="zhongshu",
        reason="质量不达标",
    )
    assert result.status == "rejected"
    assert svc.command_kwargs["event_type"] == EVENT_REJECT_ASSEMBLY
    assert svc.command_kwargs["payload"]["assembly_id"] == "asm-1"


@pytest.mark.asyncio
async def test_workflow_service_select_candidate_uses_engine_guard():
    class FakeRepo:
        async def load_snapshot(self, workflow_id: str):
            now = datetime.now(timezone.utc)
            return WorkflowSnapshot(
                workflow=WorkflowEntity(
                    id=workflow_id,
                    task_id="JJC-1",
                    type="generic",
                    title="x",
                    goal="x",
                    state="executing",
                    created_at=now,
                    updated_at=now,
                ),
                nodes=[
                    NodeEntity(
                        id="node-1",
                        workflow_id=workflow_id,
                        revision_id="rev-1",
                        kind="work_item",
                        state="approved",
                        title="n1",
                        created_at=now,
                        updated_at=now,
                    )
                ],
                candidates=[
                    CandidateEntity(
                        id="cand-1",
                        workflow_id=workflow_id,
                        node_id="node-1",
                        status="approved",
                        provider="gongbu",
                        created_at=now,
                        updated_at=now,
                    )
                ],
            )

    svc = object.__new__(WorkflowService)
    svc.repo = FakeRepo()

    async def fake_submit_command(**kwargs):
        svc.command_kwargs = kwargs
        return ["ok"]

    svc.submit_command = fake_submit_command
    result = await WorkflowService.select_candidate(
        svc,
        workflow_id="wf-1",
        node_id="node-1",
        candidate_id="cand-1",
        actor="zhongshu",
    )
    assert result["node"].id == "node-1"
    assert result["candidate"].id == "cand-1"
    assert svc.command_kwargs["event_type"] == EVENT_SELECT_CANDIDATE


@pytest.mark.asyncio
async def test_workflow_service_complete_assembly_transitions_via_engine():
    class FakeRepo:
        async def get_assembly(self, assembly_id: str):
            return type("Assembly", (), {"id": assembly_id, "status": "done"})()

    svc = object.__new__(WorkflowService)
    svc.repo = FakeRepo()

    async def fake_submit_command(**kwargs):
        svc.command_kwargs = kwargs
        return []

    svc.submit_command = fake_submit_command

    result = await WorkflowService.complete_assembly(
        svc,
        workflow_id="wf-9",
        assembly_id="asm-1",
        status=WorkflowState.DONE.value,
        actor="zhongshu",
    )
    assert result.id == "asm-1"
    assert svc.command_kwargs["event_type"] == EVENT_APPROVE_ASSEMBLY
    assert svc.command_kwargs["payload"]["assembly_id"] == "asm-1"


def test_workflow_policy_v2_review_actor_guard():
    ensure_review_actor("zhongshu")
    ensure_review_actor("emperor")
    with pytest.raises(PolicyViolation):
        ensure_review_actor("api")


def test_workflow_policy_v2_command_actor_matrix():
    ensure_command_actor(EVENT_NODE_PROGRESS, "gongbu")
    ensure_command_actor(EVENT_COMPLETE_CANDIDATE, "api")
    ensure_command_actor(EVENT_SELECT_CANDIDATE, "zhongshu")
    ensure_command_actor(EVENT_REGENERATE_NODE, "emperor")
    ensure_command_actor(EVENT_APPROVE_ASSEMBLY, "zhongshu")
    ensure_command_actor(EVENT_REJECT_ASSEMBLY, "emperor")
    ensure_command_actor(EVENT_ROLLBACK_WORKFLOW, "zhongshu")
    with pytest.raises(PolicyViolation):
        ensure_command_actor(EVENT_SELECT_CANDIDATE, "gongbu")
    ensure_action_actor("assembly", "approve", "zhongshu")
    with pytest.raises(PolicyViolation):
        ensure_action_actor("assembly", "approve", "gongbu")


def test_workflow_policy_v2_not_done_guard_includes_cancelled():
    now = datetime.now(timezone.utc)
    done_snapshot = WorkflowSnapshot(
        workflow=WorkflowEntity(
            id="wf-done",
            task_id="JJC-D",
            type="generic",
            title="x",
            goal="x",
            state="done",
            created_at=now,
            updated_at=now,
        )
    )
    cancelled_snapshot = WorkflowSnapshot(
        workflow=WorkflowEntity(
            id="wf-cancelled",
            task_id="JJC-C",
            type="generic",
            title="x",
            goal="x",
            state="cancelled",
            created_at=now,
            updated_at=now,
        )
    )
    with pytest.raises(PolicyViolation):
        ensure_not_done(done_snapshot)
    with pytest.raises(PolicyViolation):
        ensure_not_done(cancelled_snapshot)


@pytest.mark.asyncio
async def test_workflow_service_submit_command_dispatches_select_candidate():
    svc = object.__new__(WorkflowService)

    class FakeEngine:
        async def apply_event(self, event):
            self.event = event
            return ["ok"]

    class FakeDb:
        async def commit(self):
            return None

    svc.engine = FakeEngine()
    svc.db = FakeDb()

    actions = await WorkflowService.submit_command(
        svc,
        workflow_id="wf-1",
        event_type=EVENT_SELECT_CANDIDATE,
        producer="flutter",
        payload={"node_id": "node-1", "candidate_id": "cand-1", "actor": "zhongshu"},
    )
    assert actions == ["ok"]
    assert svc.engine.event.event_type == EVENT_SELECT_CANDIDATE
    assert svc.engine.event.payload["workflow_id"] == "wf-1"
    assert svc.engine.event.payload["node_id"] == "node-1"
    assert svc.engine.event.payload["candidate_id"] == "cand-1"


@pytest.mark.asyncio
async def test_workflow_service_submit_command_missing_review_actor_rejected():
    svc = object.__new__(WorkflowService)
    with pytest.raises(PolicyViolation):
        await WorkflowService.submit_command(
            svc,
            workflow_id="wf-1",
            event_type=EVENT_SELECT_CANDIDATE,
            producer="flutter",
            payload={"node_id": "node-1", "candidate_id": "cand-1"},
        )


@pytest.mark.asyncio
async def test_workflow_service_submit_command_rejected_actor_has_no_side_effects():
    class FakeEngine:
        def __init__(self):
            self.apply_called = False

        async def apply_event(self, event):
            self.apply_called = True
            return ["unexpected"]

    class FakeDb:
        def __init__(self):
            self.commit_count = 0

        async def commit(self):
            self.commit_count += 1

    svc = object.__new__(WorkflowService)
    svc.engine = FakeEngine()
    svc.db = FakeDb()

    with pytest.raises(PolicyViolation):
        await WorkflowService.submit_command(
            svc,
            workflow_id="wf-guard",
            event_type=EVENT_SELECT_CANDIDATE,
            producer="flutter",
            payload={"node_id": "node-1", "candidate_id": "cand-1"},
        )

    assert svc.engine.apply_called is False
    assert svc.db.commit_count == 0


@pytest.mark.asyncio
async def test_workflow_service_submit_command_dispatches_node_progress():
    svc = object.__new__(WorkflowService)

    async def fake_add_node_progress(**kwargs):
        svc.progress_kwargs = kwargs
        return type("Node", (), {"id": kwargs["node_id"], "state": kwargs["to_state"]})()

    svc.add_node_progress = fake_add_node_progress

    actions = await WorkflowService.submit_command(
        svc,
        workflow_id="wf-1",
        event_type=EVENT_NODE_PROGRESS,
        producer="flutter",
        payload={"node_id": "node-2", "to_state": "running", "reason": "go"},
    )
    assert actions == []
    assert svc.progress_kwargs["workflow_id"] == "wf-1"
    assert svc.progress_kwargs["node_id"] == "node-2"
    assert svc.progress_kwargs["to_state"] == "running"
    assert svc.progress_kwargs["reason"] == "go"
