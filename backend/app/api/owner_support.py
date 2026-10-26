from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.enums import UserRole
from app.models.user import User
from app.schemas.support_email import SupportEmailRequest, SupportEmailResponse
from app.services.support_email import SupportEmailError, submit_owner_support_email

router = APIRouter(prefix="/owner", tags=["owner-support"])


@router.post("/support-email", response_model=SupportEmailResponse)
def submit_support_email(
    body: SupportEmailRequest,
    user: Annotated[User, Depends(require_roles(UserRole.owner))],
    db: Annotated[Session, Depends(get_db)],
) -> SupportEmailResponse:
    try:
        detail = submit_owner_support_email(
            db,
            user,
            subject=body.subject,
            message=body.message,
        )
    except SupportEmailError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from None
    return SupportEmailResponse(status="accepted", detail=detail)
