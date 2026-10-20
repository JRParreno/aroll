"""Owner-selected Daily workday entitlement for same-date stamp conflicts.

Separate from AttendanceRecord ``*_at_completion`` historical stamps.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class DailyWorkdayRateResolution(Base):
    """One Owner-chosen Daily entitlement per employee work_date.

    Used only when completed Daily attendance stamps on that date conflict.
    Never replaces attendance completion-rate stamps.
    """

    __tablename__ = "daily_workday_rate_resolution"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "employee_id",
            "work_date",
            name="uq_daily_workday_rate_resolution_biz_emp_date",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), nullable=False, index=True
    )
    employee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employee.id"), nullable=False, index=True
    )
    work_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    daily_rate: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
