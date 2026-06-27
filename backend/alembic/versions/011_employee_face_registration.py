"""Employee face registration state

Revision ID: 011
Revises: 010
Create Date: 2026-06-20

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "011"
down_revision: Union[str, None] = "010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "employee",
        sa.Column(
            "face_registration_status",
            sa.String(length=20),
            nullable=False,
            server_default="not_registered",
        ),
    )
    op.add_column(
        "employee",
        sa.Column("face_registered_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "employee",
        sa.Column(
            "face_registration_skipped_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.alter_column("employee", "face_registration_status", server_default=None)


def downgrade() -> None:
    op.drop_column("employee", "face_registration_skipped_at")
    op.drop_column("employee", "face_registered_at")
    op.drop_column("employee", "face_registration_status")
