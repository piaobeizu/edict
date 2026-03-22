from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from types import SimpleNamespace

import pytest

from backend.app.workers.outbox_publisher_worker import OutboxPublisherWorker
from backend.app.workers.projection_worker import ProjectionWorker
from backend.app.workers.workflow_orchestrator_worker import WorkflowOrchestratorWorker
from backend.app.workers.node_dispatch_worker import NodeDispatchWorker
from backend.app.workers.assembly_worker import AssemblyWorker
from backend.app.services.workflow_guards import EVENT_START_PLANNING
from backend.app.services.workflow_service import WorkflowService


class FakeBus:
    def __init__(self):
        self.published = []

    async def connect(self):
        return None

    async def close(self):
        return None

    async def publish(self, topic, trace_id, event_type, producer, payload=None, meta=None):
        self.published.append(
            {
                "topic": topic,
                "trace_id": trace_id,
                "event_type": event_type,
                "producer": producer,
                "payload": payload or {},
                "meta": meta or {},
            }
        )
        return "evt-1"

    async def ensure_consumer_group(self, *args, **kwargs):
        return None

    async def consume(self, *args, **kwargs):
        return []

    async def ack(self, *args, **kwargs):
        return None


class FakeRows:
    def __init__(self, items):
        self._items = items

    def scalars(self):
        return self

    def all(self):
        return list(self._items)


class FakeDb:
    def __init__(self, rows=None):
        self.rows = rows or []
        self.flushed = 0
        self.committed = 0

    async def execute(self, stmt):
        return FakeRows(self.rows)

    async def flush(self):
        self.flushed += 1

    async def commit(self):
        self.committed += 1


def session_factory_for(db):
    @asynccontextmanager
    async def _factory():
        yield db

    return _factory


@pytest.mark.asyncio
async def test_outbox_publisher_worker_marks_row_published():
    row = SimpleNamespace(
        id=1,
        status="pending",
        topic="workflow.v2.created",
        trace_id="wf-1",
        event_type="workflow.v2.created",
        payload={"workflow_id": "wf-1", "workflow_version": 2},
        headers={"producer": "tester", "meta": {"scope": "test"}},
        retry_count=0,
        available_at="2026-03-18T00:00:00Z",
        published_at=None,
        last_error="",
    )
    db = FakeDb(rows=[row])
    bus = FakeBus()
    worker = OutboxPublisherWorker(bus=bus, session_factory=session_factory_for(db))
    processed = await worker._publish_batch()
    assert processed == 1
    assert row.status == "published"
    assert row.published_at == row.available_at
    assert len(bus.published) == 1
    assert bus.published[0]["topic"] == "workflow.v2.created"


@pytest.mark.asyncio
async def test_projection_worker_handles_workflow_event():
    refreshed = []

    class FakeRepo:
        def __init__(self, db):
            self.db = db

    class FakeProjectionService:
        def __init__(self, db, repo):
            self.db = db
            self.repo = repo

        async def refresh_workflow_projection(self, workflow_id: str):
            refreshed.append(workflow_id)

    db = FakeDb()
    worker = ProjectionWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_repo_factory=FakeRepo,
        projection_service_factory=FakeProjectionService,
    )
    await worker._handle_event({"payload": {"workflow_id": "wf-1", "workflow_version": 2}})
    assert refreshed == ["wf-1"]
    assert db.committed == 1


@pytest.mark.asyncio
async def test_workflow_orchestrator_worker_delegates_command():
    called = []

    class FakeWorkflowService:
        def __init__(self, db):
            self.db = db

        async def submit_command(self, *, workflow_id, event_type, producer="api", payload=None):
            called.append(
                {
                    "workflow_id": workflow_id,
                    "event_type": event_type,
                    "producer": producer,
                    "payload": payload or {},
                }
            )

    db = FakeDb()
    worker = WorkflowOrchestratorWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_service_factory=FakeWorkflowService,
    )
    await worker._handle_event(
        {
            "event_type": EVENT_START_PLANNING,
            "producer": "api",
            "payload": {"workflow_id": "wf-1", "workflow_version": 2, "content": "hello"},
        }
    )
    assert called == [
        {
            "workflow_id": "wf-1",
            "event_type": EVENT_START_PLANNING,
            "producer": "api",
            "payload": {"workflow_id": "wf-1", "workflow_version": 2, "content": "hello"},
        }
    ]


@pytest.mark.asyncio
async def test_workflow_orchestrator_worker_integration_uses_real_submit_command():
    class FakeEngine:
        async def apply_event(self, event):
            self.event = event
            return ["ok"]

    class FakeDbForService:
        def __init__(self):
            self.commits = 0

        async def commit(self):
            self.commits += 1

    svc = object.__new__(WorkflowService)
    svc.engine = FakeEngine()
    svc.db = FakeDbForService()

    class ServiceFactory:
        def __init__(self, db):
            self.db = db

        async def submit_command(self, **kwargs):
            return await WorkflowService.submit_command(svc, **kwargs)

    db = FakeDb()
    worker = WorkflowOrchestratorWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_service_factory=ServiceFactory,
    )
    await worker._handle_event(
        {
            "event_type": EVENT_START_PLANNING,
            "producer": "api",
            "payload": {"workflow_id": "wf-9", "workflow_version": 2, "content": "hello"},
        }
    )
    assert svc.engine.event.event_type == EVENT_START_PLANNING
    assert svc.engine.event.payload["workflow_id"] == "wf-9"
    assert svc.db.commits == 1


@pytest.mark.asyncio
async def test_workflow_orchestrator_worker_start_consumes_and_acks_with_real_submit_command():
    class ConsumableBus(FakeBus):
        def __init__(self):
            super().__init__()
            self.ensure_calls = []
            self.consume_calls = 0
            self.acked = []
            self.closed = False

        async def ensure_consumer_group(self, topic, group):
            self.ensure_calls.append((topic, group))

        async def consume(self, *args, **kwargs):
            self.consume_calls += 1
            if self.consume_calls == 1:
                return [
                    (
                        "entry-1",
                        {
                            "event_type": EVENT_START_PLANNING,
                            "producer": "api",
                            "payload": {
                                "workflow_id": "wf-10",
                                "workflow_version": 2,
                                "content": "hello",
                            },
                        },
                    )
                ]
            await asyncio.sleep(0.01)
            return []

        async def ack(self, topic, group, entry_id):
            self.acked.append((topic, group, entry_id))

        async def close(self):
            self.closed = True

    class FakeEngine:
        async def apply_event(self, event):
            self.event = event
            return ["ok"]

    class FakeDbForService:
        def __init__(self):
            self.commits = 0

        async def commit(self):
            self.commits += 1

    svc = object.__new__(WorkflowService)
    svc.engine = FakeEngine()
    svc.db = FakeDbForService()

    class ServiceFactory:
        def __init__(self, db):
            self.db = db

        async def submit_command(self, **kwargs):
            return await WorkflowService.submit_command(svc, **kwargs)

    bus = ConsumableBus()
    worker = WorkflowOrchestratorWorker(
        bus=bus,
        session_factory=session_factory_for(FakeDb()),
        workflow_service_factory=ServiceFactory,
    )

    task = asyncio.create_task(worker.start())
    for _ in range(20):
        if bus.acked:
            break
        await asyncio.sleep(0.01)
    await worker.stop()
    await task

    assert bus.ensure_calls, "consumer group should be initialized"
    assert bus.acked == [("workflow.v2.command", "workflow-orchestrator", "entry-1")]
    assert svc.engine.event.event_type == EVENT_START_PLANNING
    assert svc.engine.event.payload["workflow_id"] == "wf-10"
    assert svc.db.commits == 1
    assert bus.closed is True


@pytest.mark.asyncio
async def test_node_dispatch_worker_creates_candidate_and_updates_node_state():
    called = []

    class FakeWorkflowService:
        def __init__(self, db):
            self.db = db

        async def create_candidate_for_node(self, **kwargs):
            called.append(("create_candidate_for_node", kwargs))

        async def add_node_progress(self, **kwargs):
            called.append(("add_node_progress", kwargs))

    db = FakeDb()
    worker = NodeDispatchWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_service_factory=FakeWorkflowService,
    )
    await worker._handle_event(
        {
            "payload": {
                "workflow_id": "wf-1",
                "node_id": "node-1",
                "executor_id": "gongbu",
                "message": "候选已产出",
            }
        }
    )
    assert called[0][0] == "create_candidate_for_node"
    assert called[0][1]["workflow_id"] == "wf-1"
    assert called[0][1]["summary"] == "候选已产出"
    assert called[1][0] == "add_node_progress"
    assert called[1][1]["to_state"] == "produced"


@pytest.mark.asyncio
async def test_node_dispatch_worker_normalizes_placeholder_summary():
    called = []

    class FakeWorkflowService:
        def __init__(self, db):
            self.db = db

        async def create_candidate_for_node(self, **kwargs):
            called.append(("create_candidate_for_node", kwargs))

        async def add_node_progress(self, **kwargs):
            called.append(("add_node_progress", kwargs))

    db = FakeDb()
    worker = NodeDispatchWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_service_factory=FakeWorkflowService,
    )
    await worker._handle_event(
        {
            "payload": {
                "workflow_id": "wf-1",
                "node_id": "node-1",
                "executor_id": "gongbu",
                "message": "node is running",
            }
        }
    )
    assert called[0][0] == "create_candidate_for_node"
    assert called[0][1]["summary"] == "candidate produced"
    assert called[1][0] == "add_node_progress"
    assert called[1][1]["to_state"] == "produced"


@pytest.mark.asyncio
async def test_assembly_worker_upserts_assembly_from_selected_candidate():
    called = []

    class FakeWorkflowService:
        def __init__(self, db):
            self.db = db

        async def upsert_assembly_for_selected_candidate(self, **kwargs):
            called.append(kwargs)

    db = FakeDb()
    worker = AssemblyWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_service_factory=FakeWorkflowService,
    )
    await worker._handle_event(
        {
            "payload": {
                "workflow_id": "wf-1",
                "node_id": "node-1",
                "candidate_id": "cand-1",
                "summary": "汇总草稿",
            }
        }
    )
    assert len(called) == 1
    assert called[0]["workflow_id"] == "wf-1"
    assert called[0]["candidate_id"] == "cand-1"


@pytest.mark.asyncio
async def test_node_dispatch_worker_retries_then_marks_failed():
    called = []

    class FakeWorkflowService:
        def __init__(self, db):
            self.db = db

        async def create_candidate_for_node(self, **kwargs):
            called.append(("create_candidate_for_node", kwargs))
            raise RuntimeError("boom")

        async def add_node_progress(self, **kwargs):
            called.append(("add_node_progress", kwargs))

    db = FakeDb()
    worker = NodeDispatchWorker(
        bus=FakeBus(),
        session_factory=session_factory_for(db),
        workflow_service_factory=FakeWorkflowService,
    )
    await worker._handle_event(
        {
            "payload": {
                "workflow_id": "wf-1",
                "node_id": "node-1",
                "executor_id": "gongbu",
                "message": "候选失败",
                "dispatch_round": 1,
            }
        }
    )
    create_calls = [item for item in called if item[0] == "create_candidate_for_node"]
    failed_calls = [item for item in called if item[0] == "add_node_progress"]
    assert len(create_calls) == 3
    assert len(failed_calls) == 1
    assert failed_calls[0][1]["to_state"] == "failed"
