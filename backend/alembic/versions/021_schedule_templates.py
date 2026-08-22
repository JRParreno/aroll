"""Schedule templates for reusable weekly assignment patterns

Revision ID: 021
Revises: 020
Create Date: 2026-08-02

Stores named weekly schedule templates (assignments only — no attendance
or payroll). Entries use day_offset from Monday (0-6).
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "021"
down_revision: Union[str, None] = "020"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "schedule_template",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
        sa.ForeignKeyConstraint(["created_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "business_id", "name", name="uq_schedule_template_business_name"
        ),
    )
    op.create_index(
        "ix_schedule_template_business_id",
        "schedule_template",
        ["business_id"],
    )

    op.create_table(
        "schedule_template_entry",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("template_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("shift_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("day_offset", sa.Integer(), nullable=False),
        sa.Column("is_rest_day_work", sa.Boolean(), nullable=False, server_default="false"),
        sa.ForeignKeyConstraint(
            ["template_id"],
            ["schedule_template.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(["shift_id"], ["shift.id"]),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_schedule_template_entry_template_id",
        "schedule_template_entry",
        ["template_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_schedule_template_entry_template_id",
        table_name="schedule_template_entry",
    )
    op.drop_table("schedule_template_entry")
    op.drop_index("ix_schedule_template_business_id", table_name="schedule_template")
    op.drop_table("schedule_template")
