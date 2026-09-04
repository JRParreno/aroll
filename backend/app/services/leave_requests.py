"""Leave Requests create / edit / cancel / approve / reject and day helpers."""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, LeaveRequestStatus, LeaveType
from app.models.leave_request import LeaveRequest
from app.models.scheduling import ShiftAssignment
from app.models.user import User
from app.services.activity_logger import create_log
from app.services.notifications import (
    notify_business_owners,
    notify_user,
    notify_user_once,
)

LEAVE_TYPE_LABELS: dict[LeaveType, str] = {
    LeaveType.sick: "Sick Leave",
    LeaveType.vacation: "Vacation Leave",
    LeaveType.emergency: "Emergency Leave",
    LeaveType.maternity: "Maternity Leave",
    LeaveType.paternity: "Paternity Leave",
    LeaveType.unpaid: "Unpaid Leave",
    LeaveType.other: "Other",
}

MAX_SUPPORTING_DOCUMENT_CHARS = 3_500_000

ACTIVE_LEAVE_STATUSES = (
    LeaveRequestStatus.pending,
    LeaveRequestStatus.approved,
    LeaveRequestStatus.cancellation_pending,
)


def leave_type_label(leave_type: LeaveType) -> str:
    return LEAVE_TYPE_LABELS.get(leave_type, leave_type.value)


def is_leave_type_paid(leave_type: LeaveType) -> bool:
    """Legacy default used only as a last-resort fallback.

    Prefer company Leave Policy via leave_policy.is_leave_type_paid_for_business,
    and prefer stored leave_request.is_paid for payroll.
    """
    return leave_type != LeaveType.unpaid


def _apply_policy_snapshot(
    db: Session,
    *,
    business_id: uuid.UUID,
    leave_type: LeaveType,
    request: LeaveRequest,
) -> None:
    from app.services.leave_policy import is_leave_type_paid_for_business

    policy_paid = is_leave_type_paid_for_business(
        db, business_id=business_id, leave_type=leave_type
    )
    request.policy_is_paid = policy_paid
    request.is_paid = policy_paid
    request.is_paid_overridden = False


def inclusive_leave_days(start_date: date, end_date: date) -> int:
    return (end_date - start_date).days + 1


def iter_dates(start_date: date, end_date: date):
    current = start_date
    while current <= end_date:
        yield current
        current += timedelta(days=1)


def validate_supporting_document(document: str | None) -> str | None:
    if document is None:
        return None
    value = document.strip()
    if not value:
        return None
    if len(value) > MAX_SUPPORTING_DOCUMENT_CHARS:
        raise HTTPException(400, "Supporting document is too large.")
    lowered = value.lower()
    if not (
        lowered.startswith("data:image/")
        or lowered.startswith("data:application/pdf")
    ):
        raise HTTPException(
            400,
            "Supporting document must be an image or PDF.",
        )
    return value


def _snapshot(request: LeaveRequest) -> dict:
    return {
        "leave_type": request.leave_type.value,
        "start_date": request.start_date.isoformat(),
        "end_date": request.end_date.isoformat(),
        "reason": request.reason,
        "leave_days": request.leave_days,
    }


def serialize_leave_request(
    request: LeaveRequest,
    *,
    employee: Employee | None = None,
    include_document: bool = False,
) -> dict:
    previous = None
    if request.has_pending_changes and request.previous_start_date is not None:
        prev_type = request.previous_leave_type or request.leave_type
        previous = {
            "leave_type": prev_type,
            "leave_type_label": leave_type_label(prev_type),
            "start_date": request.previous_start_date,
            "end_date": request.previous_end_date,
            "leave_days": inclusive_leave_days(
                request.previous_start_date,
                request.previous_end_date or request.previous_start_date,
            ),
            "reason": request.previous_reason or "",
            "has_supporting_document": bool(request.previous_supporting_document),
            "supporting_document": (
                request.previous_supporting_document if include_document else None
            ),
            "is_paid": (
                request.policy_is_paid
                if request.previous_leave_type == request.leave_type
                else is_leave_type_paid(prev_type)
            ),
        }

    return {
        "id": request.id,
        "business_id": request.business_id,
        "employee_id": request.employee_id,
        "employee_name": employee.full_name if employee else None,
        "employee_position": (
            employee.position_title if employee is not None else None
        ),
        "employee_profile_image_url": (
            employee.profile_image_url if employee is not None else None
        ),
        "leave_type": request.leave_type,
        "leave_type_label": leave_type_label(request.leave_type),
        "start_date": request.start_date,
        "end_date": request.end_date,
        "leave_days": request.leave_days,
        "reason": request.reason,
        "supporting_document": (
            request.supporting_document if include_document else None
        ),
        "has_supporting_document": bool(request.supporting_document),
        "status": request.status,
        "policy_is_paid": bool(request.policy_is_paid),
        "is_paid": bool(request.is_paid),
        "is_paid_overridden": bool(request.is_paid_overridden),
        "has_pending_changes": bool(request.has_pending_changes),
        "previous_request": previous,
        "owner_remarks": request.owner_remarks,
        "reviewed_by": request.reviewed_by,
        "reviewed_at": request.reviewed_at,
        "created_at": request.created_at,
        "updated_at": request.updated_at,
    }


def approved_leave_covering_date(
    db: Session,
    *,
    employee_id: uuid.UUID,
    work_date: date,
) -> LeaveRequest | None:
    return (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.employee_id == employee_id,
            LeaveRequest.status == LeaveRequestStatus.approved,
            LeaveRequest.start_date <= work_date,
            LeaveRequest.end_date >= work_date,
        )
        .order_by(LeaveRequest.created_at.desc())
        .first()
    )


def pending_leave_covering_date(
    db: Session,
    *,
    employee_id: uuid.UUID,
    work_date: date,
) -> LeaveRequest | None:
    return (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.employee_id == employee_id,
            LeaveRequest.status.in_(
                [
                    LeaveRequestStatus.pending,
                    LeaveRequestStatus.cancellation_pending,
                ]
            ),
            LeaveRequest.start_date <= work_date,
            LeaveRequest.end_date >= work_date,
        )
        .order_by(LeaveRequest.created_at.desc())
        .first()
    )


def employee_on_approved_leave(
    db: Session,
    *,
    employee_id: uuid.UUID,
    work_date: date,
) -> bool:
    return approved_leave_covering_date(
        db, employee_id=employee_id, work_date=work_date
    ) is not None


def approved_leave_dates_for_employee(
    db: Session,
    *,
    employee_id: uuid.UUID,
    period_start: date,
    period_end: date,
) -> list[date]:
    """Calendar dates with approved leave overlapping a pay period (sorted)."""
    rows = (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.employee_id == employee_id,
            LeaveRequest.status == LeaveRequestStatus.approved,
            LeaveRequest.start_date <= period_end,
            LeaveRequest.end_date >= period_start,
        )
        .all()
    )
    dates: set[date] = set()
    for request in rows:
        for day in iter_dates(
            max(request.start_date, period_start),
            min(request.end_date, period_end),
        ):
            dates.add(day)
    return sorted(dates)


def leave_type_for_attendance_day(
    db: Session,
    *,
    employee_id: uuid.UUID,
    work_date: date,
) -> LeaveType | None:
    leave = approved_leave_covering_date(
        db, employee_id=employee_id, work_date=work_date
    )
    return leave.leave_type if leave else None


def leave_is_paid_for_attendance_day(
    db: Session,
    *,
    employee_id: uuid.UUID,
    work_date: date,
) -> bool | None:
    """Return stored leave_request.is_paid for payroll (never live policy)."""
    leave = approved_leave_covering_date(
        db, employee_id=employee_id, work_date=work_date
    )
    if leave is None:
        return None
    return bool(leave.is_paid)


def _assert_no_overlap(
    db: Session,
    *,
    employee_id: uuid.UUID,
    start_date: date,
    end_date: date,
    exclude_id: uuid.UUID | None = None,
) -> None:
    query = db.query(LeaveRequest).filter(
        LeaveRequest.employee_id == employee_id,
        LeaveRequest.status.in_(list(ACTIVE_LEAVE_STATUSES)),
        LeaveRequest.start_date <= end_date,
        LeaveRequest.end_date >= start_date,
    )
    if exclude_id is not None:
        query = query.filter(LeaveRequest.id != exclude_id)
    if query.first() is not None:
        raise HTTPException(
            400,
            "You already have a pending or approved leave request that overlaps "
            "these dates.",
        )


def create_leave_request(
    db: Session,
    *,
    employee: Employee,
    business_id: uuid.UUID,
    leave_type: LeaveType,
    start_date: date,
    end_date: date,
    reason: str,
    supporting_document: str | None,
    actor: User,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if end_date < start_date:
        raise HTTPException(400, "End date must be on or after the start date.")
    reason_clean = reason.strip()
    if len(reason_clean) < 3:
        raise HTTPException(400, "Please provide a short reason for the leave.")

    days = inclusive_leave_days(start_date, end_date)
    if days > 366:
        raise HTTPException(400, "Leave request cannot exceed 366 days.")

    _assert_no_overlap(
        db,
        employee_id=employee.id,
        start_date=start_date,
        end_date=end_date,
    )

    document = validate_supporting_document(supporting_document)
    request = LeaveRequest(
        business_id=business_id,
        employee_id=employee.id,
        leave_type=leave_type,
        start_date=start_date,
        end_date=end_date,
        leave_days=days,
        reason=reason_clean,
        supporting_document=document,
        status=LeaveRequestStatus.pending,
        has_pending_changes=False,
        policy_is_paid=True,
        is_paid=True,
        is_paid_overridden=False,
    )
    _apply_policy_snapshot(
        db, business_id=business_id, leave_type=leave_type, request=request
    )
    db.add(request)
    db.commit()
    db.refresh(request)

    create_log(
        db,
        user_id=actor.id,
        action="leave_request_submitted",
        description=(
            f"Employee {employee.full_name} submitted {leave_type_label(leave_type)} "
            f"from {start_date} to {end_date} ({days} day(s)). "
            f"Company policy: {'Paid' if request.policy_is_paid else 'Unpaid'} Leave."
        ),
        new_value=json.dumps(
            {
                **_snapshot(request),
                "policy_is_paid": request.policy_is_paid,
                "is_paid": request.is_paid,
            }
        ),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    notify_business_owners(
        db,
        business_id=business_id,
        type="leave_submitted",
        title="Leave Request",
        message=f"{employee.full_name} submitted a Leave Request.",
        entity_type="leave_request",
        entity_id=request.id,
        deep_link=f"/owner/leave/{request.id}",
    )
    if employee.user_id is not None:
        emp_user = db.get(User, employee.user_id)
        if emp_user is not None:
            notify_user_once(
                db,
                user=emp_user,
                type="leave_submitted",
                title="Leave Request Submitted",
                message="Your leave request was submitted and is awaiting approval.",
                entity_type="leave_request",
                entity_id=request.id,
                deep_link=f"/leave-requests/{request.id}",
            )
    db.refresh(request)
    return request


def _clear_on_leave_records(db: Session, request: LeaveRequest) -> None:
    for work_date in iter_dates(request.start_date, request.end_date):
        assignments = (
            db.query(ShiftAssignment)
            .filter(
                ShiftAssignment.employee_id == request.employee_id,
                ShiftAssignment.work_date == work_date,
            )
            .all()
        )
        for assignment in assignments:
            records = (
                db.query(AttendanceRecord)
                .filter(
                    AttendanceRecord.employee_id == request.employee_id,
                    AttendanceRecord.shift_assignment_id == assignment.id,
                    AttendanceRecord.status == AttendanceStatus.on_leave,
                )
                .all()
            )
            for record in records:
                db.delete(record)


def _ensure_on_leave_records(db: Session, request: LeaveRequest) -> int:
    created_or_updated = 0
    for work_date in iter_dates(request.start_date, request.end_date):
        assignments = (
            db.query(ShiftAssignment)
            .filter(
                ShiftAssignment.employee_id == request.employee_id,
                ShiftAssignment.work_date == work_date,
            )
            .all()
        )
        if not assignments:
            continue
        for assignment in assignments:
            record = (
                db.query(AttendanceRecord)
                .filter(
                    AttendanceRecord.employee_id == request.employee_id,
                    AttendanceRecord.shift_assignment_id == assignment.id,
                )
                .order_by(AttendanceRecord.created_at.desc())
                .first()
            )
            if record is None:
                record = AttendanceRecord(
                    business_id=request.business_id,
                    employee_id=request.employee_id,
                    shift_assignment_id=assignment.id,
                    status=AttendanceStatus.on_leave,
                    time_in=None,
                    time_out=None,
                )
                db.add(record)
                created_or_updated += 1
                continue

            if record.time_in is not None and record.status not in (
                AttendanceStatus.absent,
                AttendanceStatus.incomplete,
                AttendanceStatus.on_leave,
            ):
                continue

            record.status = AttendanceStatus.on_leave
            record.time_in = None
            record.time_out = None
            created_or_updated += 1
    return created_or_updated


def edit_leave_request(
    db: Session,
    *,
    request: LeaveRequest,
    employee: Employee,
    leave_type: LeaveType,
    start_date: date,
    end_date: date,
    reason: str,
    supporting_document: str | None,
    actor: User,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if request.status not in (
        LeaveRequestStatus.pending,
        LeaveRequestStatus.approved,
    ):
        raise HTTPException(
            400,
            "Only pending or approved leave requests can be edited.",
        )
    if end_date < start_date:
        raise HTTPException(400, "End date must be on or after the start date.")
    reason_clean = reason.strip()
    if len(reason_clean) < 3:
        raise HTTPException(400, "Please provide a short reason for the leave.")
    days = inclusive_leave_days(start_date, end_date)
    if days > 366:
        raise HTTPException(400, "Leave request cannot exceed 366 days.")

    _assert_no_overlap(
        db,
        employee_id=employee.id,
        start_date=start_date,
        end_date=end_date,
        exclude_id=request.id,
    )

    previous = _snapshot(request)
    was_approved = request.status == LeaveRequestStatus.approved

    if was_approved:
        _clear_on_leave_records(db, request)

    request.previous_leave_type = request.leave_type
    request.previous_start_date = request.start_date
    request.previous_end_date = request.end_date
    request.previous_reason = request.reason
    request.previous_supporting_document = request.supporting_document
    request.has_pending_changes = True

    request.leave_type = leave_type
    request.start_date = start_date
    request.end_date = end_date
    request.leave_days = days
    request.reason = reason_clean
    if supporting_document is not None:
        request.supporting_document = validate_supporting_document(supporting_document)
    request.status = LeaveRequestStatus.pending
    request.owner_remarks = None
    request.reviewed_by = None
    request.reviewed_at = None
    # Re-snapshot from current company policy when employee edits leave type.
    _apply_policy_snapshot(
        db,
        business_id=request.business_id,
        leave_type=leave_type,
        request=request,
    )

    db.commit()
    db.refresh(request)

    create_log(
        db,
        user_id=actor.id,
        action="leave_request_edited",
        description=(
            f"Employee {employee.full_name} updated leave request "
            f"{request.id}."
        ),
        previous_value=json.dumps(previous),
        new_value=json.dumps(
            {
                **_snapshot(request),
                "policy_is_paid": request.policy_is_paid,
                "is_paid": request.is_paid,
            }
        ),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    notify_business_owners(
        db,
        business_id=request.business_id,
        type="leave_updated",
        title="Leave Request Updated",
        message=f"{employee.full_name} updated their Leave Request.",
        entity_type="leave_request",
        entity_id=request.id,
        deep_link=f"/owner/leave/{request.id}",
    )
    db.refresh(request)
    return request


def cancel_leave_request(
    db: Session,
    *,
    request: LeaveRequest,
    employee: Employee,
    actor: User,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if request.status == LeaveRequestStatus.pending:
        previous = _snapshot(request)
        request.status = LeaveRequestStatus.cancelled
        request.has_pending_changes = False
        db.commit()
        db.refresh(request)
        create_log(
            db,
            user_id=actor.id,
            action="leave_request_cancelled",
            description=f"Employee {employee.full_name} cancelled a pending leave request.",
            previous_value=json.dumps(previous),
            new_value=json.dumps({"status": "cancelled"}),
            platform=platform,
            device=device,
            ip_address=ip_address,
        )
        notify_business_owners(
            db,
            business_id=request.business_id,
            type="leave_updated",
            title="Leave Request Cancelled",
            message=f"{employee.full_name} cancelled a pending Leave Request.",
            entity_type="leave_request",
            entity_id=request.id,
            deep_link=f"/owner/leave/{request.id}",
        )
        if employee.user_id is not None:
            emp_user = db.get(User, employee.user_id)
            if emp_user is not None:
                notify_user_once(
                    db,
                    user=emp_user,
                    type="leave_cancelled",
                    title="Leave Request Cancelled",
                    message="Your pending leave request was cancelled.",
                    entity_type="leave_request",
                    entity_id=request.id,
                    deep_link=f"/leave-requests/{request.id}",
                )
        db.refresh(request)
        return request

    if request.status == LeaveRequestStatus.approved:
        previous = _snapshot(request)
        request.status = LeaveRequestStatus.cancellation_pending
        db.commit()
        db.refresh(request)
        create_log(
            db,
            user_id=actor.id,
            action="leave_cancellation_requested",
            description=(
                f"Employee {employee.full_name} requested cancellation of approved leave."
            ),
            previous_value=json.dumps(previous),
            new_value=json.dumps({"status": "cancellation_pending"}),
            platform=platform,
            device=device,
            ip_address=ip_address,
        )
        notify_business_owners(
            db,
            business_id=request.business_id,
            type="leave_cancellation_requested",
            title="Leave Cancellation",
            message=(
                f"{employee.full_name} requested to cancel their approved leave."
            ),
            entity_type="leave_request",
            entity_id=request.id,
            deep_link=f"/owner/leave/{request.id}",
        )
        if employee.user_id is not None:
            emp_user = db.get(User, employee.user_id)
            if emp_user is not None:
                notify_user_once(
                    db,
                    user=emp_user,
                    type="leave_cancellation_requested",
                    title="Leave Cancellation Submitted",
                    message=(
                        "Your leave cancellation was submitted and is awaiting "
                        "approval."
                    ),
                    entity_type="leave_request",
                    entity_id=request.id,
                    deep_link=f"/leave-requests/{request.id}",
                )
        db.refresh(request)
        return request

    raise HTTPException(
        400,
        "Only pending or approved leave requests can be cancelled.",
    )


def approve_leave_request(
    db: Session,
    *,
    request: LeaveRequest,
    reviewer: User,
    remarks: str | None,
    is_paid: bool | None = None,
    override_reason: str | None = None,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if request.status != LeaveRequestStatus.pending:
        raise HTTPException(400, "Only pending leave requests can be approved.")

    previous = {
        **_snapshot(request),
        "policy_is_paid": request.policy_is_paid,
        "is_paid": request.is_paid,
        "is_paid_overridden": request.is_paid_overridden,
    }
    original_treatment = bool(request.policy_is_paid)
    effective_paid = original_treatment if is_paid is None else bool(is_paid)
    overridden = effective_paid != original_treatment
    reason_clean = (override_reason or "").strip() or None

    request.is_paid = effective_paid
    request.is_paid_overridden = overridden
    request.status = LeaveRequestStatus.approved
    request.owner_remarks = (remarks or "").strip() or None
    request.reviewed_by = reviewer.id
    request.reviewed_at = datetime.now(timezone.utc)
    request.has_pending_changes = False
    request.previous_leave_type = None
    request.previous_start_date = None
    request.previous_end_date = None
    request.previous_reason = None
    request.previous_supporting_document = None
    _ensure_on_leave_records(db, request)
    db.commit()
    db.refresh(request)

    employee = db.get(Employee, request.employee_id)
    name = employee.full_name if employee else str(request.employee_id)
    create_log(
        db,
        user_id=reviewer.id,
        action="leave_request_approved",
        description=(
            f"Approved leave for {name}: {leave_type_label(request.leave_type)} "
            f"{request.start_date} to {request.end_date}. "
            f"Payroll: {'Paid' if request.is_paid else 'Unpaid'} Leave."
            + (f" Remarks: {request.owner_remarks}" if request.owner_remarks else "")
        ),
        previous_value=json.dumps(previous),
        new_value=json.dumps(
            {
                **_snapshot(request),
                "status": "approved",
                "policy_is_paid": request.policy_is_paid,
                "is_paid": request.is_paid,
                "is_paid_overridden": request.is_paid_overridden,
            }
        ),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    if overridden:
        create_log(
            db,
            user_id=reviewer.id,
            action="leave_payroll_treatment_overridden",
            description=(
                f"Owner overrode Leave Policy for leave request {request.id}. "
                f"Original: {'Paid' if original_treatment else 'Unpaid'} Leave → "
                f"New: {'Paid' if effective_paid else 'Unpaid'} Leave."
                + (f" Reason: {reason_clean}" if reason_clean else "")
            ),
            previous_value=json.dumps(
                {
                    "leave_request_id": str(request.id),
                    "policy_is_paid": original_treatment,
                    "payroll_treatment": "paid" if original_treatment else "unpaid",
                }
            ),
            new_value=json.dumps(
                {
                    "leave_request_id": str(request.id),
                    "is_paid": effective_paid,
                    "payroll_treatment": "paid" if effective_paid else "unpaid",
                    "override_reason": reason_clean,
                    "owner_id": str(reviewer.id),
                }
            ),
            platform=platform,
            device=device,
            ip_address=ip_address,
        )
    if employee and employee.user_id:
        user = db.get(User, employee.user_id)
        if user is not None:
            notify_user_once(
                db,
                user=user,
                type="leave_approved",
                title="Leave Approved",
                message="Your leave request was approved.",
                entity_type="leave_request",
                entity_id=request.id,
                deep_link=f"/leave-requests/{request.id}",
            )
    db.refresh(request)
    return request


def reject_leave_request(
    db: Session,
    *,
    request: LeaveRequest,
    reviewer: User,
    remarks: str | None,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if request.status != LeaveRequestStatus.pending:
        raise HTTPException(400, "Only pending leave requests can be rejected.")

    previous = _snapshot(request)
    request.status = LeaveRequestStatus.rejected
    request.owner_remarks = (remarks or "").strip() or None
    request.reviewed_by = reviewer.id
    request.reviewed_at = datetime.now(timezone.utc)
    request.has_pending_changes = False
    db.commit()
    db.refresh(request)

    employee = db.get(Employee, request.employee_id)
    name = employee.full_name if employee else str(request.employee_id)
    create_log(
        db,
        user_id=reviewer.id,
        action="leave_request_rejected",
        description=(
            f"Rejected leave for {name}: {leave_type_label(request.leave_type)} "
            f"{request.start_date} to {request.end_date}."
            + (f" Remarks: {request.owner_remarks}" if request.owner_remarks else "")
        ),
        previous_value=json.dumps(previous),
        new_value=json.dumps({"status": "rejected"}),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    if employee and employee.user_id:
        user = db.get(User, employee.user_id)
        if user is not None:
            notify_user_once(
                db,
                user=user,
                type="leave_rejected",
                title="Leave Rejected",
                message="Your leave request was rejected.",
                entity_type="leave_request",
                entity_id=request.id,
                deep_link=f"/leave-requests/{request.id}",
            )
    db.refresh(request)
    return request


def approve_leave_cancellation(
    db: Session,
    *,
    request: LeaveRequest,
    reviewer: User,
    remarks: str | None,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if request.status != LeaveRequestStatus.cancellation_pending:
        raise HTTPException(400, "Only cancellation-pending requests can be approved.")

    previous = _snapshot(request)
    _clear_on_leave_records(db, request)
    request.status = LeaveRequestStatus.cancelled
    request.owner_remarks = (remarks or "").strip() or None
    request.reviewed_by = reviewer.id
    request.reviewed_at = datetime.now(timezone.utc)
    request.has_pending_changes = False
    db.commit()
    db.refresh(request)

    employee = db.get(Employee, request.employee_id)
    name = employee.full_name if employee else str(request.employee_id)
    create_log(
        db,
        user_id=reviewer.id,
        action="leave_cancellation_approved",
        description=f"Approved leave cancellation for {name}.",
        previous_value=json.dumps(previous),
        new_value=json.dumps({"status": "cancelled"}),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    if employee and employee.user_id:
        user = db.get(User, employee.user_id)
        if user is not None:
            notify_user_once(
                db,
                user=user,
                type="leave_cancellation_approved",
                title="Leave Cancellation Approved",
                message="Your leave cancellation was approved.",
                entity_type="leave_request",
                entity_id=request.id,
                deep_link=f"/leave-requests/{request.id}",
            )
    db.refresh(request)
    return request


def reject_leave_cancellation(
    db: Session,
    *,
    request: LeaveRequest,
    reviewer: User,
    remarks: str | None,
    platform: str | None = None,
    device: str | None = None,
    ip_address: str | None = None,
) -> LeaveRequest:
    if request.status != LeaveRequestStatus.cancellation_pending:
        raise HTTPException(400, "Only cancellation-pending requests can be rejected.")

    previous = {"status": "cancellation_pending"}
    request.status = LeaveRequestStatus.approved
    request.owner_remarks = (remarks or "").strip() or None
    request.reviewed_by = reviewer.id
    request.reviewed_at = datetime.now(timezone.utc)
    _ensure_on_leave_records(db, request)
    db.commit()
    db.refresh(request)

    employee = db.get(Employee, request.employee_id)
    name = employee.full_name if employee else str(request.employee_id)
    create_log(
        db,
        user_id=reviewer.id,
        action="leave_cancellation_rejected",
        description=f"Rejected leave cancellation for {name}; leave remains approved.",
        previous_value=json.dumps(previous),
        new_value=json.dumps({"status": "approved"}),
        platform=platform,
        device=device,
        ip_address=ip_address,
    )
    if employee and employee.user_id:
        user = db.get(User, employee.user_id)
        if user is not None:
            notify_user_once(
                db,
                user=user,
                type="leave_cancellation_rejected",
                title="Leave Cancellation Rejected",
                message="Your leave cancellation was rejected. Leave remains approved.",
                entity_type="leave_request",
                entity_id=request.id,
                deep_link=f"/leave-requests/{request.id}",
            )
    db.refresh(request)
    return request


def list_employee_leave_requests(
    db: Session,
    *,
    employee_id: uuid.UUID,
    status: LeaveRequestStatus | None = None,
) -> list[LeaveRequest]:
    query = db.query(LeaveRequest).filter(LeaveRequest.employee_id == employee_id)
    if status is not None:
        query = query.filter(LeaveRequest.status == status)
    return query.order_by(LeaveRequest.created_at.desc()).all()


def list_owner_leave_requests(
    db: Session,
    *,
    business_id: uuid.UUID,
    status: LeaveRequestStatus | None = None,
    employee_id: uuid.UUID | None = None,
    leave_type: LeaveType | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
) -> list[tuple[LeaveRequest, Employee]]:
    query = (
        db.query(LeaveRequest, Employee)
        .join(Employee, LeaveRequest.employee_id == Employee.id)
        .filter(LeaveRequest.business_id == business_id)
    )
    if status is not None:
        query = query.filter(LeaveRequest.status == status)
    if employee_id is not None:
        query = query.filter(LeaveRequest.employee_id == employee_id)
    if leave_type is not None:
        query = query.filter(LeaveRequest.leave_type == leave_type)
    if start_date is not None:
        query = query.filter(LeaveRequest.end_date >= start_date)
    if end_date is not None:
        query = query.filter(LeaveRequest.start_date <= end_date)
    return query.order_by(LeaveRequest.created_at.desc()).all()


def get_business_leave_request(
    db: Session,
    *,
    business_id: uuid.UUID,
    request_id: uuid.UUID,
) -> LeaveRequest:
    request = (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.id == request_id,
            LeaveRequest.business_id == business_id,
        )
        .first()
    )
    if request is None:
        raise HTTPException(404, "Leave request not found.")
    return request


def raise_if_on_approved_leave(
    db: Session,
    *,
    employee: Employee,
    work_date: date,
) -> None:
    leave = approved_leave_covering_date(
        db, employee_id=employee.id, work_date=work_date
    )
    if leave is None:
        return
    raise HTTPException(
        status_code=400,
        detail={
            "code": "on_leave",
            "message": (
                "You are on approved leave for this day. Time In and Time Out "
                "are not required."
            ),
            "leave_request_id": str(leave.id),
            "leave_type": leave.leave_type.value,
        },
    )


def approved_leave_dates_for_employees(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_ids: list[uuid.UUID],
    start_date: date,
    end_date: date,
) -> dict[uuid.UUID, set[date]]:
    if not employee_ids:
        return {}
    rows = (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.business_id == business_id,
            LeaveRequest.employee_id.in_(employee_ids),
            LeaveRequest.status == LeaveRequestStatus.approved,
            LeaveRequest.start_date <= end_date,
            LeaveRequest.end_date >= start_date,
        )
        .all()
    )
    result: dict[uuid.UUID, set[date]] = {eid: set() for eid in employee_ids}
    for request in rows:
        for day in iter_dates(
            max(request.start_date, start_date),
            min(request.end_date, end_date),
        ):
            result.setdefault(request.employee_id, set()).add(day)
    return result


def pending_leave_dates_for_employees(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_ids: list[uuid.UUID],
    start_date: date,
    end_date: date,
) -> dict[uuid.UUID, set[date]]:
    if not employee_ids:
        return {}
    rows = (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.business_id == business_id,
            LeaveRequest.employee_id.in_(employee_ids),
            LeaveRequest.status == LeaveRequestStatus.pending,
            LeaveRequest.start_date <= end_date,
            LeaveRequest.end_date >= start_date,
        )
        .all()
    )
    result: dict[uuid.UUID, set[date]] = {eid: set() for eid in employee_ids}
    for request in rows:
        for day in iter_dates(
            max(request.start_date, start_date),
            min(request.end_date, end_date),
        ):
            result.setdefault(request.employee_id, set()).add(day)
    return result


def leave_availability_for_date(
    db: Session,
    *,
    business_id: uuid.UUID,
    employee_ids: list[uuid.UUID],
    work_date: date,
) -> dict[uuid.UUID, dict[str, bool]]:
    approved = approved_leave_dates_for_employees(
        db,
        business_id=business_id,
        employee_ids=employee_ids,
        start_date=work_date,
        end_date=work_date,
    )
    pending = pending_leave_dates_for_employees(
        db,
        business_id=business_id,
        employee_ids=employee_ids,
        start_date=work_date,
        end_date=work_date,
    )
    return {
        eid: {
            "on_leave": work_date in approved.get(eid, set()),
            "leave_pending": work_date in pending.get(eid, set()),
        }
        for eid in employee_ids
    }
