import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.enums import UserRole
from app.models.scheduling import Shift
from app.models.user import User
from app.schemas.owner_setup import ShiftCreate, ShiftResponse, ShiftUpdate

router = APIRouter(prefix="/shifts", tags=["shifts"])


def _shift_response(shift: Shift) -> ShiftResponse:
    return ShiftResponse(
        id=str(shift.id),
        name=shift.name,
        shift_type=shift.shift_type.value,
        start_time=shift.start_time,
        end_time=shift.end_time,
        break_minutes=shift.break_minutes,
        employee_capacity=shift.employee_capacity,
        color=shift.color,
        is_active=shift.is_active,
    )


@router.get("", response_model=list[ShiftResponse])
def list_shifts(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    rows = (
        db.query(Shift)
        .filter(Shift.business_id == user.business_id, Shift.is_active.is_(True))
        .order_by(Shift.start_time)
        .all()
    )
    return [_shift_response(s) for s in rows]


@router.post("", response_model=ShiftResponse, status_code=201)
def create_shift(
    body: ShiftCreate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    shift = Shift(
        business_id=user.business_id,
        name=body.name,
        shift_type=body.shift_type,
        start_time=body.start_time,
        end_time=body.end_time,
        break_minutes=body.break_minutes,
        employee_capacity=body.employee_capacity,
        color=body.color,
    )
    db.add(shift)
    db.commit()
    db.refresh(shift)
    return _shift_response(shift)


@router.put("/{shift_id}", response_model=ShiftResponse)
def update_shift(
    shift_id: uuid.UUID,
    body: ShiftUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    shift = db.get(Shift, shift_id)
    if shift is None or shift.business_id != user.business_id:
        raise HTTPException(404, "Shift not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(shift, field, value)
    db.commit()
    db.refresh(shift)
    return _shift_response(shift)


@router.delete("/{shift_id}")
def delete_shift(
    shift_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    shift = db.get(Shift, shift_id)
    if shift is None or shift.business_id != user.business_id:
        raise HTTPException(404, "Shift not found")
    shift.is_active = False
    db.commit()
    return {"status": "ok"}
