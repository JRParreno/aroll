"""Attendance correction requests and approval.

Employees may request corrected clock-in/out times for a specific shift.
Owners/managers approve or reject; approval updates the attendance record.
Payroll and reports recompute from attendance (single source of truth).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.timezone import business_today, get_business_tz
from app.models.attendance import AttendanceRecord
from app.models.attendance_correction import AttendanceCorrectionRequest
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceCorrectionStatus, AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.attendance_clock import _attendance_policy
from app.services.attendance_status import resolve_closed_attendance_status


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        # Treat naive client times as business-local wall clock.
        raise HTTPException(
            400,
            "Time In and Time Out must include a timezone offset (e.g. 2026-07-19T09:00:00+08:00).",
        )
    return value.astimezone(timezone.utc)


def _to_business_local(value: datetime, tz_name: str | None) -> datetime:
    return value.astimezone(get_business_tz(tz_name)).replace(tzinfo=None)


def _time_label(value) -> str:
    return value.strftime("%I:%M %p").lstrip("0")


def _load_assignment_bundle(
    db: Session,
    *,
    assignment_id: uuid.UUID,
    employee_id: uuid.UUID,
    business_id: uuid.UUID,
) -> tuple[ShiftAssignment, Shift, AttendanceRecord | None]:
    row = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            ShiftAssignment.id == assignment_id,
            ShiftAssignment.employee_id == employee_id,
            Shift.business_id == business_id,
        )
        .first()
    )
    if row is None:
        raise HTTPException(404, "Shift assignment not found.")
    assignment, shift = row
    record = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.shift_assignment_id == assignment.id,
            AttendanceRecord.employee_id == employee_id,
            AttendanceRecord.business_id == business_id,
        )
        .order_by(AttendanceRecord.created_at.desc())
        .first()
    )
    return assignment, shift, record


def _recompute_status(
    *,
    time_in: datetime,
    time_out: datetime | None,
    assignment: ShiftAssignment,
    shift: Shift,
    policy: BusinessAttendancePolicy,
    business_timezone: str | None,
) -> AttendanceStatus:
    """Recompute presence status relative to the assigned shift duration."""
    return resolve_closed_attendance_status(
        time_in=time_in,
        time_out=time_out,
        assignment=assignment,
        shift=shift,
        policy=policy,
        business_timezone=business_timezone,
        local_time_in=_to_business_local(time_in, business_timezone),
    )


def serialize_correction(
    db: Session,
    request: AttendanceCorrectionRequest,
    *,
    assignment: ShiftAssignment | None = None,
    shift: Shift | None = None,
    record: AttendanceRecord | None = None,
    employee: Employee | None = None,
) -> dict:
    if assignment is None or shift is None:
        assignment, shift, record = _load_assignment_bundle(
            db,
            assignment_id=request.shift_assignment_id,
            employee_id=request.employee_id,
            business_id=request.business_id,
        )
    if employee is None:
        employee = db.get(Employee, request.employee_id)
    if record is None and request.attendance_record_id is not None:
        record = db.get(AttendanceRecord, request.attendance_record_id)
    if record is None:
        record = (
            db.query(AttendanceRecord)
            .filter(
                AttendanceRecord.shift_assignment_id == request.shift_assignment_id,
                AttendanceRecord.employee_id == request.employee_id,
            )
            .first()
        )

    return {
        "id": str(request.id),
        "business_id": str(request.business_id),
        "employee_id": str(request.employee_id),
        "employee_name": employee.full_name if employee else "Employee",
        "profile_image_url": employee.profile_image_url if employee else None,
        "shift_assignment_id": str(request.shift_assignment_id),
        "attendance_record_id": (
            str(request.attendance_record_id)
            if request.attendance_record_id
            else (str(record.id) if record else None)
        ),
        "work_date": assignment.work_date.isoformat(),
        "shift_name": shift.name if shift else None,
        "shift_start": _time_label(shift.start_time) if shift else None,
        "shift_end": _time_label(shift.end_time) if shift else None,
        "recorded_time_in": _iso(record.time_in) if record else None,
        "recorded_time_out": _iso(record.time_out) if record else None,
        "requested_time_in": _iso(request.requested_time_in),
        "requested_time_out": _iso(request.requested_time_out),
        "reason": request.reason,
        "status": request.status.value,
        "review_note": request.review_note,
        "reviewed_by": str(request.reviewed_by) if request.reviewed_by else None,
        "reviewed_at": _iso(request.reviewed_at),
        "created_at": _iso(request.created_at) or "",
    }


def create_correction_request(
    db: Session,
    *,
    employee: Employee,
    business: Business,
    shift_assignment_id: uuid.UUID,
    requested_time_in: datetime | None,
    requested_time_out: datetime | None,
    reason: str,
) -> dict:
    assignment, shift, record = _load_assignment_bundle(
        db,
        assignment_id=shift_assignment_id,
        employee_id=employee.id,
        business_id=employee.business_id,
    )

    today = business_today(business.timezone)
    if assignment.work_date > today:
        raise HTTPException(400, "Cannot request a correction for a future shift.")

    pending = (
        db.query(AttendanceCorrectionRequest)
        .filter(
            AttendanceCorrectionRequest.shift_assignment_id == assignment.id,
            AttendanceCorrectionRequest.employee_id == employee.id,
            AttendanceCorrectionRequest.status == AttendanceCorrectionStatus.pending,
        )
        .first()
    )
    if pending is not None:
        raise HTTPException(
            400,
            "A correction request for this shift is already pending approval.",
        )

    time_in_utc = _as_utc(requested_time_in) if requested_time_in else None
    time_out_utc = _as_utc(requested_time_out) if requested_time_out else None

    # Incomplete attendance: official clock-in is locked; employee may only
    # submit a corrected clock-out (+ reason). Managers correct clock-in.
    if record is not None and record.status == AttendanceStatus.incomplete:
        if record.time_in is None:
            raise HTTPException(
                400,
                "Incomplete attendance is missing a recorded Time In.",
            )
        official_in = _as_utc(record.time_in)
        if time_out_utc is None:
            raise HTTPException(
                400,
                "Please provide the corrected Time Out.",
            )
        if time_in_utc is not None and abs(
            (time_in_utc - official_in).total_seconds()
        ) > 60:
            raise HTTPException(
                400,
                "Time In cannot be changed for incomplete attendance. "
                "Contact your manager if the recorded Time In is wrong.",
            )
        time_in_utc = official_in
    elif time_in_utc is None or time_out_utc is None:
        # Non-incomplete corrections still require both punches.
        raise HTTPException(
            400,
            "Please provide corrected Time In and Time Out.",
        )
    if time_out_utc <= time_in_utc:
        raise HTTPException(400, "Time Out must be after Time In.")

    # Validate times fall on/near the work date (allow overnight).
    local_anchor = datetime.combine(assignment.work_date, shift.start_time)
    local_tz = get_business_tz(business.timezone)
    work_start_local = local_anchor.replace(tzinfo=local_tz)
    window_start = work_start_local.astimezone(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    ) - timedelta(hours=12)
    window_end = work_start_local.astimezone(timezone.utc) + timedelta(hours=36)
    for label, punch in (("Time In", time_in_utc), ("Time Out", time_out_utc)):
        if punch < window_start or punch > window_end:
            raise HTTPException(
                400,
                f"{label} must be close to the scheduled shift date.",
            )

    request = AttendanceCorrectionRequest(
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        attendance_record_id=record.id if record else None,
        requested_time_in=time_in_utc,
        requested_time_out=time_out_utc,
        reason=reason.strip(),
        status=AttendanceCorrectionStatus.pending,
    )
    db.add(request)
    db.commit()
    db.refresh(request)
    try:
        from app.services.notifications import notify_business_owners, notify_user_once

        notify_business_owners(
            db,
            business_id=employee.business_id,
            type="attendance_correction_submitted",
            title="Attendance Correction",
            message=f"{employee.full_name} submitted an attendance correction.",
            entity_type="attendance_correction",
            entity_id=request.id,
            deep_link=f"/owner/attendance?correctionId={request.id}",
        )
        if employee.user_id is not None:
            emp_user = db.get(User, employee.user_id)
            if emp_user is not None:
                notify_user_once(
                    db,
                    user=emp_user,
                    type="attendance_correction_submitted",
                    title="Correction Submitted",
                    message=(
                        "Your attendance correction was submitted and is "
                        "awaiting approval."
                    ),
                    entity_type="attendance_correction",
                    entity_id=request.id,
                    deep_link=(
                        f"/shift-history?shift_assignment_id="
                        f"{request.shift_assignment_id}"
                    ),
                )
    except Exception:
        pass
    return serialize_correction(
        db,
        request,
        assignment=assignment,
        shift=shift,
        record=record,
        employee=employee,
    )


def list_employee_corrections(
    db: Session,
    *,
    employee: Employee,
    limit: int = 50,
) -> list[dict]:
    rows = (
        db.query(AttendanceCorrectionRequest)
        .filter(AttendanceCorrectionRequest.employee_id == employee.id)
        .order_by(AttendanceCorrectionRequest.created_at.desc())
        .limit(limit)
        .all()
    )
    return [serialize_correction(db, row, employee=employee) for row in rows]


def list_owner_corrections(
    db: Session,
    *,
    business_id: uuid.UUID,
    status: AttendanceCorrectionStatus | None = AttendanceCorrectionStatus.pending,
    limit: int = 100,
) -> list[dict]:
    query = db.query(AttendanceCorrectionRequest).filter(
        AttendanceCorrectionRequest.business_id == business_id
    )
    if status is not None:
        query = query.filter(AttendanceCorrectionRequest.status == status)
    rows = query.order_by(AttendanceCorrectionRequest.created_at.desc()).limit(limit).all()
    return [serialize_correction(db, row) for row in rows]


def _get_business_request(
    db: Session,
    *,
    request_id: uuid.UUID,
    business_id: uuid.UUID,
) -> AttendanceCorrectionRequest:
    request = db.get(AttendanceCorrectionRequest, request_id)
    if request is None or request.business_id != business_id:
        raise HTTPException(404, "Correction request not found.")
    return request


def approve_correction(
    db: Session,
    *,
    request_id: uuid.UUID,
    reviewer: User,
    business: Business,
) -> dict:
    request = _get_business_request(
        db, request_id=request_id, business_id=business.id
    )
    if request.status != AttendanceCorrectionStatus.pending:
        raise HTTPException(400, "Only pending correction requests can be approved.")

    assignment, shift, record = _load_assignment_bundle(
        db,
        assignment_id=request.shift_assignment_id,
        employee_id=request.employee_id,
        business_id=request.business_id,
    )
    policy = _attendance_policy(db, business.id)

    final_in = request.requested_time_in or (record.time_in if record else None)
    final_out = request.requested_time_out or (record.time_out if record else None)
    # Preserve official clock-in when approving an incomplete-attendance fix.
    if (
        record is not None
        and record.time_in is not None
        and record.status == AttendanceStatus.incomplete
    ):
        final_in = record.time_in
    if final_in is None:
        raise HTTPException(400, "Approved correction is missing a Time In.")
    if final_out is not None and final_out <= final_in:
        raise HTTPException(400, "Time Out must be after Time In.")

    status = _recompute_status(
        time_in=final_in,
        time_out=final_out,
        assignment=assignment,
        shift=shift,
        policy=policy,
        business_timezone=business.timezone,
    )

    if record is None:
        record = AttendanceRecord(
            business_id=request.business_id,
            employee_id=request.employee_id,
            shift_assignment_id=assignment.id,
            time_in=final_in,
            time_out=final_out,
            status=status,
            liveness_passed=None,
        )
        db.add(record)
        db.flush()
        request.attendance_record_id = record.id
    else:
        # Keep official clock-in for incomplete fixes; only apply corrected out.
        if record.status != AttendanceStatus.incomplete:
            record.time_in = final_in
        record.time_out = final_out
        record.status = status
        request.attendance_record_id = record.id

    request.status = AttendanceCorrectionStatus.approved
    request.reviewed_by = reviewer.id
    request.reviewed_at = datetime.now(timezone.utc)
    request.review_note = None
    db.commit()
    db.refresh(request)
    employee = db.get(Employee, request.employee_id)
    if employee and employee.user_id:
        try:
            from app.services.notifications import notify_user_once

            emp_user = db.get(User, employee.user_id)
            if emp_user is not None:
                notify_user_once(
                    db,
                    user=emp_user,
                    type="attendance_correction_approved",
                    title="Correction Approved",
                    message="Your attendance correction was approved.",
                    entity_type="attendance_correction",
                    entity_id=request.id,
                    deep_link=(
                        f"/shift-history?shift_assignment_id="
                        f"{request.shift_assignment_id}"
                        f"&attendance_record_id="
                        f"{request.attendance_record_id or ''}"
                    ),
                )
        except Exception:
            pass
    return serialize_correction(
        db,
        request,
        assignment=assignment,
        shift=shift,
        record=record,
        employee=employee,
    )


def reject_correction(
    db: Session,
    *,
    request_id: uuid.UUID,
    reviewer: User,
    business_id: uuid.UUID,
    review_note: str,
) -> dict:
    request = _get_business_request(
        db, request_id=request_id, business_id=business_id
    )
    if request.status != AttendanceCorrectionStatus.pending:
        raise HTTPException(400, "Only pending correction requests can be rejected.")

    request.status = AttendanceCorrectionStatus.rejected
    request.reviewed_by = reviewer.id
    request.reviewed_at = datetime.now(timezone.utc)
    request.review_note = review_note.strip()

    # Keep forgotten clock-outs as Incomplete Attendance after rejection.
    if request.attendance_record_id is not None:
        record = db.get(AttendanceRecord, request.attendance_record_id)
        if (
            record is not None
            and record.time_out is None
            and record.time_in is not None
        ):
            record.status = AttendanceStatus.incomplete

    db.commit()
    db.refresh(request)
    employee = db.get(Employee, request.employee_id)
    if employee and employee.user_id:
        try:
            from app.services.notifications import notify_user_once

            emp_user = db.get(User, employee.user_id)
            if emp_user is not None:
                notify_user_once(
                    db,
                    user=emp_user,
                    type="attendance_correction_rejected",
                    title="Correction Rejected",
                    message="Your attendance correction was rejected.",
                    entity_type="attendance_correction",
                    entity_id=request.id,
                    deep_link=(
                        f"/shift-history?shift_assignment_id="
                        f"{request.shift_assignment_id}"
                        f"&attendance_record_id="
                        f"{request.attendance_record_id or ''}"
                    ),
                )
        except Exception:
            pass
    return serialize_correction(db, request, employee=employee)


def latest_corrections_by_assignment(
    db: Session,
    *,
    employee_id: uuid.UUID,
    assignment_ids: list[uuid.UUID],
) -> dict[uuid.UUID, AttendanceCorrectionRequest]:
    if not assignment_ids:
        return {}
    rows = (
        db.query(AttendanceCorrectionRequest)
        .filter(
            AttendanceCorrectionRequest.employee_id == employee_id,
            AttendanceCorrectionRequest.shift_assignment_id.in_(assignment_ids),
        )
        .order_by(AttendanceCorrectionRequest.created_at.desc())
        .all()
    )
    latest: dict[uuid.UUID, AttendanceCorrectionRequest] = {}
    for row in rows:
        if row.shift_assignment_id not in latest:
            latest[row.shift_assignment_id] = row
    return latest
