import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.enums import EmploymentType, PayBasis, UserRole
from app.models.payroll import Position
from app.models.user import User
from app.schemas.owner_setup import (
    PositionCreate,
    PositionPayConfigPayload,
    PositionPayConfigResponse,
    PositionResponse,
    PositionUpdate,
)
from app.services.position_pay_config import (
    replace_pay_configs,
    sync_legacy_position_rates,
)

router = APIRouter(prefix="/positions", tags=["positions"])


def _config_items_from_legacy(
    *,
    pay_basis: PayBasis,
    daily_rate: float | None,
    hourly_rate: float | None,
) -> list[tuple[PayBasis, float]]:
    if pay_basis == PayBasis.hourly:
        return [(PayBasis.hourly, float(hourly_rate))]
    return [(PayBasis.daily, float(daily_rate))]


def _config_items_from_payload(
    configs: list[PositionPayConfigPayload],
) -> list[tuple[PayBasis, float]]:
    return [(c.pay_basis, float(c.rate)) for c in configs]


def _position_response(pos: Position) -> PositionResponse:
    configs = sorted(
        list(getattr(pos, "pay_configs", None) or []),
        key=lambda c: c.pay_basis.value,
    )
    pay_configs = [
        PositionPayConfigResponse(
            id=str(c.id),
            pay_basis=c.pay_basis,
            rate=float(c.rate),
        )
        for c in configs
        if c.pay_basis in (PayBasis.daily, PayBasis.hourly)
    ]
    daily = next(
        (float(c.rate) for c in configs if c.pay_basis == PayBasis.daily),
        float(pos.daily_rate) if pos.daily_rate is not None else None,
    )
    hourly = next(
        (float(c.rate) for c in configs if c.pay_basis == PayBasis.hourly),
        float(pos.hourly_rate) if pos.hourly_rate is not None else None,
    )
    if hourly is not None and daily is None:
        mirror_basis = PayBasis.hourly
    else:
        mirror_basis = getattr(pos, "pay_basis", None) or PayBasis.daily
        if mirror_basis not in (PayBasis.daily, PayBasis.hourly):
            mirror_basis = PayBasis.daily
    employment_type = getattr(pos, "employment_type", None)
    return PositionResponse(
        id=str(pos.id),
        title=pos.title,
        employment_type=employment_type,
        pay_basis=mirror_basis,
        daily_rate=daily,
        hourly_rate=hourly,
        pay_configs=pay_configs,
        description=pos.description,
        is_active=pos.is_active,
    )


def _raise_rate_validation(exc: Exception) -> None:
    raise HTTPException(
        status_code=400,
        detail={"code": "invalid_position_rates", "message": str(exc)},
    )


def _load_business_position(
    db: Session, position_id: uuid.UUID, business_id: uuid.UUID
) -> Position:
    pos = (
        db.query(Position)
        .options(joinedload(Position.pay_configs))
        .filter(Position.id == position_id, Position.business_id == business_id)
        .first()
    )
    if pos is None:
        raise HTTPException(404, "Position not found")
    return pos


@router.get("", response_model=list[PositionResponse])
def list_positions(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    employment_type: Annotated[EmploymentType | None, Query()] = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    query = (
        db.query(Position)
        .options(joinedload(Position.pay_configs))
        .filter(
            Position.business_id == user.business_id,
            Position.is_active.is_(True),
        )
    )
    if employment_type is not None:
        query = query.filter(Position.employment_type == employment_type)
    rows = query.order_by(Position.title).all()
    return [_position_response(p) for p in rows]


@router.post("", response_model=PositionResponse, status_code=201)
def create_position(
    body: PositionCreate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    try:
        if body.pay_configs is not None:
            items = _config_items_from_payload(body.pay_configs)
        else:
            items = _config_items_from_legacy(
                pay_basis=body.pay_basis or PayBasis.daily,
                daily_rate=body.daily_rate,
                hourly_rate=body.hourly_rate,
            )
    except ValueError as exc:
        _raise_rate_validation(exc)

    pos = Position(
        business_id=user.business_id,
        title=body.title,
        employment_type=body.employment_type,
        description=body.description,
    )
    db.add(pos)
    db.flush()
    try:
        replace_pay_configs(pos, items)
    except ValueError as exc:
        _raise_rate_validation(exc)
    db.commit()
    pos = _load_business_position(db, pos.id, user.business_id)
    return _position_response(pos)


@router.put("/{position_id}", response_model=PositionResponse)
def update_position(
    position_id: uuid.UUID,
    body: PositionUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    pos = _load_business_position(db, position_id, user.business_id)

    updates = body.model_dump(exclude_unset=True)
    pay_configs_payload = updates.pop("pay_configs", None)
    legacy_basis = updates.pop("pay_basis", None)
    legacy_daily = updates.pop("daily_rate", None)
    legacy_hourly = updates.pop("hourly_rate", None)

    for field, value in updates.items():
        setattr(pos, field, value)

    try:
        if pay_configs_payload is not None:
            items = _config_items_from_payload(
                [PositionPayConfigPayload(**c) for c in pay_configs_payload]
            )
            replace_pay_configs(pos, items)
        elif any(v is not None for v in (legacy_basis, legacy_daily, legacy_hourly)):
            # Merge into existing configs rather than wiping siblings.
            current = {
                c.pay_basis: float(c.rate) for c in pos.pay_configs
            }
            basis = legacy_basis or pos.pay_basis or PayBasis.daily
            if basis not in (PayBasis.daily, PayBasis.hourly):
                _raise_rate_validation(
                    ValueError(
                        "Position pay_basis must be daily or hourly. "
                        "Monthly pay remains employee-only."
                    )
                )
            if basis == PayBasis.daily:
                rate = (
                    float(legacy_daily)
                    if legacy_daily is not None
                    else current.get(PayBasis.daily)
                    or (
                        float(pos.daily_rate)
                        if pos.daily_rate is not None
                        else None
                    )
                )
            else:
                rate = (
                    float(legacy_hourly)
                    if legacy_hourly is not None
                    else current.get(PayBasis.hourly)
                    or (
                        float(pos.hourly_rate)
                        if pos.hourly_rate is not None
                        else None
                    )
                )
            if rate is None or rate <= 0:
                _raise_rate_validation(
                    ValueError(f"A positive rate is required for {basis.value}.")
                )
            current[basis] = rate
            replace_pay_configs(pos, list(current.items()))
        else:
            sync_legacy_position_rates(pos)
    except ValueError as exc:
        _raise_rate_validation(exc)

    db.commit()
    pos = _load_business_position(db, position_id, user.business_id)
    return _position_response(pos)


@router.delete("/{position_id}")
def delete_position(
    position_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    pos = db.get(Position, position_id)
    if pos is None or pos.business_id != user.business_id:
        raise HTTPException(404, "Position not found")
    pos.is_active = False
    db.commit()
    return {"status": "ok"}
