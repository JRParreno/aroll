"""Add maximum_overtime_minutes attendance cutoff

Revision ID: 027
Revises: 026
Create Date: 2026-08-04

Attendance-only window after scheduled shift end during which an employee
may still clock out. Past this window, open punches become incomplete.
Does not affect payroll OT formulas or absence/no-show timing.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "027"
down_revision: Union[str, None] = "026"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_attendance_policy",
        sa.Column(
            "maximum_overtime_minutes",
            sa.Integer(),
            nullable=False,
            server_default="180",
        ),
    )


def downgrade() -> None:
    op.drop_column("business_attendance_policy", "maximum_overtime_minutes")
