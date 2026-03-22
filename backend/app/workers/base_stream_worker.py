"""Base class for Redis Streams consumer workers."""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import uuid
from abc import ABC, abstractmethod

from ..services.event_bus import EventBus

log = logging.getLogger(__name__)


class BaseStreamWorker(ABC):
    """Abstract base for workers that consume events from one or more Redis Streams topics.

    Subclasses only need to define:
      - TOPICS: list[str]  (or override `topics` property)
      - GROUP: str
      - _handle_event(event: dict) -> None

    Optional overrides:
      - CONSUMER_PREFIX: str  (default: "worker")
      - BLOCK_MS: int         (default: 500)
      - BATCH_SIZE: int       (default: 10)
    """

    TOPICS: list[str] = []
    GROUP: str = ""
    CONSUMER_PREFIX: str = "worker"
    BLOCK_MS: int = 500
    BATCH_SIZE: int = 10

    def __init__(
        self,
        *,
        bus: EventBus | None = None,
        session_factory=None,
    ):
        from ..db import async_session as default_session_factory

        self.bus = bus or EventBus()
        self.session_factory = session_factory or default_session_factory
        self._running = False
        self._consumer = f"{self.CONSUMER_PREFIX}-{os.getpid()}-{uuid.uuid4().hex[:6]}"

    @property
    def topics(self) -> list[str]:
        return self.TOPICS

    async def start(self) -> None:
        await self.bus.connect()
        for topic in self.topics:
            await self.bus.ensure_consumer_group(topic, self.GROUP)
        self._running = True
        log.info("%s started (group=%s, topics=%s)", type(self).__name__, self.GROUP, self.topics)
        while self._running:
            await self._poll_cycle()

    async def stop(self) -> None:
        self._running = False
        await self.bus.close()
        log.info("%s stopped", type(self).__name__)

    async def _poll_cycle(self) -> None:
        for topic in self.topics:
            events = await self.bus.consume(
                topic, self.GROUP, self._consumer,
                count=self.BATCH_SIZE, block_ms=self.BLOCK_MS,
            )
            for entry_id, event in events:
                try:
                    await self._handle_event(event)
                    await self.bus.ack(topic, self.GROUP, entry_id)
                except Exception:
                    log.exception("%s failed processing event from %s", type(self).__name__, topic)

    @abstractmethod
    async def _handle_event(self, event: dict) -> None:
        """Process a single event. Subclass must implement."""
        ...


async def run_worker(worker_cls: type[BaseStreamWorker], **kwargs) -> None:
    """Generic entry point to run a stream worker with signal handling."""
    worker = worker_cls(**kwargs)
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(worker.stop()))
    await worker.start()
