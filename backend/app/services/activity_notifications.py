"""Employee/owner activity notifications for existing Aroll+ workflows.

Helpers never raise to callers. Inbox rows are created only after the
related business record has already been committed by the caller, except
where the helper itself uses notify_* which commits independently.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, time
from typing import Any

from sqlalchemy.orm import Session

from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import OvertimeApprovalStatus, UserRole
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.notifications import (
    notification_exists_for_entity,
    notify_user,
    notify_user_once,
)
from app.services.payroll_adjustments import display_name

logger = logging.getLogger("aroll.notifications")


def _safe(label: str, fn) -> None:
    try:
        fn()
    except Exception:
        logger.exception("notification helper failed action=%s", label)


def _employee_user(db: Session, employee: Employee | None) -> User | None:
    if employee is None or employee.user_id is None:
        return None
    user = db.get(User, employee.user_id)
    if user is None or not user.is_active:
        return None
    return user


def _employee_by_id(db: Session, employee_id: uuid.UUID) -> Employee | None:
    return db.get(Employee, employee_id)


def format_clock(value: time | None) -> str:
    if value is None:
        return "--"
    return value.strftime("%I:%M %p").lstrip("0")


def format_work_date(value: date | None) -> str:
    if value is None:
        return "the scheduled date"
    return value.strftime("%b %d, %Y")


def format_period(start: date, end: date) -> str:
    return f"{format_work_date(start)} – {format_work_date(end)}"


def format_money(amount: float) -> str:
    return f"PHP {float(amount):,.2f}"


def shift_window_label(shift: Shift | None) -> str:
    if shift is None:
        return ""
    return f"{format_clock(shift.start_time)} to {format_clock(shift.end_time)}"


def _ot_minutes_label(minutes: float | None) -> str:
    if minutes is None or minutes <= 0:
        return ""
    if minutes >= 60:
        hours = minutes / 60.0
        return f" ({hours:.1f} hours)"
    return f" ({int(round(minutes))} minutes)"


def _assignment_and_shift(
    db: Session, record: AttendanceRecord
) -> tuple[ShiftAssignment | None, Shift | None]:
    assignment = None
    if record.shift_assignment_id is not None:
        assignment = db.get(ShiftAssignment, record.shift_assignment_id)
    shift = db.get(Shift, assignment.shift_id) if assignment is not None else None
    return assignment, shift


def overtime_identifying_label(db: Session, record: AttendanceRecord) -> str:
    assignment, shift = _assignment_and_shift(db, record)
    work_date = assignment.work_date if assignment is not None else None
    date_label = format_work_date(work_date)
    if shift is None:
        return date_label
    return f"{date_label} ({shift.name})"


def _qualifying_ot_minutes(db: Session, record: AttendanceRecord) -> float | None:
    assignment, shift = _assignment_and_shift(db, record)
    if assignment is None or shift is None:
        return None
    from app.models.attendance_policy import BusinessAttendancePolicy
    from app.models.business import Business
    from app.models.payroll import BusinessPayrollConfig
    from app.services.ot_approval import compute_qualifying_ot_for_record

    business = db.get(Business, record.business_id)
    tz = business.timezone if business is not None else "Asia/Manila"
    try:
        minutes, _recovered = compute_qualifying_ot_for_record(
            record=record,
            assignment=assignment,
            shift=shift,
            att_policy=db.get(BusinessAttendancePolicy, record.business_id),
            payroll_config=db.get(BusinessPayrollConfig, record.business_id),
            business_timezone=tz or "Asia/Manila",
        )
    except Exception:
        return None
    return minutes


def notify_owners_once(
    db: Session,
    *,
    business_id: uuid.UUID,
    type: str,
    title: str,
    message: str,
    entity_type: str,
    entity_id: uuid.UUID,
    deep_link: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> int:
    from app.services.notifications import create_notification, _try_push

    owners = (
        db.query(User)
        .filter(
            User.business_id == business_id,
            User.role.in_([UserRole.owner, UserRole.manager]),
            User.is_active.is_(True),
        )
        .all()
    )
    created: list = []
    for user in owners:
        if notification_exists_for_entity(
            db,
            type=type,
            entity_type=entity_type,
            entity_id=entity_id,
            recipient_user_id=user.id,
        ):
            continue
        row = create_notification(
            db,
            business_id=business_id,
            recipient_user_id=user.id,
            recipient_role=user.role.value,
            type=type,
            title=title,
            message=message,
            entity_type=entity_type,
            entity_id=entity_id,
            deep_link=deep_link,
            metadata=metadata,
            commit=False,
        )
        created.append(row)
    if created:
        db.commit()
        for row in created:
            db.refresh(row)
            _try_push(db, row)
    return len(created)


def notify_overtime_pending_if_needed(db: Session, record: AttendanceRecord) -> None:
    """Employee + owners: recorded OT is awaiting approval (not yet approved)."""

    def _run() -> None:
        status = record.ot_approval_status
        if hasattr(status, "value"):
            status = status.value
        if status != OvertimeApprovalStatus.pending.value:
            return
        employee = _employee_by_id(db, record.employee_id)
        user = _employee_user(db, employee)
        label = overtime_identifying_label(db, record)
        if user is not None:
            notify_user_once(
                db,
                user=user,
                type="overtime_submitted",
                title="Overtime Submitted",
                message=(
                    f"Your overtime for {label} has been submitted and is "
                    "awaiting approval."
                ),
                entity_type="attendance_record",
                entity_id=record.id,
                deep_link="/shift-history",
                metadata={"attendance_record_id": str(record.id)},
            )
        name = employee.full_name if employee is not None else "An employee"
        notify_owners_once(
            db,
            business_id=record.business_id,
            type="overtime_submitted",
            title="Overtime Awaiting Approval",
            message=f"{name} submitted overtime for {label} that needs review.",
            entity_type="attendance_record",
            entity_id=record.id,
            deep_link="/owner/attendance",
            metadata={"attendance_record_id": str(record.id)},
        )

    _safe("overtime_submitted", _run)


def notify_overtime_reviewed(
    db: Session, record: AttendanceRecord, *, approved: bool
) -> None:
    def _run() -> None:
        employee = _employee_by_id(db, record.employee_id)
        user = _employee_user(db, employee)
        if user is None:
            return
        label = overtime_identifying_label(db, record)
        duration = _ot_minutes_label(_qualifying_ot_minutes(db, record))
        if approved:
            notify_user_once(
                db,
                user=user,
                type="overtime_approved",
                title="Overtime Approved",
                message=f"Your overtime for {label} has been approved{duration}.",
                entity_type="attendance_record",
                entity_id=record.id,
                deep_link="/shift-history",
            )
            return
        notify_user_once(
            db,
            user=user,
            type="overtime_rejected",
            title="Overtime Not Approved",
            message=f"Your overtime for {label} was not approved.",
            entity_type="attendance_record",
            entity_id=record.id,
            deep_link="/shift-history",
        )

    _safe("overtime_reviewed", _run)


def notify_payroll_adjustment_event(
    db: Session,
    row: PayrollAdjustment,
    *,
    action: str,
) -> None:
    def _run() -> None:
        employee = _employee_by_id(db, row.employee_id)
        user = _employee_user(db, employee)
        if user is None:
            return
        period = format_period(row.period_start, row.period_end)
        kind_label = "earning" if row.kind == "allowance" else "deduction"
        name = display_name(row)
        amount = format_money(float(row.amount))
        if action == "added":
            notify_user_once(
                db,
                user=user,
                type="payroll_adjustment_added",
                title="Payroll Adjustment Added",
                message=(
                    f"A {amount} {name} ({kind_label}) was added to your payroll "
                    f"for {period}."
                ),
                entity_type="payroll_adjustment",
                entity_id=row.id,
                deep_link="/payslip",
            )
            return
        if action == "changed":
            notify_user(
                db,
                user=user,
                type="payroll_adjustment_changed",
                title="Payroll Adjustment Updated",
                message=(
                    f"Your {name} payroll adjustment for {period} was updated to "
                    f"{amount} ({kind_label})."
                ),
                entity_type="payroll_adjustment",
                entity_id=row.id,
                deep_link="/payslip",
            )
            return
        notify_user_once(
            db,
            user=user,
            type="payroll_adjustment_removed",
            title="Payroll Adjustment Removed",
            message=f"Your {name} payroll adjustment for {period} was removed.",
            entity_type="payroll_adjustment",
            entity_id=row.id,
            deep_link="/payslip",
        )

    _safe(f"payroll_adjustment_{action}", _run)


def notify_schedule_assigned(
    db: Session,
    *,
    assignment: ShiftAssignment,
    shift: Shift,
    employee: Employee | None = None,
) -> None:
    def _run() -> None:
        emp = employee or _employee_by_id(db, assignment.employee_id)
        user = _employee_user(db, emp)
        if user is None:
            return
        notify_user_once(
            db,
            user=user,
            type="schedule_assigned",
            title="New Schedule",
            message=(
                f"You have a new shift scheduled for "
                f"{format_work_date(assignment.work_date)} from "
                f"{shift_window_label(shift)}."
            ),
            entity_type="shift_assignment",
            entity_id=assignment.id,
            deep_link="/schedule",
            metadata={
                "work_date": assignment.work_date.isoformat(),
                "shift_id": str(shift.id),
            },
        )

    _safe("schedule_assigned", _run)


def notify_schedule_changed(
    db: Session,
    *,
    assignment: ShiftAssignment,
    shift: Shift,
    employee: Employee | None = None,
) -> None:
    def _run() -> None:
        emp = employee or _employee_by_id(db, assignment.employee_id)
        user = _employee_user(db, emp)
        if user is None:
            return
        notify_user(
            db,
            user=user,
            type="schedule_changed",
            title="Schedule Updated",
            message=(
                f"Your shift on {format_work_date(assignment.work_date)} was "
                f"changed to {shift_window_label(shift)}."
            ),
            entity_type="shift_assignment",
            entity_id=assignment.id,
            deep_link="/schedule",
            metadata={
                "work_date": assignment.work_date.isoformat(),
                "shift_id": str(shift.id),
            },
        )

    _safe("schedule_changed", _run)


def notify_schedule_cancelled(
    db: Session,
    *,
    employee: Employee,
    work_date: date,
    shift: Shift,
    assignment_id: uuid.UUID,
) -> None:
    def _run() -> None:
        user = _employee_user(db, employee)
        if user is None:
            return
        notify_user_once(
            db,
            user=user,
            type="schedule_cancelled",
            title="Shift Cancelled",
            message=(
                f"Your shift on {format_work_date(work_date)} from "
                f"{shift_window_label(shift)} was cancelled."
            ),
            entity_type="shift_assignment",
            entity_id=assignment_id,
            deep_link="/schedule",
            metadata={"work_date": work_date.isoformat(), "shift_id": str(shift.id)},
        )

    _safe("schedule_cancelled", _run)


def notify_schedule_reuse_applied(
    db: Session,
    *,
    removed: list[dict[str, Any]],
    created: list[dict[str, Any]],
) -> None:
    def _run() -> None:
        removed_keys = {
            (item["employee"].id, item["work_date"], item["shift"].id)
            for item in removed
        }
        created_keys = {
            (item["employee_id"], item["work_date"], item["shift"].id)
            for item in created
        }
        for item in removed:
            key = (item["employee"].id, item["work_date"], item["shift"].id)
            if key in created_keys:
                continue
            notify_schedule_cancelled(
                db,
                employee=item["employee"],
                work_date=item["work_date"],
                shift=item["shift"],
                assignment_id=item["assignment_id"],
            )
        for item in created:
            key = (item["employee_id"], item["work_date"], item["shift"].id)
            if key in removed_keys:
                continue
            assignment = item.get("assignment")
            if assignment is None:
                continue
            employee = _employee_by_id(db, item["employee_id"])
            notify_schedule_assigned(
                db,
                assignment=assignment,
                shift=item["shift"],
                employee=employee,
            )

    _safe("schedule_reuse", _run)
