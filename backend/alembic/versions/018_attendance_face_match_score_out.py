"""Add face_match_score_out on attendance_record

Revision ID: 018
Revises: 017
Create Date: 2026-07-19
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "018"
down_revision: Union[str, None] = "017"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "attendance_record",
        sa.Column("face_match_score_out", sa.Numeric(5, 4), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("attendance_record", "face_match_score_out")
