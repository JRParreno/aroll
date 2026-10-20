"""Business-wide leave allowance for one leave type and calendar year.

Every employee shares this allowance. Used days are not stored here. They
are calculated per employee from approved and cancellation-pending requests.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import LeaveType


class BusinessLeaveAllowance(Base):
    __tablename__ = "business_leave_allowance"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "leave_type",
            "year",
            name="uq_business_leave_allowance_business_type_year",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id", ondelete="CASCADE"), nullable=False
    )
    leave_type: Mapped[LeaveType] = mapped_column(Enum(LeaveType), nullable=False)
    year: Mapped[int] = mapped_column(Integer, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False)
    allowance_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
