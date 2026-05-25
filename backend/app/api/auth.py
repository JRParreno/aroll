from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.core.security import (
    create_access_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.business import Business
from app.models.employee import Employee
from app.models.user import User
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    TokenResponse,
    UserMeResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Annotated[Session, Depends(get_db)]):
    user = (
        db.query(User)
        .filter(User.email == body.email.lower().strip())
        .first()
    )
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )
    user.last_login_at = datetime.now(timezone.utc)
    db.commit()
    token = create_access_token(
        str(user.id),
        extra={"role": user.role.value, "business_id": str(user.business_id) if user.business_id else None},
    )
    return TokenResponse(
        access_token=token,
        must_change_password=user.must_change_password,
    )


@router.post("/change-password", response_model=TokenResponse)
def change_password(
    body: ChangePasswordRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    if not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    user.password_hash = hash_password(body.new_password)
    user.must_change_password = False
    db.commit()
    token = create_access_token(
        str(user.id),
        extra={"role": user.role.value, "business_id": str(user.business_id) if user.business_id else None},
    )
    return TokenResponse(access_token=token, must_change_password=False)


@router.get("/me", response_model=UserMeResponse)
def me(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    full_name = None
    business_name = None
    if user.role.value == "employee":
        emp = db.query(Employee).filter(Employee.user_id == user.id).first()
        if emp:
            full_name = emp.full_name
    if user.business_id:
        biz = db.get(Business, user.business_id)
        if biz:
            business_name = biz.name
    if user.role.value == "owner" and user.business_id:
        reg = db.query(Business).filter(Business.id == user.business_id).first()
        if reg:
            business_name = reg.name
    emp = db.query(Employee).filter(Employee.user_id == user.id).first()
    if emp:
        full_name = emp.full_name
    return UserMeResponse(
        id=str(user.id),
        email=user.email,
        role=user.role.value,
        business_id=str(user.business_id) if user.business_id else None,
        must_change_password=user.must_change_password,
        full_name=full_name,
        business_name=business_name,
    )
