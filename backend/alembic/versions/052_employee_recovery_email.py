"""Employee recovery email and password-reset challenges

Revision ID: 052
Revises: 051
Create Date: 2026-10-18

Adds a nullable recovery email for existing employees and a reset-challenge
table. Existing employee rows keep a null email and are not required to
register one. No employee data is deleted.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "052"
down_revision: Union[str, None] = "051"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "employee",
        sa.Column("recovery_email", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "employee",
        sa.Column(
            "recovery_email_required",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.create_table(
        "password_reset_challenge",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("lookup_key", sa.String(length=64), nullable=False),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user.id"),
            nullable=True,
        ),
        sa.Column("code_hash", sa.String(length=255), nullable=True),
        sa.Column("code_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("code_consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("resend_available_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reset_token_hash", sa.String(length=64), nullable=True),
        sa.Column("reset_token_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reset_token_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("window_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("issued_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index(
        "ix_password_reset_challenge_lookup_key",
        "password_reset_challenge",
        ["lookup_key"],
        unique=True,
    )
    op.create_index(
        "ix_password_reset_challenge_reset_token_hash",
        "password_reset_challenge",
        ["reset_token_hash"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_password_reset_challenge_reset_token_hash",
        table_name="password_reset_challenge",
    )
    op.drop_index(
        "ix_password_reset_challenge_lookup_key",
        table_name="password_reset_challenge",
    )
    op.drop_table("password_reset_challenge")
    op.drop_column("employee", "recovery_email_required")
    op.drop_column("employee", "recovery_email")
