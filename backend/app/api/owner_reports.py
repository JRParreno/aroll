import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import Date, and_, cast, or_
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.core.timezone import business_now, business_today, get_business_tz
from app.db.session import get_db
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import (
    AttendanceStatus,
    PayBasis,
    PayrollRunStatus,
    UserRole,
    Weekday,
)
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, PayrollRun, Position
from app.services.activity_logger import add_log
from app.services.payroll_snapshot import (
    PAYSLIP_SNAPSHOT_VERSION,
    build_calculation_config_json,
    create_finalized_payslip_snapshots,
    load_period_payroll,
    load_period_payslip,
    load_period_payslip_for_employee_id,
    require_loaded_slip,
    unfinalize_period_for_as_of,
)
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.holiday_pay import (
    resolve_holiday_policy,
    resolve_holiday_rules_mode,
)
from app.services.payroll_incomplete_gate import (
    count_incomplete_attendance_in_period,
    count_unresolved_scheduled_assignments_in_period,
)
from app.services.leave_requests import (
    approved_leave_dates_for_employee,
    employee_on_approved_leave,
    is_leave_type_paid,
    leave_is_paid_for_attendance_day,
    leave_type_for_attendance_day,
)
from app.services.missing_clock_out import (
    ensure_incomplete_for_employee,
    is_past_clock_out_deadline,
)
from app.services.employee_pay import (
    DEFAULT_SCHEDULED_MINUTES,
    resolve_employee_pay,
    resolve_employee_pay_context,
)
from app.services.pay_period import resolve_pay_period
from app.services.payroll_engine import (
    collect_unresolved_scheduled_assignments,
    early_departure_minutes,
    hours_worked_from_payable_minutes,
    hours_worked_from_slip,
    in_shift_payable_minutes,
    monetary_late_minutes,
    remaining_monetary_late_minutes,
    overtime_pay_amount,
    overtime_premium_percent,
    qualifying_overtime_minutes,
    scheduled_paid_minutes,
    scheduled_shift_end_at,
)

router = APIRouter(prefix="/owner/reports", tags=["owner-reports"])

_WEEKDAY_BY_INDEX = (
    Weekday.monday,
    Weekday.tuesday,
    Weekday.wednesday,
    Weekday.thursday,
    Weekday.friday,
    Weekday.saturday,
    Weekday.sunday,
)


def _shift_end_at(work_date: date, shift: Shift) -> datetime:
    return scheduled_shift_end_at(work_date, shift)


def _shift_start_at(work_date: date, shift: Shift) -> datetime:
    return datetime.combine(work_date, shift.start_time)


def _scheduled_shift_minutes(
    work_date: date,
    shift: Shift,
    *,
    breaktime_is_paid: bool = False,
) -> float:
    """Canonical scheduled paid minutes for a shift (breaktime setting applied)."""
    start = _shift_start_at(work_date, shift)
    end = _shift_end_at(work_date, shift)
    span = max((end - start).total_seconds() / 60.0, 0.0)
    return scheduled_paid_minutes(
        span_minutes=span,
        break_minutes=getattr(shift, "break_minutes", 0),
        breaktime_is_paid=breaktime_is_paid,
    )


def _weekday_for_date(work_date: date) -> Weekday:
    return _WEEKDAY_BY_INDEX[work_date.weekday()]


def _is_rest_day_work(assignment: ShiftAssignment | None) -> bool:
    return bool(assignment is not None and assignment.is_rest_day_work)


def _rest_day_premium_percent(policy: BusinessRestDayPolicy | None) -> float:
    if policy is None:
        return 0.0
    return float(policy.rest_day_premium_percent)


def _absent_day_payslip_row(
    *,
    work_date: date,
    holiday: Holiday | None,
    is_rest_day: bool,
) -> dict:
    """Payslip attendance detail for an absent day (punched or no-show)."""
    return {
        "date": work_date.isoformat(),
        "status": AttendanceStatus.absent.value,
        "time_in": None,
        "time_out": None,
        "holiday_name": holiday.name if holiday else None,
        "is_rest_day": is_rest_day,
        "rest_day_premium_pay": None,
        "day_rate_factor": 0.0,
        "scheduled_minutes": 0.0,
        "worked_minutes": 0.0,
        "hourly_rate": 0.0,
        "late_minutes": 0.0,
        "undertime_minutes": 0.0,
        "unpaid_minutes": 0.0,
        "late_deduction": 0.0,
        "undertime_deduction": 0.0,
        "shortfall_deduction": 0.0,
        "earned": 0.0,
        "payroll_status": "finalized",
    }


def _holiday_credit_payslip_row(
    *,
    work_date: date,
    holiday: Holiday | None,
    is_rest_day: bool,
    daily_rate: float,
) -> dict:
    """Payslip detail for unworked paid holiday credit (calculation only)."""
    return {
        "date": work_date.isoformat(),
        "status": "holiday_paid",
        "time_in": None,
        "time_out": None,
        "holiday_name": holiday.name if holiday else None,
        "is_rest_day": is_rest_day,
        "rest_day_premium_pay": None,
        "day_rate_factor": 1.0,
        "scheduled_minutes": 0.0,
        "worked_minutes": 0.0,
        "hourly_rate": 0.0,
        "late_minutes": 0.0,
        "undertime_minutes": 0.0,
        "unpaid_minutes": 0.0,
        "late_deduction": 0.0,
        "undertime_deduction": 0.0,
        "shortfall_deduction": 0.0,
        "earned": round(daily_rate, 2),
        "payroll_status": "finalized",
    }


def _leave_day_payslip_row(
    *,
    work_date: date,
    holiday: Holiday | None,
    paid: bool,
    daily_rate: float,
    scheduled_minutes: float = 0.0,
    hourly_rate: float = 0.0,
) -> dict:
    """Payslip detail for approved leave credited without on_leave attendance."""
    earned = daily_rate if paid else 0.0
    return {
        "date": work_date.isoformat(),
        "status": AttendanceStatus.on_leave.value,
        "time_in": None,
        "time_out": None,
        "holiday_name": holiday.name if holiday else None,
        "is_rest_day": False,
        "rest_day_premium_pay": None,
        "day_rate_factor": 1.0 if paid else 0.0,
        "scheduled_minutes": round(float(scheduled_minutes or 0.0), 2),
        "worked_minutes": 0.0,
        "hourly_rate": round(float(hourly_rate or 0.0), 4),
        "late_minutes": 0.0,
        "undertime_minutes": 0.0,
        "unpaid_minutes": 0.0,
        "late_deduction": 0.0,
        "undertime_deduction": 0.0,
        "shortfall_deduction": 0.0,
        "earned": round(earned, 2),
        "payroll_status": "finalized",
    }


def _to_business_naive(dt: datetime, tz_name: str | None) -> datetime:
    """Convert a punch timestamp to naive local time in the business timezone."""
    tz = get_business_tz(tz_name)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=tz)
    return dt.astimezone(tz).replace(tzinfo=None)


def _calculate_employee_payslip(
    db: Session,
    employee: Employee,
    period_start: date,
    period_end: date,
) -> dict:
    config = db.get(BusinessPayrollConfig, employee.business_id)
    att_policy = db.get(BusinessAttendancePolicy, employee.business_id)
    if att_policy is None:
        att_policy = BusinessAttendancePolicy(business_id=employee.business_id)
    business = db.get(Business, employee.business_id)
    tz_name = business.timezone if business is not None else "Asia/Manila"
    ensure_incomplete_for_employee(
        db, employee, business_timezone=tz_name
    )

    rest_policy = db.get(BusinessRestDayPolicy, employee.business_id)
    position = db.get(Position, employee.position_id) if employee.position_id else None
    # Employee pay first; Position.daily_rate / hourly_rate are templates/fallback.
    # All rate math goes through resolve_employee_pay_context (daily + hourly).
    resolved_pay = resolve_employee_pay(employee, position=position)

    def _pay_ctx(scheduled_minutes: float):
        return resolve_employee_pay_context(
            employee,
            scheduled_minutes,
            position=position,
            resolved=resolved_pay,
        )

    breaktime_is_paid = bool(getattr(att_policy, "breaktime_is_paid", False))

    def _paid_shift_minutes(work_date: date, shift: Shift) -> float:
        return _scheduled_shift_minutes(
            work_date, shift, breaktime_is_paid=breaktime_is_paid
        )

    late_rate = float(config.late_deduction_per_minute) if config else 0.0
    late_money_enabled = config is None or bool(
        getattr(config, "late_deduction_enabled", True)
    )
    ot_rate = float(config.overtime_per_minute) if config else 0.0
    is_hourly = resolved_pay.pay_basis == PayBasis.hourly
    overtime_pay = 0.0
    payable_minutes_total = 0.0
    paid_work_dates: set[date] = set()
    daily_work_buckets: dict[date, dict] = {}
    overtime_enabled = True
    if config is not None and not config.overtime_enabled:
        overtime_enabled = False
    if att_policy is not None and not att_policy.overtime_enabled:
        overtime_enabled = False
    late_ot_balancing = bool(
        config is not None
        and getattr(config, "enable_late_overtime_balancing", False)
    )
    grace_minutes = att_policy.on_time_grace_minutes
    ot_minimum = att_policy.overtime_minimum_minutes
    half_day_threshold = att_policy.half_day_threshold_minutes
    premium_percent = _rest_day_premium_percent(rest_policy)
    rest_day_work_allowed = True
    holiday_rules_mode = resolve_holiday_rules_mode(config)

    rows = (
        db.query(AttendanceRecord, ShiftAssignment, Shift)
        .outerjoin(ShiftAssignment, AttendanceRecord.shift_assignment_id == ShiftAssignment.id)
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            or_(
                and_(
                    ShiftAssignment.id.is_not(None),
                    ShiftAssignment.work_date >= period_start,
                    ShiftAssignment.work_date <= period_end,
                ),
                and_(
                    AttendanceRecord.shift_assignment_id.is_(None),
                    AttendanceRecord.created_at >= period_start,
                    AttendanceRecord.created_at < period_end + timedelta(days=1),
                ),
            ),
        )
        .all()
    )
    holidays = {
        holiday.holiday_date: holiday
        for holiday in db.query(Holiday)
        .filter(Holiday.business_id == employee.business_id, Holiday.is_active.is_(True))
        .all()
    }

    scheduled_assignments = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            ShiftAssignment.employee_id == employee.id,
            ShiftAssignment.work_date >= period_start,
            ShiftAssignment.work_date <= period_end,
        )
        .all()
    )
    scheduled_minutes_by_date: dict[date, float] = {}
    for scheduled_assignment, scheduled_shift in scheduled_assignments:
        scheduled_minutes_by_date[scheduled_assignment.work_date] = (
            scheduled_minutes_by_date.get(scheduled_assignment.work_date, 0.0)
            + (
                _paid_shift_minutes(
                    scheduled_assignment.work_date, scheduled_shift
                )
                or 0.0
            )
        )

    today = business_today(tz_name)
    now_local = business_now(tz_name).replace(tzinfo=None)
    records_by_assignment_id: dict = {}
    for record, assignment, _shift in rows:
        if assignment is None:
            continue
        records_by_assignment_id.setdefault(assignment.id, []).append(record)

    pending_work_dates, unresolved_assignment_ids = (
        collect_unresolved_scheduled_assignments(
            scheduled_assignments,
            records_by_assignment_id,
            now_local=now_local,
            today=today,
            grace_minutes=grace_minutes,
        )
    )

    regular_pay = 0.0
    leave_pay = 0.0
    worked_days = 0.0
    overtime_minutes = 0.0
    late_minutes = 0.0
    early_out_minutes = 0.0
    unpaid_minutes = 0.0
    absent_days = 0
    paid_leave_days = 0
    unpaid_leave_days = 0
    half_day_days = 0
    pending_attendance_count = len(unresolved_assignment_ids)
    holiday_pay = 0.0
    rest_day_pay = 0.0
    rest_day_days = 0
    attendance_records = []
    rest_day_records = []
    late_deductions_amount = 0.0
    undertime_deductions_amount = 0.0
    # Dates that already received the one Daily Rate (or holiday unworked credit).
    daily_base_credited: set[date] = set()
    daily_holiday_credited: set[date] = set()
    # Dates already credited via AttendanceRecord(status=on_leave).
    leave_dates_from_attendance: set[date] = set()
    paid_leave_dates: set[date] = set()
    dates_with_worked_regular_pay: set[date] = set()

    def _leave_pay_value(scheduled_minutes: float) -> float:
        """Option 2 leave pesos. Never invent an 8-hour day for leave."""
        minutes = float(scheduled_minutes or 0.0)
        if is_hourly:
            if minutes <= 0:
                return 0.0
            return _pay_ctx(minutes).scheduled_day_value
        ctx_minutes = minutes if minutes > 0 else DEFAULT_SCHEDULED_MINUTES
        return _pay_ctx(ctx_minutes).scheduled_day_value

    for record, assignment, shift in rows:
        work_date = assignment.work_date if assignment else record.created_at.date()
        holiday = holidays.get(work_date)
        is_rest = _is_rest_day_work(assignment)
        date_is_pending = work_date in pending_work_dates
        if (
            assignment is None
            and record.time_in is not None
            and record.time_out is None
            and record.status != AttendanceStatus.incomplete
        ):
            pending_attendance_count += 1
            date_is_pending = True

        worked_minutes = 0.0
        if record.time_in is not None and record.time_out is not None:
            worked_minutes = max(
                (record.time_out - record.time_in).total_seconds() / 60.0,
                0.0,
            )

        day_rate_factor = 0.0
        day_late_minutes = 0.0
        day_undertime_minutes = 0.0
        day_unpaid_minutes = 0.0
        day_shortfall = 0.0
        day_late_deduction = 0.0
        day_undertime_deduction = 0.0
        day_regular = 0.0
        day_earned = 0.0
        scheduled_minutes = 0.0
        hourly_rate = 0.0

        if date_is_pending:
            if record.status == AttendanceStatus.on_leave:
                leave_dates_from_attendance.add(work_date)
        elif record.status == AttendanceStatus.on_leave:
            leave_dates_from_attendance.add(work_date)
            # Use stored leave_request.is_paid snapshot — never live company policy.
            paid_flag = leave_is_paid_for_attendance_day(
                db, employee_id=employee.id, work_date=work_date
            )
            if paid_flag is None:
                leave_type = leave_type_for_attendance_day(
                    db, employee_id=employee.id, work_date=work_date
                )
                paid = is_leave_type_paid(leave_type) if leave_type else True
            else:
                paid = paid_flag
            if paid:
                # Option 2: leave pay requires a scheduled assignment on this date.
                if shift is None:
                    day_regular = 0.0
                    day_earned = 0.0
                else:
                    scheduled_minutes = _paid_shift_minutes(work_date, shift)
                    day_value = _leave_pay_value(scheduled_minutes)
                    day_rate_factor = 1.0
                    day_regular = day_value
                    day_earned = day_value
                    if scheduled_minutes > 0:
                        leave_ctx = _pay_ctx(scheduled_minutes)
                        hourly_rate = leave_ctx.hourly_rate
                    elif resolved_pay.hourly_rate is not None:
                        hourly_rate = float(resolved_pay.hourly_rate)
                    already_got_daily_base = (
                        not is_hourly and work_date in daily_base_credited
                    )
                    if not already_got_daily_base:
                        leave_pay += day_value
                        if not is_hourly:
                            daily_base_credited.add(work_date)
                        if work_date not in paid_leave_dates:
                            paid_leave_days += 1
                            paid_leave_dates.add(work_date)
                        paid_work_dates.add(work_date)
            else:
                unpaid_leave_days += 1
        elif record.status == AttendanceStatus.absent:
            absent_policy = resolve_holiday_policy(
                holiday=holiday, mode=holiday_rules_mode
            )
            if absent_policy is not None and absent_policy.pay_if_not_worked:
                if shift is not None:
                    scheduled_minutes = _paid_shift_minutes(work_date, shift)
                absent_ctx = _pay_ctx(scheduled_minutes or DEFAULT_SCHEDULED_MINUTES)
                scheduled_minutes = absent_ctx.scheduled_minutes
                hourly_rate = absent_ctx.hourly_rate
                if is_hourly or work_date not in daily_holiday_credited:
                    holiday_pay += absent_ctx.scheduled_day_value
                    if not is_hourly:
                        daily_holiday_credited.add(work_date)
                day_earned = absent_ctx.scheduled_day_value
                day_rate_factor = 1.0
            else:
                absent_days += 1
        elif record.status == AttendanceStatus.incomplete:
            # Window exceeded without a finalized Time Out. ₱0 payable.
            # Status is the source of truth — do not credit scheduled hours.
            pass
        elif record.time_in is not None and record.time_out is None:
            # Still inside the incomplete window: wait for Time Out.
            # Counted in pending_work_dates / unresolved_assignment_ids above.
            pass
        elif (
            record.time_in is not None
            and record.time_out is not None
            and shift is not None
            and assignment is not None
        ):
            # Rate source: PayrollPayContext (daily or hourly).
            # Payable regular minutes = in-shift overlap only. Early arrival
            # never offsets early departure. Daily employees credit one
            # daily_rate per calendar work_date after the loop.
            scheduled_start = _shift_start_at(work_date, shift)
            shift_end = _shift_end_at(work_date, shift)
            time_in_local = _to_business_naive(record.time_in, tz_name)
            time_out_local = _to_business_naive(record.time_out, tz_name)
            assignment_scheduled = _paid_shift_minutes(work_date, shift)
            if assignment_scheduled <= 0:
                assignment_scheduled = DEFAULT_SCHEDULED_MINUTES
            if is_hourly:
                ctx_minutes = assignment_scheduled
            else:
                ctx_minutes = (
                    scheduled_minutes_by_date.get(work_date) or assignment_scheduled
                )
            pay_ctx = _pay_ctx(ctx_minutes)
            scheduled_minutes = assignment_scheduled
            hourly_rate = pay_ctx.hourly_rate
            minute_rate = pay_ctx.minute_rate

            payable = in_shift_payable_minutes(
                time_in=time_in_local,
                time_out=time_out_local,
                scheduled_start=scheduled_start,
                scheduled_end=shift_end,
                scheduled_working=assignment_scheduled,
            )
            payable_minutes_total += payable

            ot_mins, recovered_late = qualifying_overtime_minutes(
                time_in=time_in_local,
                time_out=time_out_local,
                scheduled_start=scheduled_start,
                scheduled_end=shift_end,
                ot_minimum=ot_minimum,
                late_ot_balancing=late_ot_balancing,
            )
            overtime_minutes += ot_mins
            if overtime_enabled:
                overtime_pay += overtime_pay_amount(
                    ot_mins,
                    ot_rate,
                    overtime_premium_percent(config, holiday, is_rest),
                )

            day_late_minutes = remaining_monetary_late_minutes(
                monetary_late=monetary_late_minutes(
                    time_in=time_in_local,
                    scheduled_start=scheduled_start,
                    grace_minutes=grace_minutes,
                ),
                recovered_late_minutes=recovered_late,
                late_ot_balancing=late_ot_balancing,
            )
            day_undertime_minutes = early_departure_minutes(
                time_out=time_out_local,
                scheduled_end=shift_end,
            )
            day_late_deduction = (
                day_late_minutes * late_rate if late_money_enabled else 0.0
            )
            day_undertime_deduction = day_undertime_minutes * minute_rate
            late_minutes += day_late_minutes
            late_deductions_amount += day_late_deduction
            if day_undertime_minutes > 0:
                early_out_minutes += day_undertime_minutes
            undertime_deductions_amount += day_undertime_deduction
            day_unpaid_minutes = day_undertime_minutes
            day_shortfall = day_undertime_deduction

            if is_hourly:
                day_regular = pay_ctx.scheduled_day_value
                day_earned = max(day_regular - day_undertime_deduction, 0.0)
                day_rate_factor = 1.0
                paid_work_dates.add(work_date)
                dates_with_worked_regular_pay.add(work_date)
                if 0 < payable < half_day_threshold:
                    half_day_days += 1
                regular_pay += day_regular
                unpaid_minutes += day_undertime_minutes
            else:
                bucket = daily_work_buckets.setdefault(
                    work_date,
                    {
                        "payable": 0.0,
                        "undertime_deduction": 0.0,
                        "scheduled": ctx_minutes,
                        "holiday": holiday,
                        "is_rest": is_rest,
                        "minute_rate": minute_rate,
                    },
                )
                bucket["payable"] += payable
                bucket["undertime_deduction"] += day_undertime_deduction
                bucket["is_rest"] = bool(bucket["is_rest"] or is_rest)
                day_regular = 0.0
                day_earned = payable * minute_rate
                day_rate_factor = 1.0
                if 0 < payable < half_day_threshold:
                    half_day_days += 1
                unpaid_minutes += day_undertime_minutes
        elif record.time_in is not None and record.time_out is not None:
            # Closed punch without a linked shift: keep prior fallback rules.
            day_rate_factor = 1.0
            if 0 < worked_minutes < half_day_threshold:
                day_rate_factor = 0.5
                half_day_days += 1
            if shift is not None and assignment is not None:
                scheduled_minutes = _paid_shift_minutes(work_date, shift)
            fallback_ctx = _pay_ctx(scheduled_minutes or DEFAULT_SCHEDULED_MINUTES)
            scheduled_minutes = fallback_ctx.scheduled_minutes
            hourly_rate = fallback_ctx.hourly_rate
            day_regular = fallback_ctx.scheduled_day_value * day_rate_factor
            if day_rate_factor > 0:
                if is_hourly or work_date not in daily_base_credited:
                    paid_work_dates.add(work_date)
                    dates_with_worked_regular_pay.add(work_date)
                    regular_pay += day_regular
                    if not is_hourly:
                        daily_base_credited.add(work_date)
            day_earned = day_regular

            if shift is not None and assignment is not None:
                scheduled_start = _shift_start_at(work_date, shift)
                time_in_local = _to_business_naive(record.time_in, tz_name)
                day_late_minutes = monetary_late_minutes(
                    time_in=time_in_local,
                    scheduled_start=scheduled_start,
                    grace_minutes=grace_minutes,
                )
                late_minutes += day_late_minutes
                if late_money_enabled:
                    day_late_deduction = day_late_minutes * late_rate
                    late_deductions_amount += day_late_deduction

        open_unfinalized = (
            date_is_pending
            or (record.time_in is not None and record.time_out is None)
        )
        completed_shifted = (
            record.time_in is not None
            and record.time_out is not None
            and shift is not None
            and assignment is not None
            and record.status
            not in (
                AttendanceStatus.absent,
                AttendanceStatus.incomplete,
                AttendanceStatus.on_leave,
            )
        )
        apply_row_holiday_rest = is_hourly or not completed_shifted

        worked_holiday_policy = resolve_holiday_policy(
            holiday=holiday, mode=holiday_rules_mode
        )
        if (
            apply_row_holiday_rest
            and worked_holiday_policy is not None
            and not open_unfinalized
            and record.status
            not in (
                AttendanceStatus.absent,
                AttendanceStatus.incomplete,
                AttendanceStatus.on_leave,
            )
        ):
            holiday_pay += max(
                day_earned * (worked_holiday_policy.worked_multiplier - 1),
                0,
            )

        day_rest_premium = 0.0
        worked = (
            record.status
            not in (
                AttendanceStatus.absent,
                AttendanceStatus.incomplete,
                AttendanceStatus.on_leave,
            )
            and record.time_in is not None
            and record.time_out is not None
        )
        if apply_row_holiday_rest and is_rest and worked and day_earned > 0:
            day_rest_premium = day_earned * (premium_percent / 100.0)
            rest_day_pay += day_rest_premium
            rest_day_days += 1
            rest_day_records.append(
                {
                    "date": work_date.isoformat(),
                    "weekday": _weekday_for_date(work_date).value,
                    "status": record.status.value,
                    "time_in": record.time_in.isoformat() if record.time_in else None,
                    "time_out": (
                        record.time_out.isoformat() if record.time_out else None
                    ),
                    "shift_name": shift.name if shift else None,
                    "premium_percent": premium_percent,
                    "premium_pay": round(day_rest_premium, 2),
                    "authorized": rest_day_work_allowed,
                }
            )

        row_status = record.status.value
        if (
            record.status == AttendanceStatus.absent
            and day_earned > 0
            and holiday is not None
        ):
            row_status = "holiday_paid"

        attendance_records.append(
            {
                "date": work_date.isoformat(),
                "status": row_status,
                "time_in": record.time_in.isoformat() if record.time_in else None,
                "time_out": record.time_out.isoformat() if record.time_out else None,
                "shift_name": shift.name if shift else None,
                "shift_assignment_id": (
                    str(assignment.id) if assignment is not None else None
                ),
                "holiday_name": holiday.name if holiday else None,
                "is_rest_day": is_rest,
                "rest_day_premium_pay": (
                    round(day_rest_premium, 2) if day_rest_premium else None
                ),
                "day_rate_factor": day_rate_factor,
                "scheduled_minutes": round(scheduled_minutes, 2),
                "worked_minutes": round(worked_minutes, 2),
                "hourly_rate": round(hourly_rate, 4),
                "late_minutes": round(day_late_minutes, 2),
                "undertime_minutes": round(day_undertime_minutes, 2),
                "unpaid_minutes": round(day_unpaid_minutes, 2),
                "late_deduction": round(day_late_deduction, 2),
                "undertime_deduction": round(day_undertime_deduction, 2),
                "shortfall_deduction": round(day_shortfall, 2),
                "earned": round(day_earned, 2),
                "payroll_status": (
                    "pending_attendance_correction"
                    if record.status == AttendanceStatus.incomplete
                    else "pending"
                    if date_is_pending
                    or (record.time_in is not None and record.time_out is None)
                    else "finalized"
                ),
            }
        )

    # Daily employees: one daily_rate per calendar work_date.
    for work_date, bucket in daily_work_buckets.items():
        sched = bucket["scheduled"] if bucket["scheduled"] > 0 else DEFAULT_SCHEDULED_MINUTES
        ctx = _pay_ctx(sched)
        undertime_for_date = float(bucket.get("undertime_deduction") or 0.0)
        day_earned = max(ctx.scheduled_day_value - undertime_for_date, 0.0)
        if work_date not in daily_base_credited:
            regular_pay += ctx.scheduled_day_value
            daily_base_credited.add(work_date)
        paid_work_dates.add(work_date)
        dates_with_worked_regular_pay.add(work_date)

        holiday = bucket.get("holiday")
        worked_holiday_policy = resolve_holiday_policy(
            holiday=holiday, mode=holiday_rules_mode
        )
        if worked_holiday_policy is not None:
            holiday_pay += max(
                day_earned * (worked_holiday_policy.worked_multiplier - 1),
                0,
            )
        if bucket.get("is_rest") and day_earned > 0:
            day_rest_premium = day_earned * (premium_percent / 100.0)
            rest_day_pay += day_rest_premium
            rest_day_days += 1
            rest_day_records.append(
                {
                    "date": work_date.isoformat(),
                    "weekday": _weekday_for_date(work_date).value,
                    "status": "complete",
                    "time_in": None,
                    "time_out": None,
                    "shift_name": None,
                    "premium_percent": premium_percent,
                    "premium_pay": round(day_rest_premium, 2),
                    "authorized": rest_day_work_allowed,
                }
            )

    # Scheduled assignments already loaded above (leave recon + no-show).
    seen_assignment_ids = {
        record.shift_assignment_id
        for record, _assignment, _shift in rows
        if record.shift_assignment_id is not None
    }

    # Leave reconciliation (payroll calculation only — no DB writes).
    # Credits approved LeaveRequest days that have no AttendanceRecord(on_leave).
    # Must run before no-show so leave is never underpaid as a silent skip.
    # Option 2: credit only when the date has a scheduled assignment.
    for leave_date in approved_leave_dates_for_employee(
        db,
        employee_id=employee.id,
        period_start=period_start,
        period_end=period_end,
    ):
        if leave_date in leave_dates_from_attendance:
            continue
        if leave_date in pending_work_dates:
            continue
        if leave_date in dates_with_worked_regular_pay:
            continue
        assignments_for_date = [
            (assignment, shift)
            for assignment, shift in scheduled_assignments
            if assignment.work_date == leave_date
        ]
        if not assignments_for_date:
            continue
        paid_flag = leave_is_paid_for_attendance_day(
            db, employee_id=employee.id, work_date=leave_date
        )
        if paid_flag is None:
            leave_type = leave_type_for_attendance_day(
                db, employee_id=employee.id, work_date=leave_date
            )
            paid = is_leave_type_paid(leave_type) if leave_type else True
        else:
            paid = paid_flag
        leave_scheduled = scheduled_minutes_by_date.get(leave_date, 0.0)
        if leave_scheduled <= 0:
            _leave_shift = assignments_for_date[0][1]
            leave_scheduled = _paid_shift_minutes(leave_date, _leave_shift)
        leave_day_value = _leave_pay_value(leave_scheduled)
        leave_hourly = 0.0
        if leave_scheduled > 0:
            leave_hourly = _pay_ctx(leave_scheduled).hourly_rate
        elif resolved_pay.hourly_rate is not None:
            leave_hourly = float(resolved_pay.hourly_rate)
        if paid:
            already_got_daily_base = (
                not is_hourly and leave_date in daily_base_credited
            )
            if not already_got_daily_base:
                leave_pay += leave_day_value
                if not is_hourly:
                    daily_base_credited.add(leave_date)
                if leave_date not in paid_leave_dates:
                    paid_leave_days += 1
                    paid_leave_dates.add(leave_date)
                paid_work_dates.add(leave_date)
        else:
            unpaid_leave_days += 1
        leave_dates_from_attendance.add(leave_date)
        attendance_records.append(
            _leave_day_payslip_row(
                work_date=leave_date,
                holiday=holidays.get(leave_date),
                paid=paid,
                daily_rate=leave_day_value,
                scheduled_minutes=leave_scheduled,
                hourly_rate=leave_hourly,
            )
        )

    # No-show reconciliation (payroll calculation only — no DB writes).
    # Scheduled assignments with no AttendanceRecord are treated like
    # AttendanceStatus.absent: increment absent_days, ₱0 earned, list in output.
    daily_absent_dates: set[date] = set()

    for assignment, shift in scheduled_assignments:
        if assignment.id in seen_assignment_ids:
            continue
        if assignment.work_date in pending_work_dates:
            continue
        # True days off have no assignment; is_rest_day_work means scheduled to work.
        if employee_on_approved_leave(
            db, employee_id=employee.id, work_date=assignment.work_date
        ):
            continue
        if assignment.work_date > today:
            continue
        if not is_past_clock_out_deadline(
            now_local=now_local,
            work_date=assignment.work_date,
            shift=shift,
            grace_minutes=grace_minutes,
        ):
            continue

        holiday = holidays.get(assignment.work_date)
        unworked_policy = resolve_holiday_policy(
            holiday=holiday, mode=holiday_rules_mode
        )
        if unworked_policy is not None and unworked_policy.pay_if_not_worked:
            noshow_sched = _paid_shift_minutes(assignment.work_date, shift)
            noshow_day_value = _pay_ctx(noshow_sched).scheduled_day_value
            if is_hourly or assignment.work_date not in daily_holiday_credited:
                holiday_pay += noshow_day_value
                if not is_hourly:
                    daily_holiday_credited.add(assignment.work_date)
            attendance_records.append(
                _holiday_credit_payslip_row(
                    work_date=assignment.work_date,
                    holiday=holiday,
                    is_rest_day=_is_rest_day_work(assignment),
                    daily_rate=noshow_day_value,
                )
            )
            continue

        if not is_hourly and (
            assignment.work_date in daily_work_buckets
            or assignment.work_date in paid_work_dates
            or assignment.work_date in daily_absent_dates
        ):
            continue

        absent_days += 1
        if not is_hourly:
            daily_absent_dates.add(assignment.work_date)
        attendance_records.append(
            _absent_day_payslip_row(
                work_date=assignment.work_date,
                holiday=holiday,
                is_rest_day=_is_rest_day_work(assignment),
            )
        )

    overtime_pay = round(overtime_pay, 2) if overtime_enabled else 0.0

    # Late and undertime are independent deductions (not a split shortfall).
    deductions = late_deductions_amount + undertime_deductions_amount
    remaining_unpaid_deductions = 0.0
    gross_pay = regular_pay + leave_pay + overtime_pay + holiday_pay + rest_day_pay
    net_pay = max(gross_pay - deductions, 0)
    worked_days = float(len(paid_work_dates))
    hours_worked = hours_worked_from_payable_minutes(payable_minutes_total)

    # Display rates: daily_rate may still include Position fallback for legacy
    # clients. UI salary-rate labels must use pay_basis + hourly_rate /
    # monthly_salary (not daily_rate when basis is hourly/monthly).
    display_ctx = _pay_ctx(DEFAULT_SCHEDULED_MINUTES)

    return {
        "employee_id": str(employee.id),
        "employee_name": employee.full_name,
        "position_title": employee.position_title,
        "employment_type": employee.employment_type.value,
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
        "daily_rate": display_ctx.daily_rate,
        "pay_basis": resolved_pay.pay_basis.value,
        "hourly_rate": resolved_pay.hourly_rate,
        "monthly_salary": resolved_pay.monthly_salary,
        # Aliases kept for older clients.
        "hourly_rate_configured": resolved_pay.hourly_rate,
        "monthly_salary_configured": resolved_pay.monthly_salary,
        "worked_days": round(worked_days, 2),
        "hours_worked": hours_worked,
        "half_day_days": half_day_days,
        "overtime_minutes": round(overtime_minutes, 2),
        "overtime_hours": round(overtime_minutes / 60, 2),
        "overtime_pay": round(overtime_pay, 2),
        "late_minutes": round(late_minutes, 2),
        "early_out_minutes": round(early_out_minutes, 2),
        "undertime_minutes": round(early_out_minutes, 2),
        "unpaid_minutes": round(unpaid_minutes, 2),
        "holiday_pay": round(holiday_pay, 2),
        "rest_day_days": rest_day_days,
        "rest_day_premium_percent": premium_percent,
        "rest_day_pay": round(rest_day_pay, 2),
        "rest_day_work_allowed": rest_day_work_allowed,
        "rest_day_records": rest_day_records,
        "deductions": round(deductions, 2),
        "late_deductions": round(late_deductions_amount, 2),
        "undertime_deductions": round(undertime_deductions_amount, 2),
        "remaining_unpaid_deductions": round(remaining_unpaid_deductions, 2),
        "absent_days": absent_days,
        "paid_leave_days": paid_leave_days,
        "unpaid_leave_days": unpaid_leave_days,
        "pending_attendance_count": pending_attendance_count,
        "pending_work_dates": [
            work_date.isoformat() for work_date in sorted(pending_work_dates)
        ],
        # Base earnings for UI "Basic Salary" — do not recompute in clients.
        "regular_pay": round(regular_pay, 2),
        # Approved paid leave with a scheduled shift. Not included in regular_pay.
        "leave_pay": round(leave_pay, 2),
        "gross_pay": round(gross_pay, 2),
        "net_pay": round(net_pay, 2),
        "attendance_records": attendance_records,
        "grace_minutes_applied": grace_minutes,
        "overtime_minimum_minutes": ot_minimum,
    }


@router.get("/attendance")
def attendance_report(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    date: Annotated[date | None, Query(description="Filter by work date (YYYY-MM-DD)")] = None,
    q: Annotated[str | None, Query(description="Search name, position, or shift")] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    business = db.get(Business, user.business_id)
    from app.services.missing_clock_out import ensure_incomplete_for_business

    ensure_incomplete_for_business(
        db,
        business_id=user.business_id,
        business_timezone=business.timezone if business else None,
    )

    rest_policy = db.get(BusinessRestDayPolicy, user.business_id)
    premium_percent = _rest_day_premium_percent(rest_policy)
    rest_day_work_allowed = True

    query = (
        db.query(AttendanceRecord, Employee, ShiftAssignment, Shift, Position)
        .join(Employee, AttendanceRecord.employee_id == Employee.id)
        .outerjoin(Position, Employee.position_id == Position.id)
        .outerjoin(ShiftAssignment, AttendanceRecord.shift_assignment_id == ShiftAssignment.id)
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(AttendanceRecord.business_id == user.business_id)
    )

    if date is not None:
        query = query.filter(
            or_(
                ShiftAssignment.work_date == date,
                and_(
                    AttendanceRecord.shift_assignment_id.is_(None),
                    cast(AttendanceRecord.created_at, Date) == date,
                ),
            )
        )

    needle = (q or "").strip()
    if needle:
        like = f"%{needle}%"
        query = query.filter(
            or_(
                Employee.full_name.ilike(like),
                Employee.position_title.ilike(like),
                Shift.name.ilike(like),
            )
        )

    rows = (
        query.order_by(AttendanceRecord.created_at.desc())
        .limit(500)
        .all()
    )
    records = []
    rest_day_work = []
    present = late = absent = incomplete = on_leave = rest_day = holiday_paid = 0
    for record, employee, assignment, shift, position in rows:
        work_date = (
            assignment.work_date
            if assignment
            else record.created_at.date()
        )
        is_rest = _is_rest_day_work(assignment)
        if record.status == AttendanceStatus.absent:
            absent += 1
        elif record.status == AttendanceStatus.incomplete:
            incomplete += 1
        elif record.status == AttendanceStatus.on_leave:
            on_leave += 1
        elif record.status == AttendanceStatus.late:
            late += 1
        elif record.status in (
            AttendanceStatus.complete,
            AttendanceStatus.in_progress,
        ):
            present += 1

        item = {
            "id": str(record.id),
            "employee_id": str(employee.id),
            "employee_name": employee.full_name,
            "position_title": employee.position_title
            or (position.title if position else None),
            "employment_type": employee.employment_type.value
            if employee.employment_type
            else None,
            "daily_rate": resolve_employee_pay(
                employee, position=position
            ).daily_rate,
            "profile_image_url": employee.profile_image_url,
            "date": work_date.isoformat(),
            "weekday": _weekday_for_date(work_date).value,
            "time_in": record.time_in.isoformat() if record.time_in else None,
            "time_out": record.time_out.isoformat() if record.time_out else None,
            "status": record.status.value,
            "shift_name": shift.name if shift else None,
            "is_rest_day": is_rest,
            "rest_day_authorized": rest_day_work_allowed if is_rest else None,
            "is_synthetic": False,
        }
        records.append(item)

        if is_rest and record.time_in is not None:
            rest_day += 1
            rest_day_work.append(item)

    # Schedule no-shows (response only — no AttendanceRecord DB writes).
    # Keeps owner web/mobile attendance lists aligned with performance/payroll.
    tz_name = business.timezone if business is not None else "Asia/Manila"
    today = business_today(tz_name)
    now_local = business_now(tz_name).replace(tzinfo=None)
    att_policy = db.get(BusinessAttendancePolicy, user.business_id)
    if att_policy is None:
        att_policy = BusinessAttendancePolicy(business_id=user.business_id)
    grace_minutes = att_policy.on_time_grace_minutes
    payroll_config = db.get(BusinessPayrollConfig, user.business_id)
    holiday_mode = resolve_holiday_rules_mode(payroll_config)
    holidays = {
        holiday.holiday_date: holiday
        for holiday in db.query(Holiday)
        .filter(
            Holiday.business_id == user.business_id,
            Holiday.is_active.is_(True),
        )
        .all()
    }

    seen_assignment_ids = {
        record.shift_assignment_id
        for record, _employee, _assignment, _shift, _position in rows
        if record.shift_assignment_id is not None
    }
    if date is not None:
        range_start = date
        range_end = date
    else:
        range_start = today - timedelta(days=30)
        range_end = today

    scheduled_q = (
        db.query(ShiftAssignment, Shift, Employee, Position)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .outerjoin(Position, Employee.position_id == Position.id)
        .filter(
            Employee.business_id == user.business_id,
            Employee.is_active.is_(True),
            ShiftAssignment.work_date >= range_start,
            ShiftAssignment.work_date <= range_end,
        )
    )
    if needle:
        like = f"%{needle}%"
        scheduled_q = scheduled_q.filter(
            or_(
                Employee.full_name.ilike(like),
                Employee.position_title.ilike(like),
                Shift.name.ilike(like),
            )
        )

    for assignment, shift, employee, position in scheduled_q.all():
        if assignment.id in seen_assignment_ids:
            continue
        if employee_on_approved_leave(
            db, employee_id=employee.id, work_date=assignment.work_date
        ):
            continue
        if assignment.work_date > today:
            continue
        if not is_past_clock_out_deadline(
            now_local=now_local,
            work_date=assignment.work_date,
            shift=shift,
            grace_minutes=grace_minutes,
        ):
            continue

        holiday = holidays.get(assignment.work_date)
        policy = resolve_holiday_policy(holiday=holiday, mode=holiday_mode)
        is_rest = _is_rest_day_work(assignment)
        if policy is not None and policy.pay_if_not_worked:
            status = "holiday_paid"
            holiday_paid += 1
        else:
            status = AttendanceStatus.absent.value
            absent += 1

        records.append(
            {
                "id": f"noshow-{assignment.id}",
                "employee_id": str(employee.id),
                "employee_name": employee.full_name,
                "position_title": employee.position_title
                or (position.title if position else None),
                "employment_type": employee.employment_type.value
                if employee.employment_type
                else None,
                "daily_rate": resolve_employee_pay(
                    employee, position=position
                ).daily_rate,
                "profile_image_url": employee.profile_image_url,
                "date": assignment.work_date.isoformat(),
                "weekday": _weekday_for_date(assignment.work_date).value,
                "time_in": None,
                "time_out": None,
                "status": status,
                "shift_name": shift.name if shift else None,
                "is_rest_day": is_rest,
                "rest_day_authorized": rest_day_work_allowed if is_rest else None,
                "is_synthetic": True,
            }
        )

    tz_name = business.timezone if business is not None else "Asia/Manila"

    records.sort(key=lambda item: (item["date"], item["employee_name"]), reverse=True)

    return {
        "summary": {
            "present": present,
            "late": late,
            "absent": absent,
            "incomplete": incomplete,
            "on_leave": on_leave,
            "rest_day": rest_day,
            "holiday_paid": holiday_paid,
        },
        "timezone": tz_name,
        "rest_day_premium_percent": premium_percent,
        "rest_day_work_allowed": rest_day_work_allowed,
        "rest_day_work": rest_day_work,
        "records": records,
    }


def _payroll_status(period_start: date, period_end: date, today: date) -> str:
    if period_start <= today <= period_end:
        return "current"
    if period_end < today:
        return "completed"
    return "upcoming"


@router.get("/payroll")
def payroll_report(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    config = db.get(BusinessPayrollConfig, user.business_id)
    business = db.get(Business, user.business_id)
    today = as_of or date.today()
    loaded = load_period_payroll(
        db,
        business_id=user.business_id,
        as_of=today,
        calculate_payslip=_calculate_employee_payslip,
    )
    period_start, period_end = loaded.period_start, loaded.period_end
    incomplete_count = count_incomplete_attendance_in_period(
        db,
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        business_timezone=business.timezone if business else None,
    )
    pending_attendance_count = count_unresolved_scheduled_assignments_in_period(
        db,
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        business_timezone=business.timezone if business else None,
    )
    finalized_run = loaded.payroll_run
    items = []
    for employee, slip in loaded.entries:
        items.append(
            {
                "employee_id": slip["employee_id"],
                "employee_name": slip["employee_name"],
                "position_title": slip["position_title"],
                "profile_image_url": (
                    employee.profile_image_url if employee is not None else None
                ),
                "period_start": slip["period_start"],
                "period_end": slip["period_end"],
                "pay_date": slip["period_end"],
                "daily_rate": slip["daily_rate"],
                "pay_basis": slip.get("pay_basis", "daily"),
                "hourly_rate": slip.get("hourly_rate"),
                "monthly_salary": slip.get("monthly_salary"),
                "worked_days": slip["worked_days"],
                "hours_worked": hours_worked_from_slip(slip),
                "late_deductions": slip["late_deductions"],
                "undertime_deductions": slip["undertime_deductions"],
                "overtime_pay": slip["overtime_pay"],
                "overtime_hours": slip["overtime_hours"],
                "regular_pay": slip.get("regular_pay"),
                "leave_pay": slip.get("leave_pay", 0),
                "gross_pay": slip["gross_pay"],
                "deductions": slip["deductions"],
                "total_salary": slip["final_net_pay"],
                "net_pay": slip["net_pay"],
                "base_net_pay": slip["base_net_pay"],
                "final_net_pay": slip["final_net_pay"],
                "payroll_adjustments_total": slip["payroll_adjustments_total"],
                "payroll_adjustments_deduction_total": slip[
                    "payroll_adjustments_deduction_total"
                ],
                "payroll_adjustments_allowance_total": slip[
                    "payroll_adjustments_allowance_total"
                ],
                "pending_attendance_count": slip.get("pending_attendance_count", 0),
                "pending_work_dates": slip.get("pending_work_dates", []),
                "payroll_status": _payroll_status(
                    period_start, period_end, date.today()
                ),
                "pay_period_type": config.pay_period_type.value if config else "monthly",
                "adjustments_editable": slip["adjustments_editable"],
            }
        )
    return {
        "items": items,
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
        "pay_date": period_end.isoformat(),
        "payroll_status": _payroll_status(period_start, period_end, date.today()),
        "as_of": today.isoformat(),
        "incomplete_attendance_count": incomplete_count,
        "pending_attendance_count": pending_attendance_count,
        "can_finalize": (
            incomplete_count == 0
            and pending_attendance_count == 0
            and finalized_run is None
        ),
        "is_finalized": finalized_run is not None,
        "finalized_at": (
            finalized_run.finalized_at.isoformat()
            if finalized_run and finalized_run.finalized_at
            else None
        ),
    }


@router.post("/payroll/finalize")
def finalize_payroll(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    """Finalize the current pay period.

    Blocked while incomplete attendance or unresolved scheduled assignments
    remain in the period.
    """
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    config = db.get(BusinessPayrollConfig, user.business_id)
    business = db.get(Business, user.business_id)
    today = as_of or date.today()
    period_start, period_end = resolve_pay_period(config, today=today)

    existing = (
        db.query(PayrollRun)
        .filter(
            PayrollRun.business_id == user.business_id,
            PayrollRun.period_start == period_start,
            PayrollRun.period_end == period_end,
            PayrollRun.status == PayrollRunStatus.finalized,
        )
        .first()
    )
    if existing is not None:
        return {
            "status": "already_finalized",
            "payroll_run_id": str(existing.id),
            "period_start": period_start.isoformat(),
            "period_end": period_end.isoformat(),
            "finalized_at": (
                existing.finalized_at.isoformat() if existing.finalized_at else None
            ),
        }

    tz_name = business.timezone if business else None
    incomplete_count = count_incomplete_attendance_in_period(
        db,
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        business_timezone=tz_name,
    )
    if incomplete_count > 0:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "incomplete_attendance",
                "message": (
                    "Payroll cannot be finalized because there are employees "
                    "with incomplete attendance. Resolve all attendance "
                    "corrections first."
                ),
                "incomplete_count": incomplete_count,
            },
        )

    pending_attendance_count = count_unresolved_scheduled_assignments_in_period(
        db,
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        business_timezone=tz_name,
    )
    if pending_attendance_count > 0:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "pending_attendance",
                "message": (
                    "Payroll cannot be finalized because there are employees "
                    "with pending scheduled assignments. Resolve all pending "
                    "attendance first."
                ),
                "incomplete_count": incomplete_count,
                "pending_attendance_count": pending_attendance_count,
            },
        )

    employees = (
        db.query(Employee)
        .filter(Employee.business_id == user.business_id, Employee.is_active.is_(True))
        .order_by(Employee.full_name)
        .all()
    )

    run = PayrollRun(
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        status=PayrollRunStatus.finalized,
        run_by=user.id,
        finalized_at=datetime.now(timezone.utc),
        snapshot_version=PAYSLIP_SNAPSHOT_VERSION,
        calculation_config_json=build_calculation_config_json(db, user.business_id),
    )
    try:
        db.add(run)
        db.flush()
        create_finalized_payslip_snapshots(
            db,
            run=run,
            employees=employees,
            period_start=period_start,
            period_end=period_end,
            calculate_payslip=_calculate_employee_payslip,
        )
        db.commit()
        db.refresh(run)
    except Exception:
        db.rollback()
        raise

    # Employee inbox: payroll available (does not change payslip math).
    try:
        from app.services.notifications import notify_user_once

        period_label = f"{period_start.isoformat()} to {period_end.isoformat()}"
        active_employees = (
            db.query(Employee)
            .filter(
                Employee.business_id == user.business_id,
                Employee.is_active.is_(True),
                Employee.user_id.is_not(None),
            )
            .all()
        )
        for employee in active_employees:
            emp_user = db.get(User, employee.user_id)
            if emp_user is None or not emp_user.is_active:
                continue
            notify_user_once(
                db,
                user=emp_user,
                type="payroll_generated",
                title="Payroll Available",
                message=f"Your payslip for {period_label} is now available.",
                entity_type="payroll_run",
                entity_id=run.id,
                deep_link=f"/payslip?as_of={period_end.isoformat()}",
            )
    except Exception:
        pass

    return {
        "status": "finalized",
        "payroll_run_id": str(run.id),
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
        "finalized_at": (
            run.finalized_at.isoformat() if run.finalized_at else None
        ),
    }


@router.post("/payroll/unfinalize")
def unfinalize_payroll(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    """Reopen a finalized pay period so live calculation is used again.

    The previous PayrollRun is marked cancelled. Payslip snapshot rows are
    kept for history and are no longer the active source for this period.
    """
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    today = as_of or date.today()
    try:
        run, period_start, period_end = unfinalize_period_for_as_of(
            db,
            business_id=user.business_id,
            as_of=today,
        )
        add_log(
            db,
            user.id,
            action="payroll_unfinalized",
            description=(
                f"Payroll period {period_start.isoformat()} to "
                f"{period_end.isoformat()} reopened."
            ),
            previous_value="finalized",
            new_value="open",
        )
        db.commit()
        db.refresh(run)
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise

    return {
        "status": "unfinalized",
        "payroll_run_id": str(run.id),
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
        "previous_status": "finalized",
        "new_status": "open",
    }


@router.get("/payroll/me/payslip")
def my_payslip(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    if user.role != UserRole.employee:
        raise HTTPException(403, "Only employees can access this endpoint")
    employee = db.query(Employee).filter(Employee.user_id == user.id).first()
    if employee is None:
        raise HTTPException(404, "Employee not found")
    loaded = load_period_payslip(
        db,
        employee,
        as_of=as_of,
        calculate_payslip=_calculate_employee_payslip,
    )
    return _payslip_detail_payload(loaded)


def _payslip_detail_payload(loaded) -> dict:
    slip = require_loaded_slip(loaded)
    return {
        **slip,
        "pay_date": slip["period_end"],
        "payroll_status": _payroll_status(
            loaded.period_start, loaded.period_end, date.today()
        ),
        "hours_worked": hours_worked_from_slip(slip),
    }


@router.get("/payroll/{employee_id}/payslip")
def employee_payslip(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    employee = db.get(Employee, employee_id)
    if employee is not None and employee.business_id != user.business_id:
        raise HTTPException(404, "Employee not found")

    if employee is not None:
        if user.role == UserRole.employee:
            own_employee = (
                db.query(Employee)
                .filter(Employee.user_id == user.id, Employee.id == employee.id)
                .first()
            )
            if own_employee is None:
                raise HTTPException(403, "Employees can only view their own payslip")
        elif user.role not in (UserRole.owner, UserRole.manager):
            raise HTTPException(403, "Insufficient permissions")
        loaded = load_period_payslip(
            db,
            employee,
            as_of=as_of,
            calculate_payslip=_calculate_employee_payslip,
        )
        return _payslip_detail_payload(loaded)

    if user.role not in (UserRole.owner, UserRole.manager):
        raise HTTPException(404, "Employee not found")

    loaded = load_period_payslip_for_employee_id(
        db,
        business_id=user.business_id,
        employee_id=employee_id,
        as_of=as_of,
        calculate_payslip=_calculate_employee_payslip,
        employee=None,
    )
    if loaded.slip is None:
        raise HTTPException(404, "Employee not found")
    return _payslip_detail_payload(loaded)
