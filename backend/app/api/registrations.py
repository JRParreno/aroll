from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.business import BusinessRegistration
from app.models.enums import RegistrationStatus
from app.schemas.registration import RegistrationCreate, RegistrationResponse

router = APIRouter(prefix="/registrations", tags=["registrations"])


@router.post("", response_model=RegistrationResponse, status_code=201)
def submit_registration(
    body: RegistrationCreate,
    db: Annotated[Session, Depends(get_db)],
):
    reg = BusinessRegistration(
        business_name=body.business_name,
        owner_name=body.owner_name,
        owner_email=body.owner_email.lower(),
        owner_phone=body.owner_phone,
        proposed_address=body.proposed_address,
        status=RegistrationStatus.pending,
    )
    db.add(reg)
    db.commit()
    db.refresh(reg)
    return RegistrationResponse(
        id=str(reg.id),
        business_name=reg.business_name,
        owner_name=reg.owner_name,
        owner_email=reg.owner_email,
        status=reg.status.value,
        submitted_at=reg.submitted_at,
    )
