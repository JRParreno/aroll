"""Holiday pay multiplier and business type

Revision ID: 006
Revises: 005
Create Date: 2026-06-06

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "holiday",
        sa.Column(
            "pay_multiplier",
            sa.Numeric(5, 2),
            nullable=False,
            server_default="1.0",
        ),
    )
    op.add_column(
        "business",
        sa.Column("business_type", sa.String(100), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("business", "business_type")
    op.drop_column("holiday", "pay_multiplier")
