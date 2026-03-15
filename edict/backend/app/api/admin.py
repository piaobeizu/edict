"""Admin API — 管理操作（迁移、诊断、配置）。"""

import json
import logging
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from ..db import get_db
from ..services.event_bus import (
    get_event_bus,
    TOPIC_TASK_DISPATCH,
    TOPIC_TASK_DISPATCH_DEAD_LETTER,
)

log = logging.getLogger("edict.api.admin")
router = APIRouter()


class DeadLetterReplayRequest(BaseModel):
    entry_id: str


@router.get("/health/deep")
async def deep_health(db: AsyncSession = Depends(get_db)):
    """深度健康检查：Postgres + Redis 连通性。"""
    checks = {"postgres": False, "redis": False}
    errors: dict[str, str] = {}

    # Postgres
    try:
        result = await db.execute(text("SELECT 1"))
        checks["postgres"] = result.scalar() == 1
    except Exception as e:
        errors["postgres_error"] = str(e)

    # Redis
    try:
        bus = await get_event_bus()
        pong = await bus.redis.ping()
        checks["redis"] = pong is True
    except Exception as e:
        errors["redis_error"] = str(e)

    status = "ok" if all(checks.get(k) for k in ["postgres", "redis"]) else "degraded"
    return {"status": status, "checks": checks, **errors}


@router.get("/pending-events")
async def pending_events(
    topic: str = "task.dispatch",
    group: str = "dispatcher",
    count: int = 20,
):
    """查看未 ACK 的 pending 事件（诊断工具）。"""
    bus = await get_event_bus()
    pending = await bus.get_pending(topic, group, count)
    return {
        "topic": topic,
        "group": group,
        "pending": [
            {
                "entry_id": str(p.get("message_id", "")),
                "consumer": str(p.get("consumer", "")),
                "idle_ms": p.get("time_since_delivered", 0),
                "delivery_count": p.get("times_delivered", 0),
            }
            for p in pending
        ] if pending else [],
    }


@router.post("/migrate/check")
async def migration_check():
    """检查旧数据文件是否存在。"""
    data_dir = Path(__file__).parents[4] / "data"
    files = {
        "tasks_source": (data_dir / "tasks_source.json").exists(),
        "live_status": (data_dir / "live_status.json").exists(),
        "agent_config": (data_dir / "agent_config.json").exists(),
        "officials_stats": (data_dir / "officials_stats.json").exists(),
    }
    return {"data_dir": str(data_dir), "files": files}


@router.get("/config")
async def get_config():
    """获取当前运行配置（脱敏）。"""
    from ..config import get_settings
    settings = get_settings()
    return {
        "port": settings.port,
        "debug": settings.debug,
        "database": settings.database_url.split("@")[-1] if "@" in settings.database_url else "***",
        "redis": settings.redis_url.split("@")[-1] if "@" in settings.redis_url else settings.redis_url,
        "scheduler_scan_interval": settings.scheduler_scan_interval_seconds,
    }


@router.get("/dead-letter")
async def list_dead_letters(limit: int = 50):
    """查看 dispatch 死信事件（DLQ）。"""
    bus = await get_event_bus()
    stream_key = bus._stream_key(TOPIC_TASK_DISPATCH_DEAD_LETTER)
    raw = await bus.redis.xrevrange(stream_key, max="+", min="-", count=max(1, min(limit, 200)))

    events = []
    for entry_id, data in raw:
        try:
            payload = json.loads(data.get("payload", "{}"))
        except Exception:
            payload = {}
        events.append(
            {
                "entry_id": entry_id,
                "trace_id": data.get("trace_id", ""),
                "event_type": data.get("event_type", ""),
                "producer": data.get("producer", ""),
                "timestamp": data.get("timestamp", ""),
                "payload": payload,
            }
        )

    return {"topic": TOPIC_TASK_DISPATCH_DEAD_LETTER, "count": len(events), "events": events}


@router.post("/dead-letter/replay")
async def replay_dead_letter(body: DeadLetterReplayRequest):
    """按 entry_id 重放一条 DLQ 事件到 task.dispatch。"""
    bus = await get_event_bus()
    dlq_key = bus._stream_key(TOPIC_TASK_DISPATCH_DEAD_LETTER)
    rows = await bus.redis.xrange(dlq_key, min=body.entry_id, max=body.entry_id, count=1)
    if not rows:
        raise HTTPException(status_code=404, detail=f"DLQ entry not found: {body.entry_id}")

    _, raw = rows[0]
    try:
        payload = json.loads(raw.get("payload", "{}"))
    except Exception:
        payload = {}

    task_id = payload.get("task_id")
    agent = payload.get("agent")
    if not task_id or not agent:
        raise HTTPException(status_code=400, detail="Invalid DLQ payload: missing task_id/agent")

    dispatch_round = int(payload.get("dispatch_round") or 1) + 1
    replay_payload = {
        "task_id": task_id,
        "agent": agent,
        "state": payload.get("state", ""),
        "message": payload.get("message", ""),
        "dispatch_round": dispatch_round,
        "replay_of": body.entry_id,
    }

    entry_id = await bus.publish(
        topic=TOPIC_TASK_DISPATCH,
        trace_id=raw.get("trace_id", task_id),
        event_type="task.dispatch.replay",
        producer="admin",
        payload=replay_payload,
    )
    return {
        "message": "replayed",
        "source_entry_id": body.entry_id,
        "dispatch_entry_id": entry_id,
        "payload": replay_payload,
    }
