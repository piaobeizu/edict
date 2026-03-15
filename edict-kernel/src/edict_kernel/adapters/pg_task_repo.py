"""PostgreSQL TaskRepo 实现 — 桥接 kernel.TaskEntity ↔ SQLAlchemy Task ORM。"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from edict_kernel.task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem


class PgTaskRepo:
    """实现 kernel.ports.TaskRepo，基于 SQLAlchemy async。"""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, entity: TaskEntity) -> TaskEntity:
        from app.models.task import Task  # 延迟导入避免循环

        task = Task(
            id=entity.id,
            title=entity.title,
            state=entity.state,
            org=entity.assignee,
            official=entity.creator,
            now=entity.description,
            priority=entity.priority,
            block="无" if not entity.block_reason else entity.block_reason,
            flow_log=[e.to_dict() for e in entity.flow_log],
            progress_log=[e.to_dict() for e in entity.progress_log],
            todos=[t.to_dict() for t in entity.todos],
            scheduler=entity.scheduler_meta,
            template_id=entity.template_id,
            template_params=entity.template_params,
            ac=entity.acceptance_criteria,
            target_dept=entity.target_assignee,
        )
        self.db.add(task)
        await self.db.flush()
        await self.db.commit()
        return entity

    async def get(self, task_id: str) -> TaskEntity | None:
        from app.models.task import Task

        task = await self.db.get(Task, task_id)
        if task is None:
            return None
        return self._to_entity(task)

    async def save(self, entity: TaskEntity) -> TaskEntity:
        from app.models.task import Task

        task = await self.db.get(Task, entity.id)
        if task is None:
            raise ValueError(f"Task not found: {entity.id}")

        task.title = entity.title
        task.state = entity.state
        task.org = entity.assignee
        task.now = entity.description
        task.priority = entity.priority
        task.output = entity.output
        task.block = entity.block_reason or "无"
        task.archived = entity.archived
        task.flow_log = [e.to_dict() for e in entity.flow_log]
        task.progress_log = [e.to_dict() for e in entity.progress_log]
        task.todos = [t.to_dict() for t in entity.todos]
        task.scheduler = entity.scheduler_meta
        task.template_id = entity.template_id
        task.template_params = entity.template_params
        task.ac = entity.acceptance_criteria
        task.target_dept = entity.target_assignee
        task.updated_at = datetime.now(timezone.utc)

        await self.db.commit()
        return entity

    async def list_by_state(
        self,
        state: str | None = None,
        assignee: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[TaskEntity]:
        from app.models.task import Task

        stmt = select(Task)
        conditions = []
        if state is not None:
            conditions.append(Task.state == state)
        if assignee is not None:
            conditions.append(Task.org == assignee)
        if conditions:
            stmt = stmt.where(and_(*conditions))
        stmt = stmt.order_by(Task.created_at.desc()).limit(limit).offset(offset)
        result = await self.db.execute(stmt)
        return [self._to_entity(t) for t in result.scalars().all()]

    async def count(self, state: str | None = None) -> int:
        from app.models.task import Task

        stmt = select(func.count(Task.id))
        if state is not None:
            stmt = stmt.where(Task.state == state)
        result = await self.db.execute(stmt)
        return result.scalar_one()

    @staticmethod
    def _to_entity(task: Any) -> TaskEntity:
        """ORM Task → kernel TaskEntity。"""
        return TaskEntity(
            id=str(task.id),
            title=task.title or "",
            state=task.state.value if hasattr(task.state, "value") else str(task.state or ""),
            assignee=task.org or "",
            creator=task.official or "",
            description=task.now or "",
            priority=task.priority or "normal",
            output=task.output or "",
            block_reason=task.block or "",
            archived=bool(task.archived),
            flow_log=[
                FlowEntry(
                    from_state=e.get("from"),
                    to_state=e.get("to", ""),
                    agent=e.get("agent", ""),
                    reason=e.get("reason", ""),
                    ts=e.get("ts", ""),
                )
                for e in (task.flow_log or [])
            ],
            progress_log=[
                ProgressEntry(
                    agent=e.get("agent", ""),
                    content=e.get("content", e.get("text", "")),
                    ts=e.get("ts", ""),
                )
                for e in (task.progress_log or [])
            ],
            todos=[
                TodoItem(
                    id=t.get("id", i),
                    title=t.get("title", ""),
                    status=t.get("status", "not-started"),
                    detail=t.get("detail", ""),
                )
                for i, t in enumerate(task.todos or [])
            ],
            template_id=task.template_id or "",
            template_params=task.template_params or {},
            acceptance_criteria=task.ac or "",
            target_assignee=task.target_dept or "",
            scheduler_meta=task.scheduler or {},
            created_at=task.created_at or datetime.now(timezone.utc),
            updated_at=task.updated_at or datetime.now(timezone.utc),
        )
