from datetime import date, datetime, time

from pydantic import BaseModel, Field, model_validator

from app.models.enums import (
    HolidayType,
    MissingClockOutPolicy,
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

    class Config:
        from_attributes = True


class PositionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    daily_rate: float = Field(gt=0)
    description: str | None = None


class PositionUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=100)
    daily_rate: float | None = Field(default=None, gt=0)
    description: str | None = None
    is_active: bool | None = None


class PositionResponse(BaseModel):
    id: str
    title: str
    daily_rate: float
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
    weekly_payday_weekday: str | None
    semi_monthly_payday_1: int | None
    semi_monthly_payday_2: int | None
    monthly_payday_day: int | None


class PayrollConfigUpdate(BaseModel):
    pay_period_type: PayPeriodType = PayPeriodType.monthly
    next_payday_date: date | None = None
    auto_reset_payroll_cycle: bool = True
    late_deduction_enabled: bool = True
    late_deduction_per_minute: float = 1.0
    overtime_enabled: bool = True
    overtime_per_minute: float = 1.0
    weekly_payday_weekday: Weekday | None = None
    semi_monthly_payday_1: int | None = Field(default=None, ge=1, le=31)
    semi_monthly_payday_2: int | None = Field(default=None, ge=1, le=31)
    monthly_payday_day: int | None = Field(default=None, ge=1, le=31)

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
    early_out_deduction_enabled: bool
    early_out_deduction_per_minute: float
    overtime_enabled: bool
    overtime_minimum_minutes: int
    overtime_rate_per_minute: float
    missing_clock_out_policy: str
    attendance_based_salary_enabled: bool


class AttendancePolicyUpdate(BaseModel):
    early_clock_in_minutes: int = Field(default=15, ge=0)
    on_time_grace_minutes: int = Field(default=10, ge=0)
    half_day_threshold_minutes: int = Field(default=120, ge=0)
    absent_threshold_minutes: int = Field(default=240, ge=0)
    early_out_deduction_enabled: bool = False
    early_out_deduction_per_minute: float = 2.0
    overtime_enabled: bool = True
    overtime_minimum_minutes: int = Field(default=30, ge=0)
    overtime_rate_per_minute: float = 1.0
    missing_clock_out_policy: MissingClockOutPolicy = (
        MissingClockOutPolicy.auto_clock_out
    )
    attendance_based_salary_enabled: bool = True


class RestDayPolicyResponse(BaseModel):
    rest_day_premium_percent: float


class RestDayPolicyUpdate(BaseModel):
    rest_day_premium_percent: float = 30.0


class HolidayCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    holiday_date: date
    is_paid: bool = True
    pay_multiplier: float = Field(default=1.0, gt=0)
    holiday_type: HolidayType = HolidayType.company


class HolidayUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    holiday_date: date | None = None
    is_paid: bool | None = None
    pay_multiplier: float | None = Field(default=None, gt=0)
    holiday_type: HolidayType | None = None
    is_active: bool | None = None


class HolidayResponse(BaseModel):
    id: str
    business_id: str | None
    name: str
    holiday_date: date
    is_paid: bool
    pay_multiplier: float
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
