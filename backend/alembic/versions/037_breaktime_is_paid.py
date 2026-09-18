"""Add business-level breaktime_is_paid attendance/schedule flag

Revision ID: 037
Revises: 036
Create Date: 2026-09-17

When false (default), break minutes are unpaid and reduce scheduled paid
minutes. When true, the full shift span is paid. Default false preserves
existing payroll amounts for businesses that already subtract break time.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "037"
down_revision: Union[str, None] = "036"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_attendance_policy",
        sa.Column(
            "breaktime_is_paid",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("business_attendance_policy", "breaktime_is_paid")
