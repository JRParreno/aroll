"""Mark rest-day work on shift assignments

Revision ID: 017
Revises: 016
Create Date: 2026-07-19

Rest-day premium is approved per schedule assignment by the owner/manager,
not by a fixed weekly weekday. Adds is_rest_day_work on shift_assignment.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "017"
down_revision: Union[str, None] = "016"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "shift_assignment",
        sa.Column(
            "is_rest_day_work",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("shift_assignment", "is_rest_day_work")
