import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import HolidayRulesMode, PayPeriodType, PayrollRunStatus, Weekday


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
    hourly_rate: Mapped[float | None] = mapped_column(
        Numeric(10, 2), nullable=True, default=None
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
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
    # Owner-configured OT pesos per qualifying overtime minute (before premium).
    overtime_per_minute: Mapped[float] = mapped_column(Numeric(10, 2), default=1.0)
    # When True, minutes past shift end first recover late-from-start before
    # accruing payable OT. Default False preserves existing payslip behavior.
    enable_late_overtime_balancing: Mapped[bool] = mapped_column(
        Boolean, default=False
    )
    # Deprecated legacy columns. Kept for backward-compatible schema only.
    # Active OT premium is 0% on ordinary/rest days and holiday.ot_premium_percent
    # on holidays. Payroll OT premium selection does not read these fields.
    ordinary_ot_premium_percent: Mapped[float] = mapped_column(
        Numeric(5, 2), default=25.0
    )
    rest_day_ot_premium_percent: Mapped[float] = mapped_column(
        Numeric(5, 2), default=25.0
    )
    # Deprecated legacy columns. Kept for backward-compatible schema only.
    # Payroll OT premium selection does not read these fields.
    special_day_ot_premium_percent: Mapped[float] = mapped_column(
        Numeric(5, 2), default=30.0
    )
    regular_holiday_ot_premium_percent: Mapped[float] = mapped_column(
        Numeric(5, 2), default=30.0
    )
    holiday_rest_day_ot_premium_percent: Mapped[float] = mapped_column(
        Numeric(5, 2), default=30.0
    )
    next_payday_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    auto_reset_payroll_cycle: Mapped[bool] = mapped_column(Boolean, default=True)
    # Payday schedule, interpreted per pay_period_type. Day values 29-31 are
    # clamped to the last day of shorter months.
    weekly_payday_weekday: Mapped[Weekday | None] = mapped_column(
        Enum(Weekday), nullable=True
    )
    semi_monthly_payday_1: Mapped[int | None] = mapped_column(Integer, nullable=True)
    semi_monthly_payday_2: Mapped[int | None] = mapped_column(Integer, nullable=True)
    monthly_payday_day: Mapped[int | None] = mapped_column(Integer, nullable=True)
    holiday_rules_mode: Mapped[HolidayRulesMode] = mapped_column(
        Enum(HolidayRulesMode),
        default=HolidayRulesMode.philippine_labor,
        nullable=False,
    )


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
    # 1 = Phase 1 JSON snapshot written at finalize. NULL = legacy run (no slips).
    snapshot_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Audit-only copy of business flags used at finalize. Not used to recalculate.
    calculation_config_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Payslip(Base):
    __tablename__ = "payslip"
    __table_args__ = (
        UniqueConstraint(
            "payroll_run_id",
            "employee_id",
            name="uq_payslip_run_employee",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    payroll_run_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payroll_run.id"), nullable=False
    )
    # Nullable so deleting an employee SET NULL and keeps the historical row.
    employee_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("employee.id", ondelete="SET NULL"),
        nullable=True,
    )
    regular_hours: Mapped[float] = mapped_column(Numeric(8, 2), default=0)
    overtime_hours: Mapped[float] = mapped_column(Numeric(8, 2), default=0)
    gross_pay: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    total_deductions: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    net_pay: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    breakdown_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
