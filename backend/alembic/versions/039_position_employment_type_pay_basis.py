"""Position employment_type + pay_basis templates

Revision ID: 039
Revises: 038
Create Date: 2026-09-19

Adds optional employment_type and pay_basis on position so Business Setup can
configure roles per Full-time / Part-time with a Daily or Hourly rate template.
Existing rows keep employment_type NULL (unclassified) and pay_basis daily.
daily_rate becomes nullable so hourly-only templates need no fake daily amount.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "039"
down_revision: Union[str, None] = "038"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Reuse existing Postgres enums created in earlier migrations.
employmenttype = postgresql.ENUM(
    "full_time",
    "part_time",
    name="employmenttype",
    create_type=False,
)
paybasis = postgresql.ENUM(
    "daily",
    "hourly",
    "monthly",
    name="paybasis",
    create_type=False,
)


def upgrade() -> None:
    op.add_column(
        "position",
        sa.Column("employment_type", employmenttype, nullable=True),
    )
    op.add_column(
        "position",
        sa.Column(
            "pay_basis",
            paybasis,
            nullable=False,
            server_default="daily",
        ),
    )
    op.alter_column(
        "position",
        "daily_rate",
        existing_type=sa.Numeric(10, 2),
        nullable=True,
    )
    # Drop server default after backfill so inserts must set pay_basis explicitly
    # via the application (SQLAlchemy still sends the Python default).
    op.alter_column(
        "position",
        "pay_basis",
        server_default=None,
        existing_type=paybasis,
        existing_nullable=False,
    )


def downgrade() -> None:
    # Restore NOT NULL daily_rate: fill any NULL with 0 before tightening.
    op.execute(
        sa.text("UPDATE position SET daily_rate = 0 WHERE daily_rate IS NULL")
    )
    op.alter_column(
        "position",
        "daily_rate",
        existing_type=sa.Numeric(10, 2),
        nullable=False,
    )
    op.drop_column("position", "pay_basis")
    op.drop_column("position", "employment_type")
