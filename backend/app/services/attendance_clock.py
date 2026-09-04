"""Employee clock-in/out with geofence validation.

Geofence checks use Haversine distance against the primary business_location.
Shift windows (early clock-in, grace, late) use the business IANA timezone
(default Asia/Manila). Punch timestamps are stored in UTC.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

attendance_log = logging.getLogger("aroll.attendance")

from app.core.geofence import geofence_check
from app.core.timezone import business_now, business_today
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import BusinessLocation
from app.models.employee import Employee
from app.models.enums import AttendanceStatus
from app.models.scheduling import Shift, ShiftAssignment
from app.services.demo_tenant import (
    load_business_for_employee,
    substitute_demo_worksite_coordinates,
)


class GeofenceValidationError(HTTPException):
    def __init__(self, *, distance_m: float, allowed_radius_m: float) -> None:
        super().__init__(
            status_code=403,
            detail={
                "code": "outside_geofence",
                "message": (
                    "You’re currently outside your workplace’s allowed attendance "
                    "area. Please move closer and try again."
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


def _list_assignment_candidates(
    db: Session,
    employee: Employee,
    work_date: date,
) -> list[tuple[ShiftAssignment, Shift]]:
    """Today's assignments plus yesterday's overnight shift if it still spans today."""
    yesterday = work_date - timedelta(days=1)
    rows = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            ShiftAssignment.employee_id == employee.id,
            Shift.business_id == employee.business_id,
            ShiftAssignment.work_date.in_((yesterday, work_date)),
        )
        .order_by(ShiftAssignment.work_date.asc(), Shift.start_time.asc())
        .all()
    )
    candidates: list[tuple[ShiftAssignment, Shift]] = []
    for assignment, shift in rows:
        if assignment.work_date == work_date:
            candidates.append((assignment, shift))
            continue
        # Yesterday overnight (end <= start) can still be the active shift after midnight.
        if shift.end_time <= shift.start_time:
            candidates.append((assignment, shift))
    return candidates


def _records_by_assignment(
    db: Session,
    *,
    employee_id: uuid.UUID,
    assignment_ids: list[uuid.UUID],
) -> dict[uuid.UUID, AttendanceRecord]:
    if not assignment_ids:
        return {}
    rows = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.employee_id == employee_id,
            AttendanceRecord.shift_assignment_id.in_(assignment_ids),
        )
        .order_by(AttendanceRecord.created_at.asc())
        .all()
    )
    return {row.shift_assignment_id: row for row in rows if row.shift_assignment_id}


def pick_assignment_for_time_in(
    rows: list[tuple[ShiftAssignment, Shift]],
    records_by_assignment_id: dict[uuid.UUID, AttendanceRecord],
    *,
    now_local: datetime,
    early_clock_in_minutes: int,
    preferred_assignment_id: uuid.UUID | None = None,
) -> tuple[ShiftAssignment, Shift]:
    """Choose the scheduled shift whose Time In window applies now.

    Assignments that already have an attendance record are skipped so a completed
    morning shift does not block Time In for an evening shift on the same day.
    If the client explicitly requests a completed assignment, reject it instead of
    silently selecting a different open shift.
    """
    if preferred_assignment_id is not None:
        preferred_record = records_by_assignment_id.get(preferred_assignment_id)
        if preferred_record is not None:
            if (
                preferred_record.time_in is not None
                and preferred_record.time_out is None
            ):
                raise HTTPException(400, "You are already timed in for this shift.")
            raise HTTPException(
                400,
                "Attendance for this shift is already complete.",
            )

    open_rows = [
        (assignment, shift)
        for assignment, shift in rows
        if records_by_assignment_id.get(assignment.id) is None
    ]
    if not open_rows:
        raise HTTPException(
            400,
            "Attendance for this shift is already complete.",
        )

    in_shift: list[tuple[ShiftAssignment, Shift]] = []
    early_window: list[tuple[ShiftAssignment, Shift]] = []
    late: list[tuple[ShiftAssignment, Shift]] = []
    upcoming: list[tuple[ShiftAssignment, Shift, datetime]] = []

    for assignment, shift in open_rows:
        scheduled_start = _scheduled_start(assignment.work_date, shift)
        scheduled_end = _scheduled_end(assignment.work_date, shift)
        earliest = scheduled_start - timedelta(minutes=early_clock_in_minutes)
        if now_local < earliest:
            upcoming.append((assignment, shift, earliest))
            continue
        if scheduled_start <= now_local < scheduled_end:
            in_shift.append((assignment, shift))
        elif now_local < scheduled_start:
            early_window.append((assignment, shift))
        else:
            late.append((assignment, shift))

    def _prefer(
        group: list[tuple[ShiftAssignment, Shift]],
    ) -> tuple[ShiftAssignment, Shift]:
        if preferred_assignment_id is not None:
            for assignment, shift in group:
                if assignment.id == preferred_assignment_id:
                    return assignment, shift
        return group[0]

    if in_shift:
        return _prefer(in_shift)
    if early_window:
        return _prefer(early_window)
    if late:
        # Prefer the most recently started past shift (last in start-time order).
        if preferred_assignment_id is not None:
            for assignment, shift in reversed(late):
                if assignment.id == preferred_assignment_id:
                    return assignment, shift
        return late[-1]

    raise HTTPException(
        400,
        f"Time In opens {early_clock_in_minutes} minutes before shift start.",
    )


def _resolve_assignment(
    db: Session,
    employee: Employee,
    work_date: date,
    shift_assignment_id: uuid.UUID | None,
    *,
    now_local: datetime,
    early_clock_in_minutes: int,
) -> tuple[ShiftAssignment, Shift]:
    rows = _list_assignment_candidates(db, employee, work_date)
    if not rows:
        raise HTTPException(400, "You have no assigned shift for today.")

    if shift_assignment_id is not None:
        known_ids = {assignment.id for assignment, _shift in rows}
        if shift_assignment_id not in known_ids:
            raise HTTPException(
                400, "Selected shift assignment was not found for today."
            )

    records = _records_by_assignment(
        db,
        employee_id=employee.id,
        assignment_ids=[assignment.id for assignment, _shift in rows],
    )
    return pick_assignment_for_time_in(
        rows,
        records,
        now_local=now_local,
        early_clock_in_minutes=early_clock_in_minutes,
        preferred_assignment_id=shift_assignment_id,
    )


def _active_record(
    db: Session,
    employee: Employee,
    work_date: date | None = None,
) -> AttendanceRecord | None:
    """Open in-progress/late punch for this employee.

    Not scoped to today's assignment IDs so an overnight Time Out after midnight
    still finds the open punch when the employee also has a shift on the new day.
    Incomplete (forgotten Time Out) is excluded so it does not block the next shift.
    """
    del work_date  # kept for callers; open sessions are employee-scoped
    return (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            AttendanceRecord.time_out.is_(None),
            AttendanceRecord.status.in_(
                (AttendanceStatus.in_progress, AttendanceStatus.late)
            ),
        )
        .order_by(AttendanceRecord.created_at.desc())
        .first()
    )


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
    *,
    attendance_action: str | None = None,
) -> float:
    """Match probe image against *this* employee's enrolled samples only.

    Pipeline:
      1) Load gallery for the logged-in employee only (never 1:N search)
      2) Detect exactly one live face
      3) Build ArcFace embedding (original + mirror selfie)
      4) Cosine-compare mean + min against enrolled samples per orientation
      5) Accept only if one orientation clears both calibrated thresholds

    Face detection alone never grants attendance.
    """
    import logging
    import time

    from app.core.config import settings
    from app.models.face_embedding import EmployeeFaceEmbedding
    from app.services.face_embedding import (
        MODEL_VERSION,
        best_match_score,
        centroid_match_score,
        detect_and_observe,
        gallery_pairwise_consistency,
        identity_match_passed,
        mean_match_score,
        min_match_score,
        observe_mirrored_embedding,
        robust_match_score,
    )

    face_log = logging.getLogger("aroll.face")
    employee_id = str(employee.id)
    action = (attendance_action or "unknown").strip().lower() or "unknown"
    mean_threshold = settings.face_match_threshold
    min_threshold = settings.face_min_match_threshold
    t0 = time.perf_counter()

    samples = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .order_by(EmployeeFaceEmbedding.sample_index.asc())
        .all()
    )
    if not samples:
        face_log.warning(
            "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=NO "
            "live_embedding=NO similarity=N/A "
            "threshold_mean=%.4f threshold_min=%.4f decision=NO_MATCH "
            "attendance=NO reason=not_enrolled elapsed_ms=%.0f",
            action,
            employee_id,
            mean_threshold,
            min_threshold,
            (time.perf_counter() - t0) * 1000,
        )
        raise HTTPException(
            400,
            detail={
                "code": "not_enrolled",
                "message": "Face is not enrolled. Complete face registration first.",
            },
        )

    stored_version = samples[0].model_version or ""
    if stored_version != MODEL_VERSION:
        face_log.warning(
            "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
            "model_stored=%s model_current=%s decision=NO_MATCH attendance=NO "
            "reason=face_model_outdated elapsed_ms=%.0f",
            action,
            employee_id,
            stored_version,
            MODEL_VERSION,
            (time.perf_counter() - t0) * 1000,
        )
        raise HTTPException(
            400,
            detail={
                "code": "face_enrollment_required",
                "message": (
                    "Your face registration needs to be updated for the improved "
                    "recognition model. Please re-enroll your face, then try again."
                ),
            },
        )

    gallery = [list(row.embedding) for row in samples]
    if any(len(vec) != 512 for vec in gallery):
        face_log.error(
            "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
            "decision=NO_MATCH attendance=NO reason=bad_gallery dims=%s "
            "elapsed_ms=%.0f",
            action,
            employee_id,
            [len(v) for v in gallery],
            (time.perf_counter() - t0) * 1000,
        )
        raise HTTPException(
            500,
            detail={
                "code": "embedding_error",
                "message": "Stored face data is invalid. Please re-enroll your face.",
            },
        )

    consistency = gallery_pairwise_consistency(gallery)
    if consistency < settings.face_enrollment_consistency_min:
        face_log.warning(
            "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
            "gallery_consistency=%.4f decision=NO_MATCH attendance=NO "
            "reason=poor_enrollment elapsed_ms=%.0f",
            action,
            employee_id,
            consistency,
            (time.perf_counter() - t0) * 1000,
        )
        raise HTTPException(
            400,
            detail={
                "code": "face_enrollment_quality",
                "message": (
                    "Your enrolled face samples are inconsistent. "
                    "Please re-enroll your face before timing in."
                ),
            },
        )

    try:
        # Fast path: embed once, then only mirror if the primary orientation fails.
        observation = detect_and_observe(face_image_bytes)
    except Exception as exc:
        detail = getattr(exc, "detail", None)
        code = detail.get("code") if isinstance(detail, dict) else "detect_failed"
        face_log.warning(
            "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
            "live_embedding=NO similarity=N/A threshold_mean=%.4f "
            "threshold_min=%.4f decision=NO_MATCH attendance=NO reason=%s "
            "elapsed_ms=%.0f",
            action,
            employee_id,
            mean_threshold,
            min_threshold,
            code,
            (time.perf_counter() - t0) * 1000,
        )
        raise

    face_quality = float(observation.score)
    if observation.face_count != 1:
        face_log.warning(
            "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
            "live_face=YES face_count=%s face_quality=%.3f live_embedding=NO "
            "decision=NO_MATCH attendance=NO reason=multiple_faces elapsed_ms=%.0f",
            action,
            employee_id,
            observation.face_count,
            face_quality,
            (time.perf_counter() - t0) * 1000,
        )
        raise HTTPException(
            403,
            detail={
                "code": "multiple_faces",
                "message": "Only one person should be visible during attendance.",
            },
        )

    face_log.info(
        "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
        "gallery_loaded=%s live_embedding=YES face_quality=%.3f",
        action,
        employee_id,
        len(gallery),
        face_quality,
    )

    def _score_probe(probe: list[float]) -> tuple[float, float, float, float, float, bool]:
        probe_mean = mean_match_score(probe, gallery)
        probe_min = min_match_score(probe, gallery)
        probe_centroid = centroid_match_score(probe, gallery)
        probe_best = best_match_score(probe, gallery)
        probe_robust = robust_match_score(probe, gallery)
        ok = identity_match_passed(
            mean_score=probe_mean,
            min_score=probe_min,
            centroid_score=probe_centroid,
            threshold=mean_threshold,
            min_threshold=min_threshold,
        )
        return (
            probe_mean,
            probe_min,
            probe_centroid,
            probe_best,
            probe_robust,
            ok,
        )

    # Score primary orientation first (1:1 vs this employee only).
    mean_score, min_score, centroid_score, best_hit, robust_hit, passed = _score_probe(
        observation.embedding
    )

    # Mirror selfie fallback — only when primary fails (keeps ~1–2s path when match is clear).
    if not passed:
        try:
            mirrored_embedding = observe_mirrored_embedding(face_image_bytes)
            (
                mirror_mean,
                mirror_min,
                mirror_centroid,
                mirror_best,
                mirror_robust,
                mirror_ok,
            ) = _score_probe(mirrored_embedding)
            if mirror_ok or mirror_mean > mean_score or (
                mirror_mean == mean_score and mirror_min > min_score
            ):
                mean_score = mirror_mean
                min_score = mirror_min
                centroid_score = mirror_centroid
                best_hit = mirror_best
                robust_hit = mirror_robust
                passed = mirror_ok
        except Exception:
            pass

    elapsed_ms = (time.perf_counter() - t0) * 1000

    face_log.info(
        "FACE_ATTENDANCE action=%s employee_id=%s registered_embedding=YES "
        "live_embedding=YES face_count=1 face_quality=%.3f "
        "gallery=%s model=%s gallery_consistency=%.4f "
        "similarity_mean=%.4f similarity_min=%.4f similarity_centroid=%.4f "
        "similarity_best=%.4f similarity_robust=%.4f "
        "threshold_mean=%.4f threshold_min=%.4f "
        "decision=%s attendance=%s elapsed_ms=%.0f",
        action,
        employee_id,
        face_quality,
        len(gallery),
        MODEL_VERSION,
        consistency,
        mean_score,
        min_score,
        centroid_score,
        best_hit,
        robust_hit,
        mean_threshold,
        min_threshold,
        "MATCH" if passed else "NO_MATCH",
        "YES" if passed else "NO",
        elapsed_ms,
    )

    if not passed:
        raise HTTPException(
            403,
            detail={
                "code": "face_mismatch",
                "message": (
                    "We couldn’t verify your face. Please make sure your face "
                    "is clearly visible and try again."
                ),
                "match_score": round(mean_score, 4),
                "min_score": round(min_score, 4),
                "centroid_score": round(centroid_score, 4),
                "threshold": mean_threshold,
                "min_threshold": min_threshold,
            },
        )
    return mean_score


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
    from app.services.leave_requests import raise_if_on_approved_leave
    from app.services.missing_clock_out import ensure_incomplete_for_employee

    today = business_today(business_timezone)
    raise_if_on_approved_leave(db, employee=employee, work_date=today)
    ensure_incomplete_for_employee(
        db, employee, business_timezone=business_timezone
    )

    location = _primary_location(db, employee.business_id)
    latitude, longitude = substitute_demo_worksite_coordinates(
        business=load_business_for_employee(db, employee),
        location=location,
        latitude=latitude,
        longitude=longitude,
    )
    geofence = _validate_geofence(location, latitude, longitude)

    resolved_score = face_match_score
    if face_image_bytes is not None and resolved_score is None:
        resolved_score = verify_employee_face_match(db, employee, face_image_bytes)

    open_session = _active_record(db, employee, today)
    if open_session is not None:
        raise HTTPException(400, "You are already timed in for this shift.")

    policy = _attendance_policy(db, employee.business_id)
    now_local = business_now(business_timezone).replace(tzinfo=None)
    assignment, shift = _resolve_assignment(
        db,
        employee,
        today,
        shift_assignment_id,
        now_local=now_local,
        early_clock_in_minutes=policy.early_clock_in_minutes,
    )

    existing = _existing_assignment_record(
        db,
        employee_id=employee.id,
        shift_assignment_id=assignment.id,
    )
    if existing is not None:
        if existing.time_in is not None and existing.time_out is None:
            raise HTTPException(400, "You are already timed in for this shift.")
        raise HTTPException(
            400,
            "Attendance for this shift is already complete.",
        )

    scheduled_start = _scheduled_start(assignment.work_date, shift)
    earliest = scheduled_start - timedelta(minutes=policy.early_clock_in_minutes)
    if now_local < earliest:
        raise HTTPException(
            400,
            f"Time In opens {policy.early_clock_in_minutes} minutes before shift start.",
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

    attendance_log.info(
        "ATTENDANCE_AUDIT action=clock_in employee_id=%s result=OK "
        "timestamp=%s face_score=%s lat=%s lng=%s distance_m=%s radius_m=%s "
        "inside_geofence=%s",
        employee.id,
        now_utc.isoformat(),
        resolved_score,
        latitude,
        longitude,
        geofence.get("distance_m"),
        geofence.get("allowed_radius_m"),
        geofence.get("inside_geofence"),
    )

    message = (
        "Timed in successfully."
        if status == AttendanceStatus.in_progress
        else "Timed in successfully. You were marked late."
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
    from app.services.leave_requests import raise_if_on_approved_leave
    from app.services.missing_clock_out import raise_if_incomplete_clock_out

    today = business_today(business_timezone)
    raise_if_on_approved_leave(db, employee=employee, work_date=today)

    location = _primary_location(db, employee.business_id)
    latitude, longitude = substitute_demo_worksite_coordinates(
        business=load_business_for_employee(db, employee),
        location=location,
        latitude=latitude,
        longitude=longitude,
    )
    geofence = _validate_geofence(location, latitude, longitude)

    # If open punch is past end + maximum_overtime_minutes, mark incomplete.
    open_any = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == employee.business_id,
            AttendanceRecord.employee_id == employee.id,
            AttendanceRecord.time_out.is_(None),
            AttendanceRecord.time_in.is_not(None),
            AttendanceRecord.status.in_(
                (
                    AttendanceStatus.in_progress,
                    AttendanceStatus.late,
                    AttendanceStatus.incomplete,
                )
            ),
        )
        .order_by(AttendanceRecord.created_at.desc())
        .first()
    )
    if open_any is not None:
        raise_if_incomplete_clock_out(
            db, open_any, business_timezone=business_timezone
        )

    record = _active_record(db, employee, today)
    if record is None or record.time_in is None:
        raise HTTPException(
            400,
            detail={
                "code": "not_clocked_in",
                "message": "You need to time in before you can time out.",
            },
        )
    if record.time_out is not None:
        raise HTTPException(
            400,
            detail={
                "code": "already_clocked_out",
                "message": "You’ve already completed attendance for this shift.",
            },
        )

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

    worked_minutes = max(
        (now_utc - record.time_in).total_seconds() / 60.0,
        0.0,
    )
    was_late = record.status == AttendanceStatus.late
    if shift is not None and assignment is not None:
        from app.services.attendance_status import resolve_closed_attendance_status

        record.status = resolve_closed_attendance_status(
            time_in=record.time_in,
            time_out=now_utc,
            assignment=assignment,
            shift=shift,
            policy=policy,
            business_timezone=business_timezone,
        )
    else:
        # No assigned shift: fall back to legacy fixed-minute absent bar.
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

    attendance_log.info(
        "ATTENDANCE_AUDIT action=clock_out employee_id=%s result=OK "
        "timestamp=%s face_score=%s lat=%s lng=%s distance_m=%s radius_m=%s "
        "inside_geofence=%s",
        employee.id,
        now_utc.isoformat(),
        face_match_score,
        latitude,
        longitude,
        geofence.get("distance_m"),
        geofence.get("allowed_radius_m"),
        geofence.get("inside_geofence"),
    )

    message = "Timed out successfully."
    if record.status == AttendanceStatus.late:
        message = "Timed out successfully. Late status preserved."
    elif record.status == AttendanceStatus.absent:
        message = "Timed out. Marked absent due to insufficient worked time."
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
