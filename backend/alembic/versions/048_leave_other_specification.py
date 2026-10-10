"""Other leave specification on leave requests.

Revision ID: 048
Revises: 047
Create Date: 2026-09-28

Adds nullable specification text for Other leave. Does not change the
leavetype enum or existing Unpaid rows.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "048"
down_revision: Union[str, None] = "047"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "leave_request",
        sa.Column("other_leave_specification", sa.String(length=200), nullable=True),
    )
    op.add_column(
        "leave_request",
        sa.Column(
            "previous_other_leave_specification",
            sa.String(length=200),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("leave_request", "previous_other_leave_specification")
    op.drop_column("leave_request", "other_leave_specification")
