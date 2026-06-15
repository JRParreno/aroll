import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.enums import UserRole
from app.models.payroll import Position
from app.models.user import User
from app.schemas.owner_setup import PositionCreate, PositionResponse, PositionUpdate

router = APIRouter(prefix="/positions", tags=["positions"])


def _position_response(pos: Position) -> PositionResponse:
    return PositionResponse(
        id=str(pos.id),
        title=pos.title,
        daily_rate=float(pos.daily_rate),
        description=pos.description,
        is_active=pos.is_active,
    )


@router.get("", response_model=list[PositionResponse])
def list_positions(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    rows = (
        db.query(Position)
        .filter(Position.business_id == user.business_id, Position.is_active.is_(True))
        .order_by(Position.title)
        .all()
    )
    return [_position_response(p) for p in rows]


@router.post("", response_model=PositionResponse, status_code=201)
def create_position(
    body: PositionCreate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    pos = Position(
        business_id=user.business_id,
        title=body.title,
        daily_rate=body.daily_rate,
        description=body.description,
    )
    db.add(pos)
    db.commit()
    db.refresh(pos)
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
    pos = db.get(Position, position_id)
    if pos is None or pos.business_id != user.business_id:
        raise HTTPException(404, "Position not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(pos, field, value)
    db.commit()
    db.refresh(pos)
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
