"""E2E test harness — wires up real engine + policy with in-memory repo/bus.

This provides a WorkflowService-like interface that exercises the full
WorkflowService → GraphWorkflowEngine → MinimalWorkflowPolicy → Repo chain
without requiring a database or Redis.
"""

from __future__ import annotations

from kernel.graph_workflow import GraphWorkflowEngine
from backend.app.services.workflow_policy import MinimalWorkflowPolicy
from tests.helpers.workflow_fakes import InMemoryWorkflowRepo


class InMemoryBus:
    """In-memory EventBusPort that records all published events."""

    def __init__(self):
        self.events: list[dict] = []

    async def publish(self, topic, trace_id, event_type, producer, payload=None, meta=None):
        self.events.append(
            {
                "topic": topic,
                "trace_id": trace_id,
                "event_type": event_type,
                "producer": producer,
                "payload": payload or {},
                "meta": meta or {},
            }
        )
        return f"evt-{len(self.events)}"

    async def consume(self, topic, group, consumer, count=10, block_ms=5000):
        return []

    async def ack(self, *args, **kwargs):
        return None

    async def claim_stale(self, *args, **kwargs):
        return []


class InMemoryProjection:
    """In-memory projection that tracks refresh calls."""

    def __init__(self):
        self.refreshed: list[str] = []

    async def refresh_task_projection(self, workflow_id: str) -> None:
        self.refreshed.append(workflow_id)


class FakeDb:
    """Minimal fake AsyncSession for WorkflowService.db.commit()."""

    def __init__(self):
        self.commits = 0

    async def commit(self):
        self.commits += 1

    async def flush(self):
        pass

    async def rollback(self):
        pass


class E2EWorkflowService:
    """Service-layer harness that wires real engine+policy with in-memory fakes.

    Mirrors the WorkflowService public API but uses InMemoryWorkflowRepo + InMemoryBus,
    allowing full E2E testing of the workflow command pipeline without external deps.
    """

    def __init__(self):
        self.repo = InMemoryWorkflowRepo()
        self.bus = InMemoryBus()
        self.projection = InMemoryProjection()
        self.db = FakeDb()
        self.policy = MinimalWorkflowPolicy()
        self.engine = GraphWorkflowEngine(
            repo=self.repo,
            bus=self.bus,
            policy=self.policy,
            projection=self.projection,
        )
        # Import guards lazily to match WorkflowService
        from backend.app.services.workflow_guards import (
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
        self._event_constants = {
            "approve_plan": EVENT_APPROVE_PLAN,
            "approve_assembly": EVENT_APPROVE_ASSEMBLY,
            "complete_candidate": EVENT_COMPLETE_CANDIDATE,
            "node_progress": EVENT_NODE_PROGRESS,
            "reject_plan": EVENT_REJECT_PLAN,
            "regenerate_node": EVENT_REGENERATE_NODE,
            "reject_assembly": EVENT_REJECT_ASSEMBLY,
            "rollback": EVENT_ROLLBACK_WORKFLOW,
            "select_candidate": EVENT_SELECT_CANDIDATE,
        }

    async def create_workflow(self, *, title, goal="", workflow_type="generic", owner="", meta=None):
        workflow = await self.engine.create_workflow(
            title=title, goal=goal, workflow_type=workflow_type, owner=owner, meta=meta or {},
        )
        await self.db.commit()
        return workflow

    async def get_workflow(self, workflow_id: str):
        return await self.repo.get_workflow(workflow_id)

    async def get_snapshot(self, workflow_id: str):
        return await self.repo.load_snapshot(workflow_id, include_decisions=True)

    async def submit_command(self, *, workflow_id, event_type, producer="api", payload=None):
        """Mirrors WorkflowService.submit_command with real guard + engine logic."""
        from backend.app.services.workflow_guards import (
            ensure_command_actor,
            ensure_action_actor,
            ensure_candidate_limit,
            ensure_regenerate_allowed,
            EVENT_NODE_PROGRESS,
            EVENT_COMPLETE_CANDIDATE,
            EVENT_REGENERATE_NODE,
        )
        from kernel.graph_entities import ArtifactRef
        from kernel.workflow_events import WorkflowEvent

        command_payload = dict(payload or {})
        fallback_actor = str(producer or "api")
        command_actor = str(command_payload.get("actor") or fallback_actor)
        ensure_command_actor(event_type, command_actor)

        if event_type == EVENT_NODE_PROGRESS:
            node = await self.engine.add_node_progress(
                workflow_id=workflow_id,
                node_id=str(command_payload.get("node_id") or ""),
                to_state=str(command_payload.get("to_state") or ""),
                reason=str(command_payload.get("reason") or ""),
                executor_id=str(command_payload.get("executor_id") or ""),
                message=str(command_payload.get("message") or ""),
                producer=producer,
            )
            await self.db.commit()
            return []

        if event_type == EVENT_COMPLETE_CANDIDATE:
            artifacts_raw = command_payload.get("artifacts")
            artifact_entities = [
                ArtifactRef(
                    kind=str(item.get("kind") or ""),
                    path=str(item.get("path") or ""),
                    mime=str(item.get("mime") or ""),
                    preview_url=str(item.get("previewUrl") or ""),
                    metadata=dict(item.get("metadata") or {}),
                )
                for item in (artifacts_raw or [])
            ] if isinstance(artifacts_raw, list) else None
            await self.engine.complete_candidate(
                workflow_id=workflow_id,
                candidate_id=str(command_payload.get("candidate_id") or ""),
                status=str(command_payload.get("status") or ""),
                summary=str(command_payload.get("summary") or ""),
                score=command_payload.get("score"),
                artifacts=artifact_entities,
                producer=producer,
            )
            await self.db.commit()
            return []

        if event_type == EVENT_REGENERATE_NODE:
            node_id = str(command_payload.get("node_id") or "")
            node = await self.repo.get_node(node_id)
            if node is None:
                raise ValueError("Node not found")
            ensure_regenerate_allowed(node)
            snapshot = await self.repo.load_snapshot(workflow_id)
            ensure_candidate_limit(snapshot, node_id)
            await self.engine.submit_decision(
                workflow_id=workflow_id,
                target_type="node",
                target_id=node_id,
                action="regenerate",
                actor=command_actor,
                comment=str(command_payload.get("comment") or ""),
                payload={},
                producer=producer,
            )
            await self.db.commit()
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

    async def get_timeline(self, workflow_id: str) -> list[dict]:
        """Reuses WorkflowService.get_timeline logic."""
        snapshot = await self.repo.load_snapshot(workflow_id, include_decisions=True)
        timeline: list[dict] = []
        for revision in snapshot.revisions:
            timeline.append({"kind": "revision", "at": revision.updated_at.isoformat() if revision.updated_at else "", "id": revision.id, "number": revision.number, "status": revision.status})
        for node in snapshot.nodes:
            timeline.append({"kind": "node", "at": node.updated_at.isoformat() if node.updated_at else "", "id": node.id, "state": node.state, "title": node.title})
        for decision in snapshot.decisions:
            timeline.append({"kind": "decision", "at": decision.created_at.isoformat() if decision.created_at else "", "id": decision.id, "action": decision.action, "actor": decision.actor})
        for assembly in snapshot.assemblies:
            timeline.append({"kind": "assembly", "at": assembly.updated_at.isoformat() if assembly.updated_at else "", "id": assembly.id, "status": assembly.status})
        timeline.sort(key=lambda item: item.get("at", ""))
        return timeline
