import uuid

from sqlalchemy import Boolean, Enum, ForeignKey, Integer, Numeric
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import MissingClockOutPolicy


class BusinessAttendancePolicy(Base):
    __tablename__ = "business_attendance_policy"

    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), primary_key=True
    )
    early_clock_in_minutes: Mapped[int] = mapped_column(Integer, default=15)
    on_time_grace_minutes: Mapped[int] = mapped_column(Integer, default=10)
    half_day_threshold_minutes: Mapped[int] = mapped_column(Integer, default=120)
    absent_threshold_minutes: Mapped[int] = mapped_column(Integer, default=240)
    early_out_deduction_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    early_out_deduction_per_minute: Mapped[float] = mapped_column(
        Numeric(10, 2), default=2.0
    )
    overtime_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    overtime_minimum_minutes: Mapped[int] = mapped_column(Integer, default=30)
    overtime_rate_per_minute: Mapped[float] = mapped_column(Numeric(10, 2), default=5.0)
    missing_clock_out_policy: Mapped[MissingClockOutPolicy] = mapped_column(
        Enum(MissingClockOutPolicy), default=MissingClockOutPolicy.auto_clock_out
    )
    attendance_based_salary_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
