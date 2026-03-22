"""Project workflow snapshots into legacy task rows."""

from __future__ import annotations

from dataclasses import asdict, is_dataclass
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from ..repos.workflow_repo import WorkflowRepo
from ..models.task import Task

WORKFLOW_TO_TASK_STATE = {
    "draft": "Pending",
    "planning": "Zhongshu",
    "awaiting_plan_review": "YuLan",
    "executing": "Doing",
    "awaiting_selection": "Review",
    "assembling": "Review",
    "awaiting_final_review": "YuLan",
    "done": "Done",
    "blocked": "Blocked",
    "cancelled": "Cancelled",
}
WORKFLOW_TERMINAL_STATES = {"done", "cancelled"}


def apply_workflow_snapshot_to_task(task: Task, snapshot: Any) -> Task:
    """Apply a workflow snapshot onto a legacy task projection row."""
    workflow = snapshot.workflow
    nodes = list(getattr(snapshot, "nodes", []) or [])
    revisions = list(getattr(snapshot, "revisions", []) or [])
    previous_state = str(getattr(task, "state", "") or "")
    previous_flow_log = list(getattr(task, "flow_log", None) or [])

    task.workflow_id = getattr(workflow, "id", "") or ""
    task.workflow_type = getattr(workflow, "type", "generic") or "generic"
    task.projection_version = int(getattr(task, "projection_version", 0) or 0) + 1
    task.current_revision_id = getattr(workflow, "current_revision_id", "") or ""
    task.current_assembly_id = getattr(workflow, "current_assembly_id", "") or ""
    task.state = WORKFLOW_TO_TASK_STATE.get(getattr(workflow, "state", ""), "Pending")
    task.org = _derive_owner(workflow, nodes)
    task.now = _derive_now(workflow, nodes)
    task.output = getattr(workflow, "summary_output", "") or ""
    workflow_state = str(getattr(workflow, "state", "") or "")
    task.pending_review_count = _pending_review_count(workflow_state, nodes)
    task.running_node_count = sum(1 for node in nodes if getattr(node, "state", "") == "running")
    task.todos = _build_todos(workflow, nodes)
    task.flow_log = _build_flow_log(previous_state, task.state, workflow, previous_flow_log)
    task.progress_log = _build_progress_log(revisions, nodes)
    scheduler = dict(getattr(task, "scheduler", None) or {})
    scheduler.update(
        {
            "workflowVersion": 2,
            "workflowId": task.workflow_id,
            "currentRevisionId": task.current_revision_id,
            "currentAssemblyId": task.current_assembly_id,
            "pendingReviewCount": task.pending_review_count,
            "runningNodeCount": task.running_node_count,
        }
    )
    task.scheduler = scheduler
    return task


def _derive_owner(workflow: Any, nodes: list[Any]) -> str:
    for node in nodes:
        if getattr(node, "state", "") in {"awaiting_review", "running"} and getattr(node, "assignee", ""):
            return str(getattr(node, "assignee"))
    return str(getattr(workflow, "owner", "") or "")


def _derive_now(workflow: Any, nodes: list[Any]) -> str:
    total = len(nodes)
    if total:
        workflow_state = str(getattr(workflow, "state", "") or "")
        approved = sum(1 for node in nodes if getattr(node, "state", "") == "approved")
        running = sum(1 for node in nodes if getattr(node, "state", "") == "running")
        pending_review = _pending_review_count(workflow_state, nodes)
        return f"共 {total} 个节点，已完成 {approved} 个，执行中 {running} 个，待审 {pending_review} 个"
    return str(getattr(workflow, "summary_output", "") or "")


def _pending_review_count(workflow_state: str, nodes: list[Any]) -> int:
    if workflow_state in WORKFLOW_TERMINAL_STATES:
        return 0
    return sum(1 for node in nodes if getattr(node, "state", "") in {"awaiting_review", "produced"})


def _build_todos(workflow: Any, nodes: list[Any]) -> list[dict[str, Any]]:
    current_revision_id = getattr(workflow, "current_revision_id", "") or ""
    filtered = [n for n in nodes if not current_revision_id or getattr(n, "revision_id", "") == current_revision_id]
    todos = []
    for index, node in enumerate(sorted(filtered, key=lambda item: getattr(item, "sequence", 0)), start=1):
        state = getattr(node, "state", "")
        if state == "approved":
            todo_status = "completed"
        elif state == "running":
            todo_status = "in-progress"
        else:
            todo_status = "not-started"
        todos.append(
            {
                "id": str(getattr(node, "id", "")),
                "title": str(getattr(node, "title", f"Node {index}")),
                "status": todo_status,
                "detail": str(getattr(node, "description", "") or ""),
            }
        )
    return todos


def _build_flow_log(
    previous_state: str,
    task_state: str,
    workflow: Any,
    existing_flow_log: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    flow_log = list(existing_flow_log or [])
    if not flow_log:
        return [
            {
                "from": None,
                "to": task_state,
                "agent": "projection_worker",
                "reason": f"workflow:{getattr(workflow, 'state', '')}",
                "ts": _iso(getattr(workflow, "updated_at", None)),
            }
        ]
    last_to = str(flow_log[-1].get("to") or "")
    if last_to == task_state or previous_state == task_state:
        return flow_log
    flow_log.append(
        {
            "from": previous_state or last_to or None,
            "to": task_state,
            "agent": "projection_worker",
            "reason": f"workflow:{getattr(workflow, 'state', '')}",
            "ts": _iso(getattr(workflow, "updated_at", None)),
        }
    )
    return flow_log


def _build_progress_log(revisions: list[Any], nodes: list[Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for revision in revisions[-3:]:
        items.append(
            {
                "agent": str(getattr(revision, "created_by", "") or "workflow"),
                "content": f"revision#{getattr(revision, 'number', '?')} {getattr(revision, 'status', '')}",
                "ts": _iso(getattr(revision, "updated_at", None)),
            }
        )
    for node in sorted(nodes, key=lambda item: getattr(item, "sequence", 0))[-5:]:
        items.append(
            {
                "agent": str(getattr(node, "assignee", "") or "workflow"),
                "content": f"{getattr(node, 'title', '')}: {getattr(node, 'state', '')}",
                "ts": _iso(getattr(node, "updated_at", None)),
            }
        )
    return items


def _iso(value: Any) -> str:
    if value is None:
        return ""
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def dataclass_to_jsonable(value: Any) -> Any:
    if is_dataclass(value):
        return asdict(value)
    return value


class TaskProjectionService:
    def __init__(self, db: AsyncSession, workflow_repo: WorkflowRepo):
        self.db = db
        self.workflow_repo = workflow_repo

    async def refresh_workflow_projection(self, workflow_id: str) -> Task:
        snapshot = await self.workflow_repo.load_snapshot(workflow_id)
        task = await self.db.get(Task, snapshot.workflow.task_id)
        if task is None:
            task = Task(
                id=snapshot.workflow.task_id,
                title=snapshot.workflow.title,
                state="Pending",
                org="workflow",
                official=snapshot.workflow.owner or "",
                now="",
                priority="normal",
                flow_log=[],
                progress_log=[],
                todos=[],
                scheduler={},
            )
            self.db.add(task)
            await self.db.flush()
        task.title = snapshot.workflow.title
        task.official = snapshot.workflow.owner or task.official
        apply_workflow_snapshot_to_task(task, snapshot)
        await self.db.flush()
        return task
