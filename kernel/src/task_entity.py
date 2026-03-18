"""TaskEntity — 纯数据类，不绑定任何 ORM / 框架。

这是 kernel 对"工作项"的唯一定义。
ORM 模型 (app/models/task.py) 是这个实体的持久化映射，不是核心。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass
class FlowEntry:
    """一次流转记录。"""
    from_state: str | None
    to_state: str
    agent: str
    reason: str
    ts: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_dict(self) -> dict[str, Any]:
        return {"from": self.from_state, "to": self.to_state, "agent": self.agent, "reason": self.reason, "ts": self.ts}


@dataclass
class ProgressEntry:
    """一条进展记录。"""
    agent: str
    content: str
    ts: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    todos: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {"agent": self.agent, "content": self.content, "ts": self.ts}
        if self.todos:
            d["todos"] = self.todos
        return d


@dataclass
class TodoItem:
    """一个子任务。"""
    id: str | int
    title: str
    status: str = "not-started"  # not-started | in-progress | completed
    detail: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {"id": self.id, "title": self.title, "status": self.status, "detail": self.detail}


@dataclass
class TaskEntity:
    """工作流引擎的核心实体 — 与框架/存储无关。

    所有状态变更通过 kernel 方法执行，不允许外部直接改 state 字段。
    """

    id: str
    title: str
    state: str
    assignee: str = ""           # 当前负责人/部门
    creator: str = ""
    description: str = ""
    priority: str = "normal"
    output: str = ""
    block_reason: str = ""
    archived: bool = False

    # 日志
    flow_log: list[FlowEntry] = field(default_factory=list)
    progress_log: list[ProgressEntry] = field(default_factory=list)
    todos: list[TodoItem] = field(default_factory=list)

    # 元数据
    template_id: str = ""
    template_params: dict[str, Any] = field(default_factory=dict)
    acceptance_criteria: str = ""
    target_assignee: str = ""    # 建议的最终执行者
    scheduler_meta: dict[str, Any] = field(default_factory=dict)
    extra: dict[str, Any] = field(default_factory=dict)

    # 时间
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def touch(self) -> None:
        """更新 updated_at。"""
        self.updated_at = datetime.now(timezone.utc)

    def append_flow(self, entry: FlowEntry) -> None:
        self.flow_log.append(entry)
        self.touch()

    def append_progress(self, entry: ProgressEntry) -> None:
        self.progress_log.append(entry)
        self.touch()

    def to_dict(self) -> dict[str, Any]:
        """序列化为字典（API 响应、JSON 持久化通用）。"""
        return {
            "id": self.id,
            "title": self.title,
            "state": self.state,
            "assignee": self.assignee,
            "creator": self.creator,
            "description": self.description,
            "priority": self.priority,
            "output": self.output,
            "block_reason": self.block_reason,
            "archived": self.archived,
            "flow_log": [e.to_dict() for e in self.flow_log],
            "progress_log": [e.to_dict() for e in self.progress_log],
            "todos": [t.to_dict() for t in self.todos],
            "template_id": self.template_id,
            "template_params": self.template_params,
            "acceptance_criteria": self.acceptance_criteria,
            "target_assignee": self.target_assignee,
            "scheduler_meta": self.scheduler_meta,
            "created_at": self.created_at.isoformat() if self.created_at else "",
            "updated_at": self.updated_at.isoformat() if self.updated_at else "",
        }
