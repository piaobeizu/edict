from __future__ import annotations

import pytest

from backend.app.models.workflow_models import WorkflowOutbox
from backend.app.services.outbox_event_bus import OutboxEventBus


class FakeSession:
    def __init__(self):
        self.items = []
        self.flushed = False

    def add(self, item):
        self.items.append(item)

    async def flush(self):
        self.flushed = True


@pytest.mark.asyncio
async def test_outbox_event_bus_writes_pending_row():
    db = FakeSession()
    bus = OutboxEventBus(db)
    event_id = await bus.publish(
        topic="workflow.v2.created",
        trace_id="wf-1",
        event_type="workflow.v2.created",
        producer="tester",
        payload={"workflow_id": "wf-1", "workflow_version": 2},
        meta={"scope": "test"},
    )
    assert event_id
    assert db.flushed is True
    assert len(db.items) == 1
    row = db.items[0]
    assert isinstance(row, WorkflowOutbox)
    assert row.aggregate_id == "wf-1"
    assert row.topic == "workflow.v2.created"
    assert row.status == "pending"
    assert row.headers["producer"] == "tester"
    assert row.headers["meta"]["scope"] == "test"
