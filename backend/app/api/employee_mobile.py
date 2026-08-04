import uuid
from datetime import date, datetime, time, timezone, timedelta
from io import BytesIO
from typing import Annotated, Literal

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Response,
    UploadFile,
)
from pydantic import BaseModel

from app.schemas.profile_image import ProfileImageRequest
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.api.owner_reports import _calculate_employee_payslip
from app.services.payroll_adjustments import (
    apply_adjustments_to_slip,
    list_active_adjustments,
)
from app.core.deps import get_current_user
from app.core.profile_image import validate_profile_image_data
from app.core.timezone import business_today
from app.db.session import get_db
from app.models.attendance import AttendanceRecord
from app.models.business import Business, BusinessLocation, BusinessRegistration
from app.models.employee import Employee
from app.models.enums import (
    AttendanceStatus,
    BusinessStatus,
    EmployeeStatus,
    UserRole,
)
from app.models.holiday import Holiday
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.schemas.employee_attendance import (
    AttendanceActionResponse,
    ClockLocationRequest,
    WorksiteResponse,
)
from app.services.attendance_clock import (
    _active_record,
    clock_in_employee,
    clock_out_employee,
    verify_employee_face_match,
    worksite_for_business,
)
from app.services.missing_clock_out import (
    ensure_incomplete_for_employee,
    list_incomplete_for_employee,
)
from app.services.face_enrollment import enroll_face_sample_bytes, face_status_for_employee
from app.services.pay_period import resolve_pay_period
from app.models.payroll import BusinessPayrollConfig
from app.schemas.face import FaceEnrollResponse, FaceStatusResponse

router = APIRouter(prefix="/employee", tags=["employee-mobile"])


class FaceRegistrationRequest(BaseModel):
    status: Literal["completed"]


def _current_employee(
    db: Session,
    user: User,
) -> tuple[Employee, Business]:
    if user.role != UserRole.employee:
        raise HTTPException(403, "Only employees can access this endpoint")
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    employee = (
        db.query(Employee)
        .filter(
            Employee.user_id == user.id,
            Employee.business_id == user.business_id,
        )
        .first()
    )
    if employee is None:
        raise HTTPException(404, "Employee not found")
    if (
        employee.status != EmployeeStatus.active
        or not employee.is_active
    ):
        raise HTTPException(
            403,
            detail={
                "code": "employee_inactive",
                "message": (
                    "Your account isn’t active. Please contact your employer."
                ),
            },
        )

    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    if business.status != BusinessStatus.active:
        raise HTTPException(
            403,
            detail={
                "code": "business_inactive",
                "message": (
                    "This workplace isn’t active right now. "
                    "Please contact your employer."
                ),
            },
        )
    return employee, business


def _money(value: float | int | None) -> float:
    return round(float(value or 0), 2)


def _time_value(value: time) -> str:
    return value.strftime("%H:%M")


def _time_label(value: time) -> str:
    return value.strftime("%I:%M %p").lstrip("0")


def _dt_label(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.isoformat()


def _branding_response(business: Business) -> dict:
    theme = business.theme_settings or {}
    return {
        "logo_url": business.logo_url,
        "owner_profile_image_url": business.owner_profile_image_url,
        "display_image_url": business.display_image_url,
        "theme": {
            "primary_color": theme.get("primary_color", "#1E3A5F"),
            "secondary_color": theme.get("secondary_color", "#284B73"),
            "sidebar_color": theme.get("sidebar_color", "#1E3A5F"),
            "accent_color": theme.get("accent_color", "#3B82F6"),
            "button_color": theme.get("button_color", "#1E3A5F"),
            "card_style": theme.get("card_style", "soft"),
            "font_size": theme.get("font_size", "comfortable"),
            "color_mode": theme.get("color_mode", "light"),
            "layout_density": theme.get("layout_density", "rounded"),
        },
    }


def _primary_location(db: Session, business_id: uuid.UUID) -> BusinessLocation | None:
    return (
        db.query(BusinessLocation)
        .filter(BusinessLocation.business_id == business_id)
        .order_by(BusinessLocation.is_primary.desc(), BusinessLocation.label)
        .first()
    )


def _business_owner_name(db: Session, business: Business) -> str | None:
    if business.registration_id is None:
        return None
    registration = db.get(BusinessRegistration, business.registration_id)
    return registration.owner_name if registration else None


def _employee_profile_response(
    db: Session,
    employee: Employee,
    business: Business,
) -> dict:
    user = db.get(User, employee.user_id)
    return {
        "employee_id": str(employee.id),
        "business_id": str(business.id),
        "full_name": employee.full_name,
        "username": user.email if user else None,
        "position": employee.position_title,
        "employment_type": employee.employment_type.value,
        "phone": employee.phone,
        "profile_image_url": employee.profile_image_url,
        "hire_date": employee.hire_date.isoformat() if employee.hire_date else None,
        "status": employee.status.value,
        "business_name": business.name,
        "business_code": business.business_code,
        "business_type": business.business_type,
        "owner_name": _business_owner_name(db, business),
        "face_registration_status": employee.face_registration_status,
        "face_registered_at": _dt_label(employee.face_registered_at),
        "face_registration_skipped_at": _dt_label(
            employee.face_registration_skipped_at
        ),
        "branding": _branding_response(business),
    }


def _holiday_map(db: Session, business_id: uuid.UUID) -> dict[date, Holiday]:
    holidays = (
        db.query(Holiday)
        .filter(Holiday.business_id == business_id, Holiday.is_active.is_(True))
        .all()
    )
    return {holiday.holiday_date: holiday for holiday in holidays}


def _schedule_status(
    db: Session,
    employee: Employee,
    assignment: ShiftAssignment,
    today: date,
) -> str:
    from app.services.leave_requests import employee_on_approved_leave

    if employee_on_approved_leave(
        db, employee_id=employee.id, work_date=assignment.work_date
    ):
        return "on_leave"
    if assignment.work_date > today:
        return "upcoming"
    if assignment.work_date < today:
        return "completed"
    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.shift_assignment_id == assignment.id,
            AttendanceRecord.employee_id == employee.id,
        )
        .order_by(AttendanceRecord.created_at.desc())
        .first()
    )
    if record is not None and record.status == AttendanceStatus.on_leave:
        return "on_leave"
    if record is not None and record.status == AttendanceStatus.complete:
        return "completed"
    return "today"


def _schedule_item(
    db: Session,
    assignment: ShiftAssignment,
    shift: Shift,
    location: BusinessLocation | None,
    holiday: Holiday | None,
) -> dict:
    coworkers = (
        db.query(Employee)
        .join(ShiftAssignment, ShiftAssignment.employee_id == Employee.id)
        .filter(
            ShiftAssignment.shift_id == shift.id,
            ShiftAssignment.work_date == assignment.work_date,
            Employee.business_id == shift.business_id,
            Employee.is_active.is_(True),
        )
        .order_by(Employee.full_name.asc())
        .all()
    )
    return {
        "assignment_id": str(assignment.id),
        "shift_id": str(shift.id),
        "shift_name": shift.name,
        "work_date": assignment.work_date.isoformat(),
        "start_time": _time_value(shift.start_time),
        "end_time": _time_value(shift.end_time),
        "start_label": _time_label(shift.start_time),
        "end_label": _time_label(shift.end_time),
        "location_label": location.label if location else None,
        "location_address": location.address if location else None,
        "holiday_name": holiday.name if holiday else None,
        "notes": assignment.notes,
        "coworkers": [
            {
                "employee_id": str(coworker.id),
                "full_name": coworker.full_name,
                "profile_image_url": coworker.profile_image_url,
                "is_current_employee": coworker.id == assignment.employee_id,
            }
            for coworker in coworkers
        ],
    }


def _employee_schedule(
    db: Session,
    employee: Employee,
    *,
    start_date: date | None = None,
    end_date: date | None = None,
    today: date | None = None,
) -> list[dict]:
    location = _primary_location(db, employee.business_id)
    holidays = _holiday_map(db, employee.business_id)
    work_today = today or date.today()
    query = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            ShiftAssignment.employee_id == employee.id,
            Shift.business_id == employee.business_id,
        )
    )
    if start_date is not None:
        query = query.filter(ShiftAssignment.work_date >= start_date)
    if end_date is not None:
        query = query.filter(ShiftAssignment.work_date <= end_date)
    rows = query.order_by(
        ShiftAssignment.work_date.asc(), Shift.start_time.asc()
    ).all()
    return [
        {
            **_schedule_item(
                db, assignment, shift, location, holidays.get(assignment.work_date)
            ),
            "status": _schedule_status(db, employee, assignment, work_today),
        }
        for assignment, shift in rows
    ]


def _shift_end_at(work_date: date, shift: Shift) -> datetime:
    end_at = datetime.combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def _overtime_minutes(
    record: AttendanceRecord,
    assignment: ShiftAssignment | None,
    shift: Shift | None,
) -> float:
    if record.status == AttendanceStatus.incomplete:
        return 0
    if record.time_out is None or assignment is None or shift is None:
        return 0
    time_out = record.time_out.replace(tzinfo=None)
    overtime = (time_out - _shift_end_at(assignment.work_date, shift)).total_seconds()
    return round(max(overtime / 60, 0), 2)


def _shift_history_rows(
    db: Session,
    employee: Employee,
    *,
    today: date | None = None,
    limit: int = 100,
    business_timezone: str | None = None,
) -> list[dict]:
    """Past and punched shift assignments with linked attendance when available.

    Includes:
    - every assignment before today (missing punches surface as absent)
    - today's assignment once a clock-in exists (any status: in_progress, late,
      complete, absent) so Shift History reflects the live attendance record
      immediately after face clock-in/out — not only when status is `complete`
    """
    from app.services.attendance_correction import latest_corrections_by_assignment

    work_today = today or date.today()
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business_timezone
    )
    holidays = _holiday_map(db, employee.business_id)
    rows = (
        db.query(ShiftAssignment, Shift, AttendanceRecord)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .outerjoin(
            AttendanceRecord,
            and_(
                AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
                AttendanceRecord.employee_id == employee.id,
            ),
        )
        .filter(
            ShiftAssignment.employee_id == employee.id,
            Shift.business_id == employee.business_id,
            or_(
                ShiftAssignment.work_date < work_today,
                # Any saved punch for today (clock-in or finished clock-out).
                AttendanceRecord.time_in.isnot(None),
                AttendanceRecord.status == AttendanceStatus.on_leave,
            ),
        )
        .order_by(
            ShiftAssignment.work_date.desc(),
            Shift.start_time.desc(),
            AttendanceRecord.created_at.desc(),
        )
        .limit(limit)
        .all()
    )

    # One history row per assignment (prefer newest attendance if duplicates exist).
    deduped: list[tuple[ShiftAssignment, Shift, AttendanceRecord | None]] = []
    seen_assignments: set[uuid.UUID] = set()
    for assignment, shift, record in rows:
        if assignment.id in seen_assignments:
            continue
        seen_assignments.add(assignment.id)
        deduped.append((assignment, shift, record))

    assignment_ids = [assignment.id for assignment, _shift, _record in deduped]
    corrections = latest_corrections_by_assignment(
        db,
        employee_id=employee.id,
        assignment_ids=assignment_ids,
    )

    from app.services.leave_requests import employee_on_approved_leave

    items = []
    for assignment, shift, record in deduped:
        work_date = assignment.work_date
        holiday = holidays.get(work_date)
        on_leave = (
            (record is not None and record.status == AttendanceStatus.on_leave)
            or employee_on_approved_leave(
                db, employee_id=employee.id, work_date=work_date
            )
        )
        if on_leave:
            attendance_status = AttendanceStatus.on_leave.value
            attendance_record_id = str(record.id) if record else None
            time_in = None
            time_out = None
            overtime = 0.0
        elif record is None:
            attendance_status = AttendanceStatus.absent.value
            attendance_record_id = None
            time_in = None
            time_out = None
            overtime = 0.0
        else:
            attendance_status = record.status.value
            attendance_record_id = str(record.id)
            time_in = _dt_label(record.time_in)
            time_out = _dt_label(record.time_out)
            overtime = _overtime_minutes(record, assignment, shift)

        correction = corrections.get(assignment.id)
        # Allow a new correction only when none exists yet, or the latest was
        # rejected. Hide the action once a request is pending or approved.
        # Approved leave days do not need attendance corrections.
        can_correct = (
            not on_leave
            and work_date <= work_today
            and (
                correction is None
                or correction.status.value == "rejected"
            )
        )
        items.append(
            {
                "id": attendance_record_id or str(assignment.id),
                "assignment_id": str(assignment.id),
                "attendance_record_id": attendance_record_id,
                "date": work_date.isoformat(),
                "shift_name": shift.name,
                "shift_start": _time_label(shift.start_time),
                "shift_end": _time_label(shift.end_time),
                "time_in": time_in,
                "time_out": time_out,
                "status": attendance_status,
                "overtime_minutes": overtime,
                "holiday_name": holiday.name if holiday else None,
                "can_request_correction": can_correct,
                "correction_status": correction.status.value if correction else None,
                "correction_id": str(correction.id) if correction else None,
                "correction_review_note": (
                    correction.review_note if correction else None
                ),
            }
        )
    return items


def _performance_summary(
    db: Session,
    employee: Employee,
    days: int = 7,
    *,
    business_timezone: str | None = None,
) -> dict:
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business_timezone
    )
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = (
        db.query(AttendanceRecord, ShiftAssignment, Shift)
        .outerjoin(ShiftAssignment, AttendanceRecord.shift_assignment_id == ShiftAssignment.id)
        .outerjoin(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            AttendanceRecord.created_at >= since,
        )
        .all()
    )
    counts = {
        "on_time": 0,
        "late": 0,
        "undertime": 0,
        "overtime": 0,
        "absent": 0,
        "incomplete": 0,
    }
    scored = 0
    for record, assignment, shift in rows:
        # Incomplete and approved leave are excluded from productivity metrics.
        if record.status == AttendanceStatus.incomplete:
            counts["incomplete"] += 1
            continue
        if record.status == AttendanceStatus.on_leave:
            continue
        scored += 1
        if record.status == AttendanceStatus.absent:
            counts["absent"] += 1
        elif record.status == AttendanceStatus.late:
            counts["late"] += 1
        else:
            counts["on_time"] += 1
        if _overtime_minutes(record, assignment, shift) > 0:
            counts["overtime"] += 1
    return {"period": "weekly", "has_data": scored > 0, **counts}


def _today_attendance_status(
    db: Session,
    employee: Employee,
    today: date,
    *,
    business_timezone: str | None = None,
) -> dict:
    """Attendance state for dashboard / clock hub.

    Open sessions use the same lookup as Clock Out so "Ready to Clock Out"
    never disagrees with whether clock-out can find today's record.
    """
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business_timezone
    )
    open_record = _active_record(db, employee, today)
    if open_record is not None:
        return {
            "status": open_record.status.value,
            "time_in": _dt_label(open_record.time_in),
            "time_out": None,
        }

    today_start = datetime.combine(today, time.min)
    tomorrow_start = today_start + timedelta(days=1)
    assignment_ids = [
        row.id
        for row in db.query(ShiftAssignment)
        .filter(
            ShiftAssignment.employee_id == employee.id,
            ShiftAssignment.work_date == today,
        )
        .all()
    ]
    query = db.query(AttendanceRecord).filter(
        AttendanceRecord.business_id == employee.business_id,
        AttendanceRecord.employee_id == employee.id,
    )
    if assignment_ids:
        query = query.filter(AttendanceRecord.shift_assignment_id.in_(assignment_ids))
    else:
        query = query.filter(
            AttendanceRecord.created_at >= today_start,
            AttendanceRecord.created_at < tomorrow_start,
        )
    from app.services.leave_requests import employee_on_approved_leave

    if employee_on_approved_leave(db, employee_id=employee.id, work_date=today):
        return {"status": "on_leave", "time_in": None, "time_out": None}

    record = query.order_by(AttendanceRecord.created_at.desc()).first()
    if record is None:
        return {"status": "not_started", "time_in": None, "time_out": None}
    return {
        "status": record.status.value,
        "time_in": _dt_label(record.time_in),
        "time_out": _dt_label(record.time_out),
    }


def _current_period(
    db: Session,
    business_id: uuid.UUID,
    *,
    as_of: date | None = None,
) -> tuple[date, date]:
    config = db.get(BusinessPayrollConfig, business_id)
    return resolve_pay_period(config, today=as_of)


def _payroll_status(period_start: date, period_end: date, today: date) -> str:
    if period_start <= today <= period_end:
        return "current"
    if period_end < today:
        return "completed"
    return "upcoming"


def _payroll_response(
    db: Session,
    employee: Employee,
    business: Business,
    *,
    as_of: date | None = None,
    history_limit: int = 0,
) -> dict:
    from app.services.pay_period import list_pay_periods

    config = db.get(BusinessPayrollConfig, business.id)
    today = as_of or date.today()
    period_start, period_end = resolve_pay_period(config, today=today)
    payslip = apply_adjustments_to_slip(
        _calculate_employee_payslip(db, employee, period_start, period_end),
        list_active_adjustments(
            db,
            business_id=employee.business_id,
            employee_id=employee.id,
            period_start=period_start,
            period_end=period_end,
        ),
    )
    rows = []
    for record in payslip["attendance_records"]:
        rows.append(
            {
                "date": record["date"],
                "status": record["status"],
                "daily_rate": _money(payslip["daily_rate"]),
                "earned": _money(float(record.get("earned") or 0)),
                "holiday_name": record["holiday_name"],
            }
        )
    payload = {
        "business_name": business.name,
        "business_branding": _branding_response(business),
        "pay_period_type": config.pay_period_type.value if config else "monthly",
        "period_start": payslip["period_start"],
        "period_end": payslip["period_end"],
        "pay_date": payslip["period_end"],
        "payroll_status": _payroll_status(period_start, period_end, date.today()),
        "summary": {
            **payslip,
            "pay_date": payslip["period_end"],
            "payroll_status": _payroll_status(period_start, period_end, date.today()),
            "hours_worked": round(
                float(payslip.get("worked_days") or 0) * 8.0
                + float(payslip.get("overtime_hours") or 0),
                2,
            ),
        },
        "rows": rows,
        "history": [],
    }
    if history_limit > 0:
        history = []
        for start, end in list_pay_periods(config, limit=history_limit, today=today):
            slip = apply_adjustments_to_slip(
                _calculate_employee_payslip(db, employee, start, end),
                list_active_adjustments(
                    db,
                    business_id=employee.business_id,
                    employee_id=employee.id,
                    period_start=start,
                    period_end=end,
                ),
            )
            history.append(
                {
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
                    "net_pay": slip["net_pay"],
                    "base_net_pay": slip["base_net_pay"],
                    "final_net_pay": slip["final_net_pay"],
                    "payroll_adjustments": slip["payroll_adjustments"],
                    "payroll_adjustments_total": slip["payroll_adjustments_total"],
                    "payroll_status": _payroll_status(start, end, date.today()),
                }
            )
        payload["history"] = history
    return payload


@router.get("/profile")
def profile(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    return _employee_profile_response(db, employee, business)


@router.post("/profile/image")
def update_profile_image(
    body: ProfileImageRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    image_data = validate_profile_image_data(body.image_data)

    employee.profile_image_url = image_data
    db.commit()
    db.refresh(employee)
    return _employee_profile_response(db, employee, business)


@router.delete("/profile/image")
def remove_profile_image(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    employee.profile_image_url = None
    db.commit()
    db.refresh(employee)
    return _employee_profile_response(db, employee, business)


@router.get("/dashboard")
def dashboard(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    today = business_today(business.timezone)
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business.timezone
    )
    schedule = _employee_schedule(
        db,
        employee,
        start_date=today,
        end_date=today + timedelta(days=7),
        today=today,
    )
    payroll = _payroll_response(db, employee, business)
    incomplete_rows = list_incomplete_for_employee(db, employee)
    latest_incomplete = incomplete_rows[0] if incomplete_rows else None
    return {
        "profile": _employee_profile_response(db, employee, business),
        "today_schedule": schedule[0] if schedule else None,
        "upcoming_schedules": schedule,
        "attendance_status": _today_attendance_status(
            db, employee, today, business_timezone=business.timezone
        ),
        "payroll_summary": payroll["summary"],
        "performance": _performance_summary(
            db, employee, business_timezone=business.timezone
        ),
        "incomplete_attendance_reminder": {
            "show": latest_incomplete is not None,
            "message": (
                "You forgot to clock out.\n"
                "Please submit your correct clock-out time."
            ),
            "count": len(incomplete_rows),
            "attendance_record_id": (
                str(latest_incomplete.id) if latest_incomplete else None
            ),
            "shift_assignment_id": (
                str(latest_incomplete.shift_assignment_id)
                if latest_incomplete and latest_incomplete.shift_assignment_id
                else None
            ),
        },
    }


@router.get("/schedule")
def schedule(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    start_date: date | None = None,
    end_date: date | None = None,
    active_only: bool = False,
):
    """Return shift assignments for the logged-in employee.

    When active_only=true, only today and upcoming shifts are returned.
    Completed and past assignments belong in shift-history.
    """
    employee, business = _current_employee(db, user)
    today = business_today(business.timezone)
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business.timezone
    )
    items = _employee_schedule(
        db,
        employee,
        start_date=start_date,
        end_date=end_date,
        today=today,
    )
    if active_only:
        items = [item for item in items if item["status"] in ("today", "upcoming")]
    return {"items": items}


@router.get("/shift-history")
def shift_history(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    today = business_today(business.timezone)
    return {
        "items": _shift_history_rows(
            db,
            employee,
            today=today,
            business_timezone=business.timezone,
        )
    }


@router.get("/payroll")
def payroll(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
    history_limit: Annotated[
        int,
        Query(
            ge=0,
            le=24,
            description="Include recent period summaries (live recompute, no stored runs)",
        ),
    ] = 6,
):
    employee, business = _current_employee(db, user)
    return _payroll_response(
        db,
        employee,
        business,
        as_of=as_of,
        history_limit=history_limit,
    )


@router.get("/payslip")
def payslip(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    employee, business = _current_employee(db, user)
    period_start, period_end = _current_period(db, business.id, as_of=as_of)
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
        "business_name": business.name,
        "business_branding": _branding_response(business),
        **slip,
        "pay_date": slip["period_end"],
        "payroll_status": _payroll_status(period_start, period_end, date.today()),
        "hours_worked": round(
            float(slip.get("worked_days") or 0) * 8.0
            + float(slip.get("overtime_hours") or 0),
            2,
        ),
    }


@router.get("/worksite", response_model=WorksiteResponse)
def worksite(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """Return the primary work-site coordinates and geofence radius for display."""
    _employee, business = _current_employee(db, user)
    return worksite_for_business(db, business.id)


def _face_required() -> None:
    raise HTTPException(
        status_code=403,
        detail={
            "code": "face_required",
            "message": (
                "Face recognition is required for attendance. "
                "Use the face clock-in/out flow."
            ),
        },
    )


@router.post("/attendance/clock-in", response_model=AttendanceActionResponse)
def clock_in(
    body: ClockLocationRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """GPS-only clock-in is disabled — face + GPS is required."""
    _current_employee(db, user)
    _face_required()


@router.post("/attendance/clock-in-face", response_model=AttendanceActionResponse)
async def clock_in_with_face(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    latitude: Annotated[float, Form(...)],
    longitude: Annotated[float, Form(...)],
    file: Annotated[UploadFile, File(..., description="Face image after blink/smile")],
    shift_assignment_id: Annotated[uuid.UUID | None, Form()] = None,
    liveness_gesture: Annotated[str | None, Form()] = None,
):
    """Clock in with GPS + client blink/smile gesture + server face match."""
    employee, business = _current_employee(db, user)
    gesture = (liveness_gesture or "").strip().lower()
    if gesture not in ("blink", "smile"):
        raise HTTPException(
            400,
            detail={
                "code": "liveness_required",
                "message": "Complete a blink or smile check before clocking in.",
            },
        )
    # Identity match first (logged-in employee gallery only); then record attendance.
    image_bytes = await file.read()
    score = verify_employee_face_match(
        db, employee, image_bytes, attendance_action="clock_in"
    )
    return clock_in_employee(
        db,
        employee,
        latitude=latitude,
        longitude=longitude,
        shift_assignment_id=shift_assignment_id,
        business_timezone=business.timezone,
        face_match_score=score,
        liveness_passed=True,
    )


@router.post("/attendance/clock-out", response_model=AttendanceActionResponse)
def clock_out(
    body: ClockLocationRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """GPS-only clock-out is disabled — face + GPS is required."""
    _current_employee(db, user)
    _face_required()


@router.post("/attendance/clock-out-face", response_model=AttendanceActionResponse)
async def clock_out_with_face(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    latitude: Annotated[float, Form(...)],
    longitude: Annotated[float, Form(...)],
    file: Annotated[UploadFile, File(..., description="Face image after blink/smile")],
    liveness_gesture: Annotated[str | None, Form()] = None,
):
    """Clock out with GPS + client blink/smile gesture + server face match."""
    employee, business = _current_employee(db, user)
    gesture = (liveness_gesture or "").strip().lower()
    if gesture not in ("blink", "smile"):
        raise HTTPException(
            400,
            detail={
                "code": "liveness_required",
                "message": "Complete a blink or smile check before clocking out.",
            },
        )
    score = verify_employee_face_match(
        db, employee, await file.read(), attendance_action="clock_out"
    )
    return clock_out_employee(
        db,
        employee,
        latitude=latitude,
        longitude=longitude,
        business_timezone=business.timezone,
        face_match_score=score,
        liveness_passed=True,
    )


@router.get("/face-status", response_model=FaceStatusResponse)
def employee_face_status(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, _business = _current_employee(db, user)
    return FaceStatusResponse(**face_status_for_employee(db, employee))


@router.post("/face-samples", response_model=FaceEnrollResponse, status_code=201)
async def employee_enroll_face_samples(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    files: Annotated[list[UploadFile], File(..., description="3–5 face images")],
):
    """Employee self-enroll — same embedding pipeline as owner face demo."""
    employee, _business = _current_employee(db, user)
    payloads: list[bytes] = []
    for upload in files:
        data = await upload.read()
        if not data:
            raise HTTPException(400, f"Empty file: {upload.filename or 'upload'}")
        payloads.append(data)
    result = enroll_face_sample_bytes(
        db, employee, payloads, enrolled_by=user.id
    )
    return FaceEnrollResponse(
        employee_id=result["employee_id"],
        face_registration_status=result["face_registration_status"],
        sample_count=result["sample_count"],
        model_version=result["model_version"],
        message=result["message"],
    )


@router.post("/face-registration")
def face_registration(
    body: FaceRegistrationRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """Legacy status endpoint. Prefer POST /employee/face-samples for enrollment."""
    employee, business = _current_employee(db, user)
    status = face_status_for_employee(db, employee)
    if status["sample_count"] < 1 or employee.face_registration_status != "completed":
        raise HTTPException(
            status_code=400,
            detail={
                "code": "face_enrollment_required",
                "message": (
                    "Upload face samples via POST /employee/face-samples. "
                    "Skipping face registration is not allowed."
                ),
            },
        )
    return _employee_profile_response(db, employee, business)


@router.get("/payslip/pdf")
def payslip_pdf(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    period_start, period_end = _current_period(db, business.id)
    data = {
        "business_name": business.name,
        **apply_adjustments_to_slip(
            _calculate_employee_payslip(db, employee, period_start, period_end),
            list_active_adjustments(
                db,
                business_id=employee.business_id,
                employee_id=employee.id,
                period_start=period_start,
                period_end=period_end,
            ),
        ),
    }
    pdf = _simple_payslip_pdf(data)
    filename = f"{employee.full_name.lower().replace(' ', '-')}-payslip.pdf"
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _pdf_escape(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def _simple_payslip_pdf(data: dict) -> bytes:
    lines = [
        "SALARY SLIP",
        data["business_name"],
        f"Employee: {data['employee_name']}",
        f"Position: {data.get('position_title') or 'Employee'}",
        f"Period: {data['period_start']} to {data['period_end']}",
        f"Worked days: {data['worked_days']}",
        f"Daily rate: PHP {_money(data['daily_rate']):,.2f}",
        f"Basic salary: PHP {_money(data['daily_rate'] * data['worked_days']):,.2f}",
        f"Overtime pay: PHP {_money(data['overtime_pay']):,.2f}",
        f"Holiday pay: PHP {_money(data['holiday_pay']):,.2f}",
        f"Rest day premium: PHP {_money(data.get('rest_day_pay', 0)):,.2f}",
        f"Gross pay: PHP {_money(data['gross_pay']):,.2f}",
        f"Deductions: PHP {_money(data['deductions']):,.2f}",
        f"Base net pay: PHP {_money(data.get('base_net_pay', data['net_pay'])):,.2f}",
    ]
    for adj in data.get("payroll_adjustments") or []:
        sign = "-" if adj.get("kind") == "deduction" else "+"
        lines.append(
            f"{adj.get('display_name')}: {sign}PHP {_money(adj.get('amount', 0)):,.2f}"
        )
    lines.append(
        f"Final net pay: PHP {_money(data.get('final_net_pay', data['net_pay'])):,.2f}"
    )
    # Keep stream builder expecting a flat list.
    stream_lines = ["BT", "/F1 12 Tf", "72 760 Td"]
    for index, line in enumerate(lines):
        if index:
            stream_lines.append("0 -22 Td")
        stream_lines.append(f"({_pdf_escape(line)}) Tj")
    stream_lines.append("ET")
    stream = "\n".join(stream_lines).encode("latin-1", errors="replace")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode("ascii") + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    buffer = BytesIO()
    buffer.write(b"%PDF-1.4\n")
    offsets = [0]
    for number, obj in enumerate(objects, start=1):
        offsets.append(buffer.tell())
        buffer.write(f"{number} 0 obj\n".encode("ascii"))
        buffer.write(obj)
        buffer.write(b"\nendobj\n")
    xref_start = buffer.tell()
    buffer.write(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    buffer.write(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        buffer.write(f"{offset:010d} 00000 n \n".encode("ascii"))
    buffer.write(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_start}\n%%EOF\n".encode("ascii")
    )
    return buffer.getvalue()
