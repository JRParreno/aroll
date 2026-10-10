"""Add business_id to activity_log for Owner-scoped audit history.

Revision ID: 041
Revises: 040
Create Date: 2026-09-22

Preserves business scope after hard-delete nulls activity_log.user_id.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "041"
down_revision: Union[str, None] = "040"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "activity_log",
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "activity_log_business_id_fkey",
        "activity_log",
        "business",
        ["business_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_activity_log_business_id",
        "activity_log",
        ["business_id"],
    )
    # Backfill from the actor's business when available.
    op.execute(
        """
        UPDATE activity_log AS al
        SET business_id = u.business_id
        FROM "user" AS u
        WHERE al.user_id = u.id
          AND u.business_id IS NOT NULL
          AND al.business_id IS NULL
        """
    )


def downgrade() -> None:
    op.drop_index("ix_activity_log_business_id", table_name="activity_log")
    op.drop_constraint(
        "activity_log_business_id_fkey", "activity_log", type_="foreignkey"
    )
    op.drop_column("activity_log", "business_id")
