"""Add overtime premium percent fields to payroll config

Revision ID: 035
Revises: 034
Create Date: 2026-09-16

Statutory OT premiums are configurable per business. They apply only to
overtime minutes. holiday.pay_multiplier and rest_day_premium_percent stay
on regular/earned hours.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "035"
down_revision: Union[str, None] = "034"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "ordinary_ot_premium_percent",
            sa.Numeric(5, 2),
            nullable=False,
            server_default="25",
        ),
    )
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "special_day_ot_premium_percent",
            sa.Numeric(5, 2),
            nullable=False,
            server_default="30",
        ),
    )
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "regular_holiday_ot_premium_percent",
            sa.Numeric(5, 2),
            nullable=False,
            server_default="30",
        ),
    )
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "holiday_rest_day_ot_premium_percent",
            sa.Numeric(5, 2),
            nullable=False,
            server_default="30",
        ),
    )


def downgrade() -> None:
    op.drop_column("business_payroll_config", "holiday_rest_day_ot_premium_percent")
    op.drop_column("business_payroll_config", "regular_holiday_ot_premium_percent")
    op.drop_column("business_payroll_config", "special_day_ot_premium_percent")
    op.drop_column("business_payroll_config", "ordinary_ot_premium_percent")
