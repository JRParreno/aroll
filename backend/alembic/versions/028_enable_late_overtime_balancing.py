"""Add enable_late_overtime_balancing payroll flag

Revision ID: 028
Revises: 027
Create Date: 2026-08-04

Optional company policy: minutes past shift end first recover late arrival
(from scheduled start, not grace) before accruing payable OT.
Default false — existing payroll behavior unchanged.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "028"
down_revision: Union[str, None] = "027"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "enable_late_overtime_balancing",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("business_payroll_config", "enable_late_overtime_balancing")
