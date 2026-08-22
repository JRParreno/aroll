"""Add holiday_rules_mode to business_payroll_config

Revision ID: 025
Revises: 024
Create Date: 2026-08-04

Supports Philippine labor vs custom company holiday pay rules.
Existing businesses default to philippine_labor.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "025"
down_revision: Union[str, None] = "024"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_HOLIDAY_RULES_MODE = sa.Enum(
    "philippine_labor",
    "custom_company",
    name="holidayrulesmode",
)


def upgrade() -> None:
    bind = op.get_bind()
    _HOLIDAY_RULES_MODE.create(bind, checkfirst=True)
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "holiday_rules_mode",
            postgresql.ENUM(
                "philippine_labor",
                "custom_company",
                name="holidayrulesmode",
                create_type=False,
            ),
            nullable=False,
            server_default="philippine_labor",
        ),
    )


def downgrade() -> None:
    op.drop_column("business_payroll_config", "holiday_rules_mode")
    _HOLIDAY_RULES_MODE.drop(op.get_bind(), checkfirst=True)
