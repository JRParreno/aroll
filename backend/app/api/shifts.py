import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.core.timezone import business_today
from app.db.session import get_db
from app.models.business import Business
from app.models.enums import UserRole
from app.models.scheduling import Shift
from app.models.user import User
from app.schemas.owner_setup import ShiftCreate, ShiftResponse, ShiftUpdate
from app.services.shift_versioning import (
    ShiftDeleteBlockedError,
    ShiftInProgressError,
    apply_shift_updates,
    ensure_shift_deletable,
    shift_delete_blocked_detail,
    shift_ids_with_in_progress_today,
    shift_ids_with_open_attendance,
)

router = APIRouter(prefix="/shifts", tags=["shifts"])


def _shift_response(
    shift: Shift,
    *,
    has_in_progress_today: bool = False,
    has_open_attendance: bool = False,
) -> ShiftResponse:
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
        has_in_progress_today=has_in_progress_today,
        has_open_attendance=has_open_attendance,
    )


@router.get("", response_model=list[ShiftResponse])
def list_shifts(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    today = business_today(business.timezone if business else None)
    in_progress = shift_ids_with_in_progress_today(
        db, business_id=user.business_id, today=today
    )
    open_attendance = shift_ids_with_open_attendance(
        db, business_id=user.business_id
    )
    rows = (
        db.query(Shift)
        .filter(Shift.business_id == user.business_id, Shift.is_active.is_(True))
        .order_by(Shift.start_time)
        .all()
    )
    return [
        _shift_response(
            s,
            has_in_progress_today=s.id in in_progress,
            has_open_attendance=s.id in open_attendance,
        )
        for s in rows
    ]


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
    return _shift_response(shift, has_in_progress_today=False)


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

    updates = body.model_dump(exclude_unset=True)
    business = db.get(Business, user.business_id)
    today = business_today(business.timezone if business else None)
    try:
        result = apply_shift_updates(db, shift, updates, today=today)
    except ShiftInProgressError as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "code": exc.code,
                "title": exc.title,
                "message": exc.message,
            },
        ) from None
    except ShiftDeleteBlockedError:
        raise HTTPException(
            status_code=409, detail=shift_delete_blocked_detail()
        ) from None
    db.commit()
    db.refresh(result)
    in_progress = shift_ids_with_in_progress_today(
        db, business_id=user.business_id, today=today
    )
    open_attendance = shift_ids_with_open_attendance(
        db, business_id=user.business_id
    )
    return _shift_response(
        result,
        has_in_progress_today=result.id in in_progress,
        has_open_attendance=result.id in open_attendance,
    )


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
    try:
        ensure_shift_deletable(db, shift)
    except ShiftDeleteBlockedError:
        raise HTTPException(
            status_code=409, detail=shift_delete_blocked_detail()
        ) from None
    shift.is_active = False
    db.commit()
    return {"status": "ok"}
