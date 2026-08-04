"""Per-business leave payroll treatment configuration.

Current scope: paid/unpaid treatment per leave type.
Designed for future expansion without restructuring:
- `config_json` can hold future knobs (credits, carry-forward, max days).
- Effective-dated policy versions can be added as a child table keyed by
  business_id (e.g. business_leave_policy_version) while this row remains
  the active/current policy pointer.
- Leave credit balances should live on separate tables, not here.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class BusinessLeavePolicy(Base):
    __tablename__ = "business_leave_policy"

    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id", ondelete="CASCADE"), primary_key=True
    )
    # leave_type value -> bool (True = Paid Leave, False = Unpaid Leave)
    treatments: Mapped[dict] = mapped_column(JSONB, nullable=False)
    # Reserved for future leave credits / balances / probation rules.
    config_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
