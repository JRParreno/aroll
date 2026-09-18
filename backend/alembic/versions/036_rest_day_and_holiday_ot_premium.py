"""Add rest-day OT premium and per-holiday OT premium.

Revision ID: 036
Revises: 035
Create Date: 2026-09-16

Rest-day-only OT uses business_payroll_config.rest_day_ot_premium_percent.
Existing rows copy ordinary_ot_premium_percent so rest-day OT does not
silently change from prior ordinary-premium behavior.

holiday.ot_premium_percent is nullable: NULL means not configured (fall
back to rest-day or ordinary). 0 means a configured 0% premium.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "036"
down_revision: Union[str, None] = "035"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "rest_day_ot_premium_percent",
            sa.Numeric(5, 2),
            nullable=False,
            server_default="25",
        ),
    )
    op.execute(
        sa.text(
            "UPDATE business_payroll_config "
            "SET rest_day_ot_premium_percent = ordinary_ot_premium_percent"
        )
    )
    op.add_column(
        "holiday",
        sa.Column("ot_premium_percent", sa.Numeric(5, 2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("holiday", "ot_premium_percent")
    op.drop_column("business_payroll_config", "rest_day_ot_premium_percent")
