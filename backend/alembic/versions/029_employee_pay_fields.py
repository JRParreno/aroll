"""Add employee pay fields and backfill from Position

Revision ID: 029
Revises: 028
Create Date: 2026-08-04

Phase 1 of employee pay architecture:
- Store pay_basis / daily_rate / hourly_rate / monthly_salary on employee
- Backfill existing employees: pay_basis=daily, daily_rate=Position.daily_rate
- Position.daily_rate remains the live payroll source (unchanged)
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "029"
down_revision: Union[str, None] = "028"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

pay_basis_enum = postgresql.ENUM(
    "daily",
    "hourly",
    "monthly",
    name="paybasis",
    create_type=False,
)


def upgrade() -> None:
    pay_basis_enum.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "employee",
        sa.Column(
            "pay_basis",
            pay_basis_enum,
            nullable=False,
            server_default="daily",
        ),
    )
    op.add_column(
        "employee",
        sa.Column("daily_rate", sa.Numeric(10, 2), nullable=True),
    )
    op.add_column(
        "employee",
        sa.Column("hourly_rate", sa.Numeric(10, 2), nullable=True),
    )
    op.add_column(
        "employee",
        sa.Column("monthly_salary", sa.Numeric(10, 2), nullable=True),
    )

    # Backfill: copy Position.daily_rate; leave null when no position.
    op.execute(
        """
        UPDATE employee AS e
        SET
            pay_basis = 'daily',
            daily_rate = p.daily_rate
        FROM position AS p
        WHERE e.position_id = p.id
        """
    )
    op.execute(
        """
        UPDATE employee
        SET pay_basis = 'daily'
        WHERE pay_basis IS NULL
        """
    )


def downgrade() -> None:
    op.drop_column("employee", "monthly_salary")
    op.drop_column("employee", "hourly_rate")
    op.drop_column("employee", "daily_rate")
    op.drop_column("employee", "pay_basis")
    pay_basis_enum.drop(op.get_bind(), checkfirst=True)
