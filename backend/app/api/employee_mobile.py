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
    Request,
    Response,
    UploadFile,
)
from pydantic import BaseModel

from app.schemas.profile_image import ProfileImageRequest
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.api.owner_reports import _calculate_employee_payslip
from app.services.payroll_engine import hours_worked_from_slip
from app.services.payroll_snapshot import load_period_payslip, require_loaded_slip
from app.core.deps import get_current_user
from app.core.profile_image import validate_profile_image_data
from app.core.timezone import business_now, business_today
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
    _list_assignment_candidates,
    _records_by_assignment,
    clock_in_employee,
    clock_out_employee,
    select_open_time_in_assignment,
    verify_employee_face_match,
    worksite_for_business,
)
from app.services.demo_tenant import (
    business_is_demo,
    verify_demo_seeded_identity,
)
from app.services.missing_clock_out import (
    ensure_incomplete_for_employee,
    list_incomplete_for_employee,
)
from app.services.face_enrollment import enroll_face_sample_bytes, face_status_for_employee
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.services.employee_pay import resolve_employee_pay
from app.services.payroll_engine import resolve_overtime_calculation_method
from app.schemas.face import FaceEnrollResponse, FaceStatusResponse
from app.schemas.legal_consent import (
    LegalConsentAcceptRequest,
    LegalConsentStatusResponse,
    LegalConsentWithdrawRequest,
)
from app.services.legal_consent import (
    consent_status_payload,
    record_acceptances,
    require_biometric_consent,
    require_legal_consent,
    withdraw_biometric_consent,
)

router = APIRouter(prefix="/employee", tags=["employee-mobile"])


class FaceRegistrationRequest(BaseModel):
    status: Literal["completed"]


def _current_employee(
    db: Session,
    user: User,
    *,
    require_recovery_email: bool = True,
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
    from app.services.employee_password_reset import needs_recovery_email

    if require_recovery_email and needs_recovery_email(employee):
        raise HTTPException(
            403,
            detail={
                "code": "recovery_email_required",
                "message": "Register a recovery email to finish account setup.",
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


def _business_owner_email(db: Session, business: Business) -> str | None:
    """Registered owner email from business registration (not a Business.email field)."""
    if business.registration_id is None:
        return None
    registration = db.get(BusinessRegistration, business.registration_id)
    if registration is None:
        return None
    email = (registration.owner_email or "").strip()
    return email or None


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
        "recovery_email": employee.recovery_email,
        "profile_image_url": employee.profile_image_url,
        "hire_date": employee.hire_date.isoformat() if employee.hire_date else None,
        "status": employee.status.value,
        "business_name": business.name,
        "business_code": business.business_code,
        "business_type": business.business_type,
        "owner_name": _business_owner_name(db, business),
        "owner_email": _business_owner_email(db, business),
        "face_registration_status": employee.face_registration_status,
        "face_registered_at": _dt_label(employee.face_registered_at),
        "face_registration_skipped_at": _dt_label(
            employee.face_registration_skipped_at
        ),
        "branding": _branding_response(business),
        "timezone": business.timezone,
    }


def _employee_attendance_policy_payload(policy: BusinessAttendancePolicy | None) -> dict | None:
    if policy is None:
        return None
    return {
        "early_clock_in_minutes": policy.early_clock_in_minutes,
        "on_time_grace_minutes": policy.on_time_grace_minutes,
        "half_day_threshold_minutes": policy.half_day_threshold_minutes,
        "absent_threshold_minutes": policy.absent_threshold_minutes,
        "absent_threshold_percent": getattr(policy, "absent_threshold_percent", None),
        "half_day_threshold_percent": getattr(policy, "half_day_threshold_percent", None),
        "early_out_deduction_enabled": bool(policy.early_out_deduction_enabled),
        "early_out_deduction_per_minute": (
            float(policy.early_out_deduction_per_minute)
            if policy.early_out_deduction_enabled
            else None
        ),
        "overtime_minimum_minutes": policy.overtime_minimum_minutes,
        "maximum_overtime_minutes": getattr(policy, "maximum_overtime_minutes", None),
        "missing_clock_out_policy": policy.missing_clock_out_policy.value,
        "attendance_based_salary_enabled": bool(policy.attendance_based_salary_enabled),
        "breaktime_is_paid": bool(getattr(policy, "breaktime_is_paid", False)),
    }


def _employee_payroll_policy_payload(config: BusinessPayrollConfig | None) -> dict | None:
    if config is None:
        return None
    overtime_enabled = bool(config.overtime_enabled)
    method = resolve_overtime_calculation_method(config)
    late_enabled = bool(config.late_deduction_enabled)
    return {
        "late_deduction_enabled": late_enabled,
        "late_deduction_per_minute": (
            float(config.late_deduction_per_minute) if late_enabled else None
        ),
        "overtime_enabled": overtime_enabled,
        "overtime_calculation_method": method if overtime_enabled else None,
        "overtime_per_minute": (
            float(config.overtime_per_minute)
            if overtime_enabled and method == "flat_per_minute"
            else None
        ),
        "enable_late_overtime_balancing": bool(
            overtime_enabled and getattr(config, "enable_late_overtime_balancing", False)
        ),
        "overtime_approval_required": bool(
            overtime_enabled and getattr(config, "overtime_approval_required", False)
        ),
    }


def _employee_rest_day_policy_payload(policy: BusinessRestDayPolicy | None) -> dict | None:
    if policy is None:
        return None
    return {
        "rest_day_premium_percent": float(policy.rest_day_premium_percent),
    }


def _employee_pay_policy_payload(employee: Employee, position: Position | None) -> dict:
    resolved = resolve_employee_pay(employee, position=position)
    basis = resolved.pay_basis.value if resolved.pay_basis is not None else None
    return {
        "pay_basis": basis,
        "daily_rate": resolved.daily_rate,
        "hourly_rate": resolved.hourly_rate,
        "monthly_salary": resolved.monthly_salary,
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
    if record is not None and (
        record.time_out is not None
        or record.status
        in (
            AttendanceStatus.complete,
            AttendanceStatus.absent,
            AttendanceStatus.incomplete,
        )
    ):
        return "completed"
    if assignment.work_date < today:
        # Overnight still in progress after midnight stays actionable.
        if record is not None and record.time_out is None and record.status in (
            AttendanceStatus.in_progress,
            AttendanceStatus.late,
        ):
            return "today"
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


def _snapshot_overtime_minutes(row: dict) -> float:
    """OT minutes already frozen on a payslip attendance row (no recalculation)."""
    ot = row.get("ot")
    if isinstance(ot, dict) and ot.get("worked_ot_minutes") is not None:
        return round(float(ot["worked_ot_minutes"]), 2)
    return 0.0


def _index_snapshot_attendance_rows(slip: dict | None) -> dict[str, dict]:
    """Map shift_assignment_id (preferred) and date to frozen attendance rows."""
    by_assignment: dict[str, dict] = {}
    if not isinstance(slip, dict):
        return by_assignment
    for row in slip.get("attendance_records") or []:
        if not isinstance(row, dict):
            continue
        assignment_id = row.get("shift_assignment_id")
        if assignment_id:
            by_assignment[str(assignment_id)] = row
    return by_assignment


def _overlay_shift_history_with_finalized_snapshots(
    db: Session,
    employee: Employee,
    items: list[dict],
) -> list[dict]:
    """Replace live punch fields with frozen payslip attendance when finalized.

    Uses existing Phase 1 snapshot loaders only — never calls
    ``_calculate_employee_payslip``. Open (unfinalized) dates stay live.
    """
    from app.services.payroll_snapshot import (
        find_snapshot_run,
        load_period_payslip,
        payslips_for_run,
        snapshot_payslip_dict,
    )

    if not items:
        return items

    run_for_date: dict[date, object | None] = {}
    attendance_by_run: dict[object, dict[str, dict]] = {}
    live_by_as_of: dict[date, dict[str, dict]] = {}

    def _run_for(work_date: date):
        if work_date not in run_for_date:
            run_for_date[work_date] = find_snapshot_run(
                db,
                business_id=employee.business_id,
                as_of=work_date,
            )
        return run_for_date[work_date]

    def _attendance_index(run) -> dict[str, dict]:
        run_id = getattr(run, "id", run)
        if run_id not in attendance_by_run:
            matched: dict | None = None
            for payslip_row in payslips_for_run(db, run):
                frozen = snapshot_payslip_dict(payslip_row)
                if frozen is None:
                    continue
                if getattr(payslip_row, "employee_id", None) == employee.id:
                    matched = frozen
                    break
                if str(frozen.get("employee_id") or "") == str(employee.id):
                    matched = frozen
                    break
            attendance_by_run[run_id] = _index_snapshot_attendance_rows(matched)
        return attendance_by_run[run_id]

    def _live_index(work_date: date) -> dict[str, dict]:
        if work_date not in live_by_as_of:
            loaded = load_period_payslip(
                db,
                employee,
                as_of=work_date,
                calculate_payslip=_calculate_employee_payslip,
            )
            slip = loaded.slip if loaded is not None else None
            live_by_as_of[work_date] = _index_snapshot_attendance_rows(slip)
        return live_by_as_of[work_date]

    def _apply_pay_fields(item: dict, snap_row: dict, *, frozen: bool) -> None:
        if frozen:
            item["time_in"] = snap_row.get("time_in")
            item["time_out"] = snap_row.get("time_out")
            if snap_row.get("status") is not None:
                item["status"] = snap_row.get("status")
            if snap_row.get("shift_name"):
                item["shift_name"] = snap_row.get("shift_name")
            item["holiday_name"] = snap_row.get("holiday_name")
            item["overtime_minutes"] = _snapshot_overtime_minutes(snap_row)
        else:
            if snap_row.get("overtime_minutes") is not None:
                item["overtime_minutes"] = snap_row.get("overtime_minutes")
            elif snap_row.get("ot"):
                item["overtime_minutes"] = _snapshot_overtime_minutes(snap_row)
            # Live payslip names an unworked credit holiday_paid. Do not
            # overwrite other live statuses.
            if snap_row.get("status") == "holiday_paid":
                item["status"] = "holiday_paid"
        # Authoritative shift pay projection (live or frozen).
        for key in (
            "scheduled_start",
            "scheduled_end",
            "worked_minutes",
            "pay_basis_used",
            "rate_used",
            "expected_salary_pay",
            "earned",
            "late_minutes",
            "late_deduction",
            "undertime_minutes",
            "undertime_deduction",
            "overtime_pay",
            "rest_day_premium_pay",
            "shift_deductions",
            "shift_net",
            "holiday_pay",
            "holiday_included_in_shift_net",
            "day_holiday_pay",
            "day_entitlement",
            "day_rest_day_pay",
            "reconciled_shift_total",
            "reconciled_day_total",
            "historical_rate_required",
            "daily_rate_conflict",
            "payroll_status",
            "is_rest_day",
        ):
            if key in snap_row:
                item[key] = snap_row.get(key)
        if snap_row.get("ot") is not None:
            item["ot"] = snap_row.get("ot")

    for item in items:
        raw_date = item.get("date")
        if not raw_date:
            continue
        try:
            work_date = date.fromisoformat(str(raw_date))
        except ValueError:
            continue
        assignment_key = str(item.get("assignment_id") or "")
        run = _run_for(work_date)
        if run is not None:
            snap_row = _attendance_index(run).get(assignment_key)
            if snap_row is not None:
                _apply_pay_fields(item, snap_row, frozen=True)
            continue
        live_row = _live_index(work_date).get(assignment_key)
        if live_row is not None:
            _apply_pay_fields(item, live_row, frozen=False)
    return items


def _append_today_unworked_holiday_shifts(
    db: Session,
    employee: Employee,
    deduped: list[tuple[ShiftAssignment, Shift, AttendanceRecord | None]],
    seen_assignments: set[uuid.UUID],
    *,
    today: date,
    holidays: dict[date, Holiday],
    business_timezone: str | None,
) -> None:
    """Include today's ended shifts that payroll would credit as unworked holiday.

    Future shifts are not added. No attendance row is created.
    Ordinary same-day absences are added separately once their own
    scheduled end + grace has passed.
    """
    from app.core.timezone import business_now
    from app.models.attendance_policy import BusinessAttendancePolicy
    from app.models.payroll import BusinessPayrollConfig
    from app.services.holiday_pay import (
        resolve_holiday_policy,
        resolve_holiday_rules_mode,
    )
    from app.services.leave_requests import employee_on_payroll_active_leave
    from app.services.missing_clock_out import is_past_clock_out_deadline

    holiday = holidays.get(today)
    if holiday is None:
        return
    config = db.get(BusinessPayrollConfig, employee.business_id)
    policy = resolve_holiday_policy(
        holiday=holiday,
        mode=resolve_holiday_rules_mode(config),
    )
    if policy is None or not policy.pay_if_not_worked:
        return

    att_policy = db.get(BusinessAttendancePolicy, employee.business_id)
    grace = getattr(att_policy, "on_time_grace_minutes", None)
    grace_minutes = int(grace) if grace is not None else 0
    now_local = business_now(business_timezone)

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
            ShiftAssignment.work_date == today,
            Shift.business_id == employee.business_id,
        )
        .all()
    )
    for assignment, shift, record in rows:
        if assignment.id in seen_assignments:
            continue
        if record is not None and (
            record.time_in is not None or record.status == AttendanceStatus.on_leave
        ):
            continue
        if employee_on_payroll_active_leave(
            db, employee_id=employee.id, work_date=today
        ):
            continue
        if not is_past_clock_out_deadline(
            now_local=now_local,
            work_date=today,
            shift=shift,
            grace_minutes=grace_minutes,
        ):
            continue
        seen_assignments.add(assignment.id)
        deduped.append((assignment, shift, record))


def _append_today_elapsed_absences(
    db: Session,
    employee: Employee,
    deduped: list[tuple[ShiftAssignment, Shift, AttendanceRecord | None]],
    seen_assignments: set[uuid.UUID],
    *,
    today: date,
    business_timezone: str | None,
) -> None:
    """Include today's scheduled shifts with no attendance once they have ended.

    Visibility only. Uses the same scheduled-end + on-time grace deadline as
    unworked holiday history. Does not create an AttendanceRecord. Assignments
    already included (punches, leave, or a paid unworked holiday) are skipped.
    Each shift is judged on its own end time. Future dates are not queried.
    """
    from app.core.timezone import business_now
    from app.models.attendance_policy import BusinessAttendancePolicy
    from app.services.leave_requests import employee_on_payroll_active_leave
    from app.services.missing_clock_out import is_past_clock_out_deadline

    att_policy = db.get(BusinessAttendancePolicy, employee.business_id)
    grace = getattr(att_policy, "on_time_grace_minutes", None)
    grace_minutes = int(grace) if grace is not None else 0
    now_local = business_now(business_timezone)

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
            ShiftAssignment.work_date == today,
            Shift.business_id == employee.business_id,
        )
        .all()
    )
    for assignment, shift, record in rows:
        if assignment.id in seen_assignments:
            continue
        if assignment.work_date != today:
            continue
        if record is not None:
            continue
        if employee_on_payroll_active_leave(
            db, employee_id=employee.id, work_date=today
        ):
            continue
        if not is_past_clock_out_deadline(
            now_local=now_local,
            work_date=today,
            shift=shift,
            grace_minutes=grace_minutes,
        ):
            continue
        seen_assignments.add(assignment.id)
        deduped.append((assignment, shift, record))


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
    - today's assignment with no AttendanceRecord once that shift's scheduled
      end plus the on-time grace period has passed (absent until a payslip
      overlay marks a paid unworked holiday)

    When a work date falls in a Phase 1 finalized payroll period, punch and
    OT fields are replaced from that employee's frozen payslip snapshot so
    history matches the employee payslip. Unfinalized dates stay live.
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

    _append_today_unworked_holiday_shifts(
        db,
        employee,
        deduped,
        seen_assignments,
        today=work_today,
        holidays=holidays,
        business_timezone=business_timezone,
    )
    _append_today_elapsed_absences(
        db,
        employee,
        deduped,
        seen_assignments,
        today=work_today,
        business_timezone=business_timezone,
    )

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
    return _overlay_shift_history_with_finalized_snapshots(db, employee, items)

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
        # Incomplete and approved leave are excluded from attendance metrics.
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


def _attendance_status_payload(
    *,
    status: str,
    time_in: str | None = None,
    time_out: str | None = None,
    shift_assignment_id: str | None = None,
    time_in_available: bool = False,
    timezone: str | None = None,
) -> dict:
    return {
        "status": status,
        "time_in": time_in,
        "time_out": time_out,
        "shift_assignment_id": shift_assignment_id,
        "time_in_available": time_in_available,
        "timezone": timezone,
    }


def _today_attendance_status(
    db: Session,
    employee: Employee,
    today: date,
    *,
    business_timezone: str | None = None,
    now_local: datetime | None = None,
) -> dict:
    """Attendance state for dashboard / Time In hub, evaluated per shift.

    Open sessions use the same lookup as Time Out so "Ready to Time Out"
    never disagrees with whether Time Out can find today's record.
    After Time Out from one shift, status resets to not_started for the next
    scheduled shift instead of treating the calendar day as finished.

    Time In availability requires business-local now < scheduled_end. Ended
    assignments stay visible on the schedule but are not Time In targets.
    """
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business_timezone
    )
    now_local = (
        business_now(business_timezone).replace(tzinfo=None)
        if now_local is None
        else (now_local.replace(tzinfo=None) if now_local.tzinfo else now_local)
    )
    open_record = _active_record(db, employee, today)
    if open_record is not None:
        return _attendance_status_payload(
            status=open_record.status.value,
            time_in=_dt_label(open_record.time_in),
            shift_assignment_id=(
                str(open_record.shift_assignment_id)
                if open_record.shift_assignment_id
                else None
            ),
            time_in_available=False,
            timezone=business_timezone,
        )

    from app.services.leave_requests import employee_on_approved_leave

    if employee_on_approved_leave(db, employee_id=employee.id, work_date=today):
        return _attendance_status_payload(
            status="on_leave",
            timezone=business_timezone,
        )

    rows = _list_assignment_candidates(db, employee, today)
    if not rows:
        today_start = datetime.combine(today, time.min)
        tomorrow_start = today_start + timedelta(days=1)
        record = (
            db.query(AttendanceRecord)
            .filter(
                AttendanceRecord.business_id == employee.business_id,
                AttendanceRecord.employee_id == employee.id,
                AttendanceRecord.created_at >= today_start,
                AttendanceRecord.created_at < tomorrow_start,
            )
            .order_by(AttendanceRecord.created_at.desc())
            .first()
        )
        if record is None:
            return _attendance_status_payload(
                status="not_started",
                timezone=business_timezone,
            )
        return _attendance_status_payload(
            status=record.status.value,
            time_in=_dt_label(record.time_in),
            time_out=_dt_label(record.time_out),
            shift_assignment_id=(
                str(record.shift_assignment_id) if record.shift_assignment_id else None
            ),
            timezone=business_timezone,
        )

    records = _records_by_assignment(
        db,
        employee_id=employee.id,
        assignment_ids=[assignment.id for assignment, _shift in rows],
    )
    remaining = select_open_time_in_assignment(rows, records, now_local)
    if remaining is not None:
        next_assignment, _next_shift = remaining
        return _attendance_status_payload(
            status="not_started",
            shift_assignment_id=str(next_assignment.id),
            time_in_available=True,
            timezone=business_timezone,
        )

    latest = None
    for assignment, _shift in reversed(rows):
        record = records.get(assignment.id)
        if record is not None:
            latest = record
            break
    if latest is None:
        return _attendance_status_payload(
            status="not_started",
            timezone=business_timezone,
        )
    return _attendance_status_payload(
        status=latest.status.value,
        time_in=_dt_label(latest.time_in),
        time_out=_dt_label(latest.time_out),
        shift_assignment_id=(
            str(latest.shift_assignment_id) if latest.shift_assignment_id else None
        ),
        timezone=business_timezone,
    )


def _payroll_status(period_start: date, period_end: date, today: date) -> str:
    if period_start <= today <= period_end:
        return "current"
    if period_end < today:
        return "completed"
    return "upcoming"


def _empty_payroll_summary(loaded, *, payroll_status: str) -> dict:
    period_start = loaded.period_start.isoformat()
    period_end = loaded.period_end.isoformat()
    return {
        "employee_id": "",
        "employee_name": "",
        "period_start": period_start,
        "period_end": period_end,
        "pay_date": period_end,
        "payroll_status": payroll_status,
        "daily_rate": 0,
        "worked_days": 0,
        "hours_worked": 0,
        "regular_pay": 0,
        "leave_pay": 0,
        "overtime_hours": 0,
        "overtime_pay": 0,
        "holiday_pay": 0,
        "rest_day_pay": 0,
        "deductions": 0,
        "late_deductions": 0,
        "undertime_deductions": 0,
        "absent_days": 0,
        "gross_pay": 0,
        "net_pay": 0,
        "final_net_pay": 0,
        "payroll_adjustments": [],
        "payroll_adjustments_total": 0,
        "attendance_records": [],
    }


def _payroll_response(
    db: Session,
    employee: Employee,
    business: Business,
    *,
    as_of: date | None = None,
    history_limit: int = 0,
    require_slip: bool = True,
) -> dict:
    from app.services.pay_period import list_pay_periods

    config = db.get(BusinessPayrollConfig, business.id)
    today = as_of or date.today()
    loaded = load_period_payslip(
        db,
        employee,
        as_of=today,
        calculate_payslip=_calculate_employee_payslip,
    )
    if loaded.slip is None and not require_slip:
        status = _payroll_status(
            loaded.period_start, loaded.period_end, date.today()
        )
        empty = _empty_payroll_summary(loaded, payroll_status=status)
        return {
            "business_name": business.name,
            "business_branding": _branding_response(business),
            "pay_period_type": config.pay_period_type.value if config else "monthly",
            "period_start": empty["period_start"],
            "period_end": empty["period_end"],
            "pay_date": empty["pay_date"],
            "payroll_status": status,
            "summary": empty,
            "rows": [],
            "history": [],
        }
    payslip = require_loaded_slip(loaded)
    period_start, period_end = loaded.period_start, loaded.period_end
    rows = []
    for record in payslip["attendance_records"]:
        historical_required = bool(record.get("historical_rate_required"))
        # Day rate from the payslip row (completion stamp / expected salary).
        # Do not reuse slip-level current daily_rate for unresolved historical days.
        # Shift display uses the engine's stamp rate and shift_net. ``earned``
        # stays available for older clients and is not the employee-facing amount.
        if historical_required:
            day_rate = None
            earned_value = None
            pay_basis_used = None
            rate_used = None
            shift_net = None
        else:
            day_rate = record.get("expected_salary_pay")
            if day_rate is None:
                day_rate = payslip["daily_rate"]
            earned_raw = record.get("earned")
            earned_value = (
                None if earned_raw is None else _money(float(earned_raw))
            )
            pay_basis_used = record.get("pay_basis_used")
            raw_rate = record.get("rate_used")
            rate_used = None if raw_rate is None else _money(float(raw_rate))
            raw_net = record.get("shift_net")
            shift_net = None if raw_net is None else _money(float(raw_net))
        rows.append(
            {
                "date": record["date"],
                "status": record["status"],
                "daily_rate": (
                    None if day_rate is None else _money(float(day_rate or 0))
                ),
                "earned": earned_value,
                "pay_basis_used": pay_basis_used,
                "rate_used": rate_used,
                "shift_net": shift_net,
                "holiday_name": record["holiday_name"],
                "historical_rate_required": historical_required,
                "payroll_status": record.get("payroll_status"),
                "attendance_record_id": record.get("attendance_record_id"),
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
            "hours_worked": hours_worked_from_slip(payslip),
        },
        "rows": rows,
        "history": [],
    }
    if history_limit > 0:
        history = []
        seen: set[tuple[str, str]] = set()
        for start, _end in list_pay_periods(config, limit=history_limit, today=today):
            loaded_history = load_period_payslip(
                db,
                employee,
                as_of=start,
                calculate_payslip=_calculate_employee_payslip,
            )
            slip = loaded_history.slip
            if slip is None:
                continue
            key = (str(slip["period_start"]), str(slip["period_end"]))
            if key in seen:
                continue
            seen.add(key)
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
                    "hours_worked": hours_worked_from_slip(slip),
                    "late_deductions": slip["late_deductions"],
                    "undertime_deductions": slip["undertime_deductions"],
                    "overtime_pay": slip["overtime_pay"],
                    "overtime_hours": slip["overtime_hours"],
                    "regular_pay": slip.get("regular_pay"),
                    "leave_pay": slip.get("leave_pay", 0),
                    "gross_pay": slip["gross_pay"],
                    "deductions": slip["deductions"],
                    "net_pay": slip["net_pay"],
                    "base_net_pay": slip["base_net_pay"],
                    "final_net_pay": slip["final_net_pay"],
                    "payroll_adjustments": slip["payroll_adjustments"],
                    "payroll_adjustments_total": slip["payroll_adjustments_total"],
                    "payroll_status": _payroll_status(
                        loaded_history.period_start,
                        loaded_history.period_end,
                        date.today(),
                    ),
                }
            )
        payload["history"] = history
    return payload


class RecoveryEmailRequest(BaseModel):
    email: str


@router.post("/recovery-email")
def register_recovery_email(
    body: RecoveryEmailRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """Save this employee's own recovery email. Does not change the password."""
    from app.services.employee_password_reset import (
        needs_recovery_email,
        save_recovery_email,
    )

    employee, business = _current_employee(
        db, user, require_recovery_email=False
    )
    try:
        saved = save_recovery_email(employee, body.email)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    db.commit()
    db.refresh(employee)
    return {
        "recovery_email": saved,
        "needs_recovery_email": needs_recovery_email(employee),
    }


@router.get("/profile")
def profile(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    return _employee_profile_response(db, employee, business)


@router.get("/workplace-policies")
def workplace_policies(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """Read-only owner-configured attendance and payroll rules for this employee."""
    employee, business = _current_employee(db, user)
    attendance = db.get(BusinessAttendancePolicy, business.id)
    payroll = db.get(BusinessPayrollConfig, business.id)
    rest_day = db.get(BusinessRestDayPolicy, business.id)
    position = (
        db.get(Position, employee.position_id) if employee.position_id is not None else None
    )
    return {
        "business_name": business.name,
        "attendance": _employee_attendance_policy_payload(attendance),
        "payroll": _employee_payroll_policy_payload(payroll),
        "rest_day": _employee_rest_day_policy_payload(rest_day),
        "your_pay": _employee_pay_policy_payload(employee, position),
    }


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
        start_date=today - timedelta(days=1),
        end_date=today + timedelta(days=7),
        today=today,
    )
    payroll = _payroll_response(db, employee, business, require_slip=False)
    incomplete_rows = list_incomplete_for_employee(db, employee)
    latest_incomplete = incomplete_rows[0] if incomplete_rows else None
    attendance_status = _today_attendance_status(
        db, employee, today, business_timezone=business.timezone
    )
    target_assignment_id = attendance_status.get("shift_assignment_id")
    today_schedule = None
    if target_assignment_id:
        today_schedule = next(
            (
                item
                for item in schedule
                if item.get("assignment_id") == target_assignment_id
            ),
            None,
        )
    if today_schedule is None:
        today_items = [
            item for item in schedule if item.get("work_date") == today.isoformat()
        ]
        today_schedule = next(
            (item for item in today_items if item.get("status") == "today"),
            today_items[0] if today_items else (schedule[0] if schedule else None),
        )
    return {
        "profile": _employee_profile_response(db, employee, business),
        "today_schedule": today_schedule,
        "upcoming_schedules": schedule,
        "attendance_status": attendance_status,
        "payroll_summary": payroll["summary"],
        "performance": _performance_summary(
            db, employee, business_timezone=business.timezone
        ),
        "incomplete_attendance_reminder": {
            "show": latest_incomplete is not None,
            "message": (
                "You forgot to time out.\n"
                "Please submit your correct time-out time."
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
            description="Include recent period summaries",
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
    loaded = load_period_payslip(
        db,
        employee,
        as_of=as_of,
        calculate_payslip=_calculate_employee_payslip,
    )
    slip = require_loaded_slip(loaded)
    return {
        "business_name": business.name,
        "business_branding": _branding_response(business),
        **slip,
        "pay_date": slip["period_end"],
        "payroll_status": _payroll_status(
            loaded.period_start, loaded.period_end, date.today()
        ),
        "hours_worked": hours_worked_from_slip(slip),
    }


@router.get("/consent/status", response_model=LegalConsentStatusResponse)
def employee_consent_status(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    return LegalConsentStatusResponse(**consent_status_payload(db, employee, business))


@router.post("/consent/accept", response_model=LegalConsentStatusResponse)
def employee_accept_consent(
    body: LegalConsentAcceptRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    if not body.accepted:
        raise HTTPException(400, "Consent must be accepted to continue")
    employee, business = _current_employee(db, user)
    record_acceptances(
        db,
        employee=employee,
        business=business,
        user_id=user.id,
        types=body.types,
        versions=body.versions,
        client=body.client,
        adult_acknowledged=body.adult_acknowledged,
        request=request,
    )
    db.commit()
    return LegalConsentStatusResponse(**consent_status_payload(db, employee, business))


@router.post("/consent/withdraw-biometric", response_model=LegalConsentStatusResponse)
def employee_withdraw_biometric(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    body: LegalConsentWithdrawRequest | None = None,
):
    employee, business = _current_employee(db, user)
    withdraw_biometric_consent(
        db,
        employee=employee,
        business=business,
        actor_user_id=user.id,
        client=(body.client if body else "mobile"),
        request=request,
    )
    db.commit()
    return LegalConsentStatusResponse(**consent_status_payload(db, employee, business))


@router.post("/permissions-onboarding/complete")
def complete_permissions_onboarding(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    """Mark account-level permissions onboarding complete for the authenticated employee.

    Does not claim OS permissions were granted. Uses the auth token identity only.
    """
    employee, _business = _current_employee(db, user)
    if employee.permissions_onboarding_completed_at is None:
        employee.permissions_onboarding_completed_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(employee)
    return {
        "permissions_onboarding_completed": True,
        "completed_at": employee.permissions_onboarding_completed_at.isoformat()
        if employee.permissions_onboarding_completed_at
        else None,
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
                "Use the face Time In / Time Out flow."
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
    file: Annotated[UploadFile | None, File()] = None,
    shift_assignment_id: Annotated[uuid.UUID | None, Form()] = None,
    liveness_gesture: Annotated[str | None, Form()] = None,
):
    """Time in with GPS + client blink/smile gesture + server face match.

    Demo tenants (`business.is_demo`) ignore the live probe and client GPS;
    they resolve the seeded demo identity and the fictional worksite instead.
    """
    employee, business = _current_employee(db, user)
    if business_is_demo(business):
        score = verify_demo_seeded_identity(db, employee, business)
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

    require_legal_consent(db, employee, business)
    require_biometric_consent(db, employee, business)
    gesture = (liveness_gesture or "").strip().lower()
    if gesture not in ("blink", "smile"):
        raise HTTPException(
            400,
            detail={
                "code": "liveness_required",
                "message": "Complete a blink or smile check before timing in.",
            },
        )
    if file is None:
        raise HTTPException(
            400,
            detail={
                "code": "face_required",
                "message": "A face image is required for attendance.",
            },
        )
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
    file: Annotated[UploadFile | None, File()] = None,
    liveness_gesture: Annotated[str | None, Form()] = None,
):
    """Clock out with GPS + client blink/smile gesture + server face match."""
    employee, business = _current_employee(db, user)
    if business_is_demo(business):
        score = verify_demo_seeded_identity(db, employee, business)
        return clock_out_employee(
            db,
            employee,
            latitude=latitude,
            longitude=longitude,
            business_timezone=business.timezone,
            face_match_score=score,
            liveness_passed=True,
        )

    require_legal_consent(db, employee, business)
    require_biometric_consent(db, employee, business)
    gesture = (liveness_gesture or "").strip().lower()
    if gesture not in ("blink", "smile"):
        raise HTTPException(
            400,
            detail={
                "code": "liveness_required",
                "message": "Complete a blink or smile check before timing out.",
            },
        )
    if file is None:
        raise HTTPException(
            400,
            detail={
                "code": "face_required",
                "message": "A face image is required for attendance.",
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
    request: Request,
):
    """Employee self-enroll — same embedding pipeline as owner face demo."""
    employee, business = _current_employee(db, user)
    require_legal_consent(db, employee, business)
    require_biometric_consent(db, employee, business)
    payloads: list[bytes] = []
    for upload in files:
        data = await upload.read()
        if not data:
            raise HTTPException(400, f"Empty file: {upload.filename or 'upload'}")
        payloads.append(data)
    result = enroll_face_sample_bytes(
        db, employee, payloads, enrolled_by=user.id
    )
    from app.core.request_meta import audit_meta_from_request
    from app.services.activity_logger import add_log

    meta = audit_meta_from_request(request)
    add_log(
        db,
        user.id,
        "face_enrolled",
        f"{employee.full_name} enrolled face samples",
        platform=meta.get("platform"),
        device=meta.get("device"),
        ip_address=meta.get("ip_address"),
    )
    db.commit()
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
    as_of: Annotated[
        date | None,
        Query(description="Resolve the pay period containing this date (YYYY-MM-DD)"),
    ] = None,
):
    employee, business = _current_employee(db, user)
    loaded = load_period_payslip(
        db,
        employee,
        as_of=as_of,
        calculate_payslip=_calculate_employee_payslip,
    )
    slip = require_loaded_slip(loaded)
    data = {
        "business_name": business.name,
        **slip,
    }
    pdf = _simple_payslip_pdf(data, sample=business_is_demo(business))
    filename = f"{employee.full_name.lower().replace(' ', '-')}-payslip.pdf"
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _pdf_escape(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


PAYSLIP_RECEIPT_WIDTH = 300


def _positive_payslip_rate(value: object) -> float | None:
    amount = _money(value)
    if amount <= 0:
        return None
    return amount


def _payslip_display_rates(data: dict) -> tuple[float | None, float | None]:
    """Daily and hourly amounts for the downloaded payslip. Unused is None."""
    raw_basis = data.get("pay_basis")
    basis = str(raw_basis).lower() if raw_basis not in (None, "") else ""
    daily = _positive_payslip_rate(data.get("daily_rate"))
    hourly = _positive_payslip_rate(
        data.get("hourly_rate")
        if data.get("hourly_rate") is not None
        else data.get("hourly_rate_configured")
    )
    if basis == "hourly":
        return None, hourly
    if basis == "daily":
        return daily, None
    if basis == "monthly":
        return None, None
    return daily, hourly


def _simple_payslip_pdf(data: dict, *, sample: bool = False) -> bytes:
    lines = []
    if sample:
        lines.extend(
            [
                "SAMPLE — DEMONSTRATION ONLY",
                "NOT FOR ACTUAL SALARY PAYMENT",
            ]
        )
    daily_rate, hourly_rate = _payslip_display_rates(data)
    daily_line = (
        f"Daily Rate: PHP {daily_rate:,.2f}" if daily_rate is not None else "Daily Rate:"
    )
    hourly_line = (
        f"Hourly Rate: PHP {hourly_rate:,.2f}"
        if hourly_rate is not None
        else "Hourly Rate:"
    )
    pay_basis = str(data.get("pay_basis") or "daily").lower()
    monthly = _positive_payslip_rate(data.get("monthly_salary"))
    basic_salary = _money(data.get("regular_pay"))
    unresolved_note = None
    if data.get("has_unresolved_historical_rate"):
        unresolved_note = (
            "NOTE: Completed attendance with unresolved historical pay rate. "
            "Amounts exclude unresolved days until the Owner resolves the rate."
        )
    lines.extend(
        [
            "PAYSLIP",
            data["business_name"],
            f"Employee: {data['employee_name']}",
            f"Position: {data.get('position_title') or 'Employee'}",
            f"Period: {data['period_start']} to {data['period_end']}",
            f"Worked days: {data['worked_days']}",
            f"Hours worked: {data.get('hours_worked', 0)}",
            daily_line,
            hourly_line,
        ]
    )
    if pay_basis == "monthly" and monthly is not None:
        lines.append(f"Monthly salary: PHP {monthly:,.2f}")
    lines.extend(
        [
            f"Basic salary: PHP {basic_salary:,.2f}",
            f"Leave pay: PHP {_money(data.get('leave_pay')):,.2f}",
            f"Overtime pay: PHP {_money(data['overtime_pay']):,.2f}",
            f"Holiday pay: PHP {_money(data['holiday_pay']):,.2f}",
            f"Rest day premium: PHP {_money(data.get('rest_day_pay', 0)):,.2f}",
            f"Gross pay: PHP {_money(data['gross_pay']):,.2f}",
            f"Deductions: PHP {_money(data['deductions']):,.2f}",
            f"Base net pay: PHP {_money(data.get('base_net_pay', data['net_pay'])):,.2f}",
        ]
    )
    if unresolved_note:
        lines.insert(6, unresolved_note)
    for adj in data.get("payroll_adjustments") or []:
        sign = "-" if adj.get("kind") == "deduction" else "+"
        lines.append(
            f"{adj.get('display_name')}: {sign}PHP {_money(adj.get('amount', 0)):,.2f}"
        )
    lines.append(
        f"Final net pay: PHP {_money(data.get('final_net_pay', data['net_pay'])):,.2f}"
    )
    # Rest-day attendance dates stay off the downloaded receipt. The rest-day
    # premium amount is already in the earnings lines above.
    line_h = 13
    top = 20
    height = max(top + 16 + len(lines) * line_h + 20, 360)
    start_y = height - top
    stream_lines = ["BT", "/F1 9 Tf", f"16 {start_y} Td"]
    for index, line in enumerate(lines):
        if index:
            stream_lines.append(f"0 -{line_h} Td")
        stream_lines.append(f"({_pdf_escape(line)}) Tj")
    stream_lines.append("ET")
    stream = "\n".join(stream_lines).encode("latin-1", errors="replace")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAYSLIP_RECEIPT_WIDTH} {height}] "
            "/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>"
        ).encode("ascii"),
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
