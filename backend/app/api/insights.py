"""Insights API — 任务活动与调度状态。"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..models.task import Task

router = APIRouter()


def _allowed_roots() -> list[Path]:
    roots = [Path("/app/data"), Path("/root/.openclaw")]
    return [p.resolve() for p in roots if p.exists()]


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _annotate_artifact(a: dict) -> dict:
    """为 artifact 增加 exists/downloadable 元信息。"""
    out = dict(a)
    p = str(out.get("path") or "")
    if not p:
        out["exists"] = False
        out["downloadable"] = False
        return out

    if p.startswith("http://") or p.startswith("https://"):
        out["exists"] = True
        out["downloadable"] = True
        return out

    try:
        rp = Path(p).resolve(strict=True)
        allowed = _allowed_roots()
        ok = rp.is_file() and any(_is_within(rp, root) for root in allowed)
        out["exists"] = bool(ok)
        out["downloadable"] = bool(ok)
    except Exception:
        out["exists"] = False
        out["downloadable"] = False
    return out


def _fmt_duration(sec: int) -> str:
    sec = max(0, int(sec))
    if sec < 60:
        return f"{sec}秒"
    if sec < 3600:
        return f"{sec // 60}分{sec % 60}秒"
    h = sec // 3600
    m = (sec % 3600) // 60
    return f"{h}小时{m}分"


@router.get("/task-activity/{task_id}")
async def task_activity(task_id: str, db: AsyncSession = Depends(get_db)):
    task = await db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

    activity = []
    retry_records = []
    artifacts = []

    for fl in list(task.flow_log or []):
        activity.append(
            {
                "kind": "flow",
                "at": fl.get("at") or fl.get("ts") or "",
                "from": fl.get("from", ""),
                "to": fl.get("to", ""),
                "remark": fl.get("remark") or fl.get("reason") or "",
            }
        )

    for p in list(task.progress_log or []):
        entry = {
            "kind": "progress",
            "at": p.get("at") or p.get("ts") or "",
            "agent": p.get("agent", ""),
            "text": p.get("text") or p.get("content") or "",
        }
        details = p.get("details") or {}
        if details:
            entry["details"] = details
            retry = details.get("retry")
            if retry:
                retry_records.append(
                    {
                        "at": entry["at"],
                        "agent": entry["agent"],
                        "attempts": retry.get("attempts", 1),
                        "errorType": retry.get("error_type", "unknown"),
                        "exhausted": bool(retry.get("exhausted", False)),
                    }
                )
            for a in details.get("artifacts", []) or []:
                if isinstance(a, dict) and a.get("path"):
                    artifacts.append(a)
        activity.append(entry)

    if task.todos:
        activity.append(
            {
                "kind": "todos",
                "at": task.updated_at.isoformat() if task.updated_at else "",
                "items": task.todos,
            }
        )

    activity.sort(key=lambda x: x.get("at", ""))

    # 去重 artifacts
    uniq = {}
    for a in artifacts:
        uniq[a["path"]] = _annotate_artifact(a)

    todos = list(task.todos or [])
    done = sum(1 for t in todos if t.get("status") == "completed")
    doing = sum(1 for t in todos if t.get("status") in ("in-progress", "in_progress"))
    total = len(todos)
    not_started = max(0, total - done - doing)
    percent = int((done / total) * 100) if total else 0

    return {
        "ok": True,
        "taskId": task_id,
        "activity": activity,
        "taskMeta": {
            "title": task.title,
            "state": task.state or "",
            "org": task.org,
            "output": task.output or "",
            "block": task.block or "",
            "priority": task.priority,
            "archived": task.archived,
        },
        "todosSummary": {
            "total": total,
            "completed": done,
            "inProgress": doing,
            "notStarted": not_started,
            "percent": percent,
        },
        "retrySummary": {
            "count": len(retry_records),
            "records": retry_records[-30:],
        },
        "artifacts": list(uniq.values())[-20:],
        "lastActive": task.updated_at.isoformat() if task.updated_at else None,
    }


@router.get("/scheduler-state/{task_id}")
async def scheduler_state(task_id: str, db: AsyncSession = Depends(get_db)):
    task = await db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

    scheduler = dict(task.scheduler or {})
    now = datetime.now(timezone.utc)
    ref = task.updated_at or task.created_at or now
    stalled_sec = int((now - ref).total_seconds())

    scheduler.setdefault("retryCount", 0)
    scheduler.setdefault("escalationLevel", 0)
    scheduler.setdefault("lastDispatchStatus", "idle")
    scheduler.setdefault("stallThresholdSec", 180)
    scheduler.setdefault("enabled", True)
    scheduler.setdefault("autoRollback", True)

    return {
        "ok": True,
        "scheduler": scheduler,
        "stalledSec": max(0, stalled_sec),
        "stalledText": _fmt_duration(stalled_sec),
    }
