"""Employee clock-in/out with geofence validation.

Geofence checks use Haversine distance against the primary business_location.
Shift windows (early clock-in, grace, late) use the business IANA timezone
(default Asia/Manila). Punch timestamps are stored in UTC.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.geofence import geofence_check
from app.core.timezone import business_now, business_today
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import BusinessLocation
from app.models.employee import Employee
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment


class GeofenceValidationError(HTTPException):
    def __init__(self, *, distance_m: float, allowed_radius_m: float) -> None:
        super().__init__(
            status_code=403,
            detail={
                "code": "outside_geofence",
                "message": (
                    "You must be within the business geofence to clock attendance. "
                    f"You are {distance_m:.0f}m away; allowed radius is {allowed_radius_m:.0f}m."
                ),
                "distance_m": distance_m,
                "allowed_radius_m": allowed_radius_m,
            },
        )


def _primary_location(db: Session, business_id: uuid.UUID) -> BusinessLocation:
    location = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business_id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if location is None:
        location = (
            db.query(BusinessLocation)
            .filter(BusinessLocation.business_id == business_id)
            .order_by(BusinessLocation.label)
            .first()
        )
    if location is None:
        raise HTTPException(
            400,
            "Business location is not configured. Ask your employer to set a work site.",
        )
    if location.latitude is None or location.longitude is None:
        raise HTTPException(
            400,
            "Business location coordinates are missing. Ask your employer to update the work site.",
        )
    return location


def _attendance_policy(
    db: Session, business_id: uuid.UUID
) -> BusinessAttendancePolicy:
    policy = db.get(BusinessAttendancePolicy, business_id)
    if policy is None:
        policy = BusinessAttendancePolicy(business_id=business_id)
    return policy


def _rest_day_status(assignment: ShiftAssignment) -> tuple[bool, bool]:
    """Return (is_rest_day_work, work_authorized) for the assignment.

    Rest-day work is approved per schedule assignment by the owner/manager.
    """
    if not assignment.is_rest_day_work:
        return False, True
    return True, True


def _validate_geofence(
    location: BusinessLocation,
    latitude: float,
    longitude: float,
) -> dict[str, float | bool]:
    result = geofence_check(
        latitude=latitude,
        longitude=longitude,
        center_latitude=float(location.latitude),
        center_longitude=float(location.longitude),
        radius_m=location.geofence_radius_m,
    )
    if not result["inside_geofence"]:
        raise GeofenceValidationError(
            distance_m=float(result["distance_m"]),
            allowed_radius_m=float(result["allowed_radius_m"]),
        )
    return result


def _scheduled_start(work_date: date, shift: Shift) -> datetime:
    return datetime.combine(work_date, shift.start_time)


def _scheduled_end(work_date: date, shift: Shift) -> datetime:
    end_at = datetime.combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def _resolve_assignment(
    db: Session,
    employee: Employee,
    work_date: date,
    shift_assignment_id: uuid.UUID | None,
) -> tuple[ShiftAssignment, Shift]:
    query = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            ShiftAssignment.employee_id == employee.id,
            ShiftAssignment.work_date == work_date,
            Shift.business_id == employee.business_id,
        )
        .order_by(Shift.start_time.asc())
    )
    rows = query.all()
    if not rows:
        raise HTTPException(400, "You have no assigned shift for today.")

    if shift_assignment_id is not None:
        for assignment, shift in rows:
            if assignment.id == shift_assignment_id:
                return assignment, shift
        raise HTTPException(400, "Selected shift assignment was not found for today.")

    if len(rows) == 1:
        return rows[0]

    raise HTTPException(
        400,
        "Multiple shifts are assigned today. Open your schedule and select a shift to clock in.",
    )


def _active_record(
    db: Session,
    employee: Employee,
    work_date: date,
) -> AttendanceRecord | None:
    assignment_ids = [
        row.id
        for row in db.query(ShiftAssignment.id)
        .filter(
            ShiftAssignment.employee_id == employee.id,
            ShiftAssignment.work_date == work_date,
        )
        .all()
    ]
    query = db.query(AttendanceRecord).filter(
        AttendanceRecord.business_id == employee.business_id,
        AttendanceRecord.employee_id == employee.id,
        AttendanceRecord.time_out.is_(None),
    )
    if assignment_ids:
        query = query.filter(AttendanceRecord.shift_assignment_id.in_(assignment_ids))
    return query.order_by(AttendanceRecord.created_at.desc()).first()


def _existing_assignment_record(
    db: Session,
    *,
    employee_id: uuid.UUID,
    shift_assignment_id: uuid.UUID,
) -> AttendanceRecord | None:
    return (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.shift_assignment_id == shift_assignment_id,
            AttendanceRecord.employee_id == employee_id,
        )
        .order_by(AttendanceRecord.created_at.desc())
        .first()
    )


def _clock_in_status(
    *,
    now_local: datetime,
    scheduled_start: datetime,
    grace_minutes: int,
) -> AttendanceStatus:
    grace_end = scheduled_start + timedelta(minutes=grace_minutes)
    if now_local > grace_end:
        return AttendanceStatus.late
    return AttendanceStatus.in_progress


def verify_employee_face_match(
    db: Session,
    employee: Employee,
    face_image_bytes: bytes,
) -> float:
    """Match probe image against enrolled samples; raise on failure."""
    from app.core.config import settings
    from app.models.face_embedding import EmployeeFaceEmbedding
    from app.services.face_embedding import (
        detect_and_embed,
        match_passed,
        mean_match_score,
    )

    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .all()
    )
    if not samples:
        raise HTTPException(
            400,
            detail={
                "code": "not_enrolled",
                "message": "Face is not enrolled. Complete face registration first.",
            },
        )

    probe = detect_and_embed(face_image_bytes)
    score = mean_match_score(probe, [list(row.embedding) for row in samples])
    if not match_passed(score):
        raise HTTPException(
            403,
            detail={
                "code": "face_mismatch",
                "message": (
                    f"Face did not match enrolled samples "
                    f"(mean score {score:.3f} < {settings.face_match_threshold:.3f})."
                ),
                "match_score": round(score, 4),
                "threshold": settings.face_match_threshold,
            },
        )
    return score


def clock_in_employee(
    db: Session,
    employee: Employee,
    *,
    latitude: float,
    longitude: float,
    shift_assignment_id: uuid.UUID | None = None,
    business_timezone: str | None = "Asia/Manila",
    face_image_bytes: bytes | None = None,
    liveness_passed: bool | None = None,
    face_match_score: float | None = None,
) -> dict:
    location = _primary_location(db, employee.business_id)
    geofence = _validate_geofence(location, latitude, longitude)

    resolved_score = face_match_score
    if face_image_bytes is not None and resolved_score is None:
        resolved_score = verify_employee_face_match(db, employee, face_image_bytes)

    today = business_today(business_timezone)
    assignment, shift = _resolve_assignment(
        db, employee, today, shift_assignment_id
    )

    existing = _existing_assignment_record(
        db,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
    )
    if existing is not None:
        if existing.time_in is not None and existing.time_out is None:
            raise HTTPException(400, "You are already clocked in for this shift.")
        raise HTTPException(
            400,
            "Attendance for this shift is already complete.",
        )

    policy = _attendance_policy(db, employee.business_id)
    now_local = business_now(business_timezone).replace(tzinfo=None)
    scheduled_start = _scheduled_start(assignment.work_date, shift)
    earliest = scheduled_start - timedelta(minutes=policy.early_clock_in_minutes)
    if now_local < earliest:
        raise HTTPException(
            400,
            f"Clock-in opens {policy.early_clock_in_minutes} minutes before shift start.",
        )

    status = _clock_in_status(
        now_local=now_local,
        scheduled_start=scheduled_start,
        grace_minutes=policy.on_time_grace_minutes,
    )

    is_rest_day, rest_day_authorized = _rest_day_status(assignment)

    now_utc = datetime.now(timezone.utc)
    record = AttendanceRecord(
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=now_utc,
        status=status,
        latitude_in=latitude,
        longitude_in=longitude,
        face_match_score=resolved_score,
        liveness_passed=liveness_passed,
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    message = (
        "Clocked in successfully."
        if status == AttendanceStatus.in_progress
        else "Clocked in successfully. You were marked late."
    )
    if is_rest_day:
        message = (
            f"{message} This shift is approved rest day work; "
            "rest day premium applies."
        )
    if resolved_score is not None:
        message = f"{message} Face match score: {resolved_score:.3f}."
    if liveness_passed is True:
        message = f"{message} Liveness passed."
    return {
        "id": str(record.id),
        "status": record.status.value,
        "time_in": record.time_in.isoformat() if record.time_in else None,
        "time_out": None,
        "geofence": geofence,
        "shift_name": shift.name,
        "message": message,
        "face_match_score": (
            round(resolved_score, 4) if resolved_score is not None else None
        ),
        "liveness_passed": record.liveness_passed,
        "is_rest_day": is_rest_day,
        "rest_day_work_authorized": rest_day_authorized if is_rest_day else None,
    }


def clock_out_employee(
    db: Session,
    employee: Employee,
    *,
    latitude: float,
    longitude: float,
    business_timezone: str | None = "Asia/Manila",
    face_match_score: float | None = None,
    liveness_passed: bool | None = None,
) -> dict:
    location = _primary_location(db, employee.business_id)
    geofence = _validate_geofence(location, latitude, longitude)

    today = business_today(business_timezone)
    record = _active_record(db, employee, today)
    if record is None or record.time_in is None:
        raise HTTPException(400, "You are not clocked in yet.")

    policy = _attendance_policy(db, employee.business_id)
    shift_name = None
    shift: Shift | None = None
    assignment: ShiftAssignment | None = None
    if record.shift_assignment_id is not None:
        row = (
            db.query(ShiftAssignment, Shift)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(ShiftAssignment.id == record.shift_assignment_id)
            .first()
        )
        if row is not None:
            assignment, shift = row
            shift_name = shift.name

    now_utc = datetime.now(timezone.utc)
    record.time_out = now_utc
    record.latitude_out = latitude
    record.longitude_out = longitude
    if face_match_score is not None:
        record.face_match_score_out = face_match_score
    if liveness_passed is True:
        record.liveness_passed = True
    elif liveness_passed is False:
        record.liveness_passed = False

    was_late = record.status == AttendanceStatus.late
    worked_minutes = max(
        (now_utc - record.time_in).total_seconds() / 60.0,
        0.0,
    )

    # Absent if worked time is below the stricter of the two thresholds.
    # Half-day pay (between thresholds) is applied in payslip math; status
    # stays late/complete so reports still show presence.
    absent_bar = min(
        policy.half_day_threshold_minutes, policy.absent_threshold_minutes
    )
    if worked_minutes < absent_bar:
        record.status = AttendanceStatus.absent
    elif was_late:
        record.status = AttendanceStatus.late
    else:
        record.status = AttendanceStatus.complete

    early_out_minutes = 0.0
    if (
        shift is not None
        and assignment is not None
        and policy.early_out_deduction_enabled
    ):
        now_local = business_now(business_timezone).replace(tzinfo=None)
        scheduled_end = _scheduled_end(assignment.work_date, shift)
        if now_local < scheduled_end:
            early_out_minutes = (scheduled_end - now_local).total_seconds() / 60.0

    db.commit()
    db.refresh(record)

    message = "Clocked out successfully."
    if record.status == AttendanceStatus.late:
        message = "Clocked out successfully. Late status preserved."
    elif record.status == AttendanceStatus.absent:
        message = "Clocked out. Marked absent due to insufficient worked time."
    if early_out_minutes > 0:
        message = f"{message} Early out: {early_out_minutes:.0f} min."
    if face_match_score is not None:
        message = f"{message} Face match score: {face_match_score:.3f}."
    if liveness_passed is True:
        message = f"{message} Liveness passed."

    return {
        "id": str(record.id),
        "status": record.status.value,
        "time_in": record.time_in.isoformat() if record.time_in else None,
        "time_out": record.time_out.isoformat() if record.time_out else None,
        "geofence": geofence,
        "shift_name": shift_name,
        "message": message,
        "face_match_score": (
            float(record.face_match_score)
            if record.face_match_score is not None
            else None
        ),
        "face_match_score_out": (
            float(record.face_match_score_out)
            if record.face_match_score_out is not None
            else None
        ),
        "liveness_passed": record.liveness_passed,
        "early_out_minutes": round(early_out_minutes, 2),
        "worked_minutes": round(worked_minutes, 2),
    }


def worksite_for_business(db: Session, business_id: uuid.UUID) -> dict:
    location = _primary_location(db, business_id)
    return {
        "label": location.label,
        "address": location.address,
        "latitude": float(location.latitude),
        "longitude": float(location.longitude),
        "geofence_radius_m": location.geofence_radius_m,
    }
