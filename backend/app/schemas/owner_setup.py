from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.models.enums import (
    EmploymentType,
    HolidayRulesMode,
    HolidayType,
    LeaveType,
    MissingClockOutPolicy,
    OvertimeCalculationMethod,
    PayBasis,
    PayPeriodType,
    ShiftType,
    Weekday,
)


class ShiftCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    shift_type: ShiftType = ShiftType.morning
    start_time: time
    end_time: time
    break_minutes: int = Field(default=0, ge=0)
    employee_capacity: int = Field(default=1, ge=1)
    color: str | None = Field(default=None, max_length=7)


class ShiftUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    shift_type: ShiftType | None = None
    start_time: time | None = None
    end_time: time | None = None
    break_minutes: int | None = Field(default=None, ge=0)
    employee_capacity: int | None = Field(default=None, ge=1)
    color: str | None = Field(default=None, max_length=7)
    is_active: bool | None = None


class ShiftResponse(BaseModel):
    id: str
    name: str
    shift_type: str
    start_time: time
    end_time: time
    break_minutes: int
    employee_capacity: int
    color: str | None
    is_active: bool
    has_in_progress_today: bool = False

    class Config:
        from_attributes = True


def _validate_position_rates(
    *,
    pay_basis: PayBasis,
    daily_rate: float | None,
    hourly_rate: float | None,
) -> None:
    if pay_basis not in (PayBasis.daily, PayBasis.hourly):
        raise ValueError(
            "Position pay_basis must be daily or hourly. "
            "Monthly pay remains employee-only."
        )
    if pay_basis == PayBasis.daily:
        if daily_rate is None or daily_rate <= 0:
            raise ValueError("daily_rate is required when pay_basis is daily.")
    elif pay_basis == PayBasis.hourly:
        if hourly_rate is None or hourly_rate <= 0:
            raise ValueError("hourly_rate is required when pay_basis is hourly.")


class PositionPayConfigPayload(BaseModel):
    pay_basis: PayBasis
    rate: float = Field(gt=0)

    @model_validator(mode="after")
    def _daily_or_hourly(self):
        if self.pay_basis not in (PayBasis.daily, PayBasis.hourly):
            raise ValueError(
                "Position pay configurations must be daily or hourly. "
                "Monthly pay remains employee-only."
            )
        return self


class PositionPayConfigResponse(BaseModel):
    id: str
    pay_basis: PayBasis
    rate: float


class PositionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    employment_type: EmploymentType
    # Design B: preferred multi-config payload.
    pay_configs: list[PositionPayConfigPayload] | None = None
    # Legacy single-basis create (converted to one pay_config).
    pay_basis: PayBasis | None = None
    daily_rate: float | None = Field(default=None, gt=0)
    hourly_rate: float | None = Field(default=None, gt=0)
    description: str | None = None

    @model_validator(mode="after")
    def _rates_match_basis(self):
        if self.pay_configs is not None:
            if not self.pay_configs:
                raise ValueError(
                    "At least one pay configuration (Daily or Hourly) is required."
                )
            bases = [c.pay_basis for c in self.pay_configs]
            if len(bases) != len(set(bases)):
                raise ValueError(
                    "Duplicate pay basis is not allowed for the same role."
                )
            return self
        if self.pay_basis is None:
            self.pay_basis = PayBasis.daily
        _validate_position_rates(
            pay_basis=self.pay_basis,
            daily_rate=self.daily_rate,
            hourly_rate=self.hourly_rate,
        )
        return self


class PositionUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=100)
    employment_type: EmploymentType | None = None
    pay_configs: list[PositionPayConfigPayload] | None = None
    # Legacy single-basis update fields (still accepted).
    pay_basis: PayBasis | None = None
    daily_rate: float | None = Field(default=None, gt=0)
    hourly_rate: float | None = Field(default=None, gt=0)
    description: str | None = None
    is_active: bool | None = None


class PositionResponse(BaseModel):
    id: str
    title: str
    employment_type: EmploymentType | None = None
    # Convenience mirrors of pay_configs for older clients.
    pay_basis: PayBasis = PayBasis.daily
    daily_rate: float | None = None
    hourly_rate: float | None = None
    pay_configs: list[PositionPayConfigResponse] = []
    description: str | None
    is_active: bool

    class Config:
        from_attributes = True


class PayrollConfigResponse(BaseModel):
    pay_period_type: str
    next_payday_date: date | None
    auto_reset_payroll_cycle: bool
    late_deduction_enabled: bool
    late_deduction_per_minute: float
    overtime_enabled: bool
    overtime_per_minute: float
    overtime_calculation_method: str
    enable_late_overtime_balancing: bool
    overtime_approval_required: bool
    # Stored for API compatibility. Active payroll OT premium does not read these.
    ordinary_ot_premium_percent: float
    rest_day_ot_premium_percent: float
    weekly_payday_weekday: str | None
    semi_monthly_payday_1: int | None
    semi_monthly_payday_2: int | None
    monthly_payday_day: int | None
    holiday_rules_mode: str


class PayrollConfigUpdate(BaseModel):
    pay_period_type: PayPeriodType = PayPeriodType.monthly
    next_payday_date: date | None = None
    auto_reset_payroll_cycle: bool = True
    late_deduction_enabled: bool = True
    late_deduction_per_minute: float = 1.0
    overtime_enabled: bool = True
    overtime_per_minute: float = 1.0
    # None = leave the stored method unchanged. Unknown values are rejected.
    overtime_calculation_method: OvertimeCalculationMethod | None = None
    # Optional so older clients do not reset an existing setting.
    enable_late_overtime_balancing: bool | None = None
    overtime_approval_required: bool | None = None
    # Stored for API compatibility. Active payroll OT premium does not read these.
    ordinary_ot_premium_percent: float | None = Field(default=None, ge=0)
    rest_day_ot_premium_percent: float | None = Field(default=None, ge=0)
    weekly_payday_weekday: Weekday | None = None
    semi_monthly_payday_1: int | None = Field(default=None, ge=1, le=31)
    semi_monthly_payday_2: int | None = Field(default=None, ge=1, le=31)
    monthly_payday_day: int | None = Field(default=None, ge=1, le=31)
    # Optional so older clients do not reset an existing custom mode.
    holiday_rules_mode: HolidayRulesMode | None = None

    @model_validator(mode="after")
    def _validate_schedule(self) -> "PayrollConfigUpdate":
        if self.pay_period_type == PayPeriodType.semi_monthly:
            # Clients that don't send a schedule (e.g. the mobile wizard)
            # fall back to the common 15th/30th scheme.
            if self.semi_monthly_payday_1 is None and self.semi_monthly_payday_2 is None:
                self.semi_monthly_payday_1 = 15
                self.semi_monthly_payday_2 = 30
            if self.semi_monthly_payday_1 is None or self.semi_monthly_payday_2 is None:
                raise ValueError(
                    "Semi-monthly pay periods require both payday days."
                )
            if self.semi_monthly_payday_2 <= self.semi_monthly_payday_1:
                raise ValueError(
                    "The second semi-monthly payday must come after the first."
                )
        return self


class AttendancePolicyResponse(BaseModel):
    early_clock_in_minutes: int
    on_time_grace_minutes: int
    half_day_threshold_minutes: int
    absent_threshold_minutes: int
    absent_threshold_percent: int
    half_day_threshold_percent: int
    early_out_deduction_enabled: bool
    early_out_deduction_per_minute: float
    overtime_enabled: bool
    overtime_minimum_minutes: int
    maximum_overtime_minutes: int
    overtime_rate_per_minute: float
    missing_clock_out_policy: str
    attendance_based_salary_enabled: bool
    breaktime_is_paid: bool


class AttendancePolicyUpdate(BaseModel):
    early_clock_in_minutes: int = Field(default=15, ge=0)
    on_time_grace_minutes: int = Field(default=10, ge=0)
    half_day_threshold_minutes: int = Field(default=120, ge=0)
    absent_threshold_minutes: int = Field(default=240, ge=0)
    absent_threshold_percent: int = Field(default=25, ge=0, le=100)
    half_day_threshold_percent: int = Field(default=50, ge=0, le=100)
    early_out_deduction_enabled: bool = False
    early_out_deduction_per_minute: float = 2.0
    overtime_enabled: bool = True
    overtime_minimum_minutes: int = Field(default=30, ge=0)
    maximum_overtime_minutes: int = Field(default=180, ge=0)
    overtime_rate_per_minute: float = 1.0
    missing_clock_out_policy: MissingClockOutPolicy = (
        MissingClockOutPolicy.auto_clock_out
    )
    attendance_based_salary_enabled: bool = True
    breaktime_is_paid: bool | None = None

    @model_validator(mode="after")
    def _percent_order(self):
        if self.absent_threshold_percent > self.half_day_threshold_percent:
            raise ValueError(
                "Absent threshold percent must be less than or equal to "
                "half-day threshold percent."
            )
        return self


class RestDayPolicyResponse(BaseModel):
    rest_day_premium_percent: float


class RestDayPolicyUpdate(BaseModel):
    rest_day_premium_percent: float = 30.0


class LeavePolicyItem(BaseModel):
    leave_type: str
    leave_type_label: str
    is_paid: bool
    payroll_treatment: str


class LeavePolicyResponse(BaseModel):
    business_id: UUID
    items: list[LeavePolicyItem]
    treatments: dict[str, bool]
    minimum_advance_notice_days: int = 0
    updated_at: datetime | None = None


class LeavePolicyUpdate(BaseModel):
    treatments: dict[str, bool]
    minimum_advance_notice_days: int | None = Field(default=None, ge=0, le=365)


class LeaveAllowanceItem(BaseModel):
    leave_type: str
    leave_type_label: str
    enabled: bool
    disabled: bool = False
    configured: bool
    allowance_days: int | None = None


class LeaveAllowanceResponse(BaseModel):
    year: int
    items: list[LeaveAllowanceItem]


class LeaveAllowanceWriteItem(BaseModel):
    leave_type: LeaveType
    enabled: bool
    allowance_days: int | None = Field(default=None, ge=0, le=366)


class LeaveAllowanceUpdate(BaseModel):
    year: int = Field(ge=2000, le=2100)
    items: list[LeaveAllowanceWriteItem]


class HolidayCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    holiday_date: date
    is_paid: bool = True
    pay_multiplier: float = Field(default=1.0, gt=0)
    ot_premium_percent: float | None = Field(default=None, ge=0)
    holiday_type: HolidayType = HolidayType.company


class HolidayUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    holiday_date: date | None = None
    is_paid: bool | None = None
    pay_multiplier: float | None = Field(default=None, gt=0)
    ot_premium_percent: float | None = Field(default=None, ge=0)
    holiday_type: HolidayType | None = None
    is_active: bool | None = None


class HolidayResponse(BaseModel):
    id: str
    business_id: str | None
    name: str
    holiday_date: date
    is_paid: bool
    pay_multiplier: float
    ot_premium_percent: float | None = None
    holiday_type: str
    is_active: bool

    class Config:
        from_attributes = True


class SetupStepStatus(BaseModel):
    key: str
    label: str
    complete: bool


class SetupStatusResponse(BaseModel):
    setup_completed_at: datetime | None = None
    completion_percent: int
    completed_steps: int
    total_steps: int
    steps: list[SetupStepStatus]
    missing_items: list[str]
