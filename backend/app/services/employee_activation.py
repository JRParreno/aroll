"""Employee account activation for owner workflows.

An employee is fully activated only after both:
- first-time password change (`User.must_change_password` is False)
- successful face registration (`Employee.face_registration_status` is completed)
"""

from __future__ import annotations

from fastapi import HTTPException

from app.models.employee import Employee
from app.models.user import User

FACE_REGISTRATION_COMPLETED = "completed"

NOT_ACTIVATED_SCHEDULE_MESSAGE = (
    "Cannot assign a schedule until the employee account is fully activated "
    "(first-time password change and face registration)."
)


def is_employee_fully_activated(
    employee: Employee,
    user: User | None = None,
) -> bool:
    linked = user if user is not None else getattr(employee, "user", None)
    if linked is None:
        return False
    if bool(getattr(linked, "must_change_password", True)):
        return False
    status = getattr(employee, "face_registration_status", None) or "not_registered"
    return status == FACE_REGISTRATION_COMPLETED


def raise_if_not_activated_for_schedule(
    employees: list[tuple[Employee, User]],
) -> None:
    blocked = [
        employee
        for employee, user in employees
        if not is_employee_fully_activated(employee, user)
    ]
    if not blocked:
        return
    names = ", ".join(employee.full_name for employee in blocked)
    raise HTTPException(
        400,
        f"{NOT_ACTIVATED_SCHEDULE_MESSAGE} {names}",
    )
