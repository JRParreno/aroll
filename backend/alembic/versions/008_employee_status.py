"""Add employee onboarding status

Revision ID: 008
Revises: 007
Create Date: 2026-06-18

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

employeestatus = sa.Enum("invited", "active", "inactive", name="employeestatus")


def upgrade() -> None:
    employeestatus.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "employee",
        sa.Column(
            "status",
            employeestatus,
            nullable=False,
            server_default="invited",
        ),
    )
    op.execute(
        """
        UPDATE employee e
        SET status = CASE
            WHEN e.is_active = false THEN 'inactive'::employeestatus
            WHEN u.must_change_password = true THEN 'invited'::employeestatus
            ELSE 'active'::employeestatus
        END
        FROM "user" u
        WHERE e.user_id = u.id
        """
    )


def downgrade() -> None:
    op.drop_column("employee", "status")
    employeestatus.drop(op.get_bind(), checkfirst=True)
