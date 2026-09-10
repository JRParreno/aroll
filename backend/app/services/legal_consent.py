"""Owner-configured legal pages and typed consent records."""

from __future__ import annotations

import html
import uuid
from datetime import datetime, timezone

from fastapi import HTTPException, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.consent_record import ConsentRecord
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.face_liveness import FaceLivenessChallenge
from app.services.activity_logger import add_log

LEGAL_PAGE_PREFIX = "/legal/b/"
LEGAL_API_PREFIX = "/api/v1/public/legal/"
MAX_LEGAL_CHARS = 50_000

DEFAULT_TERMS_VERSION = "terms-2026-09-09"
DEFAULT_PRIVACY_VERSION = "privacy-2026-09-09"
DEFAULT_BIOMETRIC_VERSION = "biometric-consent-2026-09-09"

CONSENT_TERMS = "terms"
CONSENT_PRIVACY = "privacy"
CONSENT_BIOMETRIC = "biometric"
ACTION_ACCEPTED = "accepted"
ACTION_WITHDRAWN = "withdrawn"
LEGAL_TYPES = (CONSENT_TERMS, CONSENT_PRIVACY)
ALL_TYPES = (CONSENT_TERMS, CONSENT_PRIVACY, CONSENT_BIOMETRIC)

SECTION_TITLES = {
    CONSENT_TERMS: "Terms and Conditions",
    CONSENT_PRIVACY: "Privacy Policy",
    CONSENT_BIOMETRIC: "Biometric Consent",
}


def legal_page_path(business_code: str) -> str:
    return f"{LEGAL_PAGE_PREFIX}{business_code.strip().upper()}"


def legal_api_page_path(business_code: str) -> str:
    return f"{LEGAL_API_PREFIX}{business_code.strip().upper()}/page"


def legal_api_json_path(business_code: str) -> str:
    return f"{LEGAL_API_PREFIX}{business_code.strip().upper()}"


def ensure_legal_page_url(business: Business) -> str:
    path = legal_page_path(business.business_code)
    if business.legal_page_url != path:
        business.legal_page_url = path
    return path


def _trimmed(value: str | None) -> str:
    return (value or "").strip()


def section_published(content: str | None, version: str | None) -> bool:
    return bool(_trimmed(content) and _trimmed(version))


def current_version(business: Business, consent_type: str) -> str | None:
    if consent_type == CONSENT_TERMS:
        return _trimmed(business.terms_version) or None
    if consent_type == CONSENT_PRIVACY:
        return _trimmed(business.privacy_version) or None
    if consent_type == CONSENT_BIOMETRIC:
        return _trimmed(business.biometric_consent_version) or None
    return None


def current_content(business: Business, consent_type: str) -> str | None:
    if consent_type == CONSENT_TERMS:
        value = _trimmed(business.terms_content)
    elif consent_type == CONSENT_PRIVACY:
        value = _trimmed(business.privacy_content)
    elif consent_type == CONSENT_BIOMETRIC:
        value = _trimmed(business.biometric_consent_content)
    else:
        return None
    return value or None


def is_type_published(business: Business, consent_type: str) -> bool:
    return section_published(
        current_content(business, consent_type),
        current_version(business, consent_type),
    )


def latest_record(
    db: Session, employee_id: uuid.UUID, consent_type: str
) -> ConsentRecord | None:
    return (
        db.query(ConsentRecord)
        .filter(
            ConsentRecord.employee_id == employee_id,
            ConsentRecord.consent_type == consent_type,
        )
        .order_by(ConsentRecord.created_at.desc())
        .first()
    )


def type_satisfied(db: Session, employee: Employee, business: Business, consent_type: str) -> bool:
    if not is_type_published(business, consent_type):
        return False
    record = latest_record(db, employee.id, consent_type)
    if record is None or record.action != ACTION_ACCEPTED:
        return False
    return record.policy_version == current_version(business, consent_type)


def legal_satisfied(db: Session, employee: Employee, business: Business) -> bool:
    return all(type_satisfied(db, employee, business, item) for item in LEGAL_TYPES)


def biometric_satisfied(db: Session, employee: Employee, business: Business) -> bool:
    return type_satisfied(db, employee, business, CONSENT_BIOMETRIC)


def _type_status(
    db: Session, employee: Employee, business: Business, consent_type: str
) -> dict:
    published = is_type_published(business, consent_type)
    record = latest_record(db, employee.id, consent_type)
    accepted = (
        record is not None
        and record.action == ACTION_ACCEPTED
        and published
        and record.policy_version == current_version(business, consent_type)
    )
    return {
        "consent_type": consent_type,
        "published": published,
        "satisfied": accepted,
        "current_version": current_version(business, consent_type),
        "accepted_version": record.policy_version if record else None,
        "accepted_at": record.created_at if record and record.action == ACTION_ACCEPTED else None,
        "last_action": record.action if record else None,
    }


def consent_status_payload(
    db: Session, employee: Employee, business: Business
) -> dict:
    ensure_legal_page_url(business)
    terms = _type_status(db, employee, business, CONSENT_TERMS)
    privacy = _type_status(db, employee, business, CONSENT_PRIVACY)
    biometric = _type_status(db, employee, business, CONSENT_BIOMETRIC)
    adult = False
    for item in (CONSENT_TERMS, CONSENT_PRIVACY):
        record = latest_record(db, employee.id, item)
        if record is not None and record.adult_acknowledged:
            adult = True
            break
    return {
        "business_name": business.name,
        "business_code": business.business_code,
        "legal_page_url": business.legal_page_url or legal_page_path(business.business_code),
        "legal_page_api_path": legal_api_page_path(business.business_code),
        "is_demo": bool(getattr(business, "is_demo", False)),
        "legal_satisfied": bool(terms["satisfied"] and privacy["satisfied"]),
        "biometric_satisfied": bool(biometric["satisfied"]),
        "adult_acknowledged": adult,
        "terms": terms,
        "privacy": privacy,
        "biometric": biometric,
    }


def consent_summary_for_employee(
    db: Session, employee: Employee, business: Business
) -> dict:
    status = consent_status_payload(db, employee, business)
    return {
        "terms_satisfied": status["terms"]["satisfied"],
        "privacy_satisfied": status["privacy"]["satisfied"],
        "biometric_satisfied": status["biometric"]["satisfied"],
        "terms_version": status["terms"]["accepted_version"]
        if status["terms"]["satisfied"]
        else None,
        "privacy_version": status["privacy"]["accepted_version"]
        if status["privacy"]["satisfied"]
        else None,
        "biometric_version": status["biometric"]["accepted_version"]
        if status["biometric"]["satisfied"]
        else None,
        "terms_accepted_at": status["terms"]["accepted_at"],
        "privacy_accepted_at": status["privacy"]["accepted_at"],
        "biometric_accepted_at": status["biometric"]["accepted_at"],
    }


def public_legal_payload(business: Business) -> dict:
    ensure_legal_page_url(business)

    def section(consent_type: str) -> dict:
        content = current_content(business, consent_type)
        version = current_version(business, consent_type)
        published = section_published(content, version)
        return {
            "title": SECTION_TITLES[consent_type],
            "consent_type": consent_type,
            "content": content if published else None,
            "version": version if published else None,
            "published": published,
        }

    return {
        "business_name": business.name,
        "business_code": business.business_code,
        "legal_page_url": business.legal_page_url or legal_page_path(business.business_code),
        "updated_at": business.legal_updated_at,
        "is_demo": bool(getattr(business, "is_demo", False)),
        "terms": section(CONSENT_TERMS),
        "privacy": section(CONSENT_PRIVACY),
        "biometric": section(CONSENT_BIOMETRIC),
    }


def render_legal_html_page(business: Business) -> HTMLResponse:
    payload = public_legal_payload(business)
    title = html.escape(f"{business.name} — Workplace legal documents")
    name = html.escape(business.name)
    code = html.escape(business.business_code)

    def block(section: dict) -> str:
        heading = html.escape(section["title"])
        if not section["published"]:
            body = html.escape(
                f"{business.name} has not published {section['title']} yet. "
                "Contact your employer before using face enrollment or live attendance."
            )
            version = ""
        else:
            body = html.escape(section["content"] or "").replace("\n", "<br>\n")
            version = html.escape(section["version"] or "")
        version_html = (
            f'<p class="meta">Version {version}</p>' if version else ""
        )
        return (
            f'<section class="card">'
            f"<h2>{heading}</h2>"
            f"{version_html}"
            f'<div class="body">{body}</div>'
            f"</section>"
        )

    sections = "".join(
        block(payload[key]) for key in (CONSENT_TERMS, CONSENT_PRIVACY, CONSENT_BIOMETRIC)
    )
    markup = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <style>
    body {{ margin: 0; font-family: system-ui, sans-serif; background: #F4F6F8; color: #111827; }}
    main {{ max-width: 42rem; margin: 0 auto; padding: 1.5rem 1.25rem 3rem; }}
    .card {{ background: #fff; border: 1px solid #E5E7EB; border-radius: 1.25rem; padding: 1.5rem; margin-bottom: 1rem; }}
    .kicker {{ font-size: 0.75rem; letter-spacing: 0.14em; text-transform: uppercase; color: #6B7280; font-weight: 600; }}
    h1 {{ margin: 0.5rem 0 0.25rem; font-size: 1.5rem; }}
    h2 {{ margin: 0 0 0.5rem; font-size: 1.15rem; }}
    .meta {{ margin: 0 0 1rem; color: #6B7280; font-size: 0.875rem; }}
    .body {{ font-size: 0.95rem; line-height: 1.7; }}
  </style>
</head>
<body>
  <main>
    <p class="kicker">Workplace legal documents</p>
    <h1>{name}</h1>
    <p class="meta">Business code {code}</p>
    {sections}
  </main>
</body>
</html>
"""
    return HTMLResponse(markup)


def _normalize_client(value: str | None) -> str | None:
    client = (value or "").strip().lower()
    if client in {"mobile", "web"}:
        return client
    return None


def record_acceptances(
    db: Session,
    *,
    employee: Employee,
    business: Business,
    user_id: uuid.UUID,
    types: list[str],
    versions: dict[str, str],
    client: str | None,
    adult_acknowledged: bool,
    request: Request | None,
) -> list[ConsentRecord]:
    from app.core.request_meta import audit_meta_from_request

    if not types:
        raise HTTPException(400, "At least one consent type is required")
    unique_types: list[str] = []
    for item in types:
        key = (item or "").strip().lower()
        if key not in ALL_TYPES:
            raise HTTPException(400, f"Unknown consent type: {item}")
        if key not in unique_types:
            unique_types.append(key)

    needs_adult = any(item in LEGAL_TYPES for item in unique_types)
    if needs_adult and not adult_acknowledged:
        raise HTTPException(
            400,
            detail={
                "code": "adult_acknowledgement_required",
                "message": "You must confirm you are 18 or older to continue.",
            },
        )

    meta = audit_meta_from_request(request)
    client_value = _normalize_client(client) or _normalize_client(meta.get("platform"))
    if client_value is None:
        client_value = "mobile"
    page_url = ensure_legal_page_url(business)
    now = datetime.now(timezone.utc)
    created: list[ConsentRecord] = []

    for consent_type in unique_types:
        if not is_type_published(business, consent_type):
            raise HTTPException(
                400,
                detail={
                    "code": "legal_content_unpublished",
                    "message": (
                        f"{SECTION_TITLES[consent_type]} has not been published "
                        "by your employer yet."
                    ),
                },
            )
        expected = current_version(business, consent_type)
        offered = _trimmed(versions.get(consent_type))
        if not offered or offered != expected:
            raise HTTPException(
                409,
                detail={
                    "code": "consent_version_mismatch",
                    "message": (
                        f"Please review the current {SECTION_TITLES[consent_type]} "
                        "before agreeing."
                    ),
                    "consent_type": consent_type,
                    "current_version": expected,
                },
            )
        if type_satisfied(db, employee, business, consent_type):
            continue
        row = ConsentRecord(
            business_id=business.id,
            employee_id=employee.id,
            user_id=user_id,
            consent_type=consent_type,
            policy_version=expected,
            action=ACTION_ACCEPTED,
            client=client_value,
            ip_address=meta.get("ip_address"),
            device=meta.get("device"),
            platform=meta.get("platform"),
            legal_page_url=page_url,
            adult_acknowledged=adult_acknowledged if needs_adult else None,
            created_at=now,
        )
        db.add(row)
        created.append(row)
        add_log(
            db,
            user_id,
            "consent_accepted",
            f"{employee.full_name} accepted {consent_type} {expected}",
            new_value=expected,
            platform=meta.get("platform"),
            device=meta.get("device"),
            ip_address=meta.get("ip_address"),
        )
    return created


def withdraw_biometric_consent(
    db: Session,
    *,
    employee: Employee,
    business: Business,
    actor_user_id: uuid.UUID,
    client: str | None,
    request: Request | None,
) -> ConsentRecord:
    from app.core.request_meta import audit_meta_from_request

    meta = audit_meta_from_request(request)
    version = current_version(business, CONSENT_BIOMETRIC) or "unpublished"
    row = ConsentRecord(
        business_id=business.id,
        employee_id=employee.id,
        user_id=actor_user_id,
        consent_type=CONSENT_BIOMETRIC,
        policy_version=version,
        action=ACTION_WITHDRAWN,
        client=_normalize_client(client) or "web",
        ip_address=meta.get("ip_address"),
        device=meta.get("device"),
        platform=meta.get("platform"),
        legal_page_url=ensure_legal_page_url(business),
        created_at=datetime.now(timezone.utc),
    )
    db.add(row)
    deleted = clear_employee_face_data(db, employee)
    add_log(
        db,
        actor_user_id,
        "consent_withdrawn",
        f"Biometric consent withdrawn for {employee.full_name}; "
        f"cleared {deleted} face embedding(s)",
        previous_value=version,
        platform=meta.get("platform"),
        device=meta.get("device"),
        ip_address=meta.get("ip_address"),
    )
    return row


def clear_employee_face_data(db: Session, employee: Employee) -> int:
    deleted = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .delete(synchronize_session=False)
    )
    db.query(FaceLivenessChallenge).filter(
        FaceLivenessChallenge.employee_id == employee.id
    ).delete(synchronize_session=False)
    employee.face_registration_status = "not_registered"
    employee.face_registered_at = None
    return int(deleted or 0)


def require_legal_consent(db: Session, employee: Employee, business: Business) -> None:
    if getattr(business, "is_demo", False):
        return
    if legal_satisfied(db, employee, business):
        return
    raise HTTPException(
        status_code=403,
        detail={
            "code": "legal_consent_required",
            "message": (
                "Please review and agree to your workplace Terms and Privacy "
                "Policy before continuing."
            ),
        },
    )


def require_biometric_consent(
    db: Session, employee: Employee, business: Business
) -> None:
    if getattr(business, "is_demo", False):
        return
    if biometric_satisfied(db, employee, business):
        return
    raise HTTPException(
        status_code=403,
        detail={
            "code": "biometric_consent_required",
            "message": (
                "Please review and agree to biometric consent before face "
                "enrollment or live attendance."
            ),
        },
    )


def default_legal_content(business_name: str, consent_type: str) -> str:
    name = business_name.strip() or "this workplace"
    if consent_type == CONSENT_TERMS:
        return (
            f"{name} Terms and Conditions\n\n"
            "This workplace uses Aroll+ for attendance, scheduling, and payroll "
            "during the academic / pilot deployment.\n\n"
            "By agreeing, you confirm that you are authorized to use this account, "
            "will not clock in for another person, and will not spoof location or "
            "face verification.\n\n"
            "Face enrollment requires a separate biometric consent. Full template "
            "text is in the project docs/legal folder for owner review."
        )
    if consent_type == CONSENT_PRIVACY:
        return (
            f"{name} Privacy Policy\n\n"
            "Aroll+ processes account, attendance, location (for geofence checks), "
            "and face embedding data to provide workplace timekeeping.\n\n"
            "Face images are processed to create numeric templates and are not "
            "kept as a long-term photo album. Data is isolated to this business "
            "and is not used for marketing.\n\n"
            "You may request access, correction, or deletion of biometric templates "
            "through your employer. Aroll+ is intended for adult employees (18+)."
        )
    return (
        f"{name} Biometric Consent\n\n"
        "Before face enrollment, you consent to Aroll+ capturing face samples, "
        "storing face embeddings for matching, and using liveness plus workplace "
        "location checks when you Time In or Time Out.\n\n"
        "This is not Apple Face ID. Templates are stored in the Aroll+ database "
        "for this business only. You may withdraw consent; face clock-in will "
        "then be unavailable and templates will be deleted."
    )


def publish_default_legal(business: Business, *, force: bool = False) -> None:
    ensure_legal_page_url(business)
    changed = False
    if force or not is_type_published(business, CONSENT_TERMS):
        business.terms_content = default_legal_content(business.name, CONSENT_TERMS)
        business.terms_version = DEFAULT_TERMS_VERSION
        changed = True
    if force or not is_type_published(business, CONSENT_PRIVACY):
        business.privacy_content = default_legal_content(business.name, CONSENT_PRIVACY)
        business.privacy_version = DEFAULT_PRIVACY_VERSION
        changed = True
    if force or not is_type_published(business, CONSENT_BIOMETRIC):
        business.biometric_consent_content = default_legal_content(
            business.name, CONSENT_BIOMETRIC
        )
        business.biometric_consent_version = DEFAULT_BIOMETRIC_VERSION
        changed = True
    if changed:
        business.legal_updated_at = datetime.now(timezone.utc)


def seed_accepted_consents(
    db: Session,
    *,
    employee: Employee,
    business: Business,
    user_id: uuid.UUID,
    client: str = "mobile",
) -> None:
    publish_default_legal(business)
    now = datetime.now(timezone.utc)
    page_url = ensure_legal_page_url(business)
    for consent_type in ALL_TYPES:
        if type_satisfied(db, employee, business, consent_type):
            continue
        db.add(
            ConsentRecord(
                business_id=business.id,
                employee_id=employee.id,
                user_id=user_id,
                consent_type=consent_type,
                policy_version=current_version(business, consent_type) or "",
                action=ACTION_ACCEPTED,
                client=client,
                legal_page_url=page_url,
                adult_acknowledged=True,
                created_at=now,
            )
        )


def legal_settings_payload(business: Business) -> dict:
    ensure_legal_page_url(business)
    return {
        "business_name": business.name,
        "business_code": business.business_code,
        "legal_page_url": business.legal_page_url or legal_page_path(business.business_code),
        "terms_content": business.terms_content,
        "privacy_content": business.privacy_content,
        "biometric_consent_content": business.biometric_consent_content,
        "terms_version": business.terms_version,
        "privacy_version": business.privacy_version,
        "biometric_consent_version": business.biometric_consent_version,
        "legal_updated_at": business.legal_updated_at,
        "terms_published": is_type_published(business, CONSENT_TERMS),
        "privacy_published": is_type_published(business, CONSENT_PRIVACY),
        "biometric_published": is_type_published(business, CONSENT_BIOMETRIC),
    }


def apply_legal_settings_update(business: Business, body) -> None:
    ensure_legal_page_url(business)

    def assign_text(field: str, value: str | None) -> None:
        if value is None:
            return
        text = value.strip()
        if len(text) > MAX_LEGAL_CHARS:
            raise HTTPException(
                400, f"{field} exceeds {MAX_LEGAL_CHARS} characters"
            )
        setattr(business, field, text or None)

    def assign_version(field: str, value: str | None) -> None:
        if value is None:
            return
        setattr(business, field, value.strip() or None)

    assign_text("terms_content", body.terms_content)
    assign_text("privacy_content", body.privacy_content)
    assign_text("biometric_consent_content", body.biometric_consent_content)
    assign_version("terms_version", body.terms_version)
    assign_version("privacy_version", body.privacy_version)
    assign_version("biometric_consent_version", body.biometric_consent_version)
    business.legal_updated_at = datetime.now(timezone.utc)


def lookup_business_by_code(db: Session, business_code: str) -> Business:
    from sqlalchemy import func

    code = (business_code or "").strip().upper()
    if not code:
        raise HTTPException(404, "Business not found")
    business = (
        db.query(Business)
        .filter(func.upper(Business.business_code) == code)
        .first()
    )
    if business is None:
        raise HTTPException(404, "Business not found")
    ensure_legal_page_url(business)
    return business
