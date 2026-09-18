import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Enum, ForeignKey, Numeric, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import HolidayType


class Holiday(Base):
    __tablename__ = "holiday"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    holiday_date: Mapped[date] = mapped_column(Date, nullable=False)
    is_paid: Mapped[bool] = mapped_column(Boolean, default=True)
    pay_multiplier: Mapped[float] = mapped_column(Numeric(5, 2), default=1.0)
    # None = not configured (fall back to rest-day or ordinary OT). 0 = 0%.
    ot_premium_percent: Mapped[float | None] = mapped_column(
        Numeric(5, 2), nullable=True, default=None
    )
    holiday_type: Mapped[HolidayType] = mapped_column(Enum(HolidayType), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
