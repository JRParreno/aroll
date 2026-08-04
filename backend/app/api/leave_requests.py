"""Employee and owner Leave Requests APIs."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.core.request_meta import audit_meta_from_request
from app.db.session import get_db
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import EmployeeStatus, LeaveRequestStatus, LeaveType, UserRole
from app.models.user import User
from app.schemas.leave_request import (
    LeaveRequestCreate,
    LeaveRequestResponse,
    LeaveRequestReviewRequest,
    LeaveRequestUpdate,
)
from app.services.leave_requests import (
    approve_leave_cancellation,
    approve_leave_request,
    cancel_leave_request,
    create_leave_request,
    edit_leave_request,
    get_business_leave_request,
    list_employee_leave_requests,
    list_owner_leave_requests,
    reject_leave_cancellation,
    reject_leave_request,
    serialize_leave_request,
)

employee_router = APIRouter(prefix="/employee", tags=["employee-leave-requests"])
owner_router = APIRouter(prefix="/owner", tags=["owner-leave-management"])


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
    "/leave-requests",
    response_model=LeaveRequestResponse,
    status_code=201,
)
def employee_create_leave_request(
    body: LeaveRequestCreate,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    meta = audit_meta_from_request(request)
    row = create_leave_request(
        db,
        employee=employee,
        business_id=business.id,
        leave_type=body.leave_type,
        start_date=body.start_date,
        end_date=body.end_date,
        reason=body.reason,
        supporting_document=body.supporting_document,
        actor=user,
        **meta,
    )
    return serialize_leave_request(row, employee=employee, include_document=False)


@employee_router.get(
    "/leave-requests",
    response_model=list[LeaveRequestResponse],
)
def employee_list_leave_requests(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    status: Annotated[str | None, Query()] = None,
):
    employee, _business = _current_employee(db, user)
    status_filter = None
    if status not in (None, "", "all", "history"):
        try:
            status_filter = LeaveRequestStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Invalid status filter.") from exc
    rows = list_employee_leave_requests(
        db, employee_id=employee.id, status=status_filter
    )
    return [
        serialize_leave_request(row, employee=employee, include_document=False)
        for row in rows
    ]


@employee_router.get(
    "/leave-requests/{request_id}",
    response_model=LeaveRequestResponse,
)
def employee_get_leave_request(
    request_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    row = get_business_leave_request(
        db, business_id=business.id, request_id=request_id
    )
    if row.employee_id != employee.id:
        raise HTTPException(404, "Leave request not found.")
    return serialize_leave_request(row, employee=employee, include_document=True)


@employee_router.patch(
    "/leave-requests/{request_id}",
    response_model=LeaveRequestResponse,
)
def employee_edit_leave_request(
    request_id: uuid.UUID,
    body: LeaveRequestUpdate,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    row = get_business_leave_request(
        db, business_id=business.id, request_id=request_id
    )
    if row.employee_id != employee.id:
        raise HTTPException(404, "Leave request not found.")
    meta = audit_meta_from_request(request)
    updated = edit_leave_request(
        db,
        request=row,
        employee=employee,
        leave_type=body.leave_type,
        start_date=body.start_date,
        end_date=body.end_date,
        reason=body.reason,
        supporting_document=body.supporting_document,
        actor=user,
        **meta,
    )
    return serialize_leave_request(updated, employee=employee, include_document=True)


@employee_router.post(
    "/leave-requests/{request_id}/cancel",
    response_model=LeaveRequestResponse,
)
def employee_cancel_leave_request(
    request_id: uuid.UUID,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    row = get_business_leave_request(
        db, business_id=business.id, request_id=request_id
    )
    if row.employee_id != employee.id:
        raise HTTPException(404, "Leave request not found.")
    meta = audit_meta_from_request(request)
    updated = cancel_leave_request(
        db,
        request=row,
        employee=employee,
        actor=user,
        **meta,
    )
    return serialize_leave_request(updated, employee=employee, include_document=True)


@owner_router.get(
    "/leave-requests",
    response_model=list[LeaveRequestResponse],
)
def owner_list_leave_requests(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    status: Annotated[str | None, Query()] = "pending",
    employee_id: Annotated[uuid.UUID | None, Query()] = None,
    leave_type: Annotated[str | None, Query()] = None,
    start_date: Annotated[date | None, Query()] = None,
    end_date: Annotated[date | None, Query()] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    status_filter = None
    if status not in (None, "", "all"):
        try:
            status_filter = LeaveRequestStatus(status)
        except ValueError as exc:
            raise HTTPException(400, "Invalid status filter.") from exc
    type_filter = None
    if leave_type not in (None, "", "all"):
        try:
            type_filter = LeaveType(leave_type)
        except ValueError as exc:
            raise HTTPException(400, "Invalid leave type filter.") from exc
    rows = list_owner_leave_requests(
        db,
        business_id=user.business_id,
        status=status_filter,
        employee_id=employee_id,
        leave_type=type_filter,
        start_date=start_date,
        end_date=end_date,
    )
    return [
        serialize_leave_request(request, employee=employee, include_document=False)
        for request, employee in rows
    ]


@owner_router.get(
    "/leave-requests/{request_id}",
    response_model=LeaveRequestResponse,
)
def owner_get_leave_request(
    request_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    request = get_business_leave_request(
        db, business_id=user.business_id, request_id=request_id
    )
    employee = db.get(Employee, request.employee_id)
    return serialize_leave_request(request, employee=employee, include_document=True)


@owner_router.post(
    "/leave-requests/{request_id}/approve",
    response_model=LeaveRequestResponse,
)
def owner_approve_leave_request(
    request_id: uuid.UUID,
    body: LeaveRequestReviewRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    row = get_business_leave_request(
        db, business_id=user.business_id, request_id=request_id
    )
    meta = audit_meta_from_request(request)
    updated = approve_leave_request(
        db,
        request=row,
        reviewer=user,
        remarks=body.remarks,
        is_paid=body.is_paid,
        override_reason=body.override_reason,
        **meta,
    )
    employee = db.get(Employee, updated.employee_id)
    return serialize_leave_request(updated, employee=employee, include_document=True)


@owner_router.post(
    "/leave-requests/{request_id}/reject",
    response_model=LeaveRequestResponse,
)
def owner_reject_leave_request(
    request_id: uuid.UUID,
    body: LeaveRequestReviewRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    row = get_business_leave_request(
        db, business_id=user.business_id, request_id=request_id
    )
    meta = audit_meta_from_request(request)
    updated = reject_leave_request(
        db, request=row, reviewer=user, remarks=body.remarks, **meta
    )
    employee = db.get(Employee, updated.employee_id)
    return serialize_leave_request(updated, employee=employee, include_document=True)


@owner_router.post(
    "/leave-requests/{request_id}/approve-cancellation",
    response_model=LeaveRequestResponse,
)
def owner_approve_leave_cancellation(
    request_id: uuid.UUID,
    body: LeaveRequestReviewRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    row = get_business_leave_request(
        db, business_id=user.business_id, request_id=request_id
    )
    meta = audit_meta_from_request(request)
    updated = approve_leave_cancellation(
        db, request=row, reviewer=user, remarks=body.remarks, **meta
    )
    employee = db.get(Employee, updated.employee_id)
    return serialize_leave_request(updated, employee=employee, include_document=True)


@owner_router.post(
    "/leave-requests/{request_id}/reject-cancellation",
    response_model=LeaveRequestResponse,
)
def owner_reject_leave_cancellation(
    request_id: uuid.UUID,
    body: LeaveRequestReviewRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    row = get_business_leave_request(
        db, business_id=user.business_id, request_id=request_id
    )
    meta = audit_meta_from_request(request)
    updated = reject_leave_cancellation(
        db, request=row, reviewer=user, remarks=body.remarks, **meta
    )
    employee = db.get(Employee, updated.employee_id)
    return serialize_leave_request(updated, employee=employee, include_document=True)
