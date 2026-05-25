from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.business import BusinessLocation
from app.models.enums import UserRole
from app.models.payroll import BusinessPayrollConfig
from app.models.user import User
from app.schemas.business import LocationUpdate, PayrollConfigUpdate

router = APIRouter(prefix="/businesses", tags=["businesses"])


@router.put("/me/location")
def update_location(
    body: LocationUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    loc = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == user.business_id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if loc is None:
        loc = BusinessLocation(
            business_id=user.business_id,
            label=body.label,
            address=body.address,
            latitude=body.latitude,
            longitude=body.longitude,
            geofence_radius_m=body.geofence_radius_m,
            is_primary=True,
        )
        db.add(loc)
    else:
        loc.label = body.label
        loc.address = body.address
        loc.latitude = body.latitude
        loc.longitude = body.longitude
        loc.geofence_radius_m = body.geofence_radius_m
    db.commit()
    return {"status": "ok"}


@router.put("/me/payroll-config")
def update_payroll_config(
    body: PayrollConfigUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    cfg = db.get(BusinessPayrollConfig, user.business_id)
    if cfg is None:
        cfg = BusinessPayrollConfig(business_id=user.business_id)
        db.add(cfg)
    cfg.pay_period_type = body.pay_period_type
    cfg.late_deduction_enabled = body.late_deduction_enabled
    cfg.late_deduction_per_minute = body.late_deduction_per_minute
    cfg.overtime_enabled = body.overtime_enabled
    cfg.overtime_per_minute = body.overtime_per_minute
    db.commit()
    return {"status": "ok"}
