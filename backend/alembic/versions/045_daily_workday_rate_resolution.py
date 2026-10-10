"""Owner Daily workday entitlement (same-date conflict resolution).

Revision ID: 045
Revises: 044
Create Date: 2026-09-23

Stores the Owner-selected Daily rate for one employee work_date when
completed Daily attendance stamps conflict. Does not alter
attendance_record *_at_completion historical stamps.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "045"
down_revision: Union[str, None] = "044"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "daily_workday_rate_resolution",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("work_date", sa.Date(), nullable=False),
        sa.Column("daily_rate", sa.Numeric(12, 2), nullable=False),
        sa.Column("resolved_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"]),
        sa.ForeignKeyConstraint(["resolved_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "business_id",
            "employee_id",
            "work_date",
            name="uq_daily_workday_rate_resolution_biz_emp_date",
        ),
    )
    op.create_index(
        "ix_daily_workday_rate_resolution_business_id",
        "daily_workday_rate_resolution",
        ["business_id"],
    )
    op.create_index(
        "ix_daily_workday_rate_resolution_employee_id",
        "daily_workday_rate_resolution",
        ["employee_id"],
    )
    op.create_index(
        "ix_daily_workday_rate_resolution_work_date",
        "daily_workday_rate_resolution",
        ["work_date"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_daily_workday_rate_resolution_work_date",
        table_name="daily_workday_rate_resolution",
    )
    op.drop_index(
        "ix_daily_workday_rate_resolution_employee_id",
        table_name="daily_workday_rate_resolution",
    )
    op.drop_index(
        "ix_daily_workday_rate_resolution_business_id",
        table_name="daily_workday_rate_resolution",
    )
    op.drop_table("daily_workday_rate_resolution")
