"""Workflow v2 ORM models — all workflow-related tables."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, Float, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB

from ..db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ══════════════════════════════════════
# WorkflowInstance
# ══════════════════════════════════════

class WorkflowInstance(Base):
    __tablename__ = "workflow_instances"

    id = Column(String(64), primary_key=True)
    task_id = Column(String(32), nullable=False, unique=True, index=True)
    workflow_type = Column(String(32), nullable=False, default="generic", index=True)
    title = Column(Text, nullable=False)
    goal = Column(Text, default="", nullable=False)
    state = Column(String(32), nullable=False, index=True)
    owner = Column(String(64), default="", nullable=False)
    current_revision_id = Column(String(64), default="", nullable=False)
    current_assembly_id = Column(String(64), default="", nullable=False)
    summary_output = Column(Text, default="", nullable=False)
    meta = Column(JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_instances_type_state", "workflow_type", "state"),
        Index("ix_workflow_instances_updated_at", "updated_at"),
    )


# ══════════════════════════════════════
# WorkflowRevision
# ══════════════════════════════════════

class WorkflowRevision(Base):
    __tablename__ = "workflow_revisions"

    id = Column(String(64), primary_key=True)
    workflow_id = Column(String(64), nullable=False, index=True)
    revision_number = Column(Integer, nullable=False)
    status = Column(String(32), nullable=False, index=True)
    created_by = Column(String(64), nullable=False)
    source = Column(String(32), default="", nullable=False)
    content = Column(Text, default="", nullable=False)
    change_summary = Column(Text, default="", nullable=False)
    parent_revision_id = Column(String(64), default="", nullable=False)
    meta = Column(JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("workflow_id", "revision_number", name="uq_workflow_revision_number"),
        Index("ix_workflow_revisions_workflow_status", "workflow_id", "status"),
    )


# ══════════════════════════════════════
# WorkflowNode
# ══════════════════════════════════════

class WorkflowNode(Base):
    __tablename__ = "workflow_nodes"

    id = Column(String(64), primary_key=True)
    workflow_id = Column(String(64), nullable=False, index=True)
    revision_id = Column(String(64), nullable=False, index=True)
    parent_node_id = Column(String(64), default="", nullable=False, index=True)
    kind = Column(String(32), nullable=False, index=True)
    state = Column(String(32), nullable=False, index=True)
    title = Column(Text, nullable=False)
    description = Column(Text, default="", nullable=False)
    assignee = Column(String(64), default="", nullable=False)
    sequence = Column(Integer, default=0, nullable=False)
    acceptance_criteria = Column(Text, default="", nullable=False)
    selected_candidate_id = Column(String(64), default="", nullable=False)
    spec = Column(JSONB, default=dict, nullable=False)
    meta = Column(JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_nodes_workflow_seq", "workflow_id", "sequence"),
        Index("ix_workflow_nodes_revision_state", "revision_id", "state"),
    )


# ══════════════════════════════════════
# WorkflowCandidate
# ══════════════════════════════════════

class WorkflowCandidate(Base):
    __tablename__ = "workflow_candidates"

    id = Column(String(64), primary_key=True)
    workflow_id = Column(String(64), nullable=False, index=True)
    node_id = Column(String(64), nullable=False, index=True)
    status = Column(String(32), nullable=False, index=True)
    provider = Column(String(64), default="", nullable=False)
    summary = Column(Text, default="", nullable=False)
    score = Column(Float, nullable=True)
    prompt_snapshot = Column(JSONB, default=dict, nullable=False)
    metrics = Column(JSONB, default=dict, nullable=False)
    meta = Column(JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_candidates_node_status", "node_id", "status"),
    )


# ══════════════════════════════════════
# WorkflowAssembly
# ══════════════════════════════════════

class WorkflowAssembly(Base):
    __tablename__ = "workflow_assemblies"

    id = Column(String(64), primary_key=True)
    workflow_id = Column(String(64), nullable=False, index=True)
    status = Column(String(32), nullable=False, index=True)
    summary = Column(Text, default="", nullable=False)
    items = Column(JSONB, default=list, nullable=False)
    meta = Column(JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_assemblies_workflow_status", "workflow_id", "status"),
    )


# ══════════════════════════════════════
# WorkflowDecision
# ══════════════════════════════════════

class WorkflowDecision(Base):
    __tablename__ = "workflow_decisions"

    id = Column(String(64), primary_key=True)
    workflow_id = Column(String(64), nullable=False, index=True)
    target_type = Column(String(32), nullable=False, index=True)
    target_id = Column(String(64), nullable=False, index=True)
    action = Column(String(32), nullable=False, index=True)
    actor = Column(String(64), nullable=False)
    comment = Column(Text, default="", nullable=False)
    payload = Column(JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_decisions_target", "target_type", "target_id"),
    )


# ══════════════════════════════════════
# WorkflowArtifact
# ══════════════════════════════════════

class WorkflowArtifact(Base):
    __tablename__ = "workflow_artifacts"

    id = Column(String(64), primary_key=True)
    workflow_id = Column(String(64), nullable=False, index=True)
    owner_type = Column(String(32), nullable=False, index=True)
    owner_id = Column(String(64), nullable=False, index=True)
    kind = Column(String(32), nullable=False)
    path = Column(Text, nullable=False)
    mime = Column(String(128), default="", nullable=False)
    preview_url = Column(Text, default="", nullable=False)
    metadata_ = Column("metadata", JSONB, default=dict, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_artifacts_owner", "owner_type", "owner_id"),
    )


# ══════════════════════════════════════
# WorkflowOutbox
# ══════════════════════════════════════

class WorkflowOutbox(Base):
    __tablename__ = "workflow_outbox"

    id = Column(Integer, primary_key=True, autoincrement=True)
    aggregate_type = Column(String(32), nullable=False, default="workflow")
    aggregate_id = Column(String(64), nullable=False, index=True)
    topic = Column(String(128), nullable=False)
    event_type = Column(String(128), nullable=False)
    trace_id = Column(String(64), nullable=False)
    payload = Column(JSONB, default=dict, nullable=False)
    headers = Column(JSONB, default=dict, nullable=False)
    status = Column(String(16), nullable=False, default="pending", index=True)
    retry_count = Column(Integer, nullable=False, default=0)
    available_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    published_at = Column(DateTime(timezone=True), nullable=True)
    last_error = Column(Text, default="", nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)

    __table_args__ = (
        Index("ix_workflow_outbox_status_available_at", "status", "available_at"),
    )
