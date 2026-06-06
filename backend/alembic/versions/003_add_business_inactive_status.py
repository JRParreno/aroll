"""Add inactive to businessstatus enum

Revision ID: 003
Revises: 002
Create Date: 2026-06-06

"""

from typing import Sequence, Union

from alembic import op

revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TYPE businessstatus ADD VALUE IF NOT EXISTS 'inactive'")


def downgrade() -> None:
    # PostgreSQL does not support removing enum values safely.
    pass
