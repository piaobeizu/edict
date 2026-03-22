#!/usr/bin/env python3
"""Audit/backfill script for migrating legacy task rows to workflow v2.

Usage:
  python backend/migration/backfill_legacy_tasks_to_workflow_v2.py
  python backend/migration/backfill_legacy_tasks_to_workflow_v2.py --apply
  python backend/migration/backfill_legacy_tasks_to_workflow_v2.py --apply --limit 100
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import or_, select

# Ensure "app.*" imports work when script is run from repo root.
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.db import async_session
from app.models.task import Task
from app.models.workflow_models import WorkflowInstance

log = logging.getLogger("backfill.workflow_v2")

TASK_TO_WORKFLOW_STATE = {
    "Pending": "draft",
    "Taizi": "draft",
    "Zhongshu": "planning",
    "Menxia": "awaiting_plan_review",
    "YuLan": "awaiting_plan_review",
    "Assigned": "executing",
    "Next": "executing",
    "Doing": "executing",
    "Review": "awaiting_selection",
    "Done": "done",
    "Blocked": "blocked",
    "Cancelled": "cancelled",
}


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _workflow_state_from_task(task_state: str | None) -> str:
    return TASK_TO_WORKFLOW_STATE.get(str(task_state or "").strip(), "draft")


def _workflow_id_for_task(task_id: str) -> str:
    # Keep deterministic IDs so dry-run/apply are comparable.
    normalized = re.sub(r"[^A-Za-z0-9_-]", "-", task_id).strip("-")
    normalized = normalized or "task"
    return f"wf-migr-{normalized}"[:64]


async def _run(apply: bool, limit: int | None) -> int:
    changed = 0
    async with async_session() as db:
        stmt = select(Task).where(
            or_(
                Task.workflow_id.is_(None),
                Task.workflow_id == "",
                Task.workflow_type == "legacy",
            )
        ).order_by(Task.updated_at.desc(), Task.id.asc())
        if limit and limit > 0:
            stmt = stmt.limit(limit)
        tasks = list((await db.execute(stmt)).scalars().all())

        log.info("Found %d candidate legacy task rows", len(tasks))
        if not tasks:
            return 0

        created_workflows = 0
        reused_workflows = 0
        normalized_tasks = 0

        for task in tasks:
            workflow_id = str(task.workflow_id or "").strip() or _workflow_id_for_task(str(task.id))
            workflow = await db.get(WorkflowInstance, workflow_id)

            if workflow is None:
                if apply:
                    created_at = task.created_at or _now_utc()
                    updated_at = task.updated_at or created_at
                    db.add(
                        WorkflowInstance(
                            id=workflow_id,
                            task_id=str(task.id),
                            workflow_type="generic",
                            title=task.title or str(task.id),
                            goal=task.now or "",
                            state=_workflow_state_from_task(task.state),
                            owner=task.org or "",
                            current_revision_id=str(task.current_revision_id or ""),
                            current_assembly_id=str(task.current_assembly_id or ""),
                            summary_output=str(task.output or ""),
                            meta={
                                "migrated_from_legacy": True,
                                "legacy_task_state": str(task.state or ""),
                                "legacy_task_id": str(task.id),
                                "migration_script": "backfill_legacy_tasks_to_workflow_v2.py",
                            },
                            created_at=created_at,
                            updated_at=updated_at,
                        )
                    )
                created_workflows += 1
            else:
                reused_workflows += 1

            needs_task_update = (
                str(task.workflow_id or "").strip() != workflow_id
                or str(task.workflow_type or "").strip() != "generic"
            )
            if needs_task_update:
                normalized_tasks += 1
                if apply:
                    task.workflow_id = workflow_id
                    task.workflow_type = "generic"
                    task.updated_at = _now_utc()

            log.info(
                "[%s] task=%s state=%s -> workflow=%s (created=%s, normalize=%s)",
                "APPLY" if apply else "DRYRUN",
                task.id,
                task.state,
                workflow_id,
                workflow is None,
                needs_task_update,
            )

        if apply:
            await db.commit()
            changed = created_workflows + normalized_tasks
        else:
            await db.rollback()

        log.info(
            "Summary: create_workflow=%d, reuse_workflow=%d, normalize_task=%d, apply=%s",
            created_workflows,
            reused_workflows,
            normalized_tasks,
            apply,
        )
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Backfill workflow_id/workflow_type for legacy task rows."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist changes. Without this flag, runs in dry-run mode.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Only process first N candidate rows (0 means no limit).",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )
    limit = args.limit if args.limit and args.limit > 0 else None
    changed = asyncio.run(_run(apply=args.apply, limit=limit))
    log.info("Done. changed=%d", changed)


if __name__ == "__main__":
    main()
