"""Platform legal defaults, business override flag, and consent snapshots.

Revision ID: 033
Revises: 032
Create Date: 2026-09-11

Platform Admin owns default Terms, Privacy, and Biometric Consent.
Businesses use those defaults unless use_custom_consents is true.
Existing businesses that already published all three sections stay in
custom mode so their current employee-facing content is preserved.
Demo / internal-test tenants inherit Admin defaults.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "033"
down_revision: Union[str, None] = "032"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_DEFAULT_TERMS = (
    "Aroll+ Terms and Conditions\n\n"
    "This workplace uses Aroll+ for attendance, scheduling, and payroll "
    "during the academic / pilot deployment.\n\n"
    "By agreeing, you confirm that you are authorized to use this account, "
    "will not clock in for another person, and will not spoof location or "
    "face verification.\n\n"
    "Face enrollment requires a separate biometric consent. Full template "
    "text is in the project docs/legal folder for owner review."
)
_DEFAULT_PRIVACY = (
    "Aroll+ Privacy Policy\n\n"
    "Aroll+ processes account, attendance, location (for geofence checks), "
    "and face embedding data to provide workplace timekeeping.\n\n"
    "Face images are processed to create numeric templates and are not "
    "kept as a long-term photo album. Data is isolated to this business "
    "and is not used for marketing.\n\n"
    "You may request access, correction, or deletion of biometric templates "
    "through your employer. Aroll+ is intended for adult employees (18+)."
)
_DEFAULT_BIOMETRIC = (
    "Aroll+ Biometric Consent\n\n"
    "Before face enrollment, you consent to Aroll+ capturing face samples, "
    "storing face embeddings for matching, and using liveness plus workplace "
    "location checks when you Time In or Time Out.\n\n"
    "This is not Apple Face ID. Templates are stored in the Aroll+ database "
    "for this business only. You may withdraw consent; face clock-in will "
    "then be unavailable and templates will be deleted."
)


def upgrade() -> None:
    op.create_table(
        "platform_legal_document",
        sa.Column("consent_type", sa.String(length=20), primary_key=True),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("version", sa.String(length=80), nullable=False),
        sa.Column(
            "published",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.CheckConstraint(
            "consent_type IN ('terms', 'privacy', 'biometric')",
            name="ck_platform_legal_document_type",
        ),
    )
    op.bulk_insert(
        sa.table(
            "platform_legal_document",
            sa.column("consent_type", sa.String),
            sa.column("content", sa.Text),
            sa.column("version", sa.String),
            sa.column("published", sa.Boolean),
        ),
        [
            {
                "consent_type": "terms",
                "content": _DEFAULT_TERMS,
                "version": "terms-2026-09-09",
                "published": True,
            },
            {
                "consent_type": "privacy",
                "content": _DEFAULT_PRIVACY,
                "version": "privacy-2026-09-09",
                "published": True,
            },
            {
                "consent_type": "biometric",
                "content": _DEFAULT_BIOMETRIC,
                "version": "biometric-consent-2026-09-09",
                "published": True,
            },
        ],
    )

    op.add_column(
        "business",
        sa.Column(
            "use_custom_consents",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.execute(
        """
        UPDATE business
        SET use_custom_consents = true
        WHERE NOT COALESCE(is_demo, false)
          AND NOT COALESCE(is_internal_test, false)
          AND NULLIF(BTRIM(COALESCE(terms_content, '')), '') IS NOT NULL
          AND NULLIF(BTRIM(COALESCE(terms_version, '')), '') IS NOT NULL
          AND NULLIF(BTRIM(COALESCE(privacy_content, '')), '') IS NOT NULL
          AND NULLIF(BTRIM(COALESCE(privacy_version, '')), '') IS NOT NULL
          AND NULLIF(BTRIM(COALESCE(biometric_consent_content, '')), '') IS NOT NULL
          AND NULLIF(BTRIM(COALESCE(biometric_consent_version, '')), '') IS NOT NULL
        """
    )

    op.add_column(
        "consent_record",
        sa.Column("content_source", sa.String(length=20), nullable=True),
    )
    op.add_column(
        "consent_record",
        sa.Column("accepted_content_hash", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "consent_record",
        sa.Column("content_snapshot", sa.Text(), nullable=True),
    )
    op.create_check_constraint(
        "ck_consent_record_content_source",
        "consent_record",
        "content_source IS NULL OR content_source IN "
        "('admin_default', 'business_custom')",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_consent_record_content_source",
        "consent_record",
        type_="check",
    )
    op.drop_column("consent_record", "content_snapshot")
    op.drop_column("consent_record", "accepted_content_hash")
    op.drop_column("consent_record", "content_source")
    op.drop_column("business", "use_custom_consents")
    op.drop_table("platform_legal_document")
