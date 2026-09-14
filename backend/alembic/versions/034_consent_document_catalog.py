"""Consent document catalog and document_id on consent_record.

Revision ID: 034
Revises: 033
Create Date: 2026-09-14

Platform and business legal copy move into consent_document rows so Admin
and owners can manage an ordered list (text and/or file) with a public URL
per document. Existing platform_legal_document and business legal columns
are copied, not dropped.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "034"
down_revision: Union[str, None] = "033"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "consent_document",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("scope", sa.String(length=20), nullable=False),
        sa.Column(
            "business_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("business.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.Column(
            "is_required",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.Column(
            "consent_type",
            sa.String(length=20),
            nullable=False,
            server_default="custom",
        ),
        sa.Column("body_text", sa.Text(), nullable=True),
        sa.Column("file_stored_name", sa.String(length=255), nullable=True),
        sa.Column("file_content_type", sa.String(length=120), nullable=True),
        sa.Column("original_filename", sa.String(length=255), nullable=True),
        sa.Column("version", sa.String(length=80), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
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
            "scope IN ('platform', 'business')",
            name="ck_consent_document_scope",
        ),
        sa.CheckConstraint(
            "(scope = 'platform' AND business_id IS NULL) OR "
            "(scope = 'business' AND business_id IS NOT NULL)",
            name="ck_consent_document_scope_business",
        ),
        sa.CheckConstraint(
            "consent_type IN ('terms', 'privacy', 'biometric', 'custom')",
            name="ck_consent_document_type",
        ),
    )
    op.create_index(
        "idx_consent_document_scope_position",
        "consent_document",
        ["scope", "business_id", "position"],
    )

    op.add_column(
        "consent_record",
        sa.Column(
            "document_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("consent_document.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index(
        "idx_consent_record_document_id",
        "consent_record",
        ["document_id"],
    )
    op.drop_constraint("ck_consent_record_type", "consent_record", type_="check")
    op.create_check_constraint(
        "ck_consent_record_type",
        "consent_record",
        "consent_type IN ('terms', 'privacy', 'biometric', 'custom')",
    )

    op.execute(
        """
        INSERT INTO consent_document (
            id, scope, business_id, title, position, is_active, is_required,
            consent_type, body_text, version, updated_by, created_at, updated_at
        )
        SELECT
            gen_random_uuid(),
            'platform',
            NULL,
            CASE p.consent_type
                WHEN 'terms' THEN 'Terms and Conditions'
                WHEN 'privacy' THEN 'Privacy Policy'
                WHEN 'biometric' THEN 'Biometric Consent'
                ELSE initcap(p.consent_type)
            END,
            CASE p.consent_type
                WHEN 'terms' THEN 1
                WHEN 'privacy' THEN 2
                WHEN 'biometric' THEN 3
                ELSE 10
            END,
            COALESCE(p.published, true)
              AND NULLIF(BTRIM(COALESCE(p.content, '')), '') IS NOT NULL
              AND NULLIF(BTRIM(COALESCE(p.version, '')), '') IS NOT NULL,
            true,
            p.consent_type,
            p.content,
            p.version,
            p.updated_by,
            COALESCE(p.updated_at, now()),
            COALESCE(p.updated_at, now())
        FROM platform_legal_document p
        WHERE NOT EXISTS (
            SELECT 1 FROM consent_document d
            WHERE d.scope = 'platform' AND d.consent_type = p.consent_type
        )
        """
    )

    op.execute(
        """
        INSERT INTO consent_document (
            id, scope, business_id, title, position, is_active, is_required,
            consent_type, body_text, version, created_at, updated_at
        )
        SELECT
            gen_random_uuid(),
            'business',
            b.id,
            src.title,
            src.position,
            true,
            true,
            src.consent_type,
            src.body_text,
            src.version,
            COALESCE(b.legal_updated_at, now()),
            COALESCE(b.legal_updated_at, now())
        FROM business b
        CROSS JOIN LATERAL (
            VALUES
                (
                    'terms',
                    'Terms and Conditions',
                    1,
                    b.terms_content,
                    COALESCE(NULLIF(BTRIM(b.terms_version), ''), 'terms-custom')
                ),
                (
                    'privacy',
                    'Privacy Policy',
                    2,
                    b.privacy_content,
                    COALESCE(NULLIF(BTRIM(b.privacy_version), ''), 'privacy-custom')
                ),
                (
                    'biometric',
                    'Biometric Consent',
                    3,
                    b.biometric_consent_content,
                    COALESCE(
                        NULLIF(BTRIM(b.biometric_consent_version), ''),
                        'biometric-custom'
                    )
                )
        ) AS src(consent_type, title, position, body_text, version)
        WHERE COALESCE(b.use_custom_consents, false)
          AND NULLIF(BTRIM(COALESCE(src.body_text, '')), '') IS NOT NULL
        """
    )

    op.execute(
        """
        UPDATE consent_record cr
        SET document_id = d.id
        FROM consent_document d, business b
        WHERE cr.business_id = b.id
          AND d.scope = 'platform'
          AND d.consent_type = cr.consent_type
          AND NOT COALESCE(b.use_custom_consents, false)
          AND cr.document_id IS NULL
        """
    )
    op.execute(
        """
        UPDATE consent_record cr
        SET document_id = d.id
        FROM consent_document d
        WHERE d.scope = 'business'
          AND d.business_id = cr.business_id
          AND d.consent_type = cr.consent_type
          AND cr.document_id IS NULL
        """
    )


def downgrade() -> None:
    op.drop_index("idx_consent_record_document_id", table_name="consent_record")
    op.drop_column("consent_record", "document_id")
    op.drop_constraint("ck_consent_record_type", "consent_record", type_="check")
    op.create_check_constraint(
        "ck_consent_record_type",
        "consent_record",
        "consent_type IN ('terms', 'privacy', 'biometric')",
    )
    op.drop_index(
        "idx_consent_document_scope_position", table_name="consent_document"
    )
    op.drop_table("consent_document")
