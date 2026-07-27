"""Employee and owner APIs for missed attendance corrections."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceCorrectionStatus, EmployeeStatus, UserRole
from app.models.user import User
from app.schemas.attendance_correction import (
    AttendanceCorrectionCreateRequest,
    AttendanceCorrectionRejectRequest,
    AttendanceCorrectionResponse,
)
from app.services.attendance_correction import (
    approve_correction,
    create_correction_request,
    list_employee_corrections,
    list_owner_corrections,
    reject_correction,
)

employee_router = APIRouter(prefix="/employee", tags=["employee-mobile"])
owner_router = APIRouter(prefix="/owner", tags=["owner-attendance-corrections"])


def _current_employee(db: Session, user: User) -> tuple[Employee, Business]:
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
    if employee.status == EmployeeStatus.inactive or not employee.is_active:
        raise HTTPException(403, "Employee account is inactive")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return employee, business


@employee_router.post(
    "/attendance-corrections",
    response_model=AttendanceCorrectionResponse,
    status_code=201,
)
def employee_create_attendance_correction(
    body: AttendanceCorrectionCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    return create_correction_request(
        db,
        employee=employee,
        business=business,
        shift_assignment_id=body.shift_assignment_id,
        requested_time_in=body.requested_time_in,
        requested_time_out=body.requested_time_out,
        reason=body.reason,
    )


@employee_router.get(
    "/attendance-corrections",
    response_model=list[AttendanceCorrectionResponse],
)
def employee_list_attendance_corrections(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, _business = _current_employee(db, user)
    return list_employee_corrections(db, employee=employee)


@owner_router.get(
    "/attendance-corrections",
    response_model=list[AttendanceCorrectionResponse],
)
def owner_list_attendance_corrections(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    status: Annotated[str | None, Query()] = "pending",
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    status_filter: AttendanceCorrectionStatus | None
    if status in (None, "", "all"):
        status_filter = None
    else:
        try:
            status_filter = AttendanceCorrectionStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Invalid status filter.") from exc
    return list_owner_corrections(
        db,
        business_id=user.business_id,
        status=status_filter,
    )


@owner_router.post(
    "/attendance-corrections/{request_id}/approve",
    response_model=AttendanceCorrectionResponse,
)
def owner_approve_attendance_correction(
    request_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    return approve_correction(
        db,
        request_id=request_id,
        reviewer=user,
        business=business,
    )


@owner_router.post(
    "/attendance-corrections/{request_id}/reject",
    response_model=AttendanceCorrectionResponse,
)
def owner_reject_attendance_correction(
    request_id: uuid.UUID,
    body: AttendanceCorrectionRejectRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    return reject_correction(
        db,
        request_id=request_id,
        reviewer=user,
        business_id=user.business_id,
        review_note=body.review_note,
    )
