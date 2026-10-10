"""Add position_pay_config for Design B multi-basis rates.

Revision ID: 042
Revises: 041
Create Date: 2026-09-22

Does not consolidate Position rows. Does not rewrite Employee rates or payslips.
Backfills one config per existing Position from its legacy pay_basis + rate.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "042"
down_revision: Union[str, None] = "041"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

paybasis = postgresql.ENUM(
    "daily",
    "hourly",
    "monthly",
    name="paybasis",
    create_type=False,
)


def upgrade() -> None:
    op.create_table(
        "position_pay_config",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "position_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("position.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("pay_basis", paybasis, nullable=False),
        sa.Column("rate", sa.Numeric(10, 2), nullable=False),
        sa.UniqueConstraint(
            "position_id",
            "pay_basis",
            name="uq_position_pay_config_basis",
        ),
    )
    op.create_index(
        "ix_position_pay_config_position_id",
        "position_pay_config",
        ["position_id"],
    )
    # Backfill: one config per Position from its active legacy basis/rate.
    # Skip rows with no usable rate. Do not merge duplicate titles.
    op.execute(
        """
        INSERT INTO position_pay_config (id, position_id, pay_basis, rate)
        SELECT
            gen_random_uuid(),
            p.id,
            p.pay_basis,
            CASE
                WHEN p.pay_basis = 'hourly' THEN p.hourly_rate
                ELSE p.daily_rate
            END
        FROM position AS p
        WHERE p.pay_basis IN ('daily', 'hourly')
          AND (
            (p.pay_basis = 'daily' AND p.daily_rate IS NOT NULL AND p.daily_rate > 0)
            OR
            (p.pay_basis = 'hourly' AND p.hourly_rate IS NOT NULL AND p.hourly_rate > 0)
          )
          AND NOT EXISTS (
            SELECT 1
            FROM position_pay_config AS c
            WHERE c.position_id = p.id AND c.pay_basis = p.pay_basis
          )
        """
    )


def downgrade() -> None:
    op.drop_index("ix_position_pay_config_position_id", table_name="position_pay_config")
    op.drop_table("position_pay_config")
