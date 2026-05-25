import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Enum, ForeignKey, Numeric, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import PayPeriodType, PayrollRunStatus


class Position(Base):
    __tablename__ = "position"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), nullable=False
    )
    title: Mapped[str] = mapped_column(String(100), nullable=False)
    daily_rate: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class BusinessPayrollConfig(Base):
    __tablename__ = "business_payroll_config"

    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), primary_key=True
    )
    pay_period_type: Mapped[PayPeriodType] = mapped_column(
        Enum(PayPeriodType), default=PayPeriodType.monthly
    )
    late_deduction_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    late_deduction_per_minute: Mapped[float] = mapped_column(
        Numeric(10, 2), default=1.0
    )
    overtime_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    overtime_per_minute: Mapped[float] = mapped_column(Numeric(10, 2), default=1.0)
    next_payday_date: Mapped[date | None] = mapped_column(Date, nullable=True)


class PayrollRun(Base):
    __tablename__ = "payroll_run"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), nullable=False
    )
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[PayrollRunStatus] = mapped_column(
        Enum(PayrollRunStatus), default=PayrollRunStatus.draft
    )
    run_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id"), nullable=True
    )
    finalized_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Payslip(Base):
    __tablename__ = "payslip"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    payroll_run_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payroll_run.id"), nullable=False
    )
    employee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employee.id"), nullable=False
    )
    regular_hours: Mapped[float] = mapped_column(Numeric(8, 2), default=0)
    overtime_hours: Mapped[float] = mapped_column(Numeric(8, 2), default=0)
    gross_pay: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    total_deductions: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    net_pay: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    breakdown_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
