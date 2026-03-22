"""Minimal workflow v2 orchestrator worker."""

from __future__ import annotations

import logging

from ..services.workflow_guards import TOPIC_WORKFLOW_COMMAND
from ..services.workflow_service import WorkflowService
from .base_stream_worker import BaseStreamWorker, run_worker

log = logging.getLogger("edict.workflow_orchestrator")


class WorkflowOrchestratorWorker(BaseStreamWorker):
    TOPICS = [TOPIC_WORKFLOW_COMMAND]
    GROUP = "workflow-orchestrator"
    CONSUMER_PREFIX = "wf-orch"

    def __init__(self, *, bus=None, session_factory=None, workflow_service_factory=WorkflowService):
        super().__init__(bus=bus, session_factory=session_factory)
        self.workflow_service_factory = workflow_service_factory

    async def _handle_event(self, event: dict) -> None:
        payload = event.get("payload", {})
        workflow_id = str(payload.get("workflow_id") or "")
        event_type = str(event.get("event_type") or "")
        if not workflow_id or not event_type:
            return
        async with self.session_factory() as db:
            svc = self.workflow_service_factory(db)
            await svc.submit_command(
                workflow_id=workflow_id,
                event_type=event_type,
                producer=str(event.get("producer") or "workflow-worker"),
                payload=payload,
            )


async def run_workflow_orchestrator():
    await run_worker(WorkflowOrchestratorWorker)
