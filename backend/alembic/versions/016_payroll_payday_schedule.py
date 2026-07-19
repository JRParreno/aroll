"""Add payday schedule columns to business_payroll_config

Revision ID: 016
Revises: 015
Create Date: 2026-07-19

Stores the recurring payday schedule per pay period type so the setup wizard
can offer type-specific forms (e.g. semi-monthly 15/30 or 10/25) and payroll
can derive future paydays instead of relying on a single manual date.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "016"
down_revision: Union[str, None] = "015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

weekday = postgresql.ENUM(
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
    name="weekday",
    create_type=False,
)


def upgrade() -> None:
    op.add_column(
        "business_payroll_config",
        sa.Column("weekly_payday_weekday", weekday, nullable=True),
    )
    op.add_column(
        "business_payroll_config",
        sa.Column("semi_monthly_payday_1", sa.Integer(), nullable=True),
    )
    op.add_column(
        "business_payroll_config",
        sa.Column("semi_monthly_payday_2", sa.Integer(), nullable=True),
    )
    op.add_column(
        "business_payroll_config",
        sa.Column("monthly_payday_day", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("business_payroll_config", "monthly_payday_day")
    op.drop_column("business_payroll_config", "semi_monthly_payday_2")
    op.drop_column("business_payroll_config", "semi_monthly_payday_1")
    op.drop_column("business_payroll_config", "weekly_payday_weekday")
