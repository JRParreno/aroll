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
from app.models.enums import AttendanceStatus, PayrollRunStatus, UserRole, Weekday
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, PayrollRun, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.holiday_pay import (
    resolve_holiday_policy,
    resolve_holiday_rules_mode,
)
from app.services.payroll_incomplete_gate import (
    count_incomplete_attendance_in_period,
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
from app.services.payroll_adjustments import (
    apply_adjustments_to_slip,
    list_active_adjustments,
    list_active_adjustments_for_employees,
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
    end_at = datetime.combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def _shift_start_at(work_date: date, shift: Shift) -> datetime:
    return datetime.combine(work_date, shift.start_time)


def _scheduled_shift_minutes(work_date: date, shift: Shift) -> float:
    """Scheduled working minutes from the assigned shift (supports overnight)."""
    start = _shift_start_at(work_date, shift)
    end = _shift_end_at(work_date, shift)
    return max((end - start).total_seconds() / 60.0, 0.0)


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
        "scheduled_minutes": 0.0,
        "worked_minutes": 0.0,
        "hourly_rate": 0.0,
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

    overtime_rate = float(config.overtime_per_minute) if config else 0.0
    late_rate = float(config.late_deduction_per_minute) if config else 0.0
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

    regular_pay = 0.0
    worked_days = 0.0
    overtime_minutes = 0.0
    late_minutes = 0.0
    early_out_minutes = 0.0
    unpaid_minutes = 0.0
    absent_days = 0
    paid_leave_days = 0
    unpaid_leave_days = 0
    half_day_days = 0
    holiday_pay = 0.0
    rest_day_pay = 0.0
    rest_day_days = 0
    attendance_records = []
    rest_day_records = []
    # Unworked scheduled time valued at Daily Rate ÷ assigned shift hours.
    attendance_shortfall_deductions = 0.0
    late_deductions_amount = 0.0
    undertime_deductions_amount = 0.0
    # Config-rate late only for incomplete/no-shift fallback rows.
    legacy_late_deductions = 0.0
    # Dates already credited via AttendanceRecord(status=on_leave).
    leave_dates_from_attendance: set[date] = set()

    for record, assignment, shift in rows:
        work_date = assignment.work_date if assignment else record.created_at.date()
        holiday = holidays.get(work_date)
        is_rest = _is_rest_day_work(assignment)

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

        if record.status == AttendanceStatus.on_leave:
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
                paid_leave_days += 1
                day_rate_factor = 1.0
                if shift is not None:
                    scheduled_minutes = _scheduled_shift_minutes(work_date, shift)
                leave_ctx = _pay_ctx(scheduled_minutes or DEFAULT_SCHEDULED_MINUTES)
                scheduled_minutes = leave_ctx.scheduled_minutes
                hourly_rate = leave_ctx.hourly_rate
                day_regular = leave_ctx.scheduled_day_value
                day_earned = leave_ctx.scheduled_day_value
                worked_days += 1.0
                regular_pay += day_regular
            else:
                unpaid_leave_days += 1
        elif record.status == AttendanceStatus.absent:
            absent_policy = resolve_holiday_policy(
                holiday=holiday, mode=holiday_rules_mode
            )
            if absent_policy is not None and absent_policy.pay_if_not_worked:
                if shift is not None:
                    scheduled_minutes = _scheduled_shift_minutes(work_date, shift)
                absent_ctx = _pay_ctx(scheduled_minutes or DEFAULT_SCHEDULED_MINUTES)
                scheduled_minutes = absent_ctx.scheduled_minutes
                hourly_rate = absent_ctx.hourly_rate
                holiday_pay += absent_ctx.scheduled_day_value
                day_earned = absent_ctx.scheduled_day_value
                day_rate_factor = 1.0
            else:
                absent_days += 1
        elif record.status == AttendanceStatus.incomplete:
            # Forgotten clock-out: do not finalize hours, OT, undertime, or pay.
            pass
        elif (
            record.time_in is not None
            and record.time_out is not None
            and shift is not None
            and assignment is not None
        ):
            # Rate source: PayrollPayContext (daily or hourly).
            # Daily: credit scheduled_day_value (= daily_rate), deduct shortfall.
            # Hourly: same structure; scheduled_day_value = hourly × scheduled hours;
            #         net day earnings = paid_worked × minute_rate.
            scheduled_minutes = _scheduled_shift_minutes(work_date, shift)
            if scheduled_minutes <= 0:
                scheduled_minutes = DEFAULT_SCHEDULED_MINUTES
            pay_ctx = _pay_ctx(scheduled_minutes)
            scheduled_minutes = pay_ctx.scheduled_minutes
            hourly_rate = pay_ctx.hourly_rate
            minute_rate = pay_ctx.minute_rate

            paid_worked = min(worked_minutes, scheduled_minutes)
            day_unpaid_minutes = max(scheduled_minutes - paid_worked, 0.0)
            day_shortfall = day_unpaid_minutes * minute_rate

            # Base the day on the full scheduled day value; shortfall is deducted below.
            day_regular = pay_ctx.scheduled_day_value
            day_earned = max(day_regular - day_shortfall, 0.0)
            day_rate_factor = 1.0
            worked_days += 1.0
            if 0 < worked_minutes < half_day_threshold:
                half_day_days += 1

            regular_pay += day_regular
            attendance_shortfall_deductions += day_shortfall
            unpaid_minutes += day_unpaid_minutes

            scheduled_start = _shift_start_at(work_date, shift)
            grace_end = scheduled_start + timedelta(minutes=grace_minutes)
            time_in_local = _to_business_naive(record.time_in, tz_name)
            time_out_local = _to_business_naive(record.time_out, tz_name)
            shift_end = _shift_end_at(work_date, shift)

            if time_in_local > grace_end:
                # Payslip presentation only: show late minutes/deduction when
                # lateness coincided with unpaid scheduled time (shortfall > 0).
                # If the employee made up the hours (shortfall == 0), hide late
                # on the payslip — attendance status remains Late unchanged.
                # Payroll net deductions still use attendance_shortfall only.
                computed_late_minutes = (
                    time_in_local - grace_end
                ).total_seconds() / 60.0
                computed_late_deduction = computed_late_minutes * minute_rate
                if day_shortfall > 0:
                    day_late_minutes = computed_late_minutes
                    day_late_deduction = computed_late_deduction
                    late_minutes += day_late_minutes
                    late_deductions_amount += day_late_deduction

            if time_out_local < shift_end:
                day_undertime_minutes = (
                    shift_end - time_out_local
                ).total_seconds() / 60.0
                early_out_minutes += day_undertime_minutes
                day_undertime_deduction = day_undertime_minutes * minute_rate
                undertime_deductions_amount += day_undertime_deduction

            raw_ot = max((time_out_local - shift_end).total_seconds() / 60.0, 0.0)
            # Optional company policy: post-end minutes first recover late-from-
            # scheduled-start (not grace). Shortfall / status unchanged.
            if late_ot_balancing:
                late_for_balancing = max(
                    (time_in_local - scheduled_start).total_seconds() / 60.0,
                    0.0,
                )
                recoverable = min(raw_ot, late_for_balancing)
                raw_ot = max(raw_ot - recoverable, 0.0)
            if raw_ot >= ot_minimum:
                overtime_minutes += raw_ot
        elif record.time_in is not None:
            # Incomplete punch and/or no linked shift: keep prior fallback rules.
            day_rate_factor = 1.0
            if 0 < worked_minutes < half_day_threshold:
                day_rate_factor = 0.5
                half_day_days += 1
            if shift is not None and assignment is not None:
                scheduled_minutes = _scheduled_shift_minutes(work_date, shift)
            fallback_ctx = _pay_ctx(scheduled_minutes or DEFAULT_SCHEDULED_MINUTES)
            scheduled_minutes = fallback_ctx.scheduled_minutes
            hourly_rate = fallback_ctx.hourly_rate
            worked_days += day_rate_factor
            day_regular = fallback_ctx.scheduled_day_value * day_rate_factor
            day_earned = day_regular
            regular_pay += day_regular

            if shift is not None and assignment is not None:
                scheduled_start = _shift_start_at(work_date, shift)
                grace_end = scheduled_start + timedelta(minutes=grace_minutes)
                time_in_local = _to_business_naive(record.time_in, tz_name)
                if time_in_local > grace_end:
                    day_late_minutes = (
                        time_in_local - grace_end
                    ).total_seconds() / 60.0
                    late_minutes += day_late_minutes
                    if config is None or config.late_deduction_enabled:
                        legacy_late_deductions += day_late_minutes * late_rate
                        day_late_deduction = day_late_minutes * late_rate
                        late_deductions_amount += day_late_deduction

        worked_holiday_policy = resolve_holiday_policy(
            holiday=holiday, mode=holiday_rules_mode
        )
        if (
            worked_holiday_policy is not None
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
        )
        if is_rest and worked and day_earned > 0:
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
                    else "finalized"
                ),
            }
        )

    # Scheduled assignments (shared by leave recon + no-show).
    seen_assignment_ids = {
        record.shift_assignment_id
        for record, _assignment, _shift in rows
        if record.shift_assignment_id is not None
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
    shift_by_date = {
        assignment.work_date: shift for assignment, shift in scheduled_assignments
    }

    # Leave reconciliation (payroll calculation only — no DB writes).
    # Credits approved LeaveRequest days that have no AttendanceRecord(on_leave).
    # Must run before no-show so leave is never underpaid as a silent skip.
    for leave_date in approved_leave_dates_for_employee(
        db,
        employee_id=employee.id,
        period_start=period_start,
        period_end=period_end,
    ):
        if leave_date in leave_dates_from_attendance:
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
        leave_shift = shift_by_date.get(leave_date)
        leave_scheduled = (
            _scheduled_shift_minutes(leave_date, leave_shift)
            if leave_shift is not None
            else DEFAULT_SCHEDULED_MINUTES
        )
        leave_day_value = _pay_ctx(leave_scheduled).scheduled_day_value
        if paid:
            paid_leave_days += 1
            worked_days += 1.0
            regular_pay += leave_day_value
        else:
            unpaid_leave_days += 1
        leave_dates_from_attendance.add(leave_date)
        attendance_records.append(
            _leave_day_payslip_row(
                work_date=leave_date,
                holiday=holidays.get(leave_date),
                paid=paid,
                daily_rate=leave_day_value,
            )
        )

    # No-show reconciliation (payroll calculation only — no DB writes).
    # Scheduled assignments with no AttendanceRecord are treated like
    # AttendanceStatus.absent: increment absent_days, ₱0 earned, list in output.
    today = business_today(tz_name)
    now_local = business_now(tz_name).replace(tzinfo=None)

    for assignment, shift in scheduled_assignments:
        if assignment.id in seen_assignment_ids:
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
            noshow_sched = _scheduled_shift_minutes(assignment.work_date, shift)
            noshow_day_value = _pay_ctx(noshow_sched).scheduled_day_value
            holiday_pay += noshow_day_value
            attendance_records.append(
                _holiday_credit_payslip_row(
                    work_date=assignment.work_date,
                    holiday=holiday,
                    is_rest_day=_is_rest_day_work(assignment),
                    daily_rate=noshow_day_value,
                )
            )
            continue

        absent_days += 1
        attendance_records.append(
            _absent_day_payslip_row(
                work_date=assignment.work_date,
                holiday=holiday,
                is_rest_day=_is_rest_day_work(assignment),
            )
        )

    overtime_pay = overtime_minutes * overtime_rate
    if config is not None and not config.overtime_enabled:
        overtime_pay = 0.0
    if att_policy is not None and not att_policy.overtime_enabled:
        overtime_pay = 0.0

    # Net deductions = unworked scheduled minutes at dynamic hourly/minute rate
    # (covers late + undertime + any remaining unpaid gap without double-counting).
    deductions = attendance_shortfall_deductions + legacy_late_deductions
    remaining_unpaid_deductions = max(
        deductions - late_deductions_amount - undertime_deductions_amount,
        0.0,
    )
    gross_pay = regular_pay + overtime_pay + holiday_pay + rest_day_pay
    net_pay = max(gross_pay - deductions, 0)

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
        # Base earnings for UI "Basic Salary" — do not recompute in clients.
        "regular_pay": round(regular_pay, 2),
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
    period_start, period_end = resolve_pay_period(config, today=today)
    incomplete_count = count_incomplete_attendance_in_period(
        db,
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        business_timezone=business.timezone if business else None,
    )
    finalized_run = (
        db.query(PayrollRun)
        .filter(
            PayrollRun.business_id == user.business_id,
            PayrollRun.period_start == period_start,
            PayrollRun.period_end == period_end,
            PayrollRun.status == PayrollRunStatus.finalized,
        )
        .order_by(PayrollRun.created_at.desc())
        .first()
    )
    employees = (
        db.query(Employee)
        .filter(Employee.business_id == user.business_id, Employee.is_active.is_(True))
        .order_by(Employee.full_name)
        .all()
    )
    adjustment_map = list_active_adjustments_for_employees(
        db,
        business_id=user.business_id,
        employee_ids=[employee.id for employee in employees],
        period_start=period_start,
        period_end=period_end,
    )
    items = []
    for employee in employees:
        slip = apply_adjustments_to_slip(
            _calculate_employee_payslip(db, employee, period_start, period_end),
            adjustment_map.get(employee.id, []),
        )
        items.append(
            {
                "employee_id": slip["employee_id"],
                "employee_name": slip["employee_name"],
                "position_title": slip["position_title"],
                "profile_image_url": employee.profile_image_url,
                "period_start": slip["period_start"],
                "period_end": slip["period_end"],
                "pay_date": slip["period_end"],
                "daily_rate": slip["daily_rate"],
                "pay_basis": slip.get("pay_basis", "daily"),
                "hourly_rate": slip.get("hourly_rate"),
                "monthly_salary": slip.get("monthly_salary"),
                "worked_days": slip["worked_days"],
                "hours_worked": round(
                    float(slip.get("worked_days") or 0) * 8.0
                    + float(slip.get("overtime_hours") or 0),
                    2,
                ),
                "late_deductions": slip["late_deductions"],
                "undertime_deductions": slip["undertime_deductions"],
                "overtime_pay": slip["overtime_pay"],
                "overtime_hours": slip["overtime_hours"],
                "regular_pay": slip.get("regular_pay"),
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
        "can_finalize": incomplete_count == 0 and finalized_run is None,
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
    """Finalize the current pay period. Blocked while incomplete attendance exists."""
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

    incomplete_count = count_incomplete_attendance_in_period(
        db,
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        business_timezone=business.timezone if business else None,
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

    run = PayrollRun(
        business_id=user.business_id,
        period_start=period_start,
        period_end=period_end,
        status=PayrollRunStatus.finalized,
        run_by=user.id,
        finalized_at=datetime.now(timezone.utc),
    )
    db.add(run)
    db.commit()
    db.refresh(run)

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
    config = db.get(BusinessPayrollConfig, employee.business_id)
    period_start, period_end = resolve_pay_period(config, today=as_of)
    slip = apply_adjustments_to_slip(
        _calculate_employee_payslip(db, employee, period_start, period_end),
        list_active_adjustments(
            db,
            business_id=employee.business_id,
            employee_id=employee.id,
            period_start=period_start,
            period_end=period_end,
        ),
    )
    return {
        **slip,
        "pay_date": slip["period_end"],
        "payroll_status": _payroll_status(period_start, period_end, date.today()),
        "hours_worked": round(
            float(slip.get("worked_days") or 0) * 8.0
            + float(slip.get("overtime_hours") or 0),
            2,
        ),
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
    if employee is None or employee.business_id != user.business_id:
        raise HTTPException(404, "Employee not found")

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

    config = db.get(BusinessPayrollConfig, employee.business_id)
    period_start, period_end = resolve_pay_period(config, today=as_of)
    slip = apply_adjustments_to_slip(
        _calculate_employee_payslip(db, employee, period_start, period_end),
        list_active_adjustments(
            db,
            business_id=employee.business_id,
            employee_id=employee.id,
            period_start=period_start,
            period_end=period_end,
        ),
    )
    return {
        **slip,
        "pay_date": slip["period_end"],
        "payroll_status": _payroll_status(period_start, period_end, date.today()),
        "hours_worked": round(
            float(slip.get("worked_days") or 0) * 8.0
            + float(slip.get("overtime_hours") or 0),
            2,
        ),
    }
