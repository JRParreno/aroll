"""Track post-approval Business Code email delivery

Revision ID: 050
Revises: 049
Create Date: 2026-10-14

Adds delivery-status columns on business_registration so an administrator
can send the approval email after commit without creating a second Business
Code, and so concurrent duplicate sends can be refused.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "050"
down_revision: Union[str, None] = "049"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing = {col["name"] for col in inspector.get_columns("business_registration")}
    if "approval_email_status" not in existing:
        op.add_column(
            "business_registration",
            sa.Column("approval_email_status", sa.String(length=20), nullable=True),
        )
    if "approval_email_sent_at" not in existing:
        op.add_column(
            "business_registration",
            sa.Column(
                "approval_email_sent_at",
                sa.DateTime(timezone=True),
                nullable=True,
            ),
        )
    if "approval_email_last_error" not in existing:
        op.add_column(
            "business_registration",
            sa.Column(
                "approval_email_last_error",
                sa.String(length=200),
                nullable=True,
            ),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing = {col["name"] for col in inspector.get_columns("business_registration")}
    if "approval_email_last_error" in existing:
        op.drop_column("business_registration", "approval_email_last_error")
    if "approval_email_status" in existing:
        op.drop_column("business_registration", "approval_email_status")
    # approval_email_sent_at may predate this revision; do not drop it.
