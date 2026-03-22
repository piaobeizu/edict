#!/usr/bin/env python3
"""Recompute all workflow->task projections.

Usage:
  python backend/migration/recompute_workflow_projections.py
  python backend/migration/recompute_workflow_projections.py --apply
  python backend/migration/recompute_workflow_projections.py --apply --limit 100
  python backend/migration/recompute_workflow_projections.py --workflow-id wf-xxx --apply
"""

from __future__ import annotations

import argparse
import asyncio
import copy
import logging
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from sqlalchemy import select

# Ensure "app.*" imports work when script is run from repo root.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.db import async_session
from app.models.task import Task
from app.models.workflow_models import WorkflowInstance
from app.repos.workflow_repo import WorkflowRepo
from app.services.task_projection_service import apply_workflow_snapshot_to_task

log = logging.getLogger("recompute.workflow_projection")

COMPARE_FIELDS = (
    "state",
    "org",
    "now",
    "output",
    "current_revision_id",
    "current_assembly_id",
    "pending_review_count",
    "running_node_count",
    "todos",
    "flow_log",
    "progress_log",
    "scheduler",
)


def _snapshot_task_fields(task: Any) -> dict[str, Any]:
    return {name: copy.deepcopy(getattr(task, name, None)) for name in COMPARE_FIELDS}


def _clone_task_for_projection(task: Task) -> SimpleNamespace:
    # Keep fields used by apply_workflow_snapshot_to_task.
    return SimpleNamespace(
        id=getattr(task, "id", ""),
        title=getattr(task, "title", ""),
        state=getattr(task, "state", ""),
        org=getattr(task, "org", ""),
        official=getattr(task, "official", ""),
        now=getattr(task, "now", ""),
        output=getattr(task, "output", ""),
        workflow_id=getattr(task, "workflow_id", ""),
        workflow_type=getattr(task, "workflow_type", ""),
        projection_version=getattr(task, "projection_version", 0),
        current_revision_id=getattr(task, "current_revision_id", ""),
        current_assembly_id=getattr(task, "current_assembly_id", ""),
        pending_review_count=getattr(task, "pending_review_count", 0),
        running_node_count=getattr(task, "running_node_count", 0),
        todos=copy.deepcopy(getattr(task, "todos", None) or []),
        flow_log=copy.deepcopy(getattr(task, "flow_log", None) or []),
        progress_log=copy.deepcopy(getattr(task, "progress_log", None) or []),
        scheduler=copy.deepcopy(getattr(task, "scheduler", None) or {}),
    )


def _preview_projection(task: Task, snapshot: Any) -> dict[str, Any]:
    clone = _clone_task_for_projection(task)
    clone.title = snapshot.workflow.title
    clone.official = snapshot.workflow.owner or clone.official
    projected = apply_workflow_snapshot_to_task(clone, snapshot)
    return _snapshot_task_fields(projected)


async def _run(
    *,
    apply: bool,
    limit: int | None,
    workflow_id: str | None,
    batch_size: int,
) -> dict[str, int]:
    summary = {
        "total": 0,
        "missing_task": 0,
        "changed": 0,
        "unchanged": 0,
        "applied": 0,
    }
    async with async_session() as db:
        stmt = select(WorkflowInstance).order_by(WorkflowInstance.updated_at.desc(), WorkflowInstance.id.asc())
        if workflow_id:
            stmt = stmt.where(WorkflowInstance.id == workflow_id)
        if limit and limit > 0:
            stmt = stmt.limit(limit)
        workflows = list((await db.execute(stmt)).scalars().all())
        summary["total"] = len(workflows)
        log.info("Found %d workflows to recompute", len(workflows))
        if not workflows:
            return summary

        applied_in_batch = 0
        repo = WorkflowRepo(db)
        for wf in workflows:
            snapshot = await repo.load_snapshot(wf.id, include_decisions=True)
            task = await db.get(Task, snapshot.workflow.task_id)
            if task is None:
                summary["missing_task"] += 1
                log.warning("task row missing for workflow=%s task_id=%s", wf.id, snapshot.workflow.task_id)
                continue

            before = _snapshot_task_fields(task)
            after = _preview_projection(task, snapshot)
            changed = before != after
            if changed:
                summary["changed"] += 1
                log.info("[CHANGE] workflow=%s task=%s", wf.id, task.id)
                if apply:
                    task.title = snapshot.workflow.title
                    task.official = snapshot.workflow.owner or task.official
                    apply_workflow_snapshot_to_task(task, snapshot)
                    await db.flush()
                    summary["applied"] += 1
                    applied_in_batch += 1
                    if applied_in_batch >= batch_size:
                        await db.commit()
                        applied_in_batch = 0
            else:
                summary["unchanged"] += 1
                log.info("[NOOP] workflow=%s task=%s", wf.id, task.id)

        if apply:
            await db.commit()
        else:
            await db.rollback()
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Recompute workflow projections into task rows.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist changes. Without this flag, runs in dry-run mode.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Only process first N workflows (0 means no limit).",
    )
    parser.add_argument(
        "--workflow-id",
        type=str,
        default="",
        help="Recompute a single workflow by id.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=100,
        help="Commit every N changed rows when --apply is set.",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )
    limit = args.limit if args.limit and args.limit > 0 else None
    workflow_id = args.workflow_id.strip() or None
    summary = asyncio.run(
        _run(
            apply=args.apply,
            limit=limit,
            workflow_id=workflow_id,
            batch_size=max(1, int(args.batch_size or 100)),
        )
    )
    log.info(
        "Done. total=%d missing_task=%d changed=%d unchanged=%d applied=%d apply=%s",
        summary["total"],
        summary["missing_task"],
        summary["changed"],
        summary["unchanged"],
        summary["applied"],
        args.apply,
    )


if __name__ == "__main__":
    main()
