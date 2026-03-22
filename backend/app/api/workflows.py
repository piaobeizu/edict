"""Minimal workflow v2 API endpoints."""

from __future__ import annotations

import asyncio
import json
from typing import Any

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_db
from ..services.workflow_guards import PolicyViolation
from ..services.event_bus import get_event_bus, EventBus
from ..services.workflow_guards import (
    EVENT_APPROVE_ASSEMBLY,
    EVENT_COMPLETE_CANDIDATE,
    EVENT_NODE_PROGRESS,
    EVENT_REGENERATE_NODE,
    EVENT_REJECT_ASSEMBLY,
    EVENT_ROLLBACK_WORKFLOW,
    EVENT_SELECT_CANDIDATE,
    TOPIC_WORKFLOW_COMMAND,
)
from ..services.workflow_service import WorkflowService

router = APIRouter()


class WorkflowCreateBody(BaseModel):
    title: str
    goal: str = ""
    workflowType: str = "generic"
    owner: str = ""
    meta: dict | None = None


class WorkflowCommandBody(BaseModel):
    eventType: str
    producer: str = "api"
    payload: dict | None = None


class NodeProgressBody(BaseModel):
    toState: str
    reason: str = ""
    executorId: str = ""
    message: str = ""
    producer: str = "api"


class CandidateCompleteBody(BaseModel):
    status: str
    summary: str = ""
    score: float | None = None
    metrics: dict | None = None
    artifacts: list[dict] | None = None
    meta: dict | None = None
    producer: str = "api"


class SelectCandidateBody(BaseModel):
    candidateId: str
    actor: str = "zhongshu"
    comment: str = ""
    producer: str = "api"


class AssemblyCompleteBody(BaseModel):
    status: str = "done"
    summary: str = ""
    artifacts: list[dict] | None = None
    meta: dict | None = None
    actor: str = "zhongshu"
    producer: str = "api"


class AssemblyRejectBody(BaseModel):
    actor: str = "zhongshu"
    reason: str = ""
    producer: str = "api"


class DecisionBody(BaseModel):
    targetType: str
    targetId: str
    action: str
    actor: str = "zhongshu"
    comment: str = ""
    payload: dict | None = None
    producer: str = "api"


class RollbackBody(BaseModel):
    actor: str = "zhongshu"
    targetRevisionId: str | None = None
    reason: str = ""
    producer: str = "api"


async def get_workflow_service(db: AsyncSession = Depends(get_db)) -> WorkflowService:
    return WorkflowService(db)


async def get_bus() -> EventBus:
    return await get_event_bus()


def _workflow_payload(workflow) -> dict:
    return {
        "id": workflow.id,
        "taskId": workflow.task_id,
        "type": workflow.type,
        "title": workflow.title,
        "goal": workflow.goal,
        "state": workflow.state,
        "owner": workflow.owner,
        "currentRevisionId": workflow.current_revision_id,
        "currentAssemblyId": workflow.current_assembly_id,
        "summaryOutput": workflow.summary_output,
    }


def _graph_payload(snapshot) -> dict:
    return {
        "workflow": {
            "id": snapshot.workflow.id,
            "taskId": snapshot.workflow.task_id,
            "type": snapshot.workflow.type,
            "title": snapshot.workflow.title,
            "goal": snapshot.workflow.goal,
            "state": snapshot.workflow.state,
            "owner": snapshot.workflow.owner,
            "currentRevisionId": snapshot.workflow.current_revision_id,
            "currentAssemblyId": snapshot.workflow.current_assembly_id,
            "summaryOutput": snapshot.workflow.summary_output,
        },
        "revisions": [
            {
                "id": item.id,
                "number": item.number,
                "status": item.status,
                "createdBy": item.created_by,
                "source": item.source,
                "content": item.content,
                "changeSummary": item.change_summary,
                "parentRevisionId": item.parent_revision_id,
                "createdAt": item.created_at.isoformat() if item.created_at else "",
                "updatedAt": item.updated_at.isoformat() if item.updated_at else "",
            }
            for item in snapshot.revisions
        ],
        "nodes": [
            {
                "id": item.id,
                "revisionId": item.revision_id,
                "kind": item.kind,
                "state": item.state,
                "title": item.title,
                "assignee": item.assignee,
                "sequence": item.sequence,
            }
            for item in snapshot.nodes
        ],
        "candidates": [
            {
                "id": item.id,
                "nodeId": item.node_id,
                "status": item.status,
                "provider": item.provider,
                "summary": item.summary,
            }
            for item in snapshot.candidates
        ],
        "decisions": [
            {
                "id": item.id,
                "targetType": item.target_type,
                "targetId": item.target_id,
                "action": item.action,
                "actor": item.actor,
                "comment": item.comment,
            }
            for item in snapshot.decisions
        ],
        "assemblies": [
            {
                "id": item.id,
                "status": item.status,
                "summary": item.summary,
            }
            for item in snapshot.assemblies
        ],
    }


def _sse_event(data: dict, *, event_id: str | None = None) -> str:
    lines = []
    if event_id:
        lines.append(f"id: {event_id}")
    lines.append(f"data: {json.dumps(data, ensure_ascii=False)}")
    return "\n".join(lines) + "\n\n"


def _parse_pubsub_event(raw_data: Any) -> dict[str, Any] | None:
    event_data: Any = raw_data
    if isinstance(event_data, bytes):
        try:
            event_data = event_data.decode("utf-8")
        except Exception:
            return None
    if isinstance(event_data, str):
        try:
            event_data = json.loads(event_data)
        except Exception:
            return None
    if not isinstance(event_data, dict):
        return None
    payload = event_data.get("payload")
    if isinstance(payload, str):
        try:
            event_data["payload"] = json.loads(payload)
        except Exception:
            event_data["payload"] = {}
    elif not isinstance(payload, dict):
        event_data["payload"] = {}
    return event_data


def _pubsub_event_matches_workflow(event_data: dict[str, Any], workflow_id: str) -> bool:
    payload = event_data.get("payload", {})
    if not isinstance(payload, dict):
        payload = {}
    trace_id = str(event_data.get("trace_id") or "")
    return str(payload.get("workflow_id") or "") == workflow_id or trace_id == workflow_id


@router.post("")
async def create_workflow(
    body: WorkflowCreateBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    workflow = await svc.create_workflow(
        title=body.title,
        goal=body.goal,
        workflow_type=body.workflowType,
        owner=body.owner,
        meta=body.meta,
    )
    return {
        "ok": True,
        "workflowId": workflow.id,
        "taskId": workflow.task_id,
        "state": workflow.state,
    }


@router.get("/{workflow_id}")
async def get_workflow(
    workflow_id: str,
    svc: WorkflowService = Depends(get_workflow_service),
):
    workflow = await svc.get_workflow(workflow_id)
    if workflow is None:
        raise HTTPException(status_code=404, detail="Workflow not found")
    return {
        "ok": True,
        "workflow": _workflow_payload(workflow),
    }


@router.get("/{workflow_id}/graph")
async def get_workflow_graph(
    workflow_id: str,
    svc: WorkflowService = Depends(get_workflow_service),
):
    snapshot = await svc.get_snapshot(workflow_id)
    return {"ok": True, **_graph_payload(snapshot)}


@router.get("/{workflow_id}/timeline")
async def get_workflow_timeline(
    workflow_id: str,
    svc: WorkflowService = Depends(get_workflow_service),
):
    timeline = await svc.get_timeline(workflow_id)
    return {"ok": True, "workflowId": workflow_id, "timeline": timeline}


@router.get("/{workflow_id}/sync-snapshot")
async def get_workflow_sync_snapshot(
    workflow_id: str,
    svc: WorkflowService = Depends(get_workflow_service),
):
    workflow = await svc.get_workflow(workflow_id)
    if workflow is None:
        raise HTTPException(status_code=404, detail="Workflow not found")
    snapshot = await svc.get_snapshot(workflow_id)
    timeline = await svc.get_timeline(workflow_id)
    return {
        "ok": True,
        "workflowId": workflow_id,
        **_graph_payload(snapshot),
        "timeline": timeline,
    }


@router.get("/{workflow_id}/events/stream")
async def stream_workflow_events(
    workflow_id: str,
    request: Request,
    svc: WorkflowService = Depends(get_workflow_service),
):
    workflow = await svc.get_workflow(workflow_id)
    if workflow is None:
        raise HTTPException(status_code=404, detail="Workflow not found")

    async def event_stream():
        settings = get_settings()
        pubsub_redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        pubsub = pubsub_redis.pubsub()
        await pubsub.psubscribe("edict:pubsub:*")
        try:
            # Let client know stream is alive and immediately trigger one reconcile.
            yield _sse_event({"kind": "connected", "workflowId": workflow_id, "connected": True})
            while True:
                if await request.is_disconnected():
                    break
                message = await pubsub.get_message(
                    ignore_subscribe_messages=True,
                    timeout=15.0,
                )
                if not message:
                    # Keep-alive comment to prevent intermediaries from closing idle streams.
                    yield ": keep-alive\n\n"
                    continue
                if message.get("type") != "pmessage":
                    continue
                topic = str(message.get("channel") or "").replace("edict:pubsub:", "")
                event_data = _parse_pubsub_event(message.get("data"))
                if event_data is None:
                    continue
                if not _pubsub_event_matches_workflow(event_data, workflow_id):
                    continue
                event_id = str(event_data.get("stream_entry_id") or "")
                yield _sse_event(
                    {
                        "kind": "event",
                        "topic": topic,
                        "eventType": str(event_data.get("event_type") or ""),
                        "data": event_data,
                    },
                    event_id=event_id or None,
                )
                await asyncio.sleep(0)
        finally:
            await pubsub.punsubscribe("edict:pubsub:*")
            await pubsub_redis.aclose()

    headers = {
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    }
    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers=headers,
    )


@router.post("/{workflow_id}/commands")
async def submit_workflow_command(
    workflow_id: str,
    body: WorkflowCommandBody,
    bus: EventBus = Depends(get_bus),
):
    entry_id = await bus.publish(
        topic=TOPIC_WORKFLOW_COMMAND,
        trace_id=workflow_id,
        event_type=body.eventType,
        producer=body.producer,
        payload={"workflow_id": workflow_id, "workflow_version": 2, **(body.payload or {})},
    )
    return {
        "ok": True,
        "accepted": True,
        "entryId": entry_id,
    }


@router.get("/{workflow_id}/candidates")
async def list_candidates(
    workflow_id: str,
    node_id: str | None = None,
    svc: WorkflowService = Depends(get_workflow_service),
):
    candidates = await svc.list_candidates(workflow_id, node_id=node_id)
    return {
        "ok": True,
        "workflowId": workflow_id,
        "candidates": [
            {
                "id": item.id,
                "nodeId": item.node_id,
                "status": item.status,
                "provider": item.provider,
                "summary": item.summary,
                "score": item.score,
                "metrics": item.metrics,
                "artifacts": [
                    {
                        "kind": artifact.kind,
                        "path": artifact.path,
                        "mime": artifact.mime,
                        "previewUrl": artifact.preview_url,
                        "metadata": artifact.metadata,
                    }
                    for artifact in item.artifacts
                ],
            }
            for item in candidates
        ],
    }


@router.get("/{workflow_id}/assemblies")
async def list_assemblies(
    workflow_id: str,
    svc: WorkflowService = Depends(get_workflow_service),
):
    assemblies = await svc.list_assemblies(workflow_id)
    return {
        "ok": True,
        "workflowId": workflow_id,
        "assemblies": [
            {
                "id": item.id,
                "status": item.status,
                "summary": item.summary,
                "items": [
                    {
                        "order": ref.order,
                        "nodeId": ref.node_id,
                        "candidateId": ref.candidate_id,
                        "role": ref.role,
                        "meta": ref.meta,
                    }
                    for ref in item.items
                ],
                "artifacts": [
                    {
                        "kind": artifact.kind,
                        "path": artifact.path,
                        "mime": artifact.mime,
                        "previewUrl": artifact.preview_url,
                        "metadata": artifact.metadata,
                    }
                    for artifact in item.artifacts
                ],
            }
            for item in assemblies
        ],
    }


@router.post("/{workflow_id}/nodes/{node_id}/progress")
async def update_node_progress(
    workflow_id: str,
    node_id: str,
    body: NodeProgressBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    try:
        await svc.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_NODE_PROGRESS,
            producer=body.producer,
            payload={
                "node_id": node_id,
                "to_state": body.toState,
                "reason": body.reason,
                "executor_id": body.executorId,
                "message": body.message,
            },
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        if "transition" in str(exc).lower() or "invalid" in str(exc).lower():
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        raise
    return {"ok": True, "nodeId": node_id, "state": body.toState}


@router.post("/{workflow_id}/candidates/{candidate_id}/complete")
async def complete_candidate(
    workflow_id: str,
    candidate_id: str,
    body: CandidateCompleteBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    try:
        await svc.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_COMPLETE_CANDIDATE,
            producer=body.producer,
            payload={
                "candidate_id": candidate_id,
                "status": body.status,
                "summary": body.summary,
                "score": body.score,
                "metrics": body.metrics,
                "artifacts": body.artifacts,
                "meta": body.meta,
            },
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "ok": True,
        "candidateId": candidate_id,
        "status": body.status,
        "summary": body.summary,
    }


@router.post("/{workflow_id}/nodes/{node_id}/select-candidate")
async def select_candidate(
    workflow_id: str,
    node_id: str,
    body: SelectCandidateBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    try:
        await svc.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_SELECT_CANDIDATE,
            producer=body.producer,
            payload={
                "node_id": node_id,
                "candidate_id": body.candidateId,
                "actor": body.actor,
                "comment": body.comment,
            },
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "ok": True,
        "nodeId": node_id,
        "selectedCandidateId": body.candidateId,
    }


@router.post("/{workflow_id}/assemblies/{assembly_id}/complete")
async def complete_assembly(
    workflow_id: str,
    assembly_id: str,
    body: AssemblyCompleteBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    if body.status != "done":
        raise HTTPException(status_code=400, detail="only status=done is supported")
    try:
        await svc.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_APPROVE_ASSEMBLY,
            producer=body.producer,
            payload={
                "assembly_id": assembly_id,
                "summary": body.summary,
                "artifacts": body.artifacts,
                "meta": body.meta,
                "actor": body.actor,
            },
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"ok": True, "assemblyId": assembly_id, "status": body.status}


@router.post("/{workflow_id}/assemblies/{assembly_id}/reject")
async def reject_assembly(
    workflow_id: str,
    assembly_id: str,
    body: AssemblyRejectBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    try:
        await svc.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_REJECT_ASSEMBLY,
            producer=body.producer,
            payload={
                "assembly_id": assembly_id,
                "actor": body.actor,
                "reason": body.reason,
            },
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"ok": True, "assemblyId": assembly_id, "status": "rejected"}


@router.post("/{workflow_id}/decisions")
async def submit_decision(
    workflow_id: str,
    body: DecisionBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    try:
        if body.targetType == "node" and body.action == "regenerate":
            await svc.submit_command(
                workflow_id=workflow_id,
                event_type=EVENT_REGENERATE_NODE,
                producer=body.producer,
                payload={
                    "node_id": body.targetId,
                    "actor": body.actor,
                    "comment": body.comment,
                },
            )
            return {
                "ok": True,
                "decisionId": "",
                "targetType": body.targetType,
                "targetId": body.targetId,
                "action": body.action,
            }
        decision = await svc.submit_decision(
            workflow_id=workflow_id,
            target_type=body.targetType,
            target_id=body.targetId,
            action=body.action,
            actor=body.actor,
            comment=body.comment,
            payload=body.payload,
            producer=body.producer,
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "ok": True,
        "decisionId": decision.id,
        "targetType": decision.target_type,
        "targetId": decision.target_id,
        "action": decision.action,
    }


@router.post("/{workflow_id}/rollback")
async def rollback_workflow(
    workflow_id: str,
    body: RollbackBody,
    svc: WorkflowService = Depends(get_workflow_service),
):
    try:
        await svc.submit_command(
            workflow_id=workflow_id,
            event_type=EVENT_ROLLBACK_WORKFLOW,
            producer=body.producer,
            payload={
                "actor": body.actor,
                "target_revision_id": body.targetRevisionId,
                "reason": body.reason,
            },
        )
    except PolicyViolation as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"ok": True, "workflowId": workflow_id, "state": "planning"}
