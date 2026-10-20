"""Optional OS push delivery for persisted inbox notifications.

Push never replaces the inbox. Failures are logged without tokens or
payroll details and never raise to the caller.
"""

from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.device_push_token import DevicePushToken
from app.models.notification import Notification
from app.models.user import User

logger = logging.getLogger("aroll.push")

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_INVALID_TOKEN_MARKERS = (
    "UNREGISTERED",
    "INVALID_ARGUMENT",
    "NOT_FOUND",
    "registration-token-not-registered",
)


def fcm_configured() -> bool:
    return bool(settings.fcm_project_id and settings.fcm_service_account_json)


def register_device_token(
    db: Session,
    *,
    user: User,
    token: str,
    platform: str,
) -> DevicePushToken:
    cleaned = token.strip()
    platform_norm = platform.strip().lower()
    now = datetime.now(timezone.utc)
    row = (
        db.query(DevicePushToken)
        .filter(DevicePushToken.token == cleaned)
        .first()
    )
    if row is None:
        row = DevicePushToken(
            user_id=user.id,
            business_id=user.business_id,
            token=cleaned,
            platform=platform_norm,
            last_seen_at=now,
        )
        db.add(row)
    else:
        row.user_id = user.id
        row.business_id = user.business_id
        row.platform = platform_norm
        row.last_seen_at = now
    db.commit()
    db.refresh(row)
    return row


def unregister_device_token(db: Session, *, user_id: uuid.UUID, token: str) -> int:
    cleaned = token.strip()
    rows = (
        db.query(DevicePushToken)
        .filter(
            DevicePushToken.user_id == user_id,
            DevicePushToken.token == cleaned,
        )
        .all()
    )
    for row in rows:
        db.delete(row)
    if rows:
        db.commit()
    return len(rows)


def tokens_for_user(db: Session, user_id: uuid.UUID) -> list[DevicePushToken]:
    return (
        db.query(DevicePushToken)
        .filter(DevicePushToken.user_id == user_id)
        .all()
    )


def _service_account_info() -> dict | None:
    raw = (settings.fcm_service_account_json or "").strip()
    if not raw:
        return None
    if raw.startswith("{"):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("FCM service account JSON is invalid")
            return None
        return data if isinstance(data, dict) else None
    try:
        with open(raw, encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError:
        logger.warning("FCM service account file could not be read")
        return None
    return data if isinstance(data, dict) else None


def _fcm_access_token() -> str | None:
    info = _service_account_info()
    if info is None:
        return None
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError:
        logger.info("FCM is configured but google-auth is not installed")
        return None
    try:
        creds = service_account.Credentials.from_service_account_info(
            info, scopes=[_FCM_SCOPE]
        )
        creds.refresh(Request())
    except Exception:
        logger.exception("FCM access token refresh failed")
        return None
    return creds.token


def _send_fcm(token: str, notification: Notification) -> str | None:
    """Return an invalid-token marker when FCM says the token is dead."""
    access = _fcm_access_token()
    if not access:
        return None
    url = (
        f"https://fcm.googleapis.com/v1/projects/{settings.fcm_project_id}"
        "/messages:send"
    )
    body = {
        "message": {
            "token": token,
            "notification": {
                "title": notification.title,
                "body": notification.message,
            },
            "data": {
                "notification_id": str(notification.id),
                "type": notification.type,
                "deep_link": notification.deep_link or "",
            },
        }
    }
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {access}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            response.read()
        return None
    except urllib.error.HTTPError as exc:
        payload = exc.read().decode("utf-8", errors="replace")
        if any(marker in payload for marker in _INVALID_TOKEN_MARKERS):
            return "invalid"
        logger.warning("FCM send failed status=%s", exc.code)
        return None
    except Exception:
        logger.exception("FCM send failed")
        return None


def deliver_notification_push(db: Session, notification: Notification) -> dict:
    """Best-effort push to every registered device for the recipient."""
    result = {"attempted": 0, "invalid_removed": 0, "skipped": True}
    if not fcm_configured():
        return result
    rows = tokens_for_user(db, notification.recipient_user_id)
    if not rows:
        return result
    result["skipped"] = False
    stale: list[DevicePushToken] = []
    for row in rows:
        result["attempted"] += 1
        marker = _send_fcm(row.token, notification)
        if marker == "invalid":
            stale.append(row)
    for row in stale:
        db.delete(row)
        result["invalid_removed"] += 1
    if stale:
        try:
            db.commit()
        except Exception:
            db.rollback()
            logger.exception("failed to drop invalid push tokens")
    return result
