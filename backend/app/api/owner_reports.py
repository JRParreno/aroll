import uuid
from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, UserRole, Weekday
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User

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


def _weekday_for_date(work_date: date) -> Weekday:
    return _WEEKDAY_BY_INDEX[work_date.weekday()]


def _is_rest_day_work(assignment: ShiftAssignment | None) -> bool:
    return bool(assignment is not None and assignment.is_rest_day_work)


def _rest_day_premium_percent(policy: BusinessRestDayPolicy | None) -> float:
    if policy is None:
        return 0.0
    return float(policy.rest_day_premium_percent)


def _calculate_employee_payslip(
    db: Session,
    employee: Employee,
    period_start: date,
    period_end: date,
) -> dict:
    config = db.get(BusinessPayrollConfig, employee.business_id)
    rest_policy = db.get(BusinessRestDayPolicy, employee.business_id)
    position = db.get(Position, employee.position_id) if employee.position_id else None
    daily_rate = float(position.daily_rate) if position else 0.0
    overtime_rate = float(config.overtime_per_minute) if config else 0.0
    late_rate = float(config.late_deduction_per_minute) if config else 0.0
    premium_percent = _rest_day_premium_percent(rest_policy)
    rest_day_work_allowed = True

    rows = (
        db.query(AttendanceRecord, ShiftAssignment, Shift)
        .outerjoin(ShiftAssignment, AttendanceRecord.shift_assignment_id == ShiftAssignment.id)
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            AttendanceRecord.created_at >= period_start,
            AttendanceRecord.created_at < period_end + timedelta(days=1),
        )
        .all()
    )
    holidays = {
        holiday.holiday_date: holiday
        for holiday in db.query(Holiday)
        .filter(Holiday.business_id == employee.business_id, Holiday.is_active.is_(True))
        .all()
    }

    worked_days = 0
    overtime_minutes = 0.0
    late_minutes = 0.0
    absent_days = 0
    holiday_pay = 0.0
    rest_day_pay = 0.0
    rest_day_days = 0
    attendance_records = []
    rest_day_records = []

    for record, assignment, shift in rows:
        work_date = assignment.work_date if assignment else record.created_at.date()
        holiday = holidays.get(work_date)
        is_rest = _is_rest_day_work(assignment)
        worked = (
            record.status != AttendanceStatus.absent and record.time_in is not None
        )

        if record.status == AttendanceStatus.absent:
            absent_days += 1
        elif record.time_in is not None:
            worked_days += 1

        if shift is not None and assignment is not None and record.time_in is not None:
            scheduled_start = datetime.combine(work_date, shift.start_time)
            time_in = record.time_in.replace(tzinfo=None)
            if time_in > scheduled_start:
                late_minutes += (time_in - scheduled_start).total_seconds() / 60

            if record.time_out is not None:
                time_out = record.time_out.replace(tzinfo=None)
                overtime_minutes += max(
                    (time_out - _shift_end_at(work_date, shift)).total_seconds() / 60,
                    0,
                )

        if holiday is not None and record.status != AttendanceStatus.absent:
            multiplier = float(holiday.pay_multiplier)
            holiday_pay += max(daily_rate * (multiplier - 1), 0)

        day_rest_premium = 0.0
        if is_rest and worked:
            day_rest_premium = daily_rate * (premium_percent / 100.0)
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

        attendance_records.append(
            {
                "date": work_date.isoformat(),
                "status": record.status.value,
                "time_in": record.time_in.isoformat() if record.time_in else None,
                "time_out": record.time_out.isoformat() if record.time_out else None,
                "holiday_name": holiday.name if holiday else None,
                "is_rest_day": is_rest,
                "rest_day_premium_pay": (
                    round(day_rest_premium, 2) if day_rest_premium else None
                ),
            }
        )

    overtime_pay = overtime_minutes * overtime_rate
    deductions = late_minutes * late_rate
    if config is not None and not config.late_deduction_enabled:
        deductions = 0.0
    if config is not None and not config.overtime_enabled:
        overtime_pay = 0.0
    gross_pay = (
        daily_rate * worked_days + overtime_pay + holiday_pay + rest_day_pay
    )
    net_pay = max(gross_pay - deductions, 0)

    return {
        "employee_id": str(employee.id),
        "employee_name": employee.full_name,
        "position_title": employee.position_title,
        "employment_type": employee.employment_type.value,
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
        "daily_rate": daily_rate,
        "worked_days": worked_days,
        "overtime_minutes": round(overtime_minutes, 2),
        "overtime_hours": round(overtime_minutes / 60, 2),
        "overtime_pay": round(overtime_pay, 2),
        "holiday_pay": round(holiday_pay, 2),
        "rest_day_days": rest_day_days,
        "rest_day_premium_percent": premium_percent,
        "rest_day_pay": round(rest_day_pay, 2),
        "rest_day_work_allowed": rest_day_work_allowed,
        "rest_day_records": rest_day_records,
        "deductions": round(deductions, 2),
        "absent_days": absent_days,
        "gross_pay": round(gross_pay, 2),
        "net_pay": round(net_pay, 2),
        "attendance_records": attendance_records,
    }


@router.get("/attendance")
def attendance_report(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    rest_policy = db.get(BusinessRestDayPolicy, user.business_id)
    premium_percent = _rest_day_premium_percent(rest_policy)
    rest_day_work_allowed = True

    rows = (
        db.query(AttendanceRecord, Employee, ShiftAssignment, Shift)
        .join(Employee, AttendanceRecord.employee_id == Employee.id)
        .outerjoin(ShiftAssignment, AttendanceRecord.shift_assignment_id == ShiftAssignment.id)
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(AttendanceRecord.business_id == user.business_id)
        .order_by(AttendanceRecord.created_at.desc())
        .limit(200)
        .all()
    )
    records = []
    rest_day_work = []
    present = late = absent = rest_day = 0
    for record, employee, assignment, shift in rows:
        work_date = (
            assignment.work_date
            if assignment
            else record.created_at.date()
        )
        is_rest = _is_rest_day_work(assignment)
        if record.status == AttendanceStatus.absent:
            absent += 1
        elif record.status == AttendanceStatus.late:
            late += 1
        else:
            present += 1

        item = {
            "id": str(record.id),
            "employee_name": employee.full_name,
            "position_title": employee.position_title,
            "date": work_date.isoformat(),
            "weekday": _weekday_for_date(work_date).value,
            "time_in": record.time_in.isoformat() if record.time_in else None,
            "time_out": record.time_out.isoformat() if record.time_out else None,
            "status": record.status.value,
            "shift_name": shift.name if shift else None,
            "is_rest_day": is_rest,
            "rest_day_authorized": rest_day_work_allowed if is_rest else None,
        }
        records.append(item)

        if is_rest and record.time_in is not None:
            rest_day += 1
            rest_day_work.append(item)

    return {
        "summary": {
            "present": present,
            "late": late,
            "absent": absent,
            "rest_day": rest_day,
        },
        "rest_day_premium_percent": premium_percent,
        "rest_day_work_allowed": rest_day_work_allowed,
        "rest_day_work": rest_day_work,
        "records": records,
    }


@router.get("/payroll")
def payroll_report(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    period_end = date.today()
    period_start = period_end - timedelta(days=14)
    config = db.get(BusinessPayrollConfig, user.business_id)
    positions = {
        position.id: position
        for position in db.query(Position)
        .filter(Position.business_id == user.business_id, Position.is_active.is_(True))
        .all()
    }
    employees = (
        db.query(Employee)
        .filter(Employee.business_id == user.business_id, Employee.is_active.is_(True))
        .order_by(Employee.full_name)
        .all()
    )
    items = []
    for employee in employees:
        attendance_count = (
            db.query(AttendanceRecord)
            .filter(
                AttendanceRecord.business_id == user.business_id,
                AttendanceRecord.employee_id == employee.id,
                AttendanceRecord.status != AttendanceStatus.absent,
                AttendanceRecord.created_at >= period_start,
            )
            .count()
        )
        position = positions.get(employee.position_id) if employee.position_id else None
        daily_rate = float(position.daily_rate) if position else 0.0
        overtime_pay = 0.0
        deductions = 0.0
        gross = daily_rate * attendance_count + overtime_pay
        total = gross - deductions
        items.append(
            {
                "employee_id": str(employee.id),
                "employee_name": employee.full_name,
                "position_title": employee.position_title,
                "period_start": period_start.isoformat(),
                "period_end": period_end.isoformat(),
                "daily_rate": daily_rate,
                "worked_days": attendance_count,
                "overtime_pay": overtime_pay,
                "deductions": deductions,
                "total_salary": total,
                "pay_period_type": config.pay_period_type.value if config else "monthly",
            }
        )
    return {"items": items}


@router.get("/payroll/me/payslip")
def my_payslip(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    if user.role != UserRole.employee:
        raise HTTPException(403, "Only employees can access this endpoint")
    employee = db.query(Employee).filter(Employee.user_id == user.id).first()
    if employee is None:
        raise HTTPException(404, "Employee not found")
    period_end = date.today()
    period_start = period_end - timedelta(days=14)
    return _calculate_employee_payslip(db, employee, period_start, period_end)


@router.get("/payroll/{employee_id}/payslip")
def employee_payslip(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
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

    period_end = date.today()
    period_start = period_end - timedelta(days=14)
    return _calculate_employee_payslip(db, employee, period_start, period_end)
