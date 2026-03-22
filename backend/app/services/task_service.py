"""任务服务层 — CRUD + 状态机逻辑。

所有业务规则集中在此：
- 创建任务 → 发布 task.created 事件
- 状态流转 → 校验合法性 + 发布状态事件
- 查询、过滤、聚合
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.task import Task, TaskState, STATE_TRANSITIONS, TERMINAL_STATES
from .event_bus import (
    EventBus,
    TOPIC_TASK_CREATED,
    TOPIC_TASK_STATUS,
    TOPIC_TASK_COMPLETED,
    TOPIC_TASK_DISPATCH,
)

log = logging.getLogger("edict.task_service")


def generate_task_id(now: datetime | None = None) -> str:
    """生成任务 ID。

    采用秒级时间戳 + 8 位随机后缀，降低同秒内的碰撞风险，且长度保持在
    Task.id 的 32 字符上限之内。
    """
    ts = now or datetime.now(timezone.utc)
    return ts.strftime("JJC-%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]


class TaskService:
    def __init__(self, db: AsyncSession, event_bus: EventBus):
        self.db = db
        self.bus = event_bus

    # ── 创建 ──

    async def create_task(
        self,
        title: str,
        description: str = "",
        priority: str = "中",
        assignee_org: str | None = None,
        creator: str = "emperor",
        tags: list[str] | None = None,
        initial_state: TaskState = TaskState.Taizi,
        meta: dict | None = None,
    ) -> Task:
        """创建任务并发布 task.created 事件。"""
        now = datetime.now(timezone.utc)
        task_id = generate_task_id(now)

        task = Task(
            id=task_id,
            title=title,
            priority=priority,
            state=initial_state.value,
            org=assignee_org or "太子",
            official=creator,
            now=description or "",
            block="无",
            flow_log=[
                {
                    "from": None,
                    "to": initial_state.value,
                    "agent": "system",
                    "reason": "任务创建",
                    "ts": now.isoformat(),
                }
            ],
            progress_log=[],
            todos=[],
            scheduler=meta or {},
        )
        self.db.add(task)
        await self.db.commit()

        # 先提交 DB 再发布事件，确保下游消费者能查到任务
        await self.bus.publish(
            topic=TOPIC_TASK_CREATED,
            trace_id=task_id,
            event_type="task.created",
            producer="task_service",
            payload={
                "task_id": str(task.id),
                "title": title,
                "state": initial_state.value,
                "priority": priority,
                "assignee_org": assignee_org or "太子",
                "tags": tags or [],
            },
        )
        log.info(f"Created task {task.id}: {title} [{initial_state.value}]")
        return task

    # ── 状态流转 ──

    async def transition_state(
        self,
        task_id: str,
        new_state: TaskState,
        agent: str = "system",
        reason: str = "",
    ) -> Task:
        """执行状态流转，校验合法性（带行级锁防止并发竞争）。"""
        from sqlalchemy import select as sa_select
        stmt = sa_select(Task).where(Task.id == task_id).with_for_update()
        result = await self.db.execute(stmt)
        task = result.scalars().first()
        if task is None:
            raise ValueError(f"Task not found: {task_id}")
        self._assert_legacy_mutation(task, "transition_state")
        old_state = task.state if isinstance(task.state, TaskState) else TaskState(task.state)

        # 校验合法流转
        allowed = STATE_TRANSITIONS.get(old_state, set())
        if new_state not in allowed:
            raise ValueError(
                f"Invalid transition: {old_state.value} → {new_state.value}. "
                f"Allowed: {[s.value for s in allowed]}"
            )

        task.state = new_state.value
        task.updated_at = datetime.now(timezone.utc)

        # 记入 flow_log
        flow_entry = {
            "from": old_state.value,
            "to": new_state.value,
            "agent": agent,
            "reason": reason,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        if task.flow_log is None:
            task.flow_log = []
        task.flow_log = [*task.flow_log, flow_entry]

        await self.db.commit()

        # 先提交 DB 再发布事件，确保下游消费者读到最新状态
        topic = TOPIC_TASK_COMPLETED if new_state in TERMINAL_STATES else TOPIC_TASK_STATUS
        await self.bus.publish(
            topic=topic,
            trace_id=str(task.id),
            event_type=f"task.state.{new_state.value}",
            producer=agent,
            payload={
                "task_id": str(task_id),
                "from": old_state.value,
                "to": new_state.value,
                "reason": reason,
                "assignee_org": task.org,
            },
        )

        log.info(f"Task {task_id} state: {old_state.value} → {new_state.value} by {agent}")
        return task

    # ── 派发请求 ──

    async def request_dispatch(
        self,
        task_id: str,
        target_agent: str,
        message: str = "",
    ):
        """发布 task.dispatch 事件，由 DispatchWorker 消费执行。"""
        task = await self._get_task(task_id)
        self._assert_legacy_mutation(task, "request_dispatch")
        scheduler = dict(task.scheduler or {})
        dispatch_round = int(scheduler.get("lastDispatchRound", 0) or 0) + 1
        await self.bus.publish(
            topic=TOPIC_TASK_DISPATCH,
            trace_id=str(task.id),
            event_type="task.dispatch.request",
            producer="task_service",
            payload={
                "task_id": str(task_id),
                "agent": target_agent,
                "message": message,
                "state": task.state.value if isinstance(task.state, TaskState) else str(task.state),
                "dispatch_round": dispatch_round,
            },
        )
        log.info(f"Dispatch requested: task {task_id} → agent {target_agent}")

    # ── 进度/备注更新 ──

    async def add_progress(
        self,
        task_id: str,
        agent: str,
        content: str,
    ) -> Task:
        task = await self._get_task(task_id)
        self._assert_legacy_mutation(task, "add_progress")
        entry = {
            "agent": agent,
            "content": content,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        if task.progress_log is None:
            task.progress_log = []
        task.progress_log = [*task.progress_log, entry]
        task.updated_at = datetime.now(timezone.utc)
        await self.db.commit()
        return task

    async def update_todos(
        self,
        task_id: str,
        todos: list[dict],
    ) -> Task:
        task = await self._get_task(task_id)
        self._assert_legacy_mutation(task, "update_todos")
        task.todos = todos
        task.updated_at = datetime.now(timezone.utc)
        await self.db.commit()
        return task

    async def update_scheduler(
        self,
        task_id: str,
        scheduler: dict,
    ) -> Task:
        task = await self._get_task(task_id)
        self._assert_legacy_mutation(task, "update_scheduler")
        task.scheduler = scheduler
        task.updated_at = datetime.now(timezone.utc)
        await self.db.commit()
        return task

    # ── 查询 ──

    async def get_task(self, task_id: str) -> Task:
        return await self._get_task(task_id)

    async def list_tasks(
        self,
        state: TaskState | None = None,
        assignee_org: str | None = None,
        priority: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[Task]:
        stmt = select(Task)
        conditions = []
        if state is not None:
            conditions.append(Task.state == state.value)
        if assignee_org is not None:
            conditions.append(Task.org == assignee_org)
        if priority is not None:
            conditions.append(Task.priority == priority)
        if conditions:
            stmt = stmt.where(and_(*conditions))
        stmt = stmt.order_by(Task.created_at.desc()).limit(limit).offset(offset)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_live_status(self) -> dict[str, Any]:
        """生成兼容旧 live_status.json 格式的全局状态。"""
        tasks = await self.list_tasks(limit=200)
        active_tasks = {}
        completed_tasks = {}
        for t in tasks:
            # Frontend 已切换为 workflow v2 单轨，缺少 workflow_id 的遗留任务
            # 统一通过数据迁移脚本处理，避免进入新前端列表造成“不可打开”项。
            if not str(getattr(t, "workflow_id", "") or "").strip():
                continue
            d = t.to_dict()
            st = t.state if isinstance(t.state, TaskState) else TaskState(t.state)
            if st in TERMINAL_STATES:
                completed_tasks[str(t.id)] = d
            else:
                active_tasks[str(t.id)] = d
        return {
            "tasks": active_tasks,
            "completed_tasks": completed_tasks,
            "last_updated": datetime.now(timezone.utc).isoformat(),
        }

    async def count_tasks(self, state: TaskState | None = None) -> int:
        stmt = select(func.count(Task.id))
        if state is not None:
            stmt = stmt.where(Task.state == state.value)
        result = await self.db.execute(stmt)
        return result.scalar_one()

    # ── 内部 ──

    async def _get_task(self, task_id: str) -> Task:
        task = await self.db.get(Task, task_id)
        if task is None:
            raise ValueError(f"Task not found: {task_id}")
        return task

    @staticmethod
    def _assert_legacy_mutation(task: Task, op: str) -> None:
        workflow_type = str(getattr(task, "workflow_type", "legacy") or "legacy")
        if workflow_type != "legacy":
            raise ValueError(
                f"Task {task.id} is workflow_type={workflow_type}; "
                f"{op} must go through workflow v2 projection/decision flow"
            )
