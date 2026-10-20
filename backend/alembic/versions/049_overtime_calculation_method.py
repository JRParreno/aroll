"""Add overtime_calculation_method to business_payroll_config

Revision ID: 049
Revises: 048
Create Date: 2026-10-12

Existing and new businesses stay on the saved peso-per-minute overtime
rate. hourly_statutory is an explicit owner choice and does not change
overtime_per_minute.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "049"
down_revision: Union[str, None] = "048"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OVERTIME_CALCULATION_METHOD = sa.Enum(
    "flat_per_minute",
    "hourly_statutory",
    name="overtimecalculationmethod",
)


def upgrade() -> None:
    bind = op.get_bind()
    _OVERTIME_CALCULATION_METHOD.create(bind, checkfirst=True)
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "overtime_calculation_method",
            postgresql.ENUM(
                "flat_per_minute",
                "hourly_statutory",
                name="overtimecalculationmethod",
                create_type=False,
            ),
            nullable=False,
            server_default="flat_per_minute",
        ),
    )


def downgrade() -> None:
    op.drop_column("business_payroll_config", "overtime_calculation_method")
    _OVERTIME_CALCULATION_METHOD.drop(op.get_bind(), checkfirst=True)
