"""Minimal projection worker for workflow v2."""

from __future__ import annotations

import logging

from ..services.task_projection_service import TaskProjectionService
from ..repos.workflow_repo import WorkflowRepo
from .base_stream_worker import BaseStreamWorker, run_worker

log = logging.getLogger("edict.projection")

WATCHED_TOPICS = [
    "workflow.v2.created",
    "workflow.v2.state.changed",
    "workflow.v2.revision.created",
    "workflow.v2.node.created",
    "workflow.v2.node.dispatched",
    "workflow.v2.node.state.changed",
    "workflow.v2.candidate.created",
    "workflow.v2.candidate.updated",
    "workflow.v2.candidate.selected",
    "workflow.v2.assembly.created",
    "workflow.v2.assembly.updated",
    "workflow.v2.rollback",
]


class ProjectionWorker(BaseStreamWorker):
    TOPICS = WATCHED_TOPICS
    GROUP = "projection"
    CONSUMER_PREFIX = "proj"
    BLOCK_MS = 200

    def __init__(
        self,
        *,
        bus=None,
        session_factory=None,
        workflow_repo_factory=WorkflowRepo,
        projection_service_factory=TaskProjectionService,
    ):
        super().__init__(bus=bus, session_factory=session_factory)
        self.workflow_repo_factory = workflow_repo_factory
        self.projection_service_factory = projection_service_factory

    async def _handle_event(self, event: dict) -> None:
        payload = event.get("payload", {})
        workflow_id = str(payload.get("workflow_id") or "")
        if not workflow_id:
            return
        async with self.session_factory() as db:
            repo = self.workflow_repo_factory(db)
            projection = self.projection_service_factory(db, repo)
            await projection.refresh_workflow_projection(workflow_id)
            await db.commit()


async def run_projection_worker():
    await run_worker(ProjectionWorker)
