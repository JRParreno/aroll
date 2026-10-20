"""Employee recovery email and forgot-password OTP.

OTPs are generated on the server, stored only as bcrypt hashes, and emailed
to the saved recovery address. The API never returns the OTP.
"""

from __future__ import annotations

import hashlib
import html
import math
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from pydantic import EmailStr, TypeAdapter, ValidationError
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.password_validation import validate_password_strength
from app.core.security import hash_password, verify_password
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.password_reset import PasswordResetChallenge
from app.models.user import User
from app.services.approval_email import send_message, smtp_configured

OTP_LENGTH = 6
OTP_TTL = timedelta(minutes=10)
RESEND_COOLDOWN = timedelta(seconds=180)
RESET_TOKEN_TTL = timedelta(minutes=10)
MAX_VERIFY_ATTEMPTS = 5
MAX_CODES_PER_HOUR = 5

NEUTRAL_SENT_MESSAGE = (
    "If the username and recovery email match an employee account, "
    "a verification code has been sent."
)
OWNER_NEUTRAL_SENT_MESSAGE = (
    "If the email and business code match an owner account, "
    "a verification code has been sent."
)
OWNER_PASSWORD_UPDATED_MESSAGE = (
    "Your password was updated. Sign in with your email, business code, "
    "and new password."
)
WAIT_MESSAGE = "Please wait before requesting another code."
HOURLY_LIMIT_MESSAGE = "Too many reset requests. Try again later."
SEND_FAILED_MESSAGE = "We couldn't send a verification code. Please try again."
EMAIL_UNAVAILABLE_MESSAGE = (
    "Email delivery is unavailable right now. Please try again later."
)
PASSWORD_UPDATED_MESSAGE = (
    "Your password was updated. Sign in with your username and new password."
)

_email_adapter = TypeAdapter(EmailStr)


def normalize_username(value: str) -> str:
    return value.strip().lower()


def normalize_recovery_email(value: str) -> str:
    candidate = value.strip().lower()
    try:
        parsed = _email_adapter.validate_python(candidate)
    except ValidationError as exc:
        raise ValueError("Enter a valid email address") from exc
    return str(parsed).strip().lower()


def needs_recovery_email(employee: Employee | None) -> bool:
    if employee is None or not employee.recovery_email_required:
        return False
    return not (employee.recovery_email or "").strip()


def save_recovery_email(employee: Employee, email: str) -> str:
    normalized = normalize_recovery_email(email)
    employee.recovery_email = normalized
    return normalized


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _lookup_key(username: str, email: str) -> str:
    material = f"{normalize_username(username)}\n{email.strip().lower()}".encode()
    return hashlib.sha256(material).hexdigest()


def normalize_business_code(value: str) -> str:
    return value.strip().upper().replace(" ", "")


def _owner_lookup_key(business_code: str, email: str) -> str:
    material = (
        f"owner\n{normalize_business_code(business_code)}\n{email.strip().lower()}"
    ).encode()
    return hashlib.sha256(material).hexdigest()


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _remaining_seconds(until: datetime | None, now: datetime) -> int:
    moment = _as_utc(until)
    if moment is None:
        return 0
    return max(0, int(math.ceil((moment - now).total_seconds())))


def _timing(
    row: PasswordResetChallenge,
    now: datetime,
    *,
    message: str = NEUTRAL_SENT_MESSAGE,
) -> dict:
    available = _as_utc(row.resend_available_at) or now
    return {
        "message": message,
        "resend_available_at": available,
        "retry_after_seconds": _remaining_seconds(row.resend_available_at, now),
    }


def _lock_challenge(db: Session, lookup_key: str) -> PasswordResetChallenge:
    db.execute(
        insert(PasswordResetChallenge)
        .values(
            id=uuid.uuid4(),
            lookup_key=lookup_key,
            attempt_count=0,
            issued_count=0,
        )
        .on_conflict_do_nothing(index_elements=["lookup_key"])
    )
    db.flush()
    return (
        db.query(PasswordResetChallenge)
        .filter(PasswordResetChallenge.lookup_key == lookup_key)
        .with_for_update()
        .one()
    )


def _matching_employee(db: Session, username: str, email: str) -> tuple[User, Employee] | None:
    user = (
        db.query(User)
        .filter(
            User.role == UserRole.employee,
            func.lower(User.email) == normalize_username(username),
            User.is_active.is_(True),
        )
        .first()
    )
    if user is None:
        return None
    employee = db.query(Employee).filter(Employee.user_id == user.id).first()
    if employee is None or not employee.is_active:
        return None
    saved = (employee.recovery_email or "").strip().lower()
    if not saved or saved != email.strip().lower():
        return None
    return user, employee


def _matching_owner(db: Session, email: str, business_code: str) -> User | None:
    """Owner registered email and that owner's business code, together."""
    code = normalize_business_code(business_code)
    if not code:
        return None
    business = (
        db.query(Business)
        .filter(func.upper(Business.business_code) == code)
        .first()
    )
    if business is None:
        return None
    return (
        db.query(User)
        .filter(
            User.business_id == business.id,
            func.lower(User.email) == email.strip().lower(),
            User.role == UserRole.owner,
            User.is_active.is_(True),
        )
        .first()
    )


def _clear_code(row: PasswordResetChallenge) -> None:
    row.user_id = None
    row.code_hash = None
    row.code_expires_at = None
    row.code_consumed_at = None
    row.attempt_count = 0
    row.reset_token_hash = None
    row.reset_token_expires_at = None
    row.reset_token_used_at = None


def _roll_window(row: PasswordResetChallenge, now: datetime) -> None:
    started = _as_utc(row.window_started_at)
    if started is None or now - started >= timedelta(hours=1):
        row.window_started_at = now
        row.issued_count = 0


def _raise_wait(row: PasswordResetChallenge, now: datetime, message: str) -> None:
    timing = _timing(row, now)
    raise HTTPException(
        status_code=429,
        detail={
            "message": message,
            "resend_available_at": timing["resend_available_at"].isoformat(),
            "retry_after_seconds": timing["retry_after_seconds"],
        },
    )


def _generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):0{OTP_LENGTH}d}"


def _build_reset_email(code: str, *, account_label: str = "employee") -> tuple[str, str, str]:
    subject = "Your Aroll+ password reset code"
    text = (
        f"Use this verification code to reset your Aroll+ {account_label} password:\n\n"
        f"{code}\n\n"
        "This code expires in 10 minutes. It can be used once.\n"
        "You can request another code after 3 minutes.\n\n"
        "If you did not request a password reset, ignore this email. "
        "Your password will stay the same.\n"
    )
    safe_code = html.escape(code)
    safe_label = html.escape(account_label)
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:24px;background:#f4f6f8;color:#111827;font-family:Arial,Helvetica,sans-serif;">
  <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:24px;">
    <p>Use this verification code to reset your Aroll+ {safe_label} password:</p>
    <p style="font-size:28px;font-weight:700;letter-spacing:4px;">{safe_code}</p>
    <p>This code expires in 10 minutes. It can be used once.</p>
    <p>You can request another code after 3 minutes.</p>
    <p>If you did not request a password reset, ignore this email. Your password will stay the same.</p>
  </div>
</body>
</html>"""
    return subject, text, html_body


def reset_code_status(db: Session, username: str, email: str) -> dict:
    try:
        normalized_email = normalize_recovery_email(email)
    except ValueError:
        normalized_email = email.strip().lower()
    row = (
        db.query(PasswordResetChallenge)
        .filter(
            PasswordResetChallenge.lookup_key
            == _lookup_key(username, normalized_email)
        )
        .first()
    )
    now = _utcnow()
    if row is None:
        return {
            "message": NEUTRAL_SENT_MESSAGE,
            "resend_available_at": None,
            "retry_after_seconds": 0,
        }
    return _timing(row, now)


def owner_reset_code_status(db: Session, email: str, business_code: str) -> dict:
    try:
        normalized_email = normalize_recovery_email(email)
    except ValueError:
        normalized_email = email.strip().lower()
    row = (
        db.query(PasswordResetChallenge)
        .filter(
            PasswordResetChallenge.lookup_key
            == _owner_lookup_key(business_code, normalized_email)
        )
        .first()
    )
    now = _utcnow()
    if row is None:
        return {
            "message": OWNER_NEUTRAL_SENT_MESSAGE,
            "resend_available_at": None,
            "retry_after_seconds": 0,
        }
    return _timing(row, now, message=OWNER_NEUTRAL_SENT_MESSAGE)


def _normalized_email_or_422(email: str) -> str:
    try:
        return normalize_recovery_email(email)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


def _reserve_challenge(db: Session, lookup_key: str) -> tuple[PasswordResetChallenge, datetime]:
    if not smtp_configured():
        raise HTTPException(status_code=503, detail=EMAIL_UNAVAILABLE_MESSAGE)
    now = _utcnow()
    row = _lock_challenge(db, lookup_key)
    if _remaining_seconds(row.resend_available_at, now) > 0:
        _raise_wait(row, now, WAIT_MESSAGE)
    _roll_window(row, now)
    if row.issued_count >= MAX_CODES_PER_HOUR:
        row.resend_available_at = (_as_utc(row.window_started_at) or now) + timedelta(
            hours=1
        )
        db.commit()
        _raise_wait(row, now, HOURLY_LIMIT_MESSAGE)
    row.issued_count += 1
    row.resend_available_at = now + RESEND_COOLDOWN
    return row, now


def _store_and_send_code(
    db: Session,
    row: PasswordResetChallenge,
    *,
    user_id: uuid.UUID,
    recipient: str,
    account_label: str,
    message: str,
) -> dict:
    now = _utcnow()
    code = _generate_otp()
    row.user_id = user_id
    row.code_hash = hash_password(code)
    row.code_expires_at = now + OTP_TTL
    row.code_consumed_at = None
    row.attempt_count = 0
    row.reset_token_hash = None
    row.reset_token_expires_at = None
    row.reset_token_used_at = None
    subject, text, html_body = _build_reset_email(code, account_label=account_label)
    try:
        send_message(recipient, subject, text, html_body)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=503, detail=SEND_FAILED_MESSAGE)
    db.commit()
    return _timing(row, _utcnow(), message=message)


def request_reset_code(db: Session, username: str, email: str) -> dict:
    if not smtp_configured():
        raise HTTPException(status_code=503, detail=EMAIL_UNAVAILABLE_MESSAGE)
    normalized_email = _normalized_email_or_422(email)
    row, now = _reserve_challenge(db, _lookup_key(username, normalized_email))
    match = _matching_employee(db, username, normalized_email)
    if match is None:
        _clear_code(row)
        db.commit()
        return _timing(row, now)
    user, employee = match
    return _store_and_send_code(
        db,
        row,
        user_id=user.id,
        recipient=employee.recovery_email or "",
        account_label="employee",
        message=NEUTRAL_SENT_MESSAGE,
    )


def request_owner_reset_code(db: Session, email: str, business_code: str) -> dict:
    if not smtp_configured():
        raise HTTPException(status_code=503, detail=EMAIL_UNAVAILABLE_MESSAGE)
    normalized_email = _normalized_email_or_422(email)
    row, now = _reserve_challenge(
        db, _owner_lookup_key(business_code, normalized_email)
    )
    owner = _matching_owner(db, normalized_email, business_code)
    if owner is None:
        _clear_code(row)
        db.commit()
        return _timing(row, now, message=OWNER_NEUTRAL_SENT_MESSAGE)
    return _store_and_send_code(
        db,
        row,
        user_id=owner.id,
        recipient=owner.email,
        account_label="owner",
        message=OWNER_NEUTRAL_SENT_MESSAGE,
    )


def verify_reset_code(db: Session, username: str, email: str, code: str) -> dict:
    normalized_email = _normalized_email_or_422(email)
    return _verify_code(
        db,
        _lookup_key(username, normalized_email),
        code,
        role=UserRole.employee,
    )


def verify_owner_reset_code(db: Session, email: str, business_code: str, code: str) -> dict:
    normalized_email = _normalized_email_or_422(email)
    return _verify_code(
        db,
        _owner_lookup_key(business_code, normalized_email),
        code,
        role=UserRole.owner,
    )


def _verify_code(
    db: Session,
    lookup_key: str,
    code: str,
    *,
    role: UserRole,
) -> dict:
    submitted = code.strip()
    if not submitted.isdigit() or len(submitted) != OTP_LENGTH:
        raise HTTPException(status_code=400, detail="That code is incorrect.")

    now = _utcnow()
    row = _lock_challenge(db, lookup_key)
    if row.code_consumed_at is not None:
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="That code has already been used. Request a new code.",
        )
    if row.user_id is None or not row.code_hash:
        db.commit()
        raise HTTPException(status_code=400, detail="That code is incorrect.")
    user = db.get(User, row.user_id)
    if user is None or user.role != role:
        db.commit()
        raise HTTPException(status_code=400, detail="That code is incorrect.")
    if row.attempt_count >= MAX_VERIFY_ATTEMPTS:
        _clear_code(row)
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="Too many attempts. Request a new code.",
        )
    expires = _as_utc(row.code_expires_at)
    if expires is None or expires <= now:
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="That code has expired. Request a new code.",
        )

    row.attempt_count += 1
    if not verify_password(submitted, row.code_hash):
        if row.attempt_count >= MAX_VERIFY_ATTEMPTS:
            _clear_code(row)
            db.commit()
            raise HTTPException(
                status_code=400,
                detail="Too many attempts. Request a new code.",
            )
        db.commit()
        raise HTTPException(status_code=400, detail="That code is incorrect.")

    token = secrets.token_urlsafe(32)
    row.code_consumed_at = now
    row.reset_token_hash = _token_hash(token)
    row.reset_token_expires_at = now + RESET_TOKEN_TTL
    row.reset_token_used_at = None
    db.commit()
    return {"reset_token": token, "expires_in_seconds": int(RESET_TOKEN_TTL.total_seconds())}


def complete_password_reset(
    db: Session,
    reset_token: str,
    new_password: str,
    *,
    role: UserRole = UserRole.employee,
) -> dict:
    try:
        validate_password_strength(new_password)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    now = _utcnow()
    row = (
        db.query(PasswordResetChallenge)
        .filter(PasswordResetChallenge.reset_token_hash == _token_hash(reset_token))
        .with_for_update()
        .first()
    )
    if row is None or row.user_id is None or row.reset_token_used_at is not None:
        raise HTTPException(
            status_code=400,
            detail="This password reset is no longer valid. Request a new code.",
        )
    expires = _as_utc(row.reset_token_expires_at)
    if expires is None or expires <= now:
        raise HTTPException(
            status_code=400,
            detail="This password reset has expired. Request a new code.",
        )

    user = db.get(User, row.user_id)
    if user is None or user.role != role:
        raise HTTPException(
            status_code=400,
            detail="This password reset is no longer valid. Request a new code.",
        )
    user.password_hash = hash_password(new_password)
    user.must_change_password = False
    user.pending_temporary_password = None
    row.reset_token_used_at = now
    row.reset_token_hash = None
    row.code_hash = None
    db.commit()
    if role == UserRole.owner:
        return {"message": OWNER_PASSWORD_UPDATED_MESSAGE}
    return {"message": PASSWORD_UPDATED_MESSAGE}
