"""Employee clock-in/out with geofence validation."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.geofence import geofence_check
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


def clock_in_employee(
    db: Session,
    employee: Employee,
    *,
    latitude: float,
    longitude: float,
    shift_assignment_id: uuid.UUID | None = None,
) -> dict:
    location = _primary_location(db, employee.business_id)
    geofence = _validate_geofence(location, latitude, longitude)

    today = date.today()
    assignment, shift = _resolve_assignment(
        db, employee, today, shift_assignment_id
    )

    existing = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.shift_assignment_id == assignment.id,
            AttendanceRecord.employee_id == employee.id,
        )
        .order_by(AttendanceRecord.created_at.desc())
        .first()
    )
    if existing is not None and existing.time_in is not None and existing.time_out is None:
        raise HTTPException(400, "You are already clocked in for this shift.")

    policy = _attendance_policy(db, employee.business_id)
    now = datetime.now(timezone.utc)
    now_local = now.replace(tzinfo=None)
    scheduled_start = _scheduled_start(assignment.work_date, shift)
    earliest = scheduled_start - timedelta(minutes=policy.early_clock_in_minutes)
    if now_local < earliest:
        raise HTTPException(
            400,
            f"Clock-in opens {policy.early_clock_in_minutes} minutes before shift start.",
        )

    grace_end = scheduled_start + timedelta(minutes=policy.on_time_grace_minutes)
    status = (
        AttendanceStatus.late
        if now_local > grace_end
        else AttendanceStatus.in_progress
    )

    record = AttendanceRecord(
        business_id=employee.business_id,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
        time_in=now,
        status=status,
        latitude_in=latitude,
        longitude_in=longitude,
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    message = (
        "Clocked in successfully."
        if status == AttendanceStatus.in_progress
        else "Clocked in successfully. You were marked late."
    )
    return {
        "id": str(record.id),
        "status": record.status.value,
        "time_in": record.time_in.isoformat() if record.time_in else None,
        "time_out": None,
        "geofence": geofence,
        "shift_name": shift.name,
        "message": message,
    }


def clock_out_employee(
    db: Session,
    employee: Employee,
    *,
    latitude: float,
    longitude: float,
) -> dict:
    location = _primary_location(db, employee.business_id)
    geofence = _validate_geofence(location, latitude, longitude)

    today = date.today()
    record = _active_record(db, employee, today)
    if record is None or record.time_in is None:
        raise HTTPException(400, "You are not clocked in yet.")

    shift_name = None
    if record.shift_assignment_id is not None:
        row = (
            db.query(ShiftAssignment, Shift)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(ShiftAssignment.id == record.shift_assignment_id)
            .first()
        )
        if row is not None:
            shift_name = row[1].name

    now = datetime.now(timezone.utc)
    record.time_out = now
    record.latitude_out = latitude
    record.longitude_out = longitude
    record.status = AttendanceStatus.complete
    db.commit()
    db.refresh(record)

    return {
        "id": str(record.id),
        "status": record.status.value,
        "time_in": record.time_in.isoformat() if record.time_in else None,
        "time_out": record.time_out.isoformat() if record.time_out else None,
        "geofence": geofence,
        "shift_name": shift_name,
        "message": "Clocked out successfully.",
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
