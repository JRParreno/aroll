from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.core.security import (
    create_access_token,
    hash_password,
    verify_password,
    verify_user_password,
)
from app.db.session import get_db
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import EmployeeStatus, UserRole
from app.models.user import User
from app.schemas.business import BusinessBrandingSettings, BusinessThemeSettings
from app.schemas.auth import (
    BusinessOwnerLoginRequest,
    ChangePasswordRequest,
    LoginRequest,
    TokenResponse,
    UserMeResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _business_branding_response(business: Business | None):
    if business is None:
        return None
    return BusinessBrandingSettings(
        logo_url=business.logo_url,
        owner_profile_image_url=business.owner_profile_image_url,
        display_image_url=business.display_image_url,
        theme=BusinessThemeSettings(**(business.theme_settings or {})),
    )


def _employee_auth_context(
    user: User, db: Session
) -> dict[str, str | None]:
    employee_id = None
    full_name = None
    position = None
    business_name = None
    profile_image_url = None

    if user.business_id:
        biz = db.get(Business, user.business_id)
        if biz:
            business_name = biz.name

    emp = db.query(Employee).filter(Employee.user_id == user.id).first()
    if emp:
        employee_id = str(emp.id)
        full_name = emp.full_name
        position = emp.position_title
        profile_image_url = emp.profile_image_url

    return {
        "employee_id": employee_id,
        "business_id": str(user.business_id) if user.business_id else None,
        "full_name": full_name,
        "position": position,
        "role": user.role.value,
        "business_name": business_name,
        "profile_image_url": profile_image_url,
    }


def _token_response(user: User, db: Session) -> TokenResponse:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return TokenResponse(
        access_token=token,
        must_change_password=user.must_change_password,
        **_employee_auth_context(user, db),
    )


def _resolve_login_user(db: Session, login_id: str) -> User | None:
    normalized = login_id.lower().strip()
    return (
        db.query(User)
        .filter(func.lower(User.email) == normalized)
        .first()
    )


def _normalize_business_code(value: str) -> str:
    return value.strip().upper().replace(" ", "")


def _resolve_business_owner(
    db: Session,
    email: str,
    business_code: str,
) -> tuple[User, Business] | None:
    normalized_email = str(email).lower().strip()
    normalized_code = _normalize_business_code(business_code)

    business = (
        db.query(Business)
        .filter(func.upper(Business.business_code) == normalized_code)
        .first()
    )
    if business is None:
        return None

    user = (
        db.query(User)
        .filter(
            User.business_id == business.id,
            func.lower(User.email) == normalized_email,
            User.role.in_((UserRole.owner, UserRole.manager)),
        )
        .first()
    )
    if user is None:
        return None
    return user, business


def _authenticate_owner_password(
    user: User,
    password: str,
    *,
    business_code: str,
) -> bool:
    if _authenticate_password(user, password):
        return True

    # First-time owners are provisioned with the business code as their password.
    # Accept the code from the business-code field when a custom password fails.
    if user.must_change_password:
        return _authenticate_password(user, _normalize_business_code(business_code))

    return False


def _authenticate_password(user: User, password: str) -> bool:
    ok, canonical = verify_user_password(
        password,
        user.password_hash,
        pending_temporary_password=user.pending_temporary_password,
        must_change_password=user.must_change_password,
    )
    if not ok:
        return False
    if canonical is not None:
        user.password_hash = hash_password(canonical)
    return True


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Annotated[Session, Depends(get_db)]):
    user = _resolve_login_user(db, body.email)
    if user is None or not _authenticate_password(user, body.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if user.role == UserRole.employee:
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account is inactive",
            )
        emp = db.query(Employee).filter(Employee.user_id == user.id).first()
        if emp is None or emp.status == EmployeeStatus.inactive:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account is inactive",
            )
    elif user.role == UserRole.platform_admin:
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account is inactive",
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    user.last_login_at = datetime.now(timezone.utc)
    db.commit()
    return _token_response(user, db)


@router.post("/business-owner-login", response_model=TokenResponse)
def business_owner_login(
    body: BusinessOwnerLoginRequest,
    db: Annotated[Session, Depends(get_db)],
):
    resolved = _resolve_business_owner(db, str(body.email), body.business_code)
    if resolved is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid business code, email, or password",
        )

    user, business = resolved

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid business code, email, or password",
        )

    if not _authenticate_owner_password(
        user,
        body.password,
        business_code=business.business_code,
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid business code, email, or password",
        )

    user.last_login_at = datetime.now(timezone.utc)
    db.commit()
    return _token_response(user, db)


@router.post("/change-password", response_model=TokenResponse)
def change_password(
    body: ChangePasswordRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    if not _authenticate_password(user, body.current_password):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    user.password_hash = hash_password(body.new_password)
    user.must_change_password = False
    user.pending_temporary_password = None
    if user.role == UserRole.employee:
        emp = db.query(Employee).filter(Employee.user_id == user.id).first()
        if emp is not None:
            emp.status = EmployeeStatus.active
    db.commit()
    db.refresh(user)
    return _token_response(user, db)


@router.get("/me", response_model=UserMeResponse)
def me(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
):
    ctx = _employee_auth_context(user, db)
    business_code = None
    setup_completed_at = None
    business = None
    if user.business_id:
        business = db.get(Business, user.business_id)
        if business:
            business_code = business.business_code
            setup_completed_at = business.setup_completed_at
    db.refresh(user)
    return UserMeResponse(
        id=str(user.id),
        email=user.email,
        role=user.role.value,
        business_id=str(user.business_id) if user.business_id else None,
        must_change_password=user.must_change_password,
        employee_id=ctx["employee_id"],
        full_name=ctx["full_name"],
        position=ctx["position"],
        business_name=ctx["business_name"],
        business_code=business_code,
        setup_completed_at=setup_completed_at,
        branding=_business_branding_response(business),
        profile_image_url=ctx["profile_image_url"],
    )
