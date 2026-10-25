"""Shift time versioning: protect historical / started assignment windows.

When start_time / end_time / break_minutes change on a Shift that is still
referenced by past assignments, create a new Shift row and retarget only
future + today-unstarted assignments (and template entries). Past assignments
keep the old Shift id so live payroll continues to use the original schedule
window without changing payroll formulas.

Phase 3: if ANY assignment on this Shift has AttendanceRecord.time_in for
today, normal time edits are rejected (HTTP 409) — no successor, no retarget.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.models.attendance import AttendanceRecord
from app.models.schedule_template import ScheduleTemplateEntry
from app.models.scheduling import Shift, ShiftAssignment

TIME_FIELDS = frozenset({"start_time", "end_time", "break_minutes"})

SHIFT_IN_PROGRESS_CODE = "shift_in_progress"
SHIFT_IN_PROGRESS_TITLE = "Shift In Progress"
SHIFT_IN_PROGRESS_MESSAGE = (
    "This shift has already started and cannot be changed. "
    "Changes to an active shift could affect attendance and payroll records."
)


class ShiftInProgressError(Exception):
    """Time edit blocked because at least one assignment has clocked in today."""

    def __init__(self) -> None:
        super().__init__(SHIFT_IN_PROGRESS_MESSAGE)
        self.code = SHIFT_IN_PROGRESS_CODE
        self.title = SHIFT_IN_PROGRESS_TITLE
        self.message = SHIFT_IN_PROGRESS_MESSAGE


SHIFT_DELETE_BLOCKED_CODE = "shift_delete_blocked"
SHIFT_DELETE_BLOCKED_TITLE = "Cannot delete shift"
SHIFT_DELETE_BLOCKED_MESSAGE = (
    "This shift cannot be deleted because an employee assigned to it "
    "is currently timed in. Ask them to complete Time Out, then try again."
)


class ShiftDeleteBlockedError(Exception):
    """Deletion blocked because an assigned employee has Time In and no Time Out."""

    def __init__(self) -> None:
        super().__init__(SHIFT_DELETE_BLOCKED_MESSAGE)
        self.code = SHIFT_DELETE_BLOCKED_CODE
        self.title = SHIFT_DELETE_BLOCKED_TITLE
        self.message = SHIFT_DELETE_BLOCKED_MESSAGE


def shift_delete_blocked_detail() -> dict[str, str]:
    return {
        "code": SHIFT_DELETE_BLOCKED_CODE,
        "title": SHIFT_DELETE_BLOCKED_TITLE,
        "message": SHIFT_DELETE_BLOCKED_MESSAGE,
    }


def time_fields_changing(shift: Shift, updates: dict[str, Any]) -> bool:
    for key in TIME_FIELDS:
        if key not in updates:
            continue
        if updates[key] != getattr(shift, key):
            return True
    return False


def started_assignment_ids(
    db: Session,
    *,
    shift_id: uuid.UUID | None = None,
    employee_id: uuid.UUID | None = None,
    work_date: date,
) -> set[uuid.UUID]:
    """Assignment ids for work_date that already have a punch (time_in)."""
    query = (
        db.query(AttendanceRecord.shift_assignment_id)
        .join(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .filter(
            ShiftAssignment.work_date == work_date,
            AttendanceRecord.time_in.isnot(None),
            AttendanceRecord.shift_assignment_id.isnot(None),
        )
    )
    if shift_id is not None:
        query = query.filter(ShiftAssignment.shift_id == shift_id)
    if employee_id is not None:
        query = query.filter(ShiftAssignment.employee_id == employee_id)
    return {row[0] for row in query.all() if row[0] is not None}


def open_attendance_query(
    db: Session,
    *,
    business_id: uuid.UUID,
    shift_id: uuid.UUID | None = None,
):
    """Attendance rows for this business whose assignment is still open.

    Open means Time In is recorded and Time Out is not. A completed punch
    (both times set) does not match. The link is the assignment: the same
    shift, the same employee, and the same business. Any work date counts,
    so an earlier open session still blocks deletion.
    """
    query = (
        db.query(AttendanceRecord.id)
        .join(
            ShiftAssignment,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            Shift.business_id == business_id,
            AttendanceRecord.business_id == business_id,
            AttendanceRecord.employee_id == ShiftAssignment.employee_id,
            AttendanceRecord.time_in.isnot(None),
            AttendanceRecord.time_out.is_(None),
        )
    )
    if shift_id is not None:
        query = query.filter(Shift.id == shift_id)
    return query


def shift_has_open_attendance(
    db: Session, *, shift_id: uuid.UUID, business_id: uuid.UUID
) -> bool:
    return (
        open_attendance_query(
            db, business_id=business_id, shift_id=shift_id
        ).first()
        is not None
    )


def shift_ids_with_open_attendance(
    db: Session, *, business_id: uuid.UUID
) -> set[uuid.UUID]:
    rows = (
        open_attendance_query(db, business_id=business_id)
        .with_entities(Shift.id)
        .distinct()
        .all()
    )
    return {row[0] for row in rows if row[0] is not None}


def ensure_shift_deletable(db: Session, shift: Shift) -> None:
    """Reject removal while an assigned employee is still timed in."""
    if shift_has_open_attendance(
        db, shift_id=shift.id, business_id=shift.business_id
    ):
        raise ShiftDeleteBlockedError()


def shift_ids_with_in_progress_today(
    db: Session,
    *,
    business_id: uuid.UUID,
    today: date,
) -> set[uuid.UUID]:
    """Catalog shift ids that have at least one today clock-in."""
    rows = (
        db.query(ShiftAssignment.shift_id)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(
            AttendanceRecord,
            AttendanceRecord.shift_assignment_id == ShiftAssignment.id,
        )
        .filter(
            Shift.business_id == business_id,
            ShiftAssignment.work_date == today,
            AttendanceRecord.time_in.isnot(None),
        )
        .distinct()
        .all()
    )
    return {row[0] for row in rows if row[0] is not None}


def shift_has_protected_assignments(
    db: Session, shift_id: uuid.UUID, today: date
) -> bool:
    """True if any assignment must keep the current Shift times (past or started)."""
    if shift_has_past_assignments(db, shift_id, today):
        return True
    return bool(started_assignment_ids(db, shift_id=shift_id, work_date=today))


def shift_has_past_assignments(
    db: Session, shift_id: uuid.UUID, today: date
) -> bool:
    return (
        db.query(ShiftAssignment.id)
        .filter(
            ShiftAssignment.shift_id == shift_id,
            ShiftAssignment.work_date < today,
        )
        .first()
        is not None
    )


def _build_successor_shift(shift: Shift, updates: dict[str, Any]) -> Shift:
    return Shift(
        business_id=shift.business_id,
        name=updates.get("name", shift.name),
        shift_type=updates.get("shift_type", shift.shift_type),
        start_time=updates.get("start_time", shift.start_time),
        end_time=updates.get("end_time", shift.end_time),
        break_minutes=updates.get(
            "break_minutes",
            shift.break_minutes if shift.break_minutes is not None else 0,
        ),
        employee_capacity=updates.get(
            "employee_capacity",
            shift.employee_capacity if shift.employee_capacity is not None else 1,
        ),
        color=updates["color"] if "color" in updates else shift.color,
        is_active=True,
    )


def retarget_unprotected_assignments(
    db: Session,
    *,
    old_shift_id: uuid.UUID,
    new_shift_id: uuid.UUID,
    today: date,
) -> int:
    """Move future + today-unstarted assignments onto the new Shift version."""
    started_today = started_assignment_ids(
        db, shift_id=old_shift_id, work_date=today
    )
    filters = [
        ShiftAssignment.shift_id == old_shift_id,
        or_(
            ShiftAssignment.work_date > today,
            and_(
                ShiftAssignment.work_date == today,
                ~ShiftAssignment.id.in_(started_today)
                if started_today
                else ShiftAssignment.work_date == today,
            ),
        ),
    ]
    return (
        db.query(ShiftAssignment)
        .filter(*filters)
        .update(
            {ShiftAssignment.shift_id: new_shift_id},
            synchronize_session=False,
        )
    )


def retarget_template_entries(
    db: Session, *, old_shift_id: uuid.UUID, new_shift_id: uuid.UUID
) -> int:
    return (
        db.query(ScheduleTemplateEntry)
        .filter(ScheduleTemplateEntry.shift_id == old_shift_id)
        .update(
            {ScheduleTemplateEntry.shift_id: new_shift_id},
            synchronize_session=False,
        )
    )


def apply_shift_updates(
    db: Session,
    shift: Shift,
    updates: dict[str, Any],
    *,
    today: date,
) -> Shift:
    """Apply ShiftUpdate fields with time versioning when required.

    Returns the Shift that should be exposed as the current catalog version
    (either the mutated original or a newly created successor).

    Raises ShiftInProgressError when a time edit is attempted while any
    assignment on this Shift already has time_in for today.

    Raises ShiftDeleteBlockedError when the update would deactivate a shift
    that still has an open attendance session. Time versioning that hides a
    past shift row is unchanged.
    """
    if not updates:
        return shift

    if updates.get("is_active") is False and shift.is_active:
        ensure_shift_deletable(db, shift)

    if not time_fields_changing(shift, updates):
        for field, value in updates.items():
            setattr(shift, field, value)
        return shift

    # Phase 3: reject normal time edits while anyone is clocked in today.
    if started_assignment_ids(db, shift_id=shift.id, work_date=today):
        raise ShiftInProgressError()

    # Phase 2: past-only references → soft-replace; otherwise mutate in place.
    if not shift_has_past_assignments(db, shift.id, today):
        for field, value in updates.items():
            setattr(shift, field, value)
        return shift

    successor = _build_successor_shift(shift, updates)
    db.add(successor)
    db.flush()

    retarget_unprotected_assignments(
        db,
        old_shift_id=shift.id,
        new_shift_id=successor.id,
        today=today,
    )
    retarget_template_entries(
        db, old_shift_id=shift.id, new_shift_id=successor.id
    )

    # Keep old row for historical FKs; hide from active shift pickers.
    shift.is_active = False
    return successor


def assignment_ids_to_remove_on_deactivate(
    db: Session,
    *,
    employee_id: uuid.UUID,
    today: date,
) -> list[uuid.UUID]:
    """Future + today-unstarted assignment ids for deactivation cleanup."""
    started_today = started_assignment_ids(
        db, employee_id=employee_id, work_date=today
    )
    rows = (
        db.query(ShiftAssignment.id)
        .filter(
            ShiftAssignment.employee_id == employee_id,
            or_(
                ShiftAssignment.work_date > today,
                and_(
                    ShiftAssignment.work_date == today,
                    ~ShiftAssignment.id.in_(started_today)
                    if started_today
                    else ShiftAssignment.work_date == today,
                ),
            ),
        )
        .all()
    )
    return [row[0] for row in rows]
