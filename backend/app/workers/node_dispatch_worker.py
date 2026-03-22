"""Workflow v2 node dispatch worker — consumes node dispatched events and writes candidate outputs."""

from __future__ import annotations

import asyncio
import logging

from kernel.workflow_events import TOPIC_WORKFLOW_NODE_DISPATCHED

from ..services.workflow_service import WorkflowService
from .base_stream_worker import BaseStreamWorker, run_worker

log = logging.getLogger("edict.workflow_node_dispatch")

TIMEOUT_SECONDS = 60
MAX_RETRIES = 2


class NodeDispatchWorker(BaseStreamWorker):
    TOPICS = [TOPIC_WORKFLOW_NODE_DISPATCHED]
    GROUP = "workflow-node-dispatch"
    CONSUMER_PREFIX = "wf-node-disp"

    def __init__(self, *, bus=None, session_factory=None, workflow_service_factory=WorkflowService):
        super().__init__(bus=bus, session_factory=session_factory)
        self.workflow_service_factory = workflow_service_factory
        self._processed_keys: set[str] = set()

    async def _handle_event(self, event: dict) -> None:
        payload = event.get("payload", {})
        workflow_id = str(payload.get("workflow_id") or "")
        node_id = str(payload.get("node_id") or "")
        executor_id = str(payload.get("executor_id") or "")
        message = str(payload.get("message") or "")
        dispatch_round = int(payload.get("dispatch_round") or 1)
        if not workflow_id or not node_id:
            return
        dedup_key = f"{workflow_id}:{node_id}:{dispatch_round}"
        if dedup_key in self._processed_keys:
            return
        for attempt in range(1, MAX_RETRIES + 2):
            try:
                await asyncio.wait_for(
                    self._process_once(
                        workflow_id=workflow_id,
                        node_id=node_id,
                        executor_id=executor_id,
                        message=message,
                    ),
                    timeout=TIMEOUT_SECONDS,
                )
                self._processed_keys.add(dedup_key)
                return
            except Exception:
                if attempt > MAX_RETRIES:
                    await self._mark_failed(
                        workflow_id=workflow_id,
                        node_id=node_id,
                        executor_id=executor_id,
                        message=f"node dispatch failed after retries: {message}",
                    )
                    return
                await asyncio.sleep(min(2 ** (attempt - 1), 4))

    async def _process_once(self, *, workflow_id: str, node_id: str, executor_id: str, message: str) -> None:
        candidate_summary = self._candidate_summary_from_message(message)
        async with self.session_factory() as db:
            svc = self.workflow_service_factory(db)
            await svc.create_candidate_for_node(
                workflow_id=workflow_id,
                node_id=node_id,
                provider=executor_id or "node_dispatch_worker",
                summary=candidate_summary,
                producer="node_dispatch_worker",
            )
            await svc.add_node_progress(
                workflow_id=workflow_id,
                node_id=node_id,
                to_state="produced",
                reason="node dispatched and candidate produced",
                executor_id=executor_id or "node_dispatch_worker",
                message=message,
                producer="node_dispatch_worker",
            )

    @staticmethod
    def _candidate_summary_from_message(message: str) -> str:
        normalized = (message or "").strip()
        if not normalized:
            return "candidate produced"
        lowered = normalized.lower()
        if lowered in {"node is running", "node dispatched"}:
            return "candidate produced"
        return normalized

    async def _mark_failed(self, *, workflow_id: str, node_id: str, executor_id: str, message: str) -> None:
        async with self.session_factory() as db:
            svc = self.workflow_service_factory(db)
            await svc.add_node_progress(
                workflow_id=workflow_id,
                node_id=node_id,
                to_state="failed",
                reason=message or "node dispatch failed",
                executor_id=executor_id or "node_dispatch_worker",
                message=message,
                producer="node_dispatch_worker",
            )


async def run_node_dispatch_worker():
    await run_worker(NodeDispatchWorker)
