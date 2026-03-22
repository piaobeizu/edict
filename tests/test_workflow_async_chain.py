from __future__ import annotations

from contextlib import asynccontextmanager
import pytest

from kernel.graph_entities import WorkflowEntity
from kernel.graph_workflow import GraphWorkflowEngine

from backend.app.services.outbox_event_bus import OutboxEventBus
from backend.app.services.workflow_policy import MinimalWorkflowPolicy
from backend.app.services.workflow_guards import EVENT_START_PLANNING
from backend.app.workers.outbox_publisher_worker import OutboxPublisherWorker
from backend.app.workers.projection_worker import ProjectionWorker
from tests.helpers import InMemoryWorkflowRepo


class FakeOutboxSession:
    def __init__(self):
        self.items = []
        self.flushed = 0

    def add(self, item):
        self.items.append(item)

    async def flush(self):
        self.flushed += 1


class FakeOutboxRows:
    def __init__(self, items):
        self._items = items

    def scalars(self):
        return self

    def all(self):
        return list(self._items)


class FakePublishDb:
    def __init__(self, items):
        self.items = items
        self.committed = 0

    async def execute(self, stmt):
        return FakeOutboxRows([item for item in self.items if getattr(item, "status", "") == "pending"])

    async def flush(self):
        return None

    async def commit(self):
        self.committed += 1


def session_factory_for(db):
    @asynccontextmanager
    async def _factory():
        yield db

    return _factory


class QueueBus:
    def __init__(self):
        self.events = []

    async def connect(self):
        return None

    async def close(self):
        return None

    async def publish(self, topic, trace_id, event_type, producer, payload=None, meta=None):
        self.events.append(
            {
                "topic": topic,
                "trace_id": trace_id,
                "event_type": event_type,
                "producer": producer,
                "payload": payload or {},
                "meta": meta or {},
            }
        )
        return f"evt-{len(self.events)}"

    async def ensure_consumer_group(self, *args, **kwargs):
        return None

    async def consume(self, topic, group, consumer, count=10, block_ms=5000):
        matched = []
        remain = []
        for item in self.events:
            if item["topic"] == topic and len(matched) < count:
                matched.append((f"id-{len(matched)+1}", item))
            else:
                remain.append(item)
        self.events = remain
        return matched

    async def ack(self, *args, **kwargs):
        return None


@pytest.mark.asyncio
async def test_minimal_async_chain_engine_outbox_publish_projection():
    repo = InMemoryWorkflowRepo()
    outbox_session = FakeOutboxSession()
    engine = GraphWorkflowEngine(
        repo=repo,
        bus=OutboxEventBus(outbox_session),
        policy=MinimalWorkflowPolicy(),
        projection=None,
    )
    workflow = await engine.create_workflow(title="异步链路", goal="测试", workflow_type="generic", owner="tester")
    await engine.apply_event(
        event=type(
            "Evt",
            (),
            {
                "topic": "workflow.v2.command",
                "event_type": EVENT_START_PLANNING,
                "trace_id": workflow.id,
                "producer": "api",
                "payload": {"workflow_id": workflow.id, "workflow_version": 2, "content": "plan"},
            },
        )()
    )

    assert len(outbox_session.items) >= 2
    assert all(item.status == "pending" for item in outbox_session.items)

    queue_bus = QueueBus()
    publish_db = FakePublishDb(outbox_session.items)
    publisher = OutboxPublisherWorker(bus=queue_bus, session_factory=session_factory_for(publish_db))
    processed = await publisher._publish_batch()
    assert processed >= 2
    assert any(item.status == "published" for item in outbox_session.items)

    refreshed = []

    class FakeProjectionService:
        def __init__(self, db, workflow_repo):
            self.db = db
            self.workflow_repo = workflow_repo

        async def refresh_workflow_projection(self, workflow_id: str):
            snapshot = await self.workflow_repo.load_snapshot(workflow_id)
            refreshed.append((workflow_id, snapshot.workflow.state))

    projection_db = type(
        "ProjectionDb",
        (),
        {
            "commit": lambda self: None,
        },
    )()

    @asynccontextmanager
    async def projection_session_factory():
        class _Db:
            async def commit(self):
                return None

        yield _Db()

    class FakeWorkflowRepoFactory:
        def __init__(self, db):
            self.db = db

        async def load_snapshot(self, workflow_id: str):
            return await repo.load_snapshot(workflow_id)

    worker = ProjectionWorker(
        bus=queue_bus,
        session_factory=projection_session_factory,
        workflow_repo_factory=FakeWorkflowRepoFactory,
        projection_service_factory=FakeProjectionService,
    )
    await worker._poll_cycle()
    assert refreshed
    assert refreshed[-1][0] == workflow.id


@pytest.mark.asyncio
async def test_async_chain_command_stays_pending_before_publish_then_becomes_published():
    repo = InMemoryWorkflowRepo()
    outbox_session = FakeOutboxSession()
    engine = GraphWorkflowEngine(
        repo=repo,
        bus=OutboxEventBus(outbox_session),
        policy=MinimalWorkflowPolicy(),
        projection=None,
    )
    workflow = await engine.create_workflow(
        title="pending-observable",
        goal="observe outbox pending",
        workflow_type="generic",
        owner="tester",
    )
    await engine.apply_event(
        event=type(
            "Evt",
            (),
            {
                "topic": "workflow.v2.command",
                "event_type": EVENT_START_PLANNING,
                "trace_id": workflow.id,
                "producer": "api",
                "payload": {"workflow_id": workflow.id, "workflow_version": 2, "content": "plan"},
            },
        )()
    )

    pending_before_publish = [item for item in outbox_session.items if getattr(item, "status", "") == "pending"]
    assert pending_before_publish, "outbox should remain pending before publisher worker runs"

    queue_bus = QueueBus()
    publish_db = FakePublishDb(outbox_session.items)
    publisher = OutboxPublisherWorker(
        bus=queue_bus,
        session_factory=session_factory_for(publish_db),
    )
    processed = await publisher._publish_batch()

    assert processed >= 1
    pending_after_publish = [item for item in outbox_session.items if getattr(item, "status", "") == "pending"]
    assert len(pending_after_publish) < len(pending_before_publish)
    assert any(getattr(item, "status", "") == "published" for item in outbox_session.items)
