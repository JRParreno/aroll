"""Registration documents and application status

Revision ID: 007
Revises: 006
Create Date: 2026-06-06

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        DO $$ BEGIN
            CREATE TYPE applicationstatus AS ENUM ('draft', 'pending', 'approved', 'rejected');
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
        """
    )
    op.execute(
        """
        DO $$ BEGIN
            CREATE TYPE registrationdocumenttype AS ENUM (
                'business_permit',
                'valid_id',
                'dti_sec',
                'bir_cor'
            );
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
        """
    )

    op.add_column(
        "business_registration",
        sa.Column("business_type", sa.String(100), nullable=True),
    )
    application_status = postgresql.ENUM(
        "draft",
        "pending",
        "approved",
        "rejected",
        name="applicationstatus",
        create_type=False,
    )
    op.add_column(
        "business_registration",
        sa.Column(
            "application_status",
            application_status,
            nullable=False,
            server_default="pending",
        ),
    )
    op.execute(
        """
        UPDATE business_registration
        SET application_status = status::text::applicationstatus
        """
    )
    op.alter_column("business_registration", "submitted_at", nullable=True)

    op.create_table(
        "registration_document",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("registration_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "document_type",
            postgresql.ENUM(
                "business_permit",
                "valid_id",
                "dti_sec",
                "bir_cor",
                name="registrationdocumenttype",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column("original_filename", sa.String(255), nullable=False),
        sa.Column("stored_filename", sa.String(255), nullable=False),
        sa.Column("content_type", sa.String(100), nullable=False),
        sa.Column("file_size", sa.Integer(), nullable=False),
        sa.Column(
            "uploaded_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(
            ["registration_id"],
            ["business_registration.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "registration_id",
            "document_type",
            name="uq_registration_document_type",
        ),
    )


def downgrade() -> None:
    op.drop_table("registration_document")
    op.alter_column("business_registration", "submitted_at", nullable=False)
    op.drop_column("business_registration", "application_status")
    op.drop_column("business_registration", "business_type")
    op.execute("DROP TYPE IF EXISTS registrationdocumenttype")
    op.execute("DROP TYPE IF EXISTS applicationstatus")
