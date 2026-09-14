"""Catalog consent documents (platform defaults or business overrides)."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

SCOPE_PLATFORM = "platform"
SCOPE_BUSINESS = "business"


class ConsentDocument(Base):
    __tablename__ = "consent_document"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    scope: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    business_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("business.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    is_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    consent_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default="custom", server_default="custom"
    )
    body_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    file_stored_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    file_content_type: Mapped[str | None] = mapped_column(String(120), nullable=True)
    original_filename: Mapped[str | None] = mapped_column(String(255), nullable=True)
    version: Mapped[str] = mapped_column(String(80), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("user.id", ondelete="SET NULL"),
        nullable=True,
    )

    __table_args__ = (
        CheckConstraint(
            "scope IN ('platform', 'business')",
            name="ck_consent_document_scope",
        ),
        CheckConstraint(
            "(scope = 'platform' AND business_id IS NULL) OR "
            "(scope = 'business' AND business_id IS NOT NULL)",
            name="ck_consent_document_scope_business",
        ),
        CheckConstraint(
            "consent_type IN ('terms', 'privacy', 'biometric', 'custom')",
            name="ck_consent_document_type",
        ),
    )
