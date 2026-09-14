"""Per-business legal webpage and append-only consent records.

Revision ID: 032
Revises: 031
Create Date: 2026-09-09

Runtime legal content is owner-configured per business. Employee acceptance
is stored as typed consent_record rows (terms / privacy / biometric) with
policy version, identity, timestamp, client, and audit metadata.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "032"
down_revision: Union[str, None] = "031"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business",
        sa.Column("legal_page_url", sa.String(length=160), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("terms_content", sa.Text(), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("privacy_content", sa.Text(), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("biometric_consent_content", sa.Text(), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("terms_version", sa.String(length=80), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("privacy_version", sa.String(length=80), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("biometric_consent_version", sa.String(length=80), nullable=True),
    )
    op.add_column(
        "business",
        sa.Column("legal_updated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.execute(
        "UPDATE business SET legal_page_url = '/legal/b/' || business_code "
        "WHERE legal_page_url IS NULL"
    )

    op.create_table(
        "consent_record",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column(
            "business_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("business.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "employee_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("employee.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("consent_type", sa.String(length=20), nullable=False),
        sa.Column("policy_version", sa.String(length=80), nullable=False),
        sa.Column("action", sa.String(length=20), nullable=False),
        sa.Column("client", sa.String(length=20), nullable=True),
        sa.Column("ip_address", sa.String(length=64), nullable=True),
        sa.Column("device", sa.String(length=120), nullable=True),
        sa.Column("platform", sa.String(length=40), nullable=True),
        sa.Column("legal_page_url", sa.String(length=200), nullable=True),
        sa.Column("adult_acknowledged", sa.Boolean(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "consent_type IN ('terms', 'privacy', 'biometric')",
            name="ck_consent_record_type",
        ),
        sa.CheckConstraint(
            "action IN ('accepted', 'withdrawn')",
            name="ck_consent_record_action",
        ),
        sa.CheckConstraint(
            "client IS NULL OR client IN ('mobile', 'web')",
            name="ck_consent_record_client",
        ),
    )
    op.create_index(
        "idx_consent_record_employee_type_created",
        "consent_record",
        ["employee_id", "consent_type", "created_at"],
    )
    op.create_index(
        "idx_consent_record_business_id",
        "consent_record",
        ["business_id"],
    )


def downgrade() -> None:
    op.drop_index("idx_consent_record_business_id", table_name="consent_record")
    op.drop_index(
        "idx_consent_record_employee_type_created", table_name="consent_record"
    )
    op.drop_table("consent_record")
    op.drop_column("business", "legal_updated_at")
    op.drop_column("business", "biometric_consent_version")
    op.drop_column("business", "privacy_version")
    op.drop_column("business", "terms_version")
    op.drop_column("business", "biometric_consent_content")
    op.drop_column("business", "privacy_content")
    op.drop_column("business", "terms_content")
    op.drop_column("business", "legal_page_url")
