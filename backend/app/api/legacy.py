"""Legacy 兼容路由 — 通过旧版 task_id (JJC-xxx) 操作任务。

旧版 kanban_update.py 使用自定义 ID (JJC-20260301-007)，
Edict 使用 UUID。此路由通过 tags 或 meta.legacy_id 映射。
"""

import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..models.task import Task, TaskState
from ..services.event_bus import get_event_bus
from ..services.task_service import TaskService

log = logging.getLogger("edict.api.legacy")
router = APIRouter()


async def _find_by_legacy_id(db: AsyncSession, legacy_id: str) -> Task | None:
    """通过旧版 ID 查找任务。

    查找策略：
    1. 直接按主键 id 查找（当前 ID 格式就是 JJC-xxx）
    2. 在 scheduler JSON 的 legacy_id 字段中查找
    """
    # 方式1: 直接按主键查找（JJC-xxx 本身就是 task.id）
    task = await db.get(Task, legacy_id)
    if task:
        return task

    # 方式2: 模糊匹配（JJC-xxx 可能是旧格式，新 ID 带了后缀）
    # 转义 SQL LIKE 通配符防止注入
    escaped_id = legacy_id.replace("%", r"\%").replace("_", r"\_")
    stmt = select(Task).where(Task.id.like(f"{escaped_id}%")).limit(1)
    result = await db.execute(stmt)
    task = result.scalars().first()
    if task:
        return task

    # 方式3: scheduler->legacy_id
    stmt2 = select(Task).where(Task.scheduler["legacy_id"].astext == legacy_id)
    result2 = await db.execute(stmt2)
    return result2.scalars().first()


class LegacyTransition(BaseModel):
    new_state: str
    agent: str = "system"
    reason: str = ""


class LegacyProgress(BaseModel):
    agent: str
    content: str


class LegacyTodoUpdate(BaseModel):
    todos: list[dict]


@router.post("/by-legacy/{legacy_id}/transition")
async def legacy_transition(
    legacy_id: str,
    body: LegacyTransition,
    db: AsyncSession = Depends(get_db),
):
    task = await _find_by_legacy_id(db, legacy_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Legacy task not found: {legacy_id}")

    bus = await get_event_bus()
    svc = TaskService(db, bus)
    try:
        new_state = TaskState(body.new_state)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid state: {body.new_state}")

    try:
        t = await svc.transition_state(str(task.id), new_state, body.agent, body.reason)
        return {"task_id": str(t.id), "state": t.state if isinstance(t.state, str) else t.state.value}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/by-legacy/{legacy_id}/progress")
async def legacy_progress(
    legacy_id: str,
    body: LegacyProgress,
    db: AsyncSession = Depends(get_db),
):
    task = await _find_by_legacy_id(db, legacy_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Legacy task not found: {legacy_id}")

    bus = await get_event_bus()
    svc = TaskService(db, bus)
    await svc.add_progress(str(task.id), body.agent, body.content)
    return {"message": "ok"}


@router.put("/by-legacy/{legacy_id}/todos")
async def legacy_todos(
    legacy_id: str,
    body: LegacyTodoUpdate,
    db: AsyncSession = Depends(get_db),
):
    task = await _find_by_legacy_id(db, legacy_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Legacy task not found: {legacy_id}")

    bus = await get_event_bus()
    svc = TaskService(db, bus)
    await svc.update_todos(str(task.id), body.todos)
    return {"message": "ok"}


@router.get("/by-legacy/{legacy_id}")
async def legacy_get(
    legacy_id: str,
    db: AsyncSession = Depends(get_db),
):
    task = await _find_by_legacy_id(db, legacy_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Legacy task not found: {legacy_id}")
    return task.to_dict()
