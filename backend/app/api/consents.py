"""Employee consent catalog: list resolved documents and accept per document."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.api.employee_mobile import _current_employee
from app.core.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.consent_catalog import (
    EmployeeConsentAcceptRequest,
    EmployeeConsentItem,
    EmployeeConsentsResponse,
)
from app.services.consent_catalog import (
    accept_document,
    consents_completed,
    employee_consent_items,
    get_document,
)

router = APIRouter(tags=["consents"])


def _payload(db, employee, business) -> EmployeeConsentsResponse:
    items = [
        EmployeeConsentItem(**item) for item in employee_consent_items(db, employee, business)
    ]
    return EmployeeConsentsResponse(
        items=items,
        consents_completed=consents_completed(db, employee, business),
    )


@router.get("/consents", response_model=EmployeeConsentsResponse)
def list_employee_consents(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    employee, business = _current_employee(db, user)
    return _payload(db, employee, business)


@router.post("/consents/{document_id}/accept", response_model=EmployeeConsentsResponse)
def accept_employee_consent(
    document_id: UUID,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    body: EmployeeConsentAcceptRequest | None = None,
):
    employee, business = _current_employee(db, user)
    document = get_document(db, document_id)
    accept_document(
        db,
        employee=employee,
        business=business,
        document=document,
        user_id=user.id,
        client=(body.client if body else "mobile"),
        request=request,
    )
    db.commit()
    return _payload(db, employee, business)
