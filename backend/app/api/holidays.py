import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.enums import HolidayType, UserRole
from app.models.holiday import Holiday
from app.models.user import User
from app.schemas.owner_setup import HolidayCreate, HolidayResponse, HolidayUpdate

router = APIRouter(prefix="/holidays", tags=["holidays"])

# (name, month, day, type, default pay multiplier)
PH_DEFAULT_HOLIDAYS: list[tuple[str, int, int, HolidayType, float]] = [
    ("New Year's Day", 1, 1, HolidayType.regular, 2.0),
    ("EDSA People Power Revolution Anniversary", 2, 25, HolidayType.special_non_working, 1.3),
    ("Araw ng Kagitingan", 4, 9, HolidayType.regular, 2.0),
    ("Labor Day", 5, 1, HolidayType.regular, 2.0),
    ("Independence Day", 6, 12, HolidayType.regular, 2.0),
    ("National Heroes Day", 8, 26, HolidayType.regular, 2.0),
    ("All Saints' Day", 11, 1, HolidayType.special_non_working, 1.3),
    ("Bonifacio Day", 11, 30, HolidayType.regular, 2.0),
    ("Feast of the Immaculate Conception", 12, 8, HolidayType.special_non_working, 1.3),
    ("Christmas Day", 12, 25, HolidayType.regular, 2.0),
    ("Rizal Day", 12, 30, HolidayType.regular, 2.0),
]


def _holiday_response(h: Holiday) -> HolidayResponse:
    return HolidayResponse(
        id=str(h.id),
        business_id=str(h.business_id) if h.business_id else None,
        name=h.name,
        holiday_date=h.holiday_date,
        is_paid=h.is_paid,
        pay_multiplier=float(h.pay_multiplier),
        holiday_type=h.holiday_type.value,
        is_active=h.is_active,
    )


@router.get("", response_model=list[HolidayResponse])
def list_holidays(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    rows = (
        db.query(Holiday)
        .filter(
            Holiday.business_id == user.business_id,
            Holiday.is_active.is_(True),
        )
        .order_by(Holiday.holiday_date)
        .all()
    )
    return [_holiday_response(h) for h in rows]


@router.post("", response_model=HolidayResponse, status_code=201)
def create_holiday(
    body: HolidayCreate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    holiday = Holiday(
        business_id=user.business_id,
        name=body.name,
        holiday_date=body.holiday_date,
        is_paid=body.is_paid,
        pay_multiplier=body.pay_multiplier,
        holiday_type=body.holiday_type,
    )
    db.add(holiday)
    db.commit()
    db.refresh(holiday)
    return _holiday_response(holiday)


@router.put("/{holiday_id}", response_model=HolidayResponse)
def update_holiday(
    holiday_id: uuid.UUID,
    body: HolidayUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    holiday = db.get(Holiday, holiday_id)
    if holiday is None or holiday.business_id != user.business_id:
        raise HTTPException(404, "Holiday not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(holiday, field, value)
    db.commit()
    db.refresh(holiday)
    return _holiday_response(holiday)


@router.delete("/{holiday_id}")
def delete_holiday(
    holiday_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    holiday = db.get(Holiday, holiday_id)
    if holiday is None or holiday.business_id != user.business_id:
        raise HTTPException(404, "Holiday not found")
    if holiday.holiday_type != HolidayType.company:
        raise HTTPException(400, "Only custom holidays can be deleted")
    holiday.is_active = False
    db.commit()
    return {"status": "ok"}


@router.post("/seed-defaults", response_model=list[HolidayResponse])
def seed_default_holidays(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    year: int | None = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    target_year = year or date.today().year
    created: list[Holiday] = []

    for name, month, day, htype, multiplier in PH_DEFAULT_HOLIDAYS:
        hdate = date(target_year, month, day)
        exists = (
            db.query(Holiday)
            .filter(
                Holiday.business_id == user.business_id,
                Holiday.holiday_date == hdate,
                Holiday.name == name,
                Holiday.is_active.is_(True),
            )
            .first()
        )
        if exists:
            continue
        holiday = Holiday(
            business_id=user.business_id,
            name=name,
            holiday_date=hdate,
            is_paid=True,
            pay_multiplier=multiplier,
            holiday_type=htype,
        )
        db.add(holiday)
        created.append(holiday)

    db.commit()
    for h in created:
        db.refresh(h)
    return [_holiday_response(h) for h in created]
