"""One-time face liveness challenges for head-turn verification

Revision ID: 014
Revises: 013
Create Date: 2026-07-18

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "014"
down_revision: Union[str, None] = "013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "face_liveness_challenge",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("employee_id", sa.UUID(), nullable=False),
        sa.Column("requested_by", sa.UUID(), nullable=False),
        sa.Column("direction", sa.String(length=20), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["requested_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_flc_employee_id",
        "face_liveness_challenge",
        ["employee_id"],
    )
    op.create_index(
        "idx_flc_expires_at",
        "face_liveness_challenge",
        ["expires_at"],
    )


def downgrade() -> None:
    op.drop_index("idx_flc_expires_at", table_name="face_liveness_challenge")
    op.drop_index("idx_flc_employee_id", table_name="face_liveness_challenge")
    op.drop_table("face_liveness_challenge")
