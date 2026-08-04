"""Payroll adjustments (owner deductions/allowances per pay period)

Revision ID: 020
Revises: 019
Create Date: 2026-08-02

Stores payroll-specific deductions and allowances that are applied after
live payroll computation without changing attendance-based pay rules.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "020"
down_revision: Union[str, None] = "019"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "payroll_adjustment",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("type_key", sa.String(length=40), nullable=False),
        sa.Column("custom_name", sa.String(length=120), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("updated_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("previous_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"]),
        sa.ForeignKeyConstraint(["created_by"], ["user.id"]),
        sa.ForeignKeyConstraint(["updated_by"], ["user.id"]),
        sa.ForeignKeyConstraint(["deleted_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_payroll_adjustment_business_id",
        "payroll_adjustment",
        ["business_id"],
    )
    op.create_index(
        "ix_payroll_adjustment_employee_id",
        "payroll_adjustment",
        ["employee_id"],
    )
    op.create_index(
        "ix_payroll_adjustment_period",
        "payroll_adjustment",
        ["business_id", "employee_id", "period_start", "period_end"],
    )


def downgrade() -> None:
    op.drop_index("ix_payroll_adjustment_period", table_name="payroll_adjustment")
    op.drop_index("ix_payroll_adjustment_employee_id", table_name="payroll_adjustment")
    op.drop_index("ix_payroll_adjustment_business_id", table_name="payroll_adjustment")
    op.drop_table("payroll_adjustment")
