"""Business-wide yearly leave allowances.

Revision ID: 047
Revises: 046
Create Date: 2026-09-27

Adds one allowance per business, leave type, and year. Does not copy or
delete employee_leave_entitlement rows, and does not change leave requests
or payroll rows.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "047"
down_revision: Union[str, None] = "046"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_LEAVE_TYPE = postgresql.ENUM(
    "sick",
    "vacation",
    "emergency",
    "maternity",
    "paternity",
    "unpaid",
    "other",
    name="leavetype",
    create_type=False,
)


def upgrade() -> None:
    op.create_table(
        "business_leave_allowance",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("leave_type", _LEAVE_TYPE, nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("allowance_days", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "(enabled = true AND allowance_days IS NOT NULL "
            "AND allowance_days >= 0 AND allowance_days <= 366) "
            "OR (enabled = false AND allowance_days IS NULL)",
            name="ck_business_leave_allowance_enabled_days",
        ),
        sa.ForeignKeyConstraint(
            ["business_id"], ["business.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "business_id",
            "leave_type",
            "year",
            name="uq_business_leave_allowance_business_type_year",
        ),
    )
    op.create_index(
        "ix_business_leave_allowance_business_year",
        "business_leave_allowance",
        ["business_id", "year"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_business_leave_allowance_business_year",
        table_name="business_leave_allowance",
    )
    op.drop_table("business_leave_allowance")
