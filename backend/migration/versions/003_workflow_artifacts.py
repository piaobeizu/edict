"""workflow artifacts

Revision ID: 003_workflow_artifacts
Revises: 002_workflow_v2_spike
Create Date: 2026-03-18 00:10:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "003_workflow_artifacts"
down_revision: Union[str, None] = "002_workflow_v2_spike"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "workflow_artifacts",
        sa.Column("id", sa.String(64), nullable=False),
        sa.Column("workflow_id", sa.String(64), nullable=False),
        sa.Column("owner_type", sa.String(32), nullable=False),
        sa.Column("owner_id", sa.String(64), nullable=False),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("mime", sa.String(128), nullable=False, server_default=""),
        sa.Column("preview_url", sa.Text(), nullable=False, server_default=""),
        sa.Column("metadata", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_workflow_artifacts_workflow_id", "workflow_artifacts", ["workflow_id"])
    op.create_index("ix_workflow_artifacts_owner", "workflow_artifacts", ["owner_type", "owner_id"])


def downgrade() -> None:
    op.drop_index("ix_workflow_artifacts_owner", table_name="workflow_artifacts")
    op.drop_index("ix_workflow_artifacts_workflow_id", table_name="workflow_artifacts")
    op.drop_table("workflow_artifacts")
