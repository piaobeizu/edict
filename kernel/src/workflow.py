"""WorkflowEngine — kernel 核心编排逻辑。

协调 StateMachine + TaskRepo + EventBusPort，
提供创建/转换/派发/进展更新的高层方法。

不含任何业务语义（没有"太子""中书省"等概念）。
业务层通过 RoutingPolicy 注入具体路由规则。
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

try:  # installed/package mode
    from .state_machine import StateMachine, InvalidTransitionError
    from .task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
    from .ports import TaskRepo, EventBusPort, RoutingPolicy, AgentExecutor, ExecutionResult
except ImportError:  # source-path test mode
    from state_machine import StateMachine, InvalidTransitionError
    from task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
    from ports import TaskRepo, EventBusPort, RoutingPolicy, AgentExecutor, ExecutionResult

log = logging.getLogger("kernel.workflow")

# ── 标准事件类型（业务层可扩展，但这些是 kernel 保证发出的）──
EVENT_TASK_CREATED = "task.created"
EVENT_TASK_STATE_CHANGED = "task.state.changed"
EVENT_TASK_COMPLETED = "task.completed"
EVENT_TASK_DISPATCH = "task.dispatch"
EVENT_TASK_PROGRESS = "task.progress"


class WorkflowEngine:
    """工作流引擎 — kernel 的唯一入口。

    所有工作项操作都通过这个类执行。
    它协调 StateMachine（规则）+ Repo（持久化）+ Bus（事件）+ Policy（路由）。

    用法:
        engine = WorkflowEngine(
            state_machine=sm,
            repo=pg_repo,
            bus=redis_bus,
            routing=edict_routing,
        )
        task = await engine.create_task("写周报", priority="高")
        task = await engine.transition(task.id, "Zhongshu", agent="taizi")
        await engine.dispatch(task.id)
    """

    def __init__(
        self,
        state_machine: StateMachine,
        repo: TaskRepo,
        bus: EventBusPort,
        routing: RoutingPolicy | None = None,
    ):
        self.sm = state_machine
        self.repo = repo
        self.bus = bus
        self.routing = routing

    # ── 创建 ──

    async def create_task(
        self,
        title: str,
        *,
        description: str = "",
        priority: str = "normal",
        assignee: str = "",
        creator: str = "system",
        template_id: str = "",
        template_params: dict[str, Any] | None = None,
        acceptance_criteria: str = "",
        target_assignee: str = "",
        meta: dict[str, Any] | None = None,
    ) -> TaskEntity:
        """创建工作项并发布 created 事件。"""
        initial = self.sm.initial_state

        # 如有路由策略，用它决定初始 assignee
        assignee = assignee or ""

        now = datetime.now(timezone.utc)
        entity = TaskEntity(
            id=self._generate_id(now),
            title=title,
            state=initial,
            assignee=assignee,
            creator=creator,
            description=description,
            priority=priority,
            template_id=template_id,
            template_params=template_params or {},
            acceptance_criteria=acceptance_criteria,
            target_assignee=target_assignee,
            scheduler_meta=meta or {},
            flow_log=[FlowEntry(from_state=None, to_state=initial, agent="system", reason="创建")],
            created_at=now,
            updated_at=now,
        )

        entity = await self.repo.create(entity)

        await self.bus.publish(
            topic=EVENT_TASK_CREATED,
            trace_id=entity.id,
            event_type=EVENT_TASK_CREATED,
            producer=creator,
            payload={
                "task_id": entity.id,
                "title": title,
                "state": initial,
                "priority": priority,
                "assignee": assignee,
            },
        )
        log.info(f"Created task {entity.id}: {title} [{initial}]")
        return entity

    # ── 状态转换 ──

    async def transition(
        self,
        task_id: str,
        target_state: str,
        *,
        agent: str = "system",
        reason: str = "",
    ) -> TaskEntity:
        """执行状态转换。校验合法性 → 更新 → 记录 flow_log → 发事件。"""
        entity = await self._get(task_id)
        old_state = entity.state

        # 状态机校验（非法会抛 InvalidTransitionError）
        self.sm.transition(old_state, target_state, agent, reason)

        # 更新实体
        entity.state = target_state
        entity.append_flow(FlowEntry(
            from_state=old_state,
            to_state=target_state,
            agent=agent,
            reason=reason,
        ))

        entity = await self.repo.save(entity)

        # 发布事件
        is_terminal = self.sm.is_terminal(target_state)
        topic = EVENT_TASK_COMPLETED if is_terminal else EVENT_TASK_STATE_CHANGED
        await self.bus.publish(
            topic=topic,
            trace_id=task_id,
            event_type=f"task.state.{target_state}",
            producer=agent,
            payload={
                "task_id": task_id,
                "from": old_state,
                "to": target_state,
                "reason": reason,
                "assignee": entity.assignee,
            },
        )
        log.info(f"Task {task_id}: {old_state} → {target_state} by {agent}")
        return entity

    # ── 派发 ──

    async def dispatch(
        self,
        task_id: str,
        target_agent: str | None = None,
        message: str = "",
    ) -> None:
        """发布 dispatch 事件，由下游 Worker 消费执行。

        如果未指定 target_agent 且有 RoutingPolicy，自动决定。
        """
        entity = await self._get(task_id)

        if target_agent is None and self.routing:
            target_agent = self.routing.next_agent(entity)
        if not target_agent:
            log.warning(f"No agent to dispatch for task {task_id} in state {entity.state}")
            return

        dispatch_round = int(entity.scheduler_meta.get("lastDispatchRound", 0) or 0) + 1

        await self.bus.publish(
            topic=EVENT_TASK_DISPATCH,
            trace_id=task_id,
            event_type="task.dispatch.request",
            producer="workflow_engine",
            payload={
                "task_id": task_id,
                "agent": target_agent,
                "message": message,
                "state": entity.state,
                "dispatch_round": dispatch_round,
            },
        )
        log.info(f"Dispatch: task {task_id} → agent {target_agent} (round {dispatch_round})")

    # ── 进展更新 ──

    async def add_progress(
        self,
        task_id: str,
        agent: str,
        content: str,
    ) -> TaskEntity:
        """追加进展记录。"""
        entity = await self._get(task_id)
        entity.append_progress(ProgressEntry(agent=agent, content=content))
        entity = await self.repo.save(entity)

        await self.bus.publish(
            topic=EVENT_TASK_PROGRESS,
            trace_id=task_id,
            event_type="task.progress",
            producer=agent,
            payload={"task_id": task_id, "agent": agent, "content": content[:500]},
        )
        return entity

    async def update_todos(
        self,
        task_id: str,
        todos: list[dict[str, Any]],
    ) -> TaskEntity:
        """更新子任务列表。"""
        entity = await self._get(task_id)
        entity.todos = [
            TodoItem(
                id=t.get("id", i),
                title=t.get("title", ""),
                status=t.get("status", "not-started"),
                detail=t.get("detail", ""),
            )
            for i, t in enumerate(todos)
        ]
        entity.touch()
        return await self.repo.save(entity)

    # ── 查询 ──

    async def get_task(self, task_id: str) -> TaskEntity | None:
        return await self.repo.get(task_id)

    async def list_tasks(
        self,
        state: str | None = None,
        assignee: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[TaskEntity]:
        return await self.repo.list_by_state(state, assignee, limit, offset)

    # ── 内部 ──

    async def _get(self, task_id: str) -> TaskEntity:
        entity = await self.repo.get(task_id)
        if entity is None:
            raise ValueError(f"Task not found: {task_id}")
        return entity

    @staticmethod
    def _generate_id(now: datetime) -> str:
        """默认 ID 生成（业务层可通过子类覆盖）。"""
        import uuid as _uuid
        return now.strftime("WF-%Y%m%d-%H%M%S") + "-" + _uuid.uuid4().hex[:4]
