"""Add business.is_demo and business.is_internal_test

Revision ID: 031
Revises: 030
Create Date: 2026-09-04

Tenant classification for the research Demo Café vs the internal Dev Lab.
Existing businesses stay is_demo=false / is_internal_test=false.
The two flags cannot both be true.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "031"
down_revision: Union[str, None] = "030"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business",
        sa.Column(
            "is_demo",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.add_column(
        "business",
        sa.Column(
            "is_internal_test",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.create_check_constraint(
        "ck_business_demo_internal_test_mutex",
        "business",
        "NOT (is_demo AND is_internal_test)",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_business_demo_internal_test_mutex",
        "business",
        type_="check",
    )
    op.drop_column("business", "is_internal_test")
    op.drop_column("business", "is_demo")
