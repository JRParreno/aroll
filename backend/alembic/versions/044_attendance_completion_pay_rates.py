"""Attendance completion pay-rate stamp for historical live payroll.

Revision ID: 044
Revises: 043
Create Date: 2026-09-22

When an attendance record first closes (time_out + closed status), the
employee's then-current stamped pay fields are copied onto the attendance
row. Live unfinalized payroll uses those fields for that day so a later
Role/rate change does not reprice completed shifts.

Nullable columns: existing rows stay NULL and keep prior live behavior
(current Employee stamp) until newly completed after this migration.
Does not invent rates for legacy completed attendance.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "044"
down_revision: Union[str, None] = "043"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

pay_basis_enum = postgresql.ENUM(
    "daily",
    "hourly",
    "monthly",
    name="paybasis",
    create_type=False,
)


def upgrade() -> None:
    pay_basis_enum.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "attendance_record",
        sa.Column("pay_basis_at_completion", pay_basis_enum, nullable=True),
    )
    op.add_column(
        "attendance_record",
        sa.Column("daily_rate_at_completion", sa.Numeric(10, 2), nullable=True),
    )
    op.add_column(
        "attendance_record",
        sa.Column("hourly_rate_at_completion", sa.Numeric(10, 2), nullable=True),
    )
    op.add_column(
        "attendance_record",
        sa.Column("monthly_salary_at_completion", sa.Numeric(10, 2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("attendance_record", "monthly_salary_at_completion")
    op.drop_column("attendance_record", "hourly_rate_at_completion")
    op.drop_column("attendance_record", "daily_rate_at_completion")
    op.drop_column("attendance_record", "pay_basis_at_completion")
