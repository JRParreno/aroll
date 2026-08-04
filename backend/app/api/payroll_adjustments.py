import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.payroll import BusinessPayrollConfig
from app.models.user import User
from app.schemas.payroll_adjustment import (
    PayrollAdjustmentCreateRequest,
    PayrollAdjustmentUpdateRequest,
)
from app.services.pay_period import resolve_pay_period
from app.services.payroll_adjustments import (
    create_adjustment,
    list_active_adjustments,
    preset_catalog,
    serialize_adjustment,
    soft_delete_adjustment,
    update_adjustment,
)

router = APIRouter(prefix="/owner/payroll", tags=["payroll-adjustments"])


def _employee_for_business(
    db: Session, *, business_id: uuid.UUID, employee_id: uuid.UUID
) -> Employee:
    employee = db.get(Employee, employee_id)
    if employee is None or employee.business_id != business_id:
        raise HTTPException(404, "Employee not found")
    return employee


@router.get("/adjustment-types")
def get_adjustment_types(
    _: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return preset_catalog()


@router.get("/{employee_id}/adjustments")
def list_employee_adjustments(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    as_of: Annotated[date | None, Query()] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    _employee_for_business(
        db, business_id=user.business_id, employee_id=employee_id
    )
    config = db.get(BusinessPayrollConfig, user.business_id)
    period_start, period_end = resolve_pay_period(config, today=as_of)
    rows = list_active_adjustments(
        db,
        business_id=user.business_id,
        employee_id=employee_id,
        period_start=period_start,
        period_end=period_end,
    )
    return {
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
        "items": [serialize_adjustment(row) for row in rows],
    }


@router.post("/{employee_id}/adjustments")
def create_employee_adjustment(
    employee_id: uuid.UUID,
    body: PayrollAdjustmentCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    as_of: Annotated[date | None, Query()] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    _employee_for_business(
        db, business_id=user.business_id, employee_id=employee_id
    )
    config = db.get(BusinessPayrollConfig, user.business_id)
    period_start, period_end = resolve_pay_period(config, today=as_of)
    row = create_adjustment(
        db,
        business_id=user.business_id,
        employee_id=employee_id,
        period_start=period_start,
        period_end=period_end,
        kind=body.kind,
        type_key=body.type_key,
        custom_name=body.custom_name,
        description=body.description,
        amount=body.amount,
        actor_id=user.id,
    )
    return serialize_adjustment(row)


@router.patch("/adjustments/{adjustment_id}")
def patch_adjustment(
    adjustment_id: uuid.UUID,
    body: PayrollAdjustmentUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    row = update_adjustment(
        db,
        business_id=user.business_id,
        adjustment_id=adjustment_id,
        kind=body.kind,
        type_key=body.type_key,
        custom_name=body.custom_name,
        description=body.description,
        amount=body.amount,
        actor_id=user.id,
    )
    return serialize_adjustment(row)


@router.delete("/adjustments/{adjustment_id}")
def delete_adjustment(
    adjustment_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    soft_delete_adjustment(
        db,
        business_id=user.business_id,
        adjustment_id=adjustment_id,
        actor_id=user.id,
    )
    return {"ok": True}
