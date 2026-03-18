"""核心接口定义 (Ports) — 依赖倒置的关键。

Kernel 只依赖这些 Protocol，不知道具体实现。
具体实现在 adapters/ 目录：
  - TaskRepo       → adapters/pg_task_repo.py (Postgres)
  - EventBusPort   → adapters/redis_event_bus.py (Redis Streams)
  - AgentExecutor  → adapters/openclaw_executor.py (OpenClaw CLI)
  - RoutingPolicy  → adapters/edict_routing.py (三省六部)
"""

from __future__ import annotations

from typing import Any, Protocol, runtime_checkable

try:  # installed/package mode
    from .task_entity import TaskEntity
except ImportError:  # source-path test mode
    from task_entity import TaskEntity


# ══════════════════════════════════════
# 1. TaskRepo — 工作项持久化
# ══════════════════════════════════════

@runtime_checkable
class TaskRepo(Protocol):
    """工作项仓储接口。"""

    async def create(self, entity: TaskEntity) -> TaskEntity:
        """持久化新工作项。"""
        ...

    async def get(self, task_id: str) -> TaskEntity | None:
        """根据 ID 获取，不存在返回 None。"""
        ...

    async def save(self, entity: TaskEntity) -> TaskEntity:
        """保存已有工作项的变更。"""
        ...

    async def list_by_state(
        self,
        state: str | None = None,
        assignee: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[TaskEntity]:
        """按条件查询。"""
        ...

    async def count(self, state: str | None = None) -> int:
        """计数。"""
        ...


# ══════════════════════════════════════
# 2. EventBusPort — 事件发布/消费
# ══════════════════════════════════════

@runtime_checkable
class EventBusPort(Protocol):
    """事件总线接口。"""

    async def publish(
        self,
        topic: str,
        trace_id: str,
        event_type: str,
        producer: str,
        payload: dict[str, Any] | None = None,
    ) -> str:
        """发布事件，返回 event_id。"""
        ...

    async def consume(
        self,
        topic: str,
        group: str,
        consumer: str,
        count: int = 10,
        block_ms: int = 5000,
    ) -> list[tuple[str, dict[str, Any]]]:
        """消费事件，返回 [(entry_id, event_data)]。"""
        ...

    async def ack(self, topic: str, group: str, entry_id: str) -> None:
        """确认消费。"""
        ...

    async def claim_stale(
        self,
        topic: str,
        group: str,
        consumer: str,
        min_idle_ms: int = 60000,
        count: int = 10,
    ) -> list[tuple[str, dict[str, Any]]]:
        """认领超时的 pending 事件。"""
        ...


# ══════════════════════════════════════
# 3. AgentExecutor — Agent 执行
# ══════════════════════════════════════

@runtime_checkable
class AgentExecutor(Protocol):
    """Agent 执行器接口。

    一次 execute 调用 = 一次 agent 工作单元。
    具体实现可以是 OpenClaw CLI、HTTP API、本地函数等。
    """

    async def execute(
        self,
        agent_id: str,
        message: str,
        context: dict[str, Any] | None = None,
        timeout: int = 300,
    ) -> "ExecutionResult":
        """执行 agent 任务。"""
        ...


class ExecutionResult:
    """Agent 执行结果。"""

    __slots__ = ("success", "output", "error", "duration_ms", "metadata")

    def __init__(
        self,
        success: bool,
        output: str = "",
        error: str = "",
        duration_ms: int = 0,
        metadata: dict[str, Any] | None = None,
    ):
        self.success = success
        self.output = output
        self.error = error
        self.duration_ms = duration_ms
        self.metadata = metadata or {}

    def to_dict(self) -> dict[str, Any]:
        return {
            "success": self.success,
            "output": self.output,
            "error": self.error,
            "duration_ms": self.duration_ms,
            "metadata": self.metadata,
        }


# ══════════════════════════════════════
# 4. RoutingPolicy — 路由策略
# ══════════════════════════════════════

@runtime_checkable
class RoutingPolicy(Protocol):
    """任务路由策略 — 决定下一个 agent 和状态。

    三省六部的具体路由逻辑是这个接口的一个实现。
    换一套组织架构只需换一个 RoutingPolicy。
    """

    def next_agent(self, task: TaskEntity) -> str | None:
        """根据当前任务状态决定下一个 agent。返回 None 表示无需派发。"""
        ...

    def next_state_after_completion(self, task: TaskEntity) -> str | None:
        """Agent 完成后应该转到什么状态。返回 None 表示保持不变。"""
        ...

    def suggest_assignee(self, task: TaskEntity) -> str:
        """建议的执行者/部门。"""
        ...
