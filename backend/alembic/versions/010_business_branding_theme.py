"""Business branding and theme settings

Revision ID: 010
Revises: 009
Create Date: 2026-06-19

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "010"
down_revision: Union[str, None] = "009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("business", sa.Column("logo_url", sa.Text(), nullable=True))
    op.add_column(
        "business", sa.Column("owner_profile_image_url", sa.Text(), nullable=True)
    )
    op.add_column("business", sa.Column("display_image_url", sa.Text(), nullable=True))
    op.add_column(
        "business", sa.Column("theme_settings", postgresql.JSONB(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("business", "theme_settings")
    op.drop_column("business", "display_image_url")
    op.drop_column("business", "owner_profile_image_url")
    op.drop_column("business", "logo_url")
