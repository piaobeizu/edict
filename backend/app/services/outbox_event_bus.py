"""EventBusPort adapter that writes workflow events into outbox."""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from ..models.workflow_models import WorkflowOutbox


class OutboxEventBus:
    """Backend adapter for kernel EventBusPort.

    Instead of publishing directly to Redis, workflow v2 writes to the
    `workflow_outbox` table in the current DB transaction.
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    async def publish(
        self,
        topic: str,
        trace_id: str,
        event_type: str,
        producer: str,
        payload: dict[str, Any] | None = None,
        meta: dict[str, Any] | None = None,
    ) -> str:
        event_id = str(uuid.uuid4())
        headers = {
            "producer": producer,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "meta": meta or {},
        }
        aggregate_id = str((payload or {}).get("workflow_id") or trace_id)
        row = WorkflowOutbox(
            aggregate_type="workflow",
            aggregate_id=aggregate_id,
            topic=topic,
            event_type=event_type,
            trace_id=trace_id,
            payload=payload or {},
            headers=headers,
            status="pending",
        )
        self.db.add(row)
        await self.db.flush()
        return event_id

    async def consume(self, *args, **kwargs):
        raise NotImplementedError("OutboxEventBus does not consume")

    async def ack(self, *args, **kwargs):
        raise NotImplementedError("OutboxEventBus does not ack")

    async def claim_stale(self, *args, **kwargs):
        raise NotImplementedError("OutboxEventBus does not claim stale")
