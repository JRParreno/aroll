"""Store pending temporary password for employee onboarding

Revision ID: 009
Revises: 008
Create Date: 2026-06-18

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "009"
down_revision: Union[str, None] = "008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user",
        sa.Column("pending_temporary_password", sa.String(50), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user", "pending_temporary_password")
