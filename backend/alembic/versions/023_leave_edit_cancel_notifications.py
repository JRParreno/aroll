"""Leave edit/cancel statuses, revision fields, notifications, audit extras

Revision ID: 023
Revises: 022
Create Date: 2026-08-03
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "023"
down_revision: Union[str, None] = "022"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TYPE leaverequeststatus ADD VALUE IF NOT EXISTS 'cancellation_pending'"
    )
    op.execute(
        "ALTER TYPE leaverequeststatus ADD VALUE IF NOT EXISTS 'cancelled'"
    )

    op.add_column(
        "leave_request",
        sa.Column(
            "previous_leave_type",
            postgresql.ENUM(
                "sick",
                "vacation",
                "emergency",
                "maternity",
                "paternity",
                "unpaid",
                "other",
                name="leavetype",
                create_type=False,
            ),
            nullable=True,
        ),
    )
    op.add_column(
        "leave_request", sa.Column("previous_start_date", sa.Date(), nullable=True)
    )
    op.add_column(
        "leave_request", sa.Column("previous_end_date", sa.Date(), nullable=True)
    )
    op.add_column(
        "leave_request", sa.Column("previous_reason", sa.Text(), nullable=True)
    )
    op.add_column(
        "leave_request",
        sa.Column("previous_supporting_document", sa.Text(), nullable=True),
    )
    op.add_column(
        "leave_request",
        sa.Column(
            "has_pending_changes",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )

    op.add_column(
        "activity_log", sa.Column("previous_value", sa.Text(), nullable=True)
    )
    op.add_column("activity_log", sa.Column("new_value", sa.Text(), nullable=True))
    op.add_column(
        "activity_log", sa.Column("platform", sa.String(length=40), nullable=True)
    )
    op.add_column(
        "activity_log", sa.Column("device", sa.String(length=120), nullable=True)
    )
    op.add_column(
        "activity_log", sa.Column("ip_address", sa.String(length=64), nullable=True)
    )

    op.create_table(
        "notification",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("business_id", sa.UUID(), nullable=True),
        sa.Column("recipient_user_id", sa.UUID(), nullable=False),
        sa.Column("recipient_role", sa.String(length=32), nullable=False),
        sa.Column("type", sa.String(length=64), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("message", sa.String(length=280), nullable=False),
        sa.Column("entity_type", sa.String(length=64), nullable=True),
        sa.Column("entity_id", sa.UUID(), nullable=True),
        sa.Column("deep_link", sa.String(length=255), nullable=True),
        sa.Column("is_read", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("metadata_json", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recipient_user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_notification_recipient_created",
        "notification",
        ["recipient_user_id", "created_at"],
    )
    op.create_index(
        "ix_notification_recipient_unread",
        "notification",
        ["recipient_user_id", "is_read"],
    )


def downgrade() -> None:
    op.drop_index("ix_notification_recipient_unread", table_name="notification")
    op.drop_index("ix_notification_recipient_created", table_name="notification")
    op.drop_table("notification")

    op.drop_column("activity_log", "ip_address")
    op.drop_column("activity_log", "device")
    op.drop_column("activity_log", "platform")
    op.drop_column("activity_log", "new_value")
    op.drop_column("activity_log", "previous_value")

    op.drop_column("leave_request", "has_pending_changes")
    op.drop_column("leave_request", "previous_supporting_document")
    op.drop_column("leave_request", "previous_reason")
    op.drop_column("leave_request", "previous_end_date")
    op.drop_column("leave_request", "previous_start_date")
    op.drop_column("leave_request", "previous_leave_type")
