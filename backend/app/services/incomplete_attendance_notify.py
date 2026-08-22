"""Notify employee + owners when attendance is marked incomplete (deduped)."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.models.attendance import AttendanceRecord
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.scheduling import ShiftAssignment
from app.models.user import User
from app.services.notifications import (
    create_notification,
    notification_exists_for_entity,
    notify_user,
)


def notify_incomplete_attendance(
    db: Session,
    *,
    record: AttendanceRecord,
    employee: Employee | None = None,
) -> None:
    """Send one employee + owner notification per unresolved incomplete record."""
    if employee is None:
        employee = db.get(Employee, record.employee_id)
    if employee is None:
        return

    work_date_label = ""
    if record.shift_assignment_id is not None:
        assignment = db.get(ShiftAssignment, record.shift_assignment_id)
        if assignment is not None:
            work_date_label = assignment.work_date.strftime("%B %d, %Y")

    name = employee.full_name
    date_part = f" on {work_date_label}" if work_date_label else ""
    deep_link = (
        f"/shift-history?attendance_record_id={record.id}"
        f"&shift_assignment_id={record.shift_assignment_id or ''}"
    )

    if employee.user_id is not None:
        emp_user = db.get(User, employee.user_id)
        if emp_user is not None and not notification_exists_for_entity(
            db,
            type="incomplete_attendance",
            entity_type="attendance_record",
            entity_id=record.id,
            recipient_user_id=emp_user.id,
        ):
            try:
                notify_user(
                    db,
                    user=emp_user,
                    type="incomplete_attendance",
                    title="Incomplete Attendance",
                    message=(
                        f"You forgot to time out{date_part}. "
                        "Please submit your correct time-out time."
                    ),
                    entity_type="attendance_record",
                    entity_id=record.id,
                    deep_link=deep_link,
                    metadata={"attendance_record_id": str(record.id)},
                )
            except Exception:
                pass

    owners = (
        db.query(User)
        .filter(
            User.business_id == record.business_id,
            User.role.in_([UserRole.owner, UserRole.manager]),
            User.is_active.is_(True),
        )
        .all()
    )
    created = 0
    for owner in owners:
        if notification_exists_for_entity(
            db,
            type="incomplete_attendance",
            entity_type="attendance_record",
            entity_id=record.id,
            recipient_user_id=owner.id,
        ):
            continue
        try:
            create_notification(
                db,
                business_id=record.business_id,
                recipient_user_id=owner.id,
                recipient_role=owner.role.value,
                type="incomplete_attendance",
                title="Incomplete Attendance",
                message=(
                    f"{name} has an incomplete attendance requiring review"
                    f"{date_part}."
                ),
                entity_type="attendance_record",
                entity_id=record.id,
                deep_link="/owner/attendance",
                metadata={
                    "attendance_record_id": str(record.id),
                    "employee_id": str(employee.id),
                },
                commit=False,
            )
            created += 1
        except Exception:
            pass
    if created:
        try:
            db.commit()
        except Exception:
            pass
