import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Numeric, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import AttendanceStatus, OvertimeApprovalStatus, PayBasis


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
    face_match_score_out: Mapped[float | None] = mapped_column(
        Numeric(5, 4), nullable=True
    )
    liveness_passed: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    # Payable OT gate when business requires OT approval. Null when approval is
    # off or there is no qualifying OT. Does not alter Time In / Time Out.
    ot_approval_status: Mapped[OvertimeApprovalStatus | None] = mapped_column(
        Enum(
            OvertimeApprovalStatus,
            name="overtimeapprovalstatus",
            values_callable=lambda enum_cls: [item.value for item in enum_cls],
        ),
        nullable=True,
    )
    ot_reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id"), nullable=True
    )
    ot_reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Pay rates captured when the punch first closes (time_out + closed status).
    # Live unfinalized payroll uses these for that day so a later Employee Role
    # restamp does not reprice completed shifts. Null = legacy / not yet stamped
    # → keep using current Employee rates (existing Design B behavior).
    pay_basis_at_completion: Mapped[PayBasis | None] = mapped_column(
        Enum(
            PayBasis,
            name="paybasis",
            values_callable=lambda enum_cls: [item.value for item in enum_cls],
            create_type=False,
        ),
        nullable=True,
    )
    daily_rate_at_completion: Mapped[float | None] = mapped_column(
        Numeric(10, 2), nullable=True
    )
    hourly_rate_at_completion: Mapped[float | None] = mapped_column(
        Numeric(10, 2), nullable=True
    )
    monthly_salary_at_completion: Mapped[float | None] = mapped_column(
        Numeric(10, 2), nullable=True
    )
    # Optional secondary evidence. Null means Wi-Fi was not evaluated.
    # Payroll and attendance status do not read these columns.
    wifi_verification_in: Mapped[str | None] = mapped_column(String(32), nullable=True)
    wifi_verification_out: Mapped[str | None] = mapped_column(String(32), nullable=True)
    matched_wifi_access_point_id_in: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workplace_wifi_access_point.id", ondelete="SET NULL"),
        nullable=True,
    )
    matched_wifi_access_point_id_out: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workplace_wifi_access_point.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
