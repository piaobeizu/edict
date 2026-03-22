"""workflow v2 spike schema

Revision ID: 002_workflow_v2_spike
Revises: 001_initial
Create Date: 2026-03-18 00:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "002_workflow_v2_spike"
down_revision: Union[str, None] = "001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("tasks", sa.Column("workflow_id", sa.String(64), nullable=True, server_default=""))
    op.add_column("tasks", sa.Column("workflow_type", sa.String(32), nullable=False, server_default="legacy"))
    op.add_column("tasks", sa.Column("projection_version", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("tasks", sa.Column("current_revision_id", sa.String(64), nullable=False, server_default=""))
    op.add_column("tasks", sa.Column("current_assembly_id", sa.String(64), nullable=False, server_default=""))
    op.add_column("tasks", sa.Column("pending_review_count", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("tasks", sa.Column("running_node_count", sa.Integer(), nullable=False, server_default="0"))
    op.create_index("ix_tasks_workflow_id", "tasks", ["workflow_id"])
    op.create_index("ix_tasks_workflow_type", "tasks", ["workflow_type"])

    op.create_table(
        "workflow_instances",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("task_id", sa.String(32), nullable=False),
        sa.Column("workflow_type", sa.String(32), nullable=False, server_default="generic"),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("goal", sa.Text(), nullable=False, server_default=""),
        sa.Column("state", sa.String(32), nullable=False),
        sa.Column("owner", sa.String(64), nullable=False, server_default=""),
        sa.Column("current_revision_id", sa.String(64), nullable=False, server_default=""),
        sa.Column("current_assembly_id", sa.String(64), nullable=False, server_default=""),
        sa.Column("summary_output", sa.Text(), nullable=False, server_default=""),
        sa.Column("meta", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("task_id"),
    )
    op.create_index("ix_workflow_instances_task_id", "workflow_instances", ["task_id"])
    op.create_index("ix_workflow_instances_state", "workflow_instances", ["state"])
    op.create_index("ix_workflow_instances_type_state", "workflow_instances", ["workflow_type", "state"])

    op.create_table(
        "workflow_revisions",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=False),
        sa.Column("revision_number", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("created_by", sa.String(64), nullable=False),
        sa.Column("source", sa.String(32), nullable=False, server_default=""),
        sa.Column("content", sa.Text(), nullable=False, server_default=""),
        sa.Column("change_summary", sa.Text(), nullable=False, server_default=""),
        sa.Column("parent_revision_id", sa.String(64), nullable=False, server_default=""),
        sa.Column("meta", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("workflow_id", "revision_number", name="uq_workflow_revision_number"),
    )
    op.create_index("ix_workflow_revisions_workflow_id", "workflow_revisions", ["workflow_id"])
    op.create_index("ix_workflow_revisions_workflow_status", "workflow_revisions", ["workflow_id", "status"])

    op.create_table(
        "workflow_nodes",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=False),
        sa.Column("revision_id", sa.String(64), nullable=False),
        sa.Column("parent_node_id", sa.String(64), nullable=False, server_default=""),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("state", sa.String(32), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("assignee", sa.String(64), nullable=False, server_default=""),
        sa.Column("sequence", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("acceptance_criteria", sa.Text(), nullable=False, server_default=""),
        sa.Column("selected_candidate_id", sa.String(64), nullable=False, server_default=""),
        sa.Column("spec", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("meta", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_workflow_nodes_workflow_id", "workflow_nodes", ["workflow_id"])
    op.create_index("ix_workflow_nodes_revision_id", "workflow_nodes", ["revision_id"])
    op.create_index("ix_workflow_nodes_parent_node_id", "workflow_nodes", ["parent_node_id"])
    op.create_index("ix_workflow_nodes_kind", "workflow_nodes", ["kind"])
    op.create_index("ix_workflow_nodes_state", "workflow_nodes", ["state"])
    op.create_index("ix_workflow_nodes_workflow_seq", "workflow_nodes", ["workflow_id", "sequence"])

    op.create_table(
        "workflow_candidates",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=False),
        sa.Column("node_id", sa.String(64), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("provider", sa.String(64), nullable=False, server_default=""),
        sa.Column("summary", sa.Text(), nullable=False, server_default=""),
        sa.Column("score", sa.Float(), nullable=True),
        sa.Column("prompt_snapshot", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("metrics", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("meta", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_workflow_candidates_workflow_id", "workflow_candidates", ["workflow_id"])
    op.create_index("ix_workflow_candidates_node_id", "workflow_candidates", ["node_id"])
    op.create_index("ix_workflow_candidates_node_status", "workflow_candidates", ["node_id", "status"])

    op.create_table(
        "workflow_decisions",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=False),
        sa.Column("target_type", sa.String(32), nullable=False),
        sa.Column("target_id", sa.String(64), nullable=False),
        sa.Column("action", sa.String(32), nullable=False),
        sa.Column("actor", sa.String(64), nullable=False),
        sa.Column("comment", sa.Text(), nullable=False, server_default=""),
        sa.Column("payload", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_workflow_decisions_workflow_id", "workflow_decisions", ["workflow_id"])
    op.create_index("ix_workflow_decisions_action", "workflow_decisions", ["action"])
    op.create_index("ix_workflow_decisions_target", "workflow_decisions", ["target_type", "target_id"])

    op.create_table(
        "workflow_assemblies",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False, server_default=""),
        sa.Column("items", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("meta", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_workflow_assemblies_workflow_status", "workflow_assemblies", ["workflow_id", "status"])

    op.create_table(
        "workflow_outbox",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("aggregate_type", sa.String(32), nullable=False, server_default="workflow"),
        sa.Column("aggregate_id", sa.String(64), nullable=False),
        sa.Column("topic", sa.String(128), nullable=False),
        sa.Column("event_type", sa.String(128), nullable=False),
        sa.Column("trace_id", sa.String(64), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("headers", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("available_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
    )
    op.create_index("ix_workflow_outbox_aggregate", "workflow_outbox", ["aggregate_type", "aggregate_id"])
    op.create_index("ix_workflow_outbox_status_available_at", "workflow_outbox", ["status", "available_at"])


def downgrade() -> None:
    op.drop_index("ix_workflow_outbox_status_available_at", table_name="workflow_outbox")
    op.drop_index("ix_workflow_outbox_aggregate", table_name="workflow_outbox")
    op.drop_table("workflow_outbox")
    op.drop_index("ix_workflow_assemblies_workflow_status", table_name="workflow_assemblies")
    op.drop_table("workflow_assemblies")
    op.drop_index("ix_workflow_decisions_target", table_name="workflow_decisions")
    op.drop_index("ix_workflow_decisions_action", table_name="workflow_decisions")
    op.drop_index("ix_workflow_decisions_workflow_id", table_name="workflow_decisions")
    op.drop_table("workflow_decisions")
    op.drop_index("ix_workflow_candidates_node_status", table_name="workflow_candidates")
    op.drop_index("ix_workflow_candidates_node_id", table_name="workflow_candidates")
    op.drop_index("ix_workflow_candidates_workflow_id", table_name="workflow_candidates")
    op.drop_table("workflow_candidates")
    op.drop_index("ix_workflow_nodes_workflow_seq", table_name="workflow_nodes")
    op.drop_index("ix_workflow_nodes_state", table_name="workflow_nodes")
    op.drop_index("ix_workflow_nodes_kind", table_name="workflow_nodes")
    op.drop_index("ix_workflow_nodes_parent_node_id", table_name="workflow_nodes")
    op.drop_index("ix_workflow_nodes_revision_id", table_name="workflow_nodes")
    op.drop_index("ix_workflow_nodes_workflow_id", table_name="workflow_nodes")
    op.drop_table("workflow_nodes")
    op.drop_index("ix_workflow_revisions_workflow_status", table_name="workflow_revisions")
    op.drop_index("ix_workflow_revisions_workflow_id", table_name="workflow_revisions")
    op.drop_table("workflow_revisions")
    op.drop_index("ix_workflow_instances_type_state", table_name="workflow_instances")
    op.drop_index("ix_workflow_instances_state", table_name="workflow_instances")
    op.drop_index("ix_workflow_instances_task_id", table_name="workflow_instances")
    op.drop_table("workflow_instances")
    op.drop_index("ix_tasks_workflow_type", table_name="tasks")
    op.drop_index("ix_tasks_workflow_id", table_name="tasks")
    op.drop_column("tasks", "running_node_count")
    op.drop_column("tasks", "pending_review_count")
    op.drop_column("tasks", "current_assembly_id")
    op.drop_column("tasks", "current_revision_id")
    op.drop_column("tasks", "projection_version")
    op.drop_column("tasks", "workflow_type")
    op.drop_column("tasks", "workflow_id")
