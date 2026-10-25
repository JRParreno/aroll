"""Send the post-approval Business Code email after a committed approval."""

from __future__ import annotations

import html
import smtplib
import ssl
import uuid
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings, smtp_settings
from app.models.business import Business, BusinessRegistration
from app.models.enums import ApplicationStatus, UserRole
from app.models.user import User
from app.services.activity_logger import create_log

EMAIL_NOT_SENT = "not_sent"
EMAIL_SENDING = "sending"
EMAIL_SENT = "sent"
EMAIL_FAILED = "failed"

_SENDING_LOCK_SECONDS = 120
_SAFE_PROVIDER_ERROR = "The email provider could not accept the message."
_SAFE_CONFIG_ERROR = (
    "Email delivery is not configured. Set SMTP_HOST, SMTP_FROM_EMAIL, "
    "and SMTP credentials."
)


class ApprovalEmailConfigError(Exception):
    """SMTP settings are missing."""


def smtp_configured() -> bool:
    current = smtp_settings()
    host = (current.smtp_host or "").strip()
    from_email = (current.smtp_from_email or "").strip()
    if not host or not from_email:
        return False
    username = (current.smtp_username or "").strip()
    if username and not (current.smtp_password or "").strip():
        return False
    return True


def owner_login_url() -> str:
    return (settings.owner_login_url or "http://localhost:5173/owner-login").strip()


def build_approval_email(
    *,
    owner_name: str,
    business_name: str,
    business_code: str,
    owner_email: str,
    login_url: str,
) -> tuple[str, str, str]:
    """Return subject, plain text, and HTML. Caller supplies trusted values."""
    name = (owner_name or "").strip() or "Business Owner"
    subject = "Your Aroll+ Business Registration Has Been Approved"
    text = (
        f"Dear {name},\n\n"
        f"We are pleased to inform you that your business registration for "
        f"{business_name} has been approved.\n\n"
        "Your business account has been created successfully. Please keep the "
        "following information for your first login to Aroll+.\n\n"
        "Business Account Details\n"
        f"- Business Name: {business_name}\n"
        f"- Business Code: {business_code}\n"
        f"- Registered Email Address: {owner_email}\n\n"
        "How to Log In for the First Time\n"
        f"1. Open the existing Aroll+ Business Owner login page: {login_url}\n"
        "2. Enter your Business Code in the Business Code field.\n"
        "3. Enter your registered email address in the Email field.\n"
        "4. Enter your Business Code again in the Password field. Your "
        "Business Code serves as your temporary initial password.\n"
        "5. Sign in and follow the system's instructions to change your "
        "temporary password when prompted.\n\n"
        "Important Security Reminder\n"
        "Your Business Code is confidential and also serves as your initial "
        "password. Do not share it with other individuals. After your first "
        "login, change your temporary password and keep your new credentials "
        "secure.\n\n"
        "If you experience any difficulty accessing your account, please "
        "contact the Aroll+ platform administrator for assistance.\n\n"
        "Thank you for registering with Aroll+. We look forward to supporting "
        "your business through our platform.\n\n"
        "Sincerely,\n\n"
        "Aroll+ Administration Team"
    )
    safe_name = html.escape(name)
    safe_business = html.escape(business_name)
    safe_code = html.escape(business_code)
    safe_email = html.escape(owner_email)
    safe_url = html.escape(login_url)
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(subject)}</title>
</head>
<body style="margin:0;padding:24px;background:#f4f6f8;color:#111827;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.55;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;padding:24px;">
    <p>Dear {safe_name},</p>
    <p>We are pleased to inform you that your business registration for <strong>{safe_business}</strong> has been approved.</p>
    <p>Your business account has been created successfully. Please keep the following information for your first login to Aroll+.</p>
    <p><strong>Business Account Details</strong></p>
    <ul>
      <li>Business Name: {safe_business}</li>
      <li>Business Code: {safe_code}</li>
      <li>Registered Email Address: {safe_email}</li>
    </ul>
    <p><strong>How to Log In for the First Time</strong></p>
    <ol>
      <li>Open the existing Aroll+ Business Owner login page: <a href="{safe_url}">{safe_url}</a></li>
      <li>Enter your Business Code in the Business Code field.</li>
      <li>Enter your registered email address in the Email field.</li>
      <li>Enter your Business Code again in the Password field. Your Business Code serves as your temporary initial password.</li>
      <li>Sign in and follow the system's instructions to change your temporary password when prompted.</li>
    </ol>
    <p><strong>Important Security Reminder</strong></p>
    <p>Your Business Code is confidential and also serves as your initial password. Do not share it with other individuals. After your first login, change your temporary password and keep your new credentials secure.</p>
    <p>If you experience any difficulty accessing your account, please contact the Aroll+ platform administrator for assistance.</p>
    <p>Thank you for registering with Aroll+. We look forward to supporting your business through our platform.</p>
    <p>Sincerely,<br /><br />Aroll+ Administration Team</p>
  </div>
</body>
</html>
"""
    return subject, text, html_body


def build_rejection_email(
    *,
    owner_name: str,
    business_name: str,
    rejection_reason: str | None = None,
) -> tuple[str, str, str]:
    """Return subject, plain text, and HTML for a registration rejection."""
    from app.services.registration_rejection import rejection_reason_lines

    name = (owner_name or "").strip() or "Business Owner"
    business = (business_name or "").strip() or "your business"
    reasons = rejection_reason_lines(rejection_reason)
    subject = "Update on Your Aroll+ Business Registration"
    if reasons:
        reason_text = (
            "After reviewing your registration application, we regret to inform "
            "you that it has not been approved for the following reason(s):\n\n"
            + "\n".join(f"- {item}" for item in reasons)
            + "\n\n"
        )
        reason_html = (
            "<p>After reviewing your registration application, we regret to "
            "inform you that it has not been approved for the following "
            "reason(s):</p><ul>"
            + "".join(f"<li>{html.escape(item)}</li>" for item in reasons)
            + "</ul>"
        )
    else:
        reason_text = (
            "After reviewing your application, we are unable to approve it at "
            "this time.\n\n"
        )
        reason_html = (
            "<p>After reviewing your application, we are unable to approve it "
            "at this time.</p>"
        )
    text = (
        f"Dear {name},\n\n"
        f"Thank you for applying to register {business} with Aroll+.\n\n"
        f"{reason_text}"
        "You may update your documents and resubmit your application for review "
        "through the existing Aroll+ registration tracking process.\n\n"
        "If you have questions about this decision, please contact the Aroll+ "
        "platform administrator for assistance.\n\n"
        "Sincerely,\n\n"
        "Aroll+ Administration Team"
    )
    safe_name = html.escape(name)
    safe_business = html.escape(business)
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(subject)}</title>
</head>
<body style="margin:0;padding:24px;background:#f4f6f8;color:#111827;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.55;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;padding:24px;">
    <p>Dear {safe_name},</p>
    <p>Thank you for applying to register <strong>{safe_business}</strong> with Aroll+.</p>
    {reason_html}
    <p>You may update your documents and resubmit your application for review through the existing Aroll+ registration tracking process.</p>
    <p>If you have questions about this decision, please contact the Aroll+ platform administrator for assistance.</p>
    <p>Sincerely,<br /><br />Aroll+ Administration Team</p>
  </div>
</body>
</html>
"""
    return subject, text, html_body


def send_rejection_message(registration: BusinessRegistration) -> str:
    """Send a rejection notice to the registering owner's email.

    Does not change registration status. Caller must persist rejection first.
    Returns the recipient address on success.
    """
    if not smtp_configured():
        raise ApprovalEmailConfigError(_SAFE_CONFIG_ERROR)
    recipient = (registration.owner_email or "").strip()
    if not recipient:
        raise RuntimeError("Owner email was not found")
    subject, text_body, html_body = build_rejection_email(
        owner_name=registration.owner_name,
        business_name=registration.business_name,
        rejection_reason=registration.rejection_reason,
    )
    send_message(recipient, subject, text_body, html_body)
    return recipient


def send_message(to_email: str, subject: str, text_body: str, html_body: str) -> None:
    """Deliver one message through SMTP. Tests may replace this function."""
    if not smtp_configured():
        raise ApprovalEmailConfigError(_SAFE_CONFIG_ERROR)
    current = smtp_settings()
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = current.smtp_from_email.strip()
    message["To"] = to_email
    message.set_content(text_body)
    message.add_alternative(html_body, subtype="html")

    host = current.smtp_host.strip()
    port = int(current.smtp_port)
    username = (current.smtp_username or "").strip()
    password = current.smtp_password or ""
    context = ssl.create_default_context()
    if current.smtp_use_ssl:
        client = smtplib.SMTP_SSL(host, port, timeout=30, context=context)
    else:
        client = smtplib.SMTP(host, port, timeout=30)
    try:
        if current.smtp_use_tls and not current.smtp_use_ssl:
            client.starttls(context=context)
        if username:
            client.login(username, password)
        client.send_message(message)
    finally:
        try:
            client.quit()
        except Exception:
            pass


def _safe_error_message(exc: Exception) -> str:
    if isinstance(exc, ApprovalEmailConfigError):
        return _SAFE_CONFIG_ERROR
    return _SAFE_PROVIDER_ERROR


def _sending_lock_active(registration: BusinessRegistration, now: datetime) -> bool:
    if (registration.approval_email_status or "") != EMAIL_SENDING:
        return False
    started = registration.approval_email_sent_at
    if started is None:
        return True
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    return now - started < timedelta(seconds=_SENDING_LOCK_SECONDS)


def send_approved_registration_email(
    db: Session,
    registration_id: uuid.UUID,
    *,
    admin_id: uuid.UUID | None = None,
) -> dict:
    """Send login instructions for an already-approved registration.

    Uses the Owner account email and stored Business Code. Ignores any
    client-supplied recipient or code.
    """
    if not smtp_configured():
        raise HTTPException(503, _SAFE_CONFIG_ERROR)

    now = datetime.now(timezone.utc)
    registration = (
        db.query(BusinessRegistration)
        .filter(BusinessRegistration.id == registration_id)
        .with_for_update()
        .first()
    )
    if registration is None:
        raise HTTPException(404, "Registration not found")
    if registration.application_status != ApplicationStatus.approved:
        raise HTTPException(400, "Registration is not approved")

    if _sending_lock_active(registration, now):
        raise HTTPException(
            409,
            "An approval email is already being sent. Try again shortly.",
        )

    business = (
        db.query(Business)
        .filter(Business.registration_id == registration.id)
        .first()
    )
    if business is None or not (business.business_code or "").strip():
        raise HTTPException(400, "Approved business was not found")

    owner = (
        db.query(User)
        .filter(
            User.business_id == business.id,
            User.role == UserRole.owner,
            User.is_active.is_(True),
            func.lower(User.email) == (registration.owner_email or "").lower(),
        )
        .first()
    )
    if owner is None:
        owner = (
            db.query(User)
            .filter(
                User.business_id == business.id,
                User.role == UserRole.owner,
                User.is_active.is_(True),
            )
            .order_by(User.created_at.asc())
            .first()
        )
    if owner is None or not (owner.email or "").strip():
        raise HTTPException(400, "Owner account was not found")

    previously_sent = (registration.approval_email_status or "") == EMAIL_SENT
    registration.approval_email_status = EMAIL_SENDING
    registration.approval_email_sent_at = now
    registration.approval_email_last_error = None
    db.commit()

    recipient = owner.email.strip()
    subject, text_body, html_body = build_approval_email(
        owner_name=registration.owner_name,
        business_name=business.name,
        business_code=business.business_code,
        owner_email=recipient,
        login_url=owner_login_url(),
    )
    try:
        send_message(recipient, subject, text_body, html_body)
    except Exception as exc:
        registration.approval_email_status = EMAIL_FAILED
        registration.approval_email_last_error = _safe_error_message(exc)[:200]
        db.commit()
        if isinstance(exc, ApprovalEmailConfigError):
            raise HTTPException(503, _SAFE_CONFIG_ERROR) from exc
        raise HTTPException(502, _SAFE_PROVIDER_ERROR) from exc

    registration.approval_email_status = EMAIL_SENT
    registration.approval_email_sent_at = datetime.now(timezone.utc)
    registration.approval_email_last_error = None
    db.commit()

    if admin_id is not None:
        try:
            create_log(
                db,
                admin_id,
                "APPROVAL_EMAIL_SENT",
                f"Sent approval login email for {registration.business_name}",
            )
        except Exception:
            pass

    return {
        "status": EMAIL_SENT,
        "recipient": recipient,
        "previously_sent": previously_sent,
    }
