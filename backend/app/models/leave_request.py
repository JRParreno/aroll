import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Enum, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import LeaveRequestStatus, LeaveType


class LeaveRequest(Base):
    """Employee leave request.

    Current fields hold the active (possibly edited) values.
    previous_* fields hold the last committed version for owner comparison
    when has_pending_changes is true. Leave balances/credits are intentionally
    not modeled here yet — keep this table free of hard-coded quota assumptions.
    """

    __tablename__ = "leave_request"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id", ondelete="CASCADE"), nullable=False
    )
    employee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employee.id", ondelete="CASCADE"), nullable=False
    )
    leave_type: Mapped[LeaveType] = mapped_column(Enum(LeaveType), nullable=False)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    leave_days: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    supporting_document: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Snapshot of company Leave Policy at create/edit; payroll uses is_paid.
    policy_is_paid: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    is_paid: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    is_paid_overridden: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    status: Mapped[LeaveRequestStatus] = mapped_column(
        Enum(LeaveRequestStatus),
        nullable=False,
        default=LeaveRequestStatus.pending,
    )
    previous_leave_type: Mapped[LeaveType | None] = mapped_column(
        Enum(LeaveType), nullable=True
    )
    previous_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    previous_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    previous_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    previous_supporting_document: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )
    has_pending_changes: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    owner_remarks: Mapped[str | None] = mapped_column(String(500), nullable=True)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
