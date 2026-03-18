"""Metrics API — 运行时指标与健康度。"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..db import get_db
from ..models.task import Task, TaskState, TERMINAL_STATES
from ..services.event_bus import (
    TOPIC_AGENT_HEARTBEAT,
    TOPIC_AGENT_THOUGHTS,
    TOPIC_TASK_COMPLETED,
    TOPIC_TASK_CREATED,
    TOPIC_TASK_DISPATCH,
    TOPIC_TASK_DISPATCH_DEAD_LETTER,
    TOPIC_TASK_STALLED,
    TOPIC_TASK_STATUS,
    get_event_bus,
)
from ..services.metrics import get_metrics

router = APIRouter()


def _parse_labels(key: str) -> tuple[str, dict[str, str]]:
    """Parse 'metric_name|k1=v1,k2=v2' into (metric_name, {k1: v1, ...})."""
    if "|" not in key:
        return key, {}
    name, label_str = key.split("|", 1)
    labels = {}
    for part in label_str.split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            labels[k] = v
    return name, labels


def _sum_counters(counters: dict[str, float], metric: str, **match_labels) -> float:
    """Sum all counter entries matching metric name and optional label filters."""
    total = 0.0
    for key, value in counters.items():
        name, labels = _parse_labels(key)
        if name != metric:
            continue
        if all(labels.get(k) == str(v) for k, v in match_labels.items()):
            total += value
    return total


def _dispatch_by_agent(counters: dict[str, float]) -> dict[str, dict[str, float]]:
    """Group dispatch_total counters by agent → {result: count}."""
    result: dict[str, dict[str, float]] = {}
    for key, value in counters.items():
        name, labels = _parse_labels(key)
        if name != "dispatch_total":
            continue
        agent = labels.get("agent", "unknown")
        res = labels.get("result", "unknown")
        result.setdefault(agent, {})[res] = value
    return result


async def _task_counts(db: AsyncSession) -> dict[str, int]:
    rows = await db.execute(select(Task.state, func.count()).group_by(Task.state))
    grouped = {str(state): int(cnt) for state, cnt in rows.all()}
    return {s.value: grouped.get(s.value, 0) for s in TaskState}


async def _stalled_count(db: AsyncSession) -> int:
    settings = get_settings()
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=settings.stall_threshold_sec)
    terminal_values = tuple(s.value for s in TERMINAL_STATES)
    stmt = select(func.count()).where(
        Task.archived.is_(False),
        Task.state.notin_(terminal_values),
        Task.updated_at < cutoff,
    )
    return int((await db.execute(stmt)).scalar() or 0)


async def _queue_depth_snapshot() -> dict[str, int]:
    topics = [
        TOPIC_TASK_CREATED,
        TOPIC_TASK_STATUS,
        TOPIC_TASK_DISPATCH,
        TOPIC_TASK_DISPATCH_DEAD_LETTER,
        TOPIC_TASK_COMPLETED,
        TOPIC_TASK_STALLED,
        TOPIC_AGENT_HEARTBEAT,
        TOPIC_AGENT_THOUGHTS,
    ]
    bus = await get_event_bus()
    depth: dict[str, int] = {}
    metrics = get_metrics()

    for topic in topics:
        info = await bus.stream_info(topic)
        length = int(info.get("length", 0)) if info else 0
        depth[topic] = length
        metrics.set_gauge("queue_depth", length, labels={"topic": topic})

    return depth


@router.get("/metrics")
async def metrics_snapshot(db: AsyncSession = Depends(get_db)):
    metrics = get_metrics()
    queue_depth = await _queue_depth_snapshot()
    by_state = await _task_counts(db)
    stalled = await _stalled_count(db)
    metrics.set_gauge("stalled_tasks", stalled)

    task_rollup = {
        "done": by_state.get(TaskState.Done.value, 0),
        "cancelled": by_state.get(TaskState.Cancelled.value, 0),
        "blocked": by_state.get(TaskState.Blocked.value, 0),
        "active": sum(
            count
            for state, count in by_state.items()
            if state not in {TaskState.Done.value, TaskState.Cancelled.value, TaskState.Blocked.value}
        ),
    }
    for state_key, value in task_rollup.items():
        metrics.set_gauge("tasks_total", value, labels={"state": state_key})

    snapshot = metrics.snapshot()
    by_agent = _dispatch_by_agent(snapshot.get("counters", {}))

    # Aggregate histogram for latency
    histograms = snapshot.get("histograms", {})
    latency_count = 0
    latency_sum = 0.0
    for key, hist in histograms.items():
        name, _ = _parse_labels(key)
        if name == "dispatch_latency_seconds":
            latency_count += hist.get("count", 0)
            latency_sum += hist.get("sum", 0.0)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "metrics": snapshot,
        "queue_depth": queue_depth,
        "tasks": {
            "by_state": by_state,
            "rollup": task_rollup,
            "stalled": stalled,
        },
        "dispatch": {
            "by_agent": by_agent,
            "total": _sum_counters(snapshot.get("counters", {}), "dispatch_total"),
            "ok": _sum_counters(snapshot.get("counters", {}), "dispatch_total", result="ok"),
            "retries": _sum_counters(snapshot.get("counters", {}), "dispatch_retry_total"),
            "rate_limits": _sum_counters(snapshot.get("counters", {}), "rate_limit_total"),
            "avg_latency_seconds": (latency_sum / latency_count) if latency_count > 0 else 0.0,
        },
    }


@router.get("/metrics/health")
async def metrics_health(db: AsyncSession = Depends(get_db)):
    settings = get_settings()
    metrics = get_metrics()

    queue_depth = await _queue_depth_snapshot()
    stalled = await _stalled_count(db)
    metrics.set_gauge("stalled_tasks", stalled)
    snapshot = metrics.snapshot()

    counters = snapshot.get("counters", {})
    ok_count = _sum_counters(counters, "dispatch_total", result="ok")
    total = _sum_counters(counters, "dispatch_total")
    success_rate = (ok_count / total) if total > 0 else 1.0

    # Aggregate latency histogram
    histograms = snapshot.get("histograms", {})
    hist_count = 0
    hist_sum = 0.0
    for key, hist in histograms.items():
        name, _ = _parse_labels(key)
        if name == "dispatch_latency_seconds":
            hist_count += hist.get("count", 0)
            hist_sum += hist.get("sum", 0.0)
    avg_latency_seconds = (hist_sum / hist_count) if hist_count > 0 else 0.0

    max_queue_depth = max(queue_depth.values(), default=0)
    queue_ok = max_queue_depth < 1000

    if success_rate < 0.7 or max_queue_depth >= 5000 or stalled > 100:
        overall = "critical"
    elif success_rate < 0.9 or (not queue_ok) or stalled > max(10, settings.stall_threshold_sec // 10):
        overall = "degraded"
    else:
        overall = "ok"

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "overall": overall,
        "success_rate": round(success_rate, 4),
        "avg_latency_seconds": round(avg_latency_seconds, 4),
        "queue_health": {
            "ok": queue_ok,
            "max_depth": max_queue_depth,
            "threshold": 1000,
            "depth_by_topic": queue_depth,
        },
        "stalled_count": stalled,
    }
