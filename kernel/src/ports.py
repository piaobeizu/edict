"""核心接口定义 (Ports) — 依赖倒置的关键。

Kernel 只依赖这些 Protocol，不知道具体实现。
"""

from __future__ import annotations

from typing import Any, Protocol, runtime_checkable

from .task_entity import TaskEntity


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
# 3. ExecutionResult — Agent 执行结果
# ══════════════════════════════════════

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
