"""Employee legal consent flag and per-business consent webpage

Revision ID: 032
Revises: 031
Create Date: 2026-09-08

Employee.legal_consent_accepted is the source of truth for whether the
employee has agreed to their workplace consent page.

Business.legal_consent_content is owner-configured Terms / Privacy /
biometric consent text. Business.legal_consent_url stores the generated
public path /legal/b/{business_code}.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "032"
down_revision: Union[str, None] = "031"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "employee",
        sa.Column(
            "legal_consent_accepted",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.add_column(
        "employee",
        sa.Column(
            "legal_consent_accepted_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.add_column(
        "business",
        sa.Column("legal_consent_content", sa.Text(), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("legal_consent_url", sa.String(length=160), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column(
            "legal_consent_updated_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.execute(
        "UPDATE business SET legal_consent_url = '/legal/b/' || business_code "
        "WHERE legal_consent_url IS NULL"
    )


def downgrade() -> None:
    op.drop_column("business", "legal_consent_updated_at")
    op.drop_column("business", "legal_consent_url")
    op.drop_column("business", "legal_consent_content")
    op.drop_column("employee", "legal_consent_accepted_at")
    op.drop_column("employee", "legal_consent_accepted")
