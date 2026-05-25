import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Numeric, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import AttendanceStatus


class AttendanceRecord(Base):
    __tablename__ = "attendance_record"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), nullable=False
    )
    employee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employee.id"), nullable=False
    )
    shift_assignment_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("shift_assignment.id"), nullable=True
    )
    time_in: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    time_out: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    status: Mapped[AttendanceStatus] = mapped_column(
        Enum(AttendanceStatus), default=AttendanceStatus.in_progress
    )
    latitude_in: Mapped[float | None] = mapped_column(Numeric(10, 7), nullable=True)
    longitude_in: Mapped[float | None] = mapped_column(Numeric(10, 7), nullable=True)
    latitude_out: Mapped[float | None] = mapped_column(Numeric(10, 7), nullable=True)
    longitude_out: Mapped[float | None] = mapped_column(Numeric(10, 7), nullable=True)
    face_match_score: Mapped[float | None] = mapped_column(Numeric(5, 4), nullable=True)
    liveness_passed: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
