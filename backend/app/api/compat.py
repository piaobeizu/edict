"""兼容 API：对接现有前端动作接口。"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, cast

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..models.task import Task, TaskState, STATE_AGENT_MAP, ORG_AGENT_MAP
from ..services.event_bus import get_event_bus, TOPIC_TASK_ESCALATED
from ..services.morning_brief import DEFAULT_SUB_CONFIG, load_by_date, load_config, load_latest, refresh as refresh_morning_payload, save_config as save_morning_payload
from ..services.officials_stats import build_officials_stats
from ..services.task_service import TaskService
from ..services.workflow_service import WorkflowService
from ..services.workflow_guards import (
    TOPIC_WORKFLOW_COMMAND,
    EVENT_APPROVE_PLAN,
    EVENT_CANCEL_WORKFLOW,
    EVENT_REJECT_PLAN,
    EVENT_RESUME_WORKFLOW,
    EVENT_START_PLANNING,
    EVENT_STOP_WORKFLOW,
    EVENT_SUBMIT_PLAN,
)

router = APIRouter()

async def _svc(db: AsyncSession) -> TaskService:
    bus = await get_event_bus()
    return TaskService(db, bus)


def _is_workflow_task(task: Task) -> bool:
    return str(getattr(task, "workflow_type", "legacy") or "legacy") != "legacy"


async def _publish_workflow_command(task: Task, *, event_type: str, producer: str, payload: dict | None = None):
    bus = await get_event_bus()
    workflow_id = str(getattr(task, "workflow_id", "") or "")
    if not workflow_id:
        raise ValueError("workflow task missing workflow_id")
    await bus.publish(
        topic=TOPIC_WORKFLOW_COMMAND,
        trace_id=workflow_id,
        event_type=event_type,
        producer=producer,
        payload={"workflow_id": workflow_id, "workflow_version": 2, **(payload or {})},
    )


async def _handle_workflow_task_action(task: Task, action: str, reason: str) -> dict:
    if action == "stop":
        await _publish_workflow_command(task, event_type=EVENT_STOP_WORKFLOW, producer="compat", payload={"reason": reason})
        return {"ok": True, "message": "已提交 workflow 叫停指令"}
    if action == "cancel":
        await _publish_workflow_command(task, event_type=EVENT_CANCEL_WORKFLOW, producer="compat", payload={"reason": reason})
        return {"ok": True, "message": "已提交 workflow 取消指令"}
    if action == "resume":
        await _publish_workflow_command(task, event_type=EVENT_RESUME_WORKFLOW, producer="compat", payload={"reason": reason})
        return {"ok": True, "message": "已提交 workflow 恢复指令"}
    return {"ok": False, "error": f"workflow 任务暂不支持 action: {action}"}


async def _handle_workflow_review_action(task: Task, action: str, comment: str) -> dict:
    current = str(getattr(task, "state", "") or "")
    if action == "approve" and current in {"Pending", "Taizi", "draft"}:
        await _publish_workflow_command(task, event_type=EVENT_START_PLANNING, producer="compat", payload={"content": comment})
        return {"ok": True, "message": "已提交 workflow 开始规划指令"}
    if action == "approve" and current in {"Zhongshu", "planning"}:
        await _publish_workflow_command(task, event_type=EVENT_SUBMIT_PLAN, producer="compat", payload={"comment": comment})
        return {"ok": True, "message": "已提交 workflow 提交审议指令"}
    if action == "approve" and current in {"YuLan", "awaiting_plan_review"}:
        await _publish_workflow_command(task, event_type=EVENT_APPROVE_PLAN, producer="compat", payload={"comment": comment})
        return {"ok": True, "message": "已提交 workflow 方案批准指令"}
    if action == "reject" and current in {"YuLan", "awaiting_plan_review"}:
        await _publish_workflow_command(task, event_type=EVENT_REJECT_PLAN, producer="compat", payload={"comment": comment})
        return {"ok": True, "message": "已提交 workflow 方案驳回指令"}
    return {"ok": False, "error": f"workflow 任务当前状态不支持 {action}: {current}"}


async def _handle_workflow_advance(task: Task, comment: str) -> dict:
    current = str(getattr(task, "state", "") or "")
    if current in {"Pending", "Taizi", "draft"}:
        await _publish_workflow_command(task, event_type=EVENT_START_PLANNING, producer="compat", payload={"content": comment})
        return {"ok": True, "message": "已提交 workflow 开始规划指令"}
    if current in {"planning", "Zhongshu"}:
        await _publish_workflow_command(task, event_type=EVENT_SUBMIT_PLAN, producer="compat", payload={"comment": comment})
        return {"ok": True, "message": "已提交 workflow 提交审议指令"}
    if current in {"YuLan", "awaiting_plan_review"}:
        await _publish_workflow_command(task, event_type=EVENT_APPROVE_PLAN, producer="compat", payload={"comment": comment})
        return {"ok": True, "message": "已提交 workflow 方案批准指令"}
    return {"ok": False, "error": f"workflow 任务当前状态不可推进: {current}"}


class CreateTaskBody(BaseModel):
    title: str
    org: str = "太子"
    targetDept: str | None = None
    priority: str | None = None
    templateId: str | None = None
    params: dict[str, str] | None = None


class TaskActionBody(BaseModel):
    taskId: str
    action: str
    reason: str = ""


class ReviewActionBody(BaseModel):
    taskId: str
    action: str
    comment: str = ""


class AdvanceBody(BaseModel):
    taskId: str
    comment: str = ""


class ArchiveBody(BaseModel):
    taskId: str | None = None
    archived: bool | None = None
    archiveAllDone: bool | None = None


class SchedulerBody(BaseModel):
    taskId: str | None = None
    reason: str = ""
    thresholdSec: int = 180


@router.post("/create-task")
async def create_task_compat(body: CreateTaskBody, db: AsyncSession = Depends(get_db)):
    workflow_svc = WorkflowService(db)
    workflow = await workflow_svc.create_workflow(
        title=body.title,
        goal="",
        workflow_type="generic",
        owner=body.org or "taizi",
        meta={
            "created_via": "compat.create-task",
            "priority": body.priority or "中",
            "template_id": body.templateId or "",
            "template_params": body.params or {},
            "target_dept": body.targetDept or "",
        },
    )
    return {
        "ok": True,
        "taskId": str(workflow.task_id),
        "workflowId": str(workflow.id),
        "traceId": str(workflow.task_id),
        "state": str(workflow.state),
    }


@router.get("/officials-stats")
async def officials_stats_compat(db: AsyncSession = Depends(get_db)):
    payload = await build_officials_stats(db)
    return {
        "officials": payload.get("officials", []),
        "totals": payload.get("totals", {}),
        "top_official": payload.get("top_official", ""),
    }


@router.post("/task-action")
async def task_action(body: TaskActionBody, db: AsyncSession = Depends(get_db)):
    svc = await _svc(db)
    task = await svc.get_task(body.taskId)
    if _is_workflow_task(task):
        try:
            return await _handle_workflow_task_action(task, body.action, body.reason)
        except Exception as e:
            return {"ok": False, "error": str(e)}
    cur = TaskState(str(cast(Any, task).state))

    try:
        if body.action == "stop":
            await svc.transition_state(body.taskId, TaskState.Blocked, agent="compat", reason=body.reason)
        elif body.action == "cancel":
            await svc.transition_state(body.taskId, TaskState.Cancelled, agent="compat", reason=body.reason)
        elif body.action == "resume":
            if cur != TaskState.Blocked:
                return {"ok": False, "error": "仅 Blocked 任务可恢复"}

            prev = TaskState.Taizi
            flow_log = cast(Any, task).flow_log
            for item in reversed(flow_log if isinstance(flow_log, list) else []):
                if (item.get("to") or "") == TaskState.Blocked.value and item.get("from"):
                    prev = TaskState(item.get("from"))
                    break
            await svc.transition_state(body.taskId, prev, agent="compat", reason=body.reason or "恢复执行")
        else:
            return {"ok": False, "error": f"未知 action: {body.action}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}

    return {"ok": True, "message": "操作成功"}


@router.post("/review-action")
async def review_action(body: ReviewActionBody, db: AsyncSession = Depends(get_db)):
    svc = await _svc(db)
    task = await svc.get_task(body.taskId)
    if _is_workflow_task(task):
        try:
            return await _handle_workflow_review_action(task, body.action, body.comment)
        except Exception as e:
            return {"ok": False, "error": str(e)}
    cur = task.state if isinstance(task.state, TaskState) else TaskState(task.state)

    approve_map = {
        TaskState.Menxia: TaskState.YuLan,
        TaskState.YuLan: TaskState.Assigned,
        TaskState.Review: TaskState.Done,
    }
    reject_map = {
        TaskState.Menxia: TaskState.Zhongshu,
        TaskState.YuLan: TaskState.Zhongshu,
        TaskState.Review: TaskState.Doing,
    }

    target = approve_map.get(cur) if body.action == "approve" else reject_map.get(cur)
    if target is None:
        return {"ok": False, "error": f"当前状态不支持 {body.action}: {cur.value}"}

    try:
        await svc.transition_state(body.taskId, target, agent="compat", reason=body.comment)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "message": "操作成功"}


@router.post("/advance-state")
async def advance_state(body: AdvanceBody, db: AsyncSession = Depends(get_db)):
    svc = await _svc(db)
    task = await svc.get_task(body.taskId)
    if _is_workflow_task(task):
        try:
            return await _handle_workflow_advance(task, body.comment)
        except Exception as e:
            return {"ok": False, "error": str(e)}
    cur = task.state if isinstance(task.state, TaskState) else TaskState(task.state)

    next_map = {
        TaskState.Pending: TaskState.Taizi,
        TaskState.Taizi: TaskState.Zhongshu,
        TaskState.Zhongshu: TaskState.Menxia,
        TaskState.Menxia: TaskState.YuLan,
        TaskState.YuLan: TaskState.Assigned,
        TaskState.Assigned: TaskState.Doing,
        TaskState.Next: TaskState.Doing,
        TaskState.Doing: TaskState.Review,
        TaskState.Review: TaskState.Done,
        TaskState.Blocked: TaskState.Taizi,
    }
    target = next_map.get(cur)
    if target is None:
        return {"ok": False, "error": f"当前状态不可推进: {cur.value}"}

    try:
        await svc.transition_state(body.taskId, target, agent="compat", reason=body.comment)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "message": f"{cur.value} → {target.value}"}


@router.post("/archive-task")
async def archive_task(body: ArchiveBody, db: AsyncSession = Depends(get_db)):
    if body.archiveAllDone:
        stmt = select(Task).where(Task.archived.is_(False), Task.state.in_([TaskState.Done.value, TaskState.Cancelled.value]))
        rows = await db.execute(stmt)
        tasks = list(rows.scalars().all())
        for t in tasks:
            cast(Any, t).archived = True
        await db.commit()
        return {"ok": True, "count": len(tasks), "message": "批量归档完成"}

    if not body.taskId:
        return {"ok": False, "error": "缺少 taskId"}
    task = await db.get(Task, body.taskId)
    if task is None:
        return {"ok": False, "error": "任务不存在"}

    cast(Any, task).archived = bool(body.archived)
    cast(Any, task).updated_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True, "message": "归档状态已更新"}


@router.post("/scheduler-scan")
async def scheduler_scan(_body: SchedulerBody):
    return {"ok": True, "count": 0, "actions": [], "checkedAt": datetime.now(timezone.utc).isoformat()}


@router.post("/scheduler-retry")
async def scheduler_retry(body: SchedulerBody, db: AsyncSession = Depends(get_db)):
    if not body.taskId:
        return {"ok": False, "error": "缺少 taskId"}
    svc = await _svc(db)
    task = await svc.get_task(body.taskId)
    if _is_workflow_task(task):
        return {"ok": False, "error": "workflow 任务暂不支持 scheduler-retry，请通过 workflow command/decision"}
    st = TaskState(str(cast(Any, task).state))
    agent = STATE_AGENT_MAP.get(st)
    if st == TaskState.Assigned:
        agent = ORG_AGENT_MAP.get(str(cast(Any, task).org), agent)
    if agent is None:
        return {"ok": False, "error": f"当前状态无可重试 agent: {st.value}"}
    await svc.request_dispatch(body.taskId, agent, body.reason or "scheduler retry")
    return {"ok": True, "message": "已重试派发"}


@router.post("/scheduler-escalate")
async def scheduler_escalate(body: SchedulerBody, db: AsyncSession = Depends(get_db)):
    if not body.taskId:
        return {"ok": False, "error": "缺少 taskId"}
    task = await db.get(Task, body.taskId)
    if task is not None and _is_workflow_task(task):
        return {"ok": False, "error": "workflow 任务暂不支持 scheduler-escalate，请通过 workflow command/decision"}
    bus = await get_event_bus()
    await bus.publish(
        topic=TOPIC_TASK_ESCALATED,
        trace_id=body.taskId,
        event_type="task.scheduler.escalated",
        producer="compat",
        payload={"task_id": body.taskId, "reason": body.reason or "manual escalate"},
    )
    return {"ok": True, "message": "已升级协调"}


@router.post("/scheduler-rollback")
async def scheduler_rollback(body: SchedulerBody, db: AsyncSession = Depends(get_db)):
    if not body.taskId:
        return {"ok": False, "error": "缺少 taskId"}
    svc = await _svc(db)
    task = await svc.get_task(body.taskId)
    if _is_workflow_task(task):
        return {"ok": False, "error": "workflow 任务暂不支持 scheduler-rollback，请通过 workflow rollback"}
    try:
        await svc.transition_state(body.taskId, TaskState.Taizi, agent="compat", reason=body.reason or "scheduler rollback")
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "message": "已回滚到太子分拣"}


@router.get("/morning-brief")
async def get_morning_brief():
    return load_latest()


@router.get("/morning-brief/{date}")
async def get_morning_brief_by_date(date: str):
    date_clean = date.replace("-", "")
    if not date_clean.isdigit() or len(date_clean) != 8:
        return {"ok": False, "error": f"日期格式无效: {date}，请使用 YYYYMMDD"}
    return load_by_date(date_clean)


@router.get("/morning-config")
async def get_morning_config():
    return load_config()


@router.post("/morning-config")
async def save_morning_config(body: dict):
    if not isinstance(body, dict):
        return {"ok": False, "error": "请求体必须是 JSON 对象"}
    allowed_keys = {"categories", "keywords", "custom_feeds", "feishu_webhook"}
    unknown = set(body.keys()) - allowed_keys
    if unknown:
        return {"ok": False, "error": f"未知字段: {', '.join(unknown)}"}
    merged = {**DEFAULT_SUB_CONFIG, **body}
    return save_morning_payload(merged)


@router.post("/morning-brief/refresh")
async def refresh_morning_brief():
    import threading

    def do_refresh():
        try:
            refresh_morning_payload(force=True)
        except Exception:
            pass

    threading.Thread(target=do_refresh, daemon=True).start()
    return {"ok": True, "message": "采集已触发，约30-60秒后刷新"}
