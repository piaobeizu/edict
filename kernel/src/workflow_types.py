"""Shared enum types for workflow v2."""

from __future__ import annotations

from enum import StrEnum


class WorkflowState(StrEnum):
    DRAFT = "draft"
    PLANNING = "planning"
    AWAITING_PLAN_REVIEW = "awaiting_plan_review"
    EXECUTING = "executing"
    AWAITING_SELECTION = "awaiting_selection"
    ASSEMBLING = "assembling"
    AWAITING_FINAL_REVIEW = "awaiting_final_review"
    BLOCKED = "blocked"
    DONE = "done"
    CANCELLED = "cancelled"


class NodeState(StrEnum):
    PENDING = "pending"
    READY = "ready"
    RUNNING = "running"
    PRODUCED = "produced"
    AWAITING_REVIEW = "awaiting_review"
    APPROVED = "approved"
    REJECTED = "rejected"
    FAILED = "failed"
    SUPERSEDED = "superseded"
    CANCELLED = "cancelled"


class CandidateState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    PRODUCED = "produced"
    APPROVED = "approved"
    REJECTED = "rejected"
    FAILED = "failed"
    SUPERSEDED = "superseded"
    CANCELLED = "cancelled"


class DecisionAction(StrEnum):
    APPROVE = "approve"
    REJECT = "reject"
    SELECT = "select"
    REGENERATE = "regenerate"
    ROLLBACK = "rollback"
    SUBMIT = "submit"
    COMMENT = "comment"


class NodeKind(StrEnum):
    PLAN = "plan"
    WORK_ITEM = "work_item"
    REVIEW = "review"
    ASSEMBLY = "assembly"
    EXECUTION = "execution"
