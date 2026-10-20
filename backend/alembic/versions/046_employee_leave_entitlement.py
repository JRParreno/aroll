"""Employee leave entitlements and business advance notice.

Revision ID: 046
Revises: 045
Create Date: 2026-09-27

Adds a per-employee, per-type, per-year allowance. Does not backfill
allowances and does not change existing leave requests or payroll rows.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "046"
down_revision: Union[str, None] = "045"
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
    op.add_column(
        "business_leave_policy",
        sa.Column(
            "minimum_advance_notice_days",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.create_table(
        "employee_leave_entitlement",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("leave_type", _LEAVE_TYPE, nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("allocated_days", sa.Integer(), nullable=False),
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
            "allocated_days >= 0",
            name="ck_employee_leave_entitlement_allocated_nonnegative",
        ),
        sa.ForeignKeyConstraint(
            ["business_id"], ["business.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["employee_id"], ["employee.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "employee_id",
            "leave_type",
            "year",
            name="uq_employee_leave_entitlement_employee_type_year",
        ),
    )
    op.create_index(
        "ix_employee_leave_entitlement_business_employee",
        "employee_leave_entitlement",
        ["business_id", "employee_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_employee_leave_entitlement_business_employee",
        table_name="employee_leave_entitlement",
    )
    op.drop_table("employee_leave_entitlement")
    op.drop_column("business_leave_policy", "minimum_advance_notice_days")
