"""Owner Help messages delivered through the existing SMTP settings."""

from __future__ import annotations

import html
import logging
import re
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.employee import Employee
from app.models.user import User
from app.services.approval_email import (
    ApprovalEmailConfigError,
    send_message,
    smtp_configured,
)

logger = logging.getLogger(__name__)

SUPPORT_RECIPIENT = "arollplus1111@gmail.com"
SUBJECT_MAX_LENGTH = 120
MESSAGE_MAX_LENGTH = 4000
_RATE_LIMIT = 5
_RATE_WINDOW = timedelta(minutes=10)
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

CONFIG_ERROR = (
    "Email delivery is not configured. Set SMTP_HOST, SMTP_FROM_EMAIL, "
    "and SMTP credentials."
)
PROVIDER_ERROR = "The email provider could not accept the message."
RATE_LIMIT_ERROR = (
    "Too many support messages were sent. Wait a few minutes and try again."
)
ACCEPTED_DETAIL = (
    "The email provider accepted the message. "
    "Delivery to the inbox is not guaranteed."
)

_attempts: dict[uuid.UUID, list[datetime]] = {}


class SupportEmailError(Exception):
    def __init__(self, message: str, status_code: int) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def reset_support_email_rate_limit() -> None:
    _attempts.clear()


def _clean_header(value: str) -> str:
    return " ".join(value.replace("\r", " ").replace("\n", " ").split())


def _clean_message(value: str) -> str:
    text = value.replace("\x00", "").replace("\r\n", "\n").replace("\r", "\n")
    return text.strip()


def prepare_support_fields(subject: str, message: str) -> tuple[str, str]:
    clean_subject = _clean_header(subject)
    clean_message = _clean_message(message)
    if not clean_subject:
        raise SupportEmailError("Enter a subject.", 422)
    if len(clean_subject) > SUBJECT_MAX_LENGTH:
        raise SupportEmailError(
            f"Subject must be {SUBJECT_MAX_LENGTH} characters or less.",
            422,
        )
    if not clean_message:
        raise SupportEmailError("Enter the concern or message.", 422)
    if len(clean_message) > MESSAGE_MAX_LENGTH:
        raise SupportEmailError(
            f"Message must be {MESSAGE_MAX_LENGTH} characters or less.",
            422,
        )
    return clean_subject, clean_message


def _reply_to(email: str | None) -> str | None:
    candidate = (email or "").strip()
    if any(char in candidate for char in ("\r", "\n", "\x00")):
        return None
    if not _EMAIL_RE.fullmatch(candidate):
        return None
    return candidate


def _reserve_attempt(user_id: uuid.UUID, now: datetime) -> None:
    recent = [
        stamp
        for stamp in _attempts.get(user_id, [])
        if now - stamp < _RATE_WINDOW
    ]
    if len(recent) >= _RATE_LIMIT:
        _attempts[user_id] = recent
        raise SupportEmailError(RATE_LIMIT_ERROR, 429)
    recent.append(now)
    _attempts[user_id] = recent


def submit_owner_support_email(
    db: Session,
    user: User,
    *,
    subject: str,
    message: str,
) -> str:
    """Send one support message. Returns the acceptance detail.

    The recipient is fixed. Business name and owner identity come from the
    authenticated account. Success means the SMTP server accepted the message.
    """
    clean_subject, clean_message = prepare_support_fields(subject, message)
    if user.business_id is None:
        raise SupportEmailError("This account is not linked to a business.", 403)
    business = db.get(Business, user.business_id)
    if business is None:
        raise SupportEmailError("This account is not linked to a business.", 403)

    employee = (
        db.query(Employee)
        .filter(Employee.user_id == user.id, Employee.business_id == business.id)
        .one_or_none()
    )
    owner_name = (employee.full_name.strip() if employee and employee.full_name else "")
    owner_name = owner_name or "Business owner"
    account_email = (user.email or "").strip()
    phone = (employee.phone or "").strip() if employee and employee.phone else ""

    if not smtp_configured():
        raise SupportEmailError(CONFIG_ERROR, 503)

    _reserve_attempt(user.id, datetime.now(timezone.utc))
    mail_subject = f"[Aroll+ Support] {clean_subject}"
    text = (
        "An authenticated Aroll+ business owner submitted this message from Help.\n"
        "The account email below is the address stored on the account. "
        "It has not been independently verified for this message.\n\n"
        f"Business: {business.name}\n"
        f"Owner: {owner_name}\n"
        f"Account email: {account_email or 'Not on file'}\n"
        f"Phone: {phone or 'Not on file'}\n\n"
        "Concern:\n"
        f"{clean_message}\n"
    )
    safe_business = html.escape(business.name)
    safe_owner = html.escape(owner_name)
    safe_email = html.escape(account_email or "Not on file")
    safe_phone = html.escape(phone or "Not on file")
    safe_message = html.escape(clean_message).replace("\n", "<br />")
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<body style="font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.5;color:#111827;">
  <p>An authenticated Aroll+ business owner submitted this message from Help.</p>
  <p>The account email is the address stored on the account. It has not been independently verified for this message.</p>
  <ul>
    <li>Business: {safe_business}</li>
    <li>Owner: {safe_owner}</li>
    <li>Account email: {safe_email}</li>
    <li>Phone: {safe_phone}</li>
  </ul>
  <p><strong>Concern</strong></p>
  <p>{safe_message}</p>
</body>
</html>
"""
    try:
        send_message(
            SUPPORT_RECIPIENT,
            mail_subject,
            text,
            html_body,
            reply_to=_reply_to(account_email),
        )
    except ApprovalEmailConfigError:
        raise SupportEmailError(CONFIG_ERROR, 503) from None
    except SupportEmailError:
        raise
    except Exception as exc:
        logger.warning(
            "Owner support email was not accepted (%s).",
            type(exc).__name__,
        )
        raise SupportEmailError(PROVIDER_ERROR, 502) from None
    return ACCEPTED_DETAIL
