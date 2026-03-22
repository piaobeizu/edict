"""Run workflow-v2 workers inside backend process."""

from __future__ import annotations

import asyncio
import logging

from .assembly_worker import AssemblyWorker
from .node_dispatch_worker import NodeDispatchWorker
from .outbox_publisher_worker import OutboxPublisherWorker
from .projection_worker import ProjectionWorker
from .workflow_orchestrator_worker import WorkflowOrchestratorWorker

log = logging.getLogger("edict.workflow_inprocess")


class InProcessWorkflowWorkers:
    def __init__(self):
        self._workers = [
            ("workflow_orchestrator", WorkflowOrchestratorWorker()),
            ("node_dispatch", NodeDispatchWorker()),
            ("assembly", AssemblyWorker()),
            ("projection", ProjectionWorker()),
            ("outbox_publisher", OutboxPublisherWorker()),
        ]
        self._tasks: list[asyncio.Task] = []

    async def start(self) -> None:
        for name, worker in self._workers:
            task = asyncio.create_task(worker.start(), name=f"worker:{name}")
            task.add_done_callback(self._done_callback)
            self._tasks.append(task)
        log.info("started in-process workflow workers: %s", ", ".join(name for name, _ in self._workers))

    async def stop(self) -> None:
        for _, worker in self._workers:
            await worker.stop()
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
            self._tasks.clear()
        log.info("stopped in-process workflow workers")

    @staticmethod
    def _done_callback(task: asyncio.Task) -> None:
        if task.cancelled():
            return
        err = task.exception()
        if err:
            log.exception("in-process workflow worker exited with error", exc_info=err)
