"""Device tokens for optional push notifications

Revision ID: 051
Revises: 050
Create Date: 2026-10-18

Adds device_push_token so inbox notifications can also be delivered as
OS push when FCM credentials are configured. Existing notification rows
are unchanged.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "051"
down_revision: Union[str, None] = "050"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "device_push_token",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "business_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("business.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("token", sa.String(512), nullable=False),
        sa.Column("platform", sa.String(16), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("token", name="uq_device_push_token_token"),
    )
    op.create_index(
        "ix_device_push_token_user_id",
        "device_push_token",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_device_push_token_user_id", table_name="device_push_token")
    op.drop_table("device_push_token")
