"""Workflow v2 assembly worker — maintains assembly records on candidate selection."""

from __future__ import annotations

import asyncio
import logging

from kernel.workflow_events import TOPIC_WORKFLOW_CANDIDATE_SELECTED

from ..services.workflow_service import WorkflowService
from .base_stream_worker import BaseStreamWorker, run_worker

log = logging.getLogger("edict.workflow_assembly")

# 补偿检查间隔（秒）
_COMPENSATE_INTERVAL = 30


class AssemblyWorker(BaseStreamWorker):
    TOPICS = [TOPIC_WORKFLOW_CANDIDATE_SELECTED]
    GROUP = "workflow-assembly"
    CONSUMER_PREFIX = "wf-asm"

    def __init__(self, *, bus=None, session_factory=None, workflow_service_factory=WorkflowService):
        super().__init__(bus=bus, session_factory=session_factory)
        self.workflow_service_factory = workflow_service_factory
        self._compensate_task: asyncio.Task | None = None

    async def start(self) -> None:
        self._compensate_task = asyncio.create_task(
            self._compensate_loop(), name="assembly-compensate"
        )
        await super().start()

    async def stop(self) -> None:
        if self._compensate_task and not self._compensate_task.done():
            self._compensate_task.cancel()
            try:
                await self._compensate_task
            except (asyncio.CancelledError, Exception):
                pass
        await super().stop()

    async def _handle_event(self, event: dict) -> None:
        payload = event.get("payload", {})
        workflow_id = str(payload.get("workflow_id") or "")
        node_id = str(payload.get("node_id") or "")
        candidate_id = str(payload.get("candidate_id") or "")
        summary = str(payload.get("summary") or "")
        if not workflow_id or not node_id or not candidate_id:
            return
        async with self.session_factory() as db:
            svc = self.workflow_service_factory(db)
            await svc.upsert_assembly_for_selected_candidate(
                workflow_id=workflow_id,
                node_id=node_id,
                candidate_id=candidate_id,
                summary=summary,
            )

    async def _compensate_loop(self) -> None:
        """定时检查: 如果有 node 已经 selected candidate 但 workflow 仍卡在 executing/awaiting_selection，
        则触发补偿创建 assembly 并推进到 awaiting_final_review。"""
        while True:
            try:
                await asyncio.sleep(_COMPENSATE_INTERVAL)
                await self._run_compensate()
            except asyncio.CancelledError:
                return
            except Exception:
                log.exception("assembly compensate check failed")

    async def _run_compensate(self) -> None:
        from sqlalchemy import select as sa_select
        from ..models.workflow_models import WorkflowInstance, WorkflowNode

        async with self.session_factory() as db:
            # 查找处于 executing / awaiting_selection 状态的 workflow
            result = await db.execute(
                sa_select(WorkflowInstance).where(
                    WorkflowInstance.state.in_(["executing", "awaiting_selection"])
                )
            )
            workflows = list(result.scalars().all())
            for wf in workflows:
                try:
                    # 检查该 workflow 是否有 selected_candidate_id 但没有 assembly
                    node_result = await db.execute(
                        sa_select(WorkflowNode).where(
                            WorkflowNode.workflow_id == wf.id,
                            WorkflowNode.selected_candidate_id.isnot(None),
                            WorkflowNode.selected_candidate_id != "",
                        )
                    )
                    nodes_with_selection = list(node_result.scalars().all())
                    if not nodes_with_selection:
                        continue
                    if wf.current_assembly_id:
                        continue
                    # 有 selected candidate 但没有 assembly —— 需要补偿
                    node = nodes_with_selection[0]
                    log.warning(
                        "assembly compensate: workflow=%s node=%s candidate=%s — creating assembly",
                        wf.id, node.id, node.selected_candidate_id,
                    )
                    svc = self.workflow_service_factory(db)
                    await svc.upsert_assembly_for_selected_candidate(
                        workflow_id=wf.id,
                        node_id=node.id,
                        candidate_id=node.selected_candidate_id,
                    )
                except Exception:
                    log.exception("assembly compensate failed for workflow=%s", wf.id)


async def run_assembly_worker():
    await run_worker(AssemblyWorker)
