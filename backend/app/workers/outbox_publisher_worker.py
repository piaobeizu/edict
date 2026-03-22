"""Publish workflow outbox rows to Redis event bus."""

from __future__ import annotations

import asyncio
import logging
import signal

from sqlalchemy import select

from ..db import async_session
from ..models.workflow_models import WorkflowOutbox
from ..services.event_bus import EventBus

log = logging.getLogger("edict.outbox_publisher")


class OutboxPublisherWorker:
    def __init__(
        self,
        poll_interval_seconds: float = 0.25,
        batch_size: int = 50,
        *,
        bus: EventBus | None = None,
        session_factory=async_session,
    ):
        self.bus = bus or EventBus()
        self.session_factory = session_factory
        self.poll_interval_seconds = poll_interval_seconds
        self.batch_size = batch_size
        self._running = False

    async def start(self):
        await self.bus.connect()
        self._running = True
        while self._running:
            processed = await self._publish_batch()
            if processed == 0:
                await asyncio.sleep(self.poll_interval_seconds)

    async def stop(self):
        self._running = False
        await self.bus.close()

    async def _publish_batch(self) -> int:
        async with self.session_factory() as db:
            rows = await db.execute(
                select(WorkflowOutbox)
                .where(WorkflowOutbox.status == "pending")
                .order_by(WorkflowOutbox.id.asc())
                .limit(self.batch_size)
                .with_for_update(skip_locked=True)
            )
            items = list(rows.scalars().all())
            processed = 0
            for item in items:
                try:
                    item.status = "publishing"
                    await db.flush()
                    headers = dict(item.headers or {})
                    await self.bus.publish(
                        topic=item.topic,
                        trace_id=item.trace_id,
                        event_type=item.event_type,
                        producer=str(headers.get("producer") or "outbox_publisher"),
                        payload=dict(item.payload or {}),
                        meta=dict(headers.get("meta") or {}),
                    )
                    item.status = "published"
                    item.published_at = item.published_at or item.available_at
                    processed += 1
                except Exception as exc:
                    item.retry_count = int(item.retry_count or 0) + 1
                    item.status = "dead_letter" if item.retry_count >= 10 else "pending"
                    item.last_error = str(exc)[:1000]
                    log.exception("failed to publish outbox row id=%s", item.id)
            await db.commit()
            return processed


async def run_outbox_publisher():
    worker = OutboxPublisherWorker()
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(worker.stop()))
    await worker.start()


if __name__ == "__main__":
    asyncio.run(run_outbox_publisher())
