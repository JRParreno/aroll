"""Add percent-of-shift attendance status thresholds

Revision ID: 026
Revises: 025
Create Date: 2026-08-04

Absent / half-day status cutoffs are evaluated as a percent of the assigned
shift duration so short shifts are not wrongly marked absent.
Legacy minute columns remain for payroll half-day math and no-shift fallback.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "026"
down_revision: Union[str, None] = "025"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_attendance_policy",
        sa.Column(
            "absent_threshold_percent",
            sa.Integer(),
            nullable=False,
            server_default="25",
        ),
    )
    op.add_column(
        "business_attendance_policy",
        sa.Column(
            "half_day_threshold_percent",
            sa.Integer(),
            nullable=False,
            server_default="50",
        ),
    )


def downgrade() -> None:
    op.drop_column("business_attendance_policy", "half_day_threshold_percent")
    op.drop_column("business_attendance_policy", "absent_threshold_percent")
