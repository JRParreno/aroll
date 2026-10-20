from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.enums import UserRole
from app.services.employee_password_reset import (
    complete_password_reset,
    owner_reset_code_status,
    request_owner_reset_code,
    request_reset_code,
    reset_code_status,
    verify_owner_reset_code,
    verify_reset_code,
)

router = APIRouter(prefix="/auth/employee/password-reset", tags=["auth"])


class ResetCodeRequest(BaseModel):
    username: str = Field(min_length=1, max_length=255)
    email: str = Field(min_length=3, max_length=255)


class ResetCodeStatusResponse(BaseModel):
    message: str
    resend_available_at: str | None = None
    retry_after_seconds: int = 0


class VerifyResetCodeRequest(ResetCodeRequest):
    code: str = Field(min_length=6, max_length=6)


class VerifyResetCodeResponse(BaseModel):
    reset_token: str
    expires_in_seconds: int


class CompleteResetRequest(BaseModel):
    reset_token: str = Field(min_length=20, max_length=255)
    new_password: str = Field(min_length=8, max_length=200)


class CompleteResetResponse(BaseModel):
    message: str


def _status_payload(result: dict) -> ResetCodeStatusResponse:
    available = result.get("resend_available_at")
    return ResetCodeStatusResponse(
        message=result["message"],
        resend_available_at=available.isoformat() if available is not None else None,
        retry_after_seconds=int(result.get("retry_after_seconds") or 0),
    )


@router.post("/status", response_model=ResetCodeStatusResponse)
def password_reset_status(
    body: ResetCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return _status_payload(reset_code_status(db, body.username, body.email))


@router.post("/request", response_model=ResetCodeStatusResponse)
def password_reset_request(
    body: ResetCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return _status_payload(request_reset_code(db, body.username, body.email))


@router.post("/verify", response_model=VerifyResetCodeResponse)
def password_reset_verify(
    body: VerifyResetCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return verify_reset_code(db, body.username, body.email, body.code)


@router.post("/complete", response_model=CompleteResetResponse)
def password_reset_complete(
    body: CompleteResetRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return complete_password_reset(db, body.reset_token, body.new_password)


owner_router = APIRouter(prefix="/auth/owner/password-reset", tags=["auth"])


class OwnerResetCodeRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    business_code: str = Field(min_length=1, max_length=20)


class OwnerVerifyResetCodeRequest(OwnerResetCodeRequest):
    code: str = Field(min_length=6, max_length=6)


@owner_router.post("/status", response_model=ResetCodeStatusResponse)
def owner_password_reset_status(
    body: OwnerResetCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return _status_payload(owner_reset_code_status(db, body.email, body.business_code))


@owner_router.post("/request", response_model=ResetCodeStatusResponse)
def owner_password_reset_request(
    body: OwnerResetCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return _status_payload(
        request_owner_reset_code(db, body.email, body.business_code)
    )


@owner_router.post("/verify", response_model=VerifyResetCodeResponse)
def owner_password_reset_verify(
    body: OwnerVerifyResetCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return verify_owner_reset_code(db, body.email, body.business_code, body.code)


@owner_router.post("/complete", response_model=CompleteResetResponse)
def owner_password_reset_complete(
    body: CompleteResetRequest,
    db: Annotated[Session, Depends(get_db)],
):
    return complete_password_reset(
        db,
        body.reset_token,
        body.new_password,
        role=UserRole.owner,
    )
