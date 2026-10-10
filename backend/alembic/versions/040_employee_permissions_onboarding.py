"""Employee permissions onboarding completed timestamp

Revision ID: 040
Revises: 039
Create Date: 2026-09-19

Account-level (not device-level) flag for whether the employee has completed
the mobile permissions onboarding explanation. OS permission grants remain
device-local and are never stored here.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "040"
down_revision: Union[str, None] = "039"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "employee",
        sa.Column(
            "permissions_onboarding_completed_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("employee", "permissions_onboarding_completed_at")
