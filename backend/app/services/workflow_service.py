"""Workflow v2 service layer for the minimal spike."""

from __future__ import annotations

from kernel.graph_entities import ArtifactRef
from sqlalchemy.ext.asyncio import AsyncSession

from kernel.graph_workflow import GraphWorkflowEngine
from kernel.workflow_events import WorkflowEvent

from ..repos.workflow_repo import WorkflowRepo
from .outbox_event_bus import OutboxEventBus
from .workflow_guards import (
    EVENT_APPROVE_PLAN,
    EVENT_APPROVE_ASSEMBLY,
    EVENT_COMPLETE_CANDIDATE,
    EVENT_NODE_PROGRESS,
    EVENT_REJECT_PLAN,
    EVENT_REGENERATE_NODE,
    EVENT_REJECT_ASSEMBLY,
    EVENT_ROLLBACK_WORKFLOW,
    EVENT_SELECT_CANDIDATE,
)
from .workflow_policy import MinimalWorkflowPolicy
from .workflow_guards import (
    ensure_action_actor,
    ensure_candidate_limit,
    ensure_command_actor,
    ensure_regenerate_allowed,
)


class WorkflowService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = WorkflowRepo(db)
        self.outbox_bus = OutboxEventBus(db)
        self.policy = MinimalWorkflowPolicy()
        self.engine = GraphWorkflowEngine(
            repo=self.repo,
            bus=self.outbox_bus,
            policy=self.policy,
            projection=None,
        )

    async def create_workflow(
        self,
        *,
        title: str,
        goal: str = "",
        workflow_type: str = "generic",
        owner: str = "",
        meta: dict | None = None,
    ):
        workflow = await self.engine.create_workflow(
            title=title,
            goal=goal,
            workflow_type=workflow_type,
            owner=owner,
            meta=meta or {},
        )
        await self.db.commit()
        return workflow

    async def get_workflow(self, workflow_id: str):
        return await self.repo.get_workflow(workflow_id)

    async def get_snapshot(self, workflow_id: str):
        return await self.repo.load_snapshot(workflow_id, include_decisions=True)

    async def get_timeline(self, workflow_id: str) -> list[dict]:
        snapshot = await self.repo.load_snapshot(workflow_id, include_decisions=True)
        timeline: list[dict] = []
        for revision in snapshot.revisions:
            timeline.append(
                {
                    "kind": "revision",
                    "at": revision.updated_at.isoformat() if revision.updated_at else "",
                    "id": revision.id,
                    "number": revision.number,
                    "status": revision.status,
                    "actor": revision.created_by,
                    "text": revision.change_summary or revision.content[:200],
                }
            )
        for node in snapshot.nodes:
            timeline.append(
                {
                    "kind": "node",
                    "at": node.updated_at.isoformat() if node.updated_at else "",
                    "id": node.id,
                    "state": node.state,
                    "title": node.title,
                    "actor": node.assignee,
                    "text": f"{node.title}: {node.state}",
                }
            )
        for decision in snapshot.decisions:
            timeline.append(
                {
                    "kind": "decision",
                    "at": decision.created_at.isoformat() if decision.created_at else "",
                    "id": decision.id,
                    "targetType": decision.target_type,
                    "targetId": decision.target_id,
                    "action": decision.action,
                    "actor": decision.actor,
                    "text": decision.comment or decision.action,
                }
            )
        for assembly in snapshot.assemblies:
            timeline.append(
                {
                    "kind": "assembly",
                    "at": assembly.updated_at.isoformat() if assembly.updated_at else "",
                    "id": assembly.id,
                    "status": assembly.status,
                    "text": assembly.summary,
                    "artifacts": [
                        {
                            "kind": artifact.kind,
                            "path": artifact.path,
                            "mime": artifact.mime,
                            "previewUrl": artifact.preview_url,
                        }
                        for artifact in assembly.artifacts
                    ],
                }
            )
        timeline.sort(key=lambda item: item.get("at", ""))
        return timeline

    async def submit_command(
        self,
        *,
        workflow_id: str,
        event_type: str,
        producer: str = "api",
        payload: dict | None = None,
    ):
        command_payload = dict(payload or {})
        review_guarded_events = {
            EVENT_APPROVE_PLAN,
            EVENT_REJECT_PLAN,
            EVENT_SELECT_CANDIDATE,
            EVENT_REGENERATE_NODE,
            EVENT_APPROVE_ASSEMBLY,
            EVENT_REJECT_ASSEMBLY,
            EVENT_ROLLBACK_WORKFLOW,
        }
        fallback_actor = str(producer or "api")
        command_actor = str(command_payload.get("actor") or fallback_actor)
        ensure_command_actor(event_type, command_actor)
        if event_type == EVENT_NODE_PROGRESS:
            await self.add_node_progress(
                workflow_id=workflow_id,
                node_id=str(command_payload.get("node_id") or ""),
                to_state=str(command_payload.get("to_state") or ""),
                reason=str(command_payload.get("reason") or ""),
                executor_id=str(command_payload.get("executor_id") or ""),
                message=str(command_payload.get("message") or ""),
                producer=producer,
            )
            return []
        if event_type == EVENT_COMPLETE_CANDIDATE:
            metrics = command_payload.get("metrics")
            artifacts = command_payload.get("artifacts")
            meta = command_payload.get("meta")
            await self.complete_candidate(
                workflow_id=workflow_id,
                candidate_id=str(command_payload.get("candidate_id") or ""),
                status=str(command_payload.get("status") or ""),
                summary=str(command_payload.get("summary") or ""),
                score=command_payload.get("score"),
                metrics=dict(metrics) if isinstance(metrics, dict) else None,
                artifacts=list(artifacts) if isinstance(artifacts, list) else None,
                meta=dict(meta) if isinstance(meta, dict) else None,
                producer=producer,
            )
            return []
        if event_type == EVENT_REGENERATE_NODE:
            await self.submit_decision(
                workflow_id=workflow_id,
                target_type="node",
                target_id=str(command_payload.get("node_id") or ""),
                action="regenerate",
                actor=command_actor,
                comment=str(command_payload.get("comment") or ""),
                payload={},
                producer=producer,
            )
            return []
        event = WorkflowEvent(
            topic="workflow.v2.command",
            event_type=event_type,
            trace_id=workflow_id,
            producer=producer,
            payload={"workflow_id": workflow_id, "workflow_version": 2, **(payload or {})},
        )
        actions = await self.engine.apply_event(event)
        await self.db.commit()
        return actions

    async def list_candidates(self, workflow_id: str, node_id: str | None = None):
        if node_id:
            return await self.repo.list_candidates_for_node(node_id)
        return await self.repo.list_candidates(workflow_id)

    async def list_assemblies(self, workflow_id: str):
        return await self.repo.list_assemblies(workflow_id)

    async def add_node_progress(
        self,
        *,
        workflow_id: str,
        node_id: str,
        to_state: str,
        reason: str = "",
        executor_id: str = "",
        message: str = "",
        producer: str = "api",
    ):
        node = await self.engine.add_node_progress(
            workflow_id=workflow_id,
            node_id=node_id,
            to_state=to_state,
            reason=reason,
            executor_id=executor_id,
            message=message,
            producer=producer,
        )
        await self.db.commit()
        return node

    async def complete_candidate(
        self,
        *,
        workflow_id: str,
        candidate_id: str,
        status: str,
        summary: str = "",
        score: float | None = None,
        metrics: dict | None = None,
        artifacts: list[dict] | None = None,
        meta: dict | None = None,
        producer: str = "api",
    ):
        artifact_entities = [
            ArtifactRef(
                kind=str(item.get("kind") or ""),
                path=str(item.get("path") or ""),
                mime=str(item.get("mime") or ""),
                preview_url=str(item.get("previewUrl") or ""),
                metadata=dict(item.get("metadata") or {}),
            )
            for item in (artifacts or [])
        ]
        candidate = await self.engine.complete_candidate(
            workflow_id=workflow_id,
            candidate_id=candidate_id,
            status=status,
            summary=summary,
            score=score,
            metrics=metrics,
            artifacts=artifact_entities,
            meta=meta,
            producer=producer,
        )
        await self.db.commit()
        return candidate

    async def select_candidate(
        self,
        *,
        workflow_id: str,
        node_id: str,
        candidate_id: str,
        actor: str = "api",
        comment: str = "",
        producer: str = "api",
    ):
        ensure_action_actor("candidate", "select", actor)
        await self.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_SELECT_CANDIDATE,
            producer=producer,
            payload={
                "node_id": node_id,
                "candidate_id": candidate_id,
                "actor": actor,
                "comment": comment,
            },
        )
        snapshot = await self.repo.load_snapshot(workflow_id)
        node = next((item for item in snapshot.nodes if item.id == node_id), None)
        candidate = next((item for item in snapshot.candidates if item.id == candidate_id), None)
        if node is None or candidate is None:
            raise ValueError("Node or candidate not found")
        return {"node": node, "candidate": candidate}

    async def complete_assembly(
        self,
        *,
        workflow_id: str,
        assembly_id: str | None = None,
        status: str = "done",
        summary: str = "",
        artifacts: list[dict] | None = None,
        meta: dict | None = None,
        actor: str = "api",
        producer: str = "api",
    ):
        if status == "done":
            ensure_action_actor("assembly", "approve", actor)
            resolved_assembly_id = str(assembly_id or "")
            if not resolved_assembly_id:
                raise ValueError("assembly_id is required when approving assembly")
            await self.submit_command(
                workflow_id=workflow_id,
                event_type=EVENT_APPROVE_ASSEMBLY,
                producer=producer,
                payload={
                    "assembly_id": resolved_assembly_id,
                    "summary": summary,
                    "artifacts": artifacts,
                    "meta": meta,
                    "actor": actor,
                },
            )
            assembly = await self.repo.get_assembly(resolved_assembly_id)
            if assembly is None:
                raise ValueError("Assembly not found after approval")
            return assembly
        artifact_entities = [
            ArtifactRef(
                kind=str(item.get("kind") or ""),
                path=str(item.get("path") or ""),
                mime=str(item.get("mime") or ""),
                preview_url=str(item.get("previewUrl") or ""),
                metadata=dict(item.get("metadata") or {}),
            )
            for item in (artifacts or [])
        ]
        assembly = await self.engine.complete_assembly(
            workflow_id=workflow_id,
            assembly_id=assembly_id,
            status=status,
            summary=summary,
            artifacts=artifact_entities,
            meta=meta,
            producer=producer,
        )
        await self.db.commit()
        return assembly

    async def submit_decision(
        self,
        *,
        workflow_id: str,
        target_type: str,
        target_id: str,
        action: str,
        actor: str,
        comment: str = "",
        payload: dict | None = None,
        producer: str = "api",
    ):
        if target_type and action:
            ensure_action_actor(target_type, action, actor)
        if action == "regenerate" and target_type == "node":
            snapshot = await self.repo.load_snapshot(workflow_id)
            node = next((item for item in snapshot.nodes if item.id == target_id), None)
            if node is None:
                raise ValueError("Node not found")
            next_count = ensure_regenerate_allowed(node)
            ensure_candidate_limit(snapshot, target_id)
            node.meta = dict(node.meta or {})
            node.meta["regenerate_count"] = next_count
            node.touch()
            await self.repo.save_node(node)
            await self.create_candidate_for_node(
                workflow_id=workflow_id,
                node_id=target_id,
                provider="regenerate",
                summary=str((payload or {}).get("summary") or ""),
                producer=producer,
            )
        decision = await self.engine.submit_decision(
            workflow_id=workflow_id,
            target_type=target_type,
            target_id=target_id,
            action=action,
            actor=actor,
            comment=comment,
            payload=payload,
            producer=producer,
        )
        await self.db.commit()
        return decision

    async def rollback(
        self,
        *,
        workflow_id: str,
        actor: str,
        target_revision_id: str | None = None,
        reason: str = "",
        producer: str = "api",
    ):
        ensure_action_actor("workflow", "rollback", actor)
        await self.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_ROLLBACK_WORKFLOW,
            producer=producer,
            payload={
                "actor": actor,
                "target_revision_id": target_revision_id,
                "reason": reason,
            },
        )
        workflow = await self.repo.get_workflow(workflow_id)
        if workflow is None:
            raise ValueError("Workflow not found")
        return workflow

    async def create_candidate_for_node(
        self,
        *,
        workflow_id: str,
        node_id: str,
        provider: str,
        summary: str = "",
        producer: str = "node_dispatch_worker",
    ):
        snapshot = await self.repo.load_snapshot(workflow_id)
        ensure_candidate_limit(snapshot, node_id)
        candidate = await self.engine.create_candidate(
            workflow_id=workflow_id,
            node_id=node_id,
            provider=provider,
            producer=producer,
        )
        if summary:
            candidate = await self.engine.complete_candidate(
                workflow_id=workflow_id,
                candidate_id=candidate.id,
                status="running",
                summary="",
                producer=producer,
            )
            candidate = await self.engine.complete_candidate(
                workflow_id=workflow_id,
                candidate_id=candidate.id,
                status="produced",
                summary=summary,
                producer=producer,
            )
        await self.db.commit()
        return candidate

    async def upsert_assembly_for_selected_candidate(
        self,
        *,
        workflow_id: str,
        node_id: str,
        candidate_id: str,
        summary: str = "",
    ):
        assembly = await self.engine.upsert_assembly_for_selected_candidate(
            workflow_id=workflow_id,
            node_id=node_id,
            candidate_id=candidate_id,
            summary=summary,
        )
        await self.db.commit()
        return assembly

    async def reject_assembly(
        self,
        *,
        workflow_id: str,
        assembly_id: str,
        actor: str = "zhongshu",
        reason: str = "",
        producer: str = "api",
    ):
        ensure_action_actor("assembly", "reject", actor)
        await self.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_REJECT_ASSEMBLY,
            producer=producer,
            payload={
                "assembly_id": assembly_id,
                "actor": actor,
                "reason": reason,
            },
        )
        assembly = await self.repo.get_assembly(assembly_id)
        if assembly is None:
            raise ValueError("Assembly not found after reject")
        return assembly
