"""Platform defaults, optional business override, and typed consent records."""

from __future__ import annotations

import hashlib
import html
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from fastapi import HTTPException, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.consent_record import ConsentRecord
from app.models.employee import Employee
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.face_liveness import FaceLivenessChallenge
from app.models.platform_legal_document import PlatformLegalDocument
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

CONTENT_SOURCE_ADMIN = "admin_default"
CONTENT_SOURCE_CUSTOM = "business_custom"

SECTION_TITLES = {
    CONSENT_TERMS: "Terms and Conditions",
    CONSENT_PRIVACY: "Privacy Policy",
    CONSENT_BIOMETRIC: "Biometric Consent",
}

DEFAULT_VERSIONS = {
    CONSENT_TERMS: DEFAULT_TERMS_VERSION,
    CONSENT_PRIVACY: DEFAULT_PRIVACY_VERSION,
    CONSENT_BIOMETRIC: DEFAULT_BIOMETRIC_VERSION,
}


@dataclass(frozen=True)
class EffectiveLegalSection:
    consent_type: str
    content: str | None
    version: str | None
    content_source: str
    published: bool


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


def content_hash(content: str | None) -> str | None:
    text = _trimmed(content)
    if not text:
        return None
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def custom_content(business: Business, consent_type: str) -> str | None:
    if consent_type == CONSENT_TERMS:
        value = _trimmed(business.terms_content)
    elif consent_type == CONSENT_PRIVACY:
        value = _trimmed(business.privacy_content)
    elif consent_type == CONSENT_BIOMETRIC:
        value = _trimmed(business.biometric_consent_content)
    else:
        return None
    return value or None


def custom_version(business: Business, consent_type: str) -> str | None:
    if consent_type == CONSENT_TERMS:
        return _trimmed(business.terms_version) or None
    if consent_type == CONSENT_PRIVACY:
        return _trimmed(business.privacy_version) or None
    if consent_type == CONSENT_BIOMETRIC:
        return _trimmed(business.biometric_consent_version) or None
    return None


def platform_document(
    db: Session, consent_type: str
) -> PlatformLegalDocument | None:
    return db.get(PlatformLegalDocument, consent_type)


def resolve_legal_section(
    db: Session, business: Business, consent_type: str
) -> EffectiveLegalSection:
    if getattr(business, "use_custom_consents", False):
        content = custom_content(business, consent_type)
        version = custom_version(business, consent_type)
        published = section_published(content, version)
        return EffectiveLegalSection(
            consent_type=consent_type,
            content=content if published else None,
            version=version if published else None,
            content_source=CONTENT_SOURCE_CUSTOM,
            published=published,
        )

    document = platform_document(db, consent_type)
    if document is None or not document.published:
        return EffectiveLegalSection(
            consent_type=consent_type,
            content=None,
            version=None,
            content_source=CONTENT_SOURCE_ADMIN,
            published=False,
        )
    content = _trimmed(document.content) or None
    version = _trimmed(document.version) or None
    published = section_published(content, version)
    return EffectiveLegalSection(
        consent_type=consent_type,
        content=content if published else None,
        version=version if published else None,
        content_source=CONTENT_SOURCE_ADMIN,
        published=published,
    )


def current_version(db: Session, business: Business, consent_type: str) -> str | None:
    return resolve_legal_section(db, business, consent_type).version


def current_content(db: Session, business: Business, consent_type: str) -> str | None:
    return resolve_legal_section(db, business, consent_type).content


def is_type_published(db: Session, business: Business, consent_type: str) -> bool:
    return resolve_legal_section(db, business, consent_type).published


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


def type_satisfied(
    db: Session, employee: Employee, business: Business, consent_type: str
) -> bool:
    section = resolve_legal_section(db, business, consent_type)
    if not section.published:
        return False
    record = latest_record(db, employee.id, consent_type)
    if record is None or record.action != ACTION_ACCEPTED:
        return False
    if record.policy_version != section.version:
        return False
    if (
        record.content_source
        and record.content_source != section.content_source
    ):
        return False
    return True


def legal_satisfied(db: Session, employee: Employee, business: Business) -> bool:
    return all(type_satisfied(db, employee, business, item) for item in LEGAL_TYPES)


def biometric_satisfied(db: Session, employee: Employee, business: Business) -> bool:
    return type_satisfied(db, employee, business, CONSENT_BIOMETRIC)


def _section_public_dict(section: EffectiveLegalSection) -> dict:
    return {
        "title": SECTION_TITLES[section.consent_type],
        "consent_type": section.consent_type,
        "content": section.content if section.published else None,
        "version": section.version if section.published else None,
        "published": section.published,
        "content_source": section.content_source,
    }


def _type_status(
    db: Session, employee: Employee, business: Business, consent_type: str
) -> dict:
    section = resolve_legal_section(db, business, consent_type)
    record = latest_record(db, employee.id, consent_type)
    accepted = (
        record is not None
        and record.action == ACTION_ACCEPTED
        and section.published
        and record.policy_version == section.version
        and (
            not record.content_source
            or record.content_source == section.content_source
        )
    )
    return {
        "consent_type": consent_type,
        "published": section.published,
        "satisfied": accepted,
        "current_version": section.version,
        "accepted_version": record.policy_version if record else None,
        "accepted_at": record.created_at if record and record.action == ACTION_ACCEPTED else None,
        "last_action": record.action if record else None,
        "content_source": section.content_source,
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
        "use_custom_consents": bool(getattr(business, "use_custom_consents", False)),
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


def public_legal_payload(db: Session, business: Business) -> dict:
    ensure_legal_page_url(business)
    terms = resolve_legal_section(db, business, CONSENT_TERMS)
    privacy = resolve_legal_section(db, business, CONSENT_PRIVACY)
    biometric = resolve_legal_section(db, business, CONSENT_BIOMETRIC)
    updated_at = business.legal_updated_at
    if not getattr(business, "use_custom_consents", False):
        stamps = [
            platform_document(db, item).updated_at
            for item in ALL_TYPES
            if platform_document(db, item) is not None
        ]
        updated_at = max(stamps) if stamps else None
    return {
        "business_name": business.name,
        "business_code": business.business_code,
        "legal_page_url": business.legal_page_url or legal_page_path(business.business_code),
        "updated_at": updated_at,
        "is_demo": bool(getattr(business, "is_demo", False)),
        "use_custom_consents": bool(getattr(business, "use_custom_consents", False)),
        "terms": _section_public_dict(terms),
        "privacy": _section_public_dict(privacy),
        "biometric": _section_public_dict(biometric),
    }


def render_legal_html_page(db: Session, business: Business) -> HTMLResponse:
    payload = public_legal_payload(db, business)
    title = html.escape(f"{business.name} — Workplace legal documents")
    name = html.escape(business.name)
    code = html.escape(business.business_code)

    def block(section: dict) -> str:
        heading = html.escape(section["title"])
        source = section.get("content_source")
        source_label = (
            "Aroll+ default"
            if source == CONTENT_SOURCE_ADMIN
            else "Custom for this workplace"
        )
        if not section["published"]:
            if source == CONTENT_SOURCE_ADMIN:
                body = html.escape(
                    f"Aroll+ has not published {section['title']} yet."
                )
            else:
                body = html.escape(
                    f"{business.name} has not published {section['title']} yet. "
                    "Contact your employer before using face enrollment or live attendance."
                )
            version = ""
        else:
            body = html.escape(section["content"] or "").replace("\n", "<br>\n")
            version = html.escape(section["version"] or "")
        version_html = (
            f'<p class="meta">Version {version} · {html.escape(source_label)}</p>'
            if version
            else f'<p class="meta">{html.escape(source_label)}</p>'
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
        section = resolve_legal_section(db, business, consent_type)
        if not section.published:
            raise HTTPException(
                400,
                detail={
                    "code": "legal_content_unpublished",
                    "message": (
                        f"{SECTION_TITLES[consent_type]} has not been published "
                        "yet."
                    ),
                },
            )
        expected = section.version
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
        snapshot = section.content
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
            content_source=section.content_source,
            accepted_content_hash=content_hash(snapshot),
            content_snapshot=snapshot,
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
    section = resolve_legal_section(db, business, CONSENT_BIOMETRIC)
    version = section.version or "unpublished"
    snapshot = section.content
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
        content_source=section.content_source,
        accepted_content_hash=content_hash(snapshot),
        content_snapshot=snapshot,
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


def ensure_platform_legal_defaults(
    db: Session,
    *,
    force: bool = False,
    updated_by: uuid.UUID | None = None,
) -> None:
    now = datetime.now(timezone.utc)
    for consent_type in ALL_TYPES:
        existing = platform_document(db, consent_type)
        content = default_legal_content("Aroll+", consent_type)
        version = DEFAULT_VERSIONS[consent_type]
        if existing is None:
            db.add(
                PlatformLegalDocument(
                    consent_type=consent_type,
                    content=content,
                    version=version,
                    published=True,
                    updated_at=now,
                    updated_by=updated_by,
                )
            )
            continue
        if force or not section_published(existing.content, existing.version):
            existing.content = content
            existing.version = version
            existing.published = True
            existing.updated_at = now
            if updated_by is not None:
                existing.updated_by = updated_by


def publish_default_legal(
    db: Session, business: Business, *, force: bool = False
) -> None:
    """Point this business at platform Admin defaults (no per-business copy)."""
    ensure_platform_legal_defaults(db, force=force)
    business.use_custom_consents = False
    ensure_legal_page_url(business)


def seed_accepted_consents(
    db: Session,
    *,
    employee: Employee,
    business: Business,
    user_id: uuid.UUID,
    client: str = "mobile",
) -> None:
    publish_default_legal(db, business)
    now = datetime.now(timezone.utc)
    page_url = ensure_legal_page_url(business)
    for consent_type in ALL_TYPES:
        if type_satisfied(db, employee, business, consent_type):
            continue
        section = resolve_legal_section(db, business, consent_type)
        snapshot = section.content
        db.add(
            ConsentRecord(
                business_id=business.id,
                employee_id=employee.id,
                user_id=user_id,
                consent_type=consent_type,
                policy_version=section.version or "",
                action=ACTION_ACCEPTED,
                client=client,
                legal_page_url=page_url,
                adult_acknowledged=True,
                content_source=section.content_source,
                accepted_content_hash=content_hash(snapshot),
                content_snapshot=snapshot,
                created_at=now,
            )
        )


def _platform_section_dict(document: PlatformLegalDocument | None, consent_type: str) -> dict:
    if document is None:
        return {
            "title": SECTION_TITLES[consent_type],
            "consent_type": consent_type,
            "content": None,
            "version": None,
            "published": False,
            "updated_at": None,
            "updated_by": None,
        }
    published = bool(document.published) and section_published(
        document.content, document.version
    )
    return {
        "title": SECTION_TITLES[consent_type],
        "consent_type": consent_type,
        "content": document.content,
        "version": document.version,
        "published": published,
        "updated_at": document.updated_at,
        "updated_by": str(document.updated_by) if document.updated_by else None,
    }


def platform_legal_payload(db: Session) -> dict:
    return {
        "terms": _platform_section_dict(platform_document(db, CONSENT_TERMS), CONSENT_TERMS),
        "privacy": _platform_section_dict(
            platform_document(db, CONSENT_PRIVACY), CONSENT_PRIVACY
        ),
        "biometric": _platform_section_dict(
            platform_document(db, CONSENT_BIOMETRIC), CONSENT_BIOMETRIC
        ),
    }


def apply_platform_legal_update(db: Session, body, *, updated_by: uuid.UUID) -> None:
    now = datetime.now(timezone.utc)

    def assign(consent_type: str, content: str | None, version: str | None, published: bool | None) -> None:
        document = platform_document(db, consent_type)
        if document is None:
            document = PlatformLegalDocument(
                consent_type=consent_type,
                content="",
                version="",
                published=False,
                updated_at=now,
                updated_by=updated_by,
            )
            db.add(document)
            db.flush()
        if content is not None:
            text = content.strip()
            if len(text) > MAX_LEGAL_CHARS:
                raise HTTPException(
                    400, f"{consent_type} exceeds {MAX_LEGAL_CHARS} characters"
                )
            document.content = text
        if version is not None:
            document.version = version.strip()
        if published is not None:
            document.published = published
        document.updated_at = now
        document.updated_by = updated_by

    changed = False
    if any(
        value is not None
        for value in (body.terms_content, body.terms_version, body.terms_published)
    ):
        assign(CONSENT_TERMS, body.terms_content, body.terms_version, body.terms_published)
        changed = True
    if any(
        value is not None
        for value in (body.privacy_content, body.privacy_version, body.privacy_published)
    ):
        assign(
            CONSENT_PRIVACY,
            body.privacy_content,
            body.privacy_version,
            body.privacy_published,
        )
        changed = True
    if any(
        value is not None
        for value in (
            body.biometric_consent_content,
            body.biometric_consent_version,
            body.biometric_published,
        )
    ):
        assign(
            CONSENT_BIOMETRIC,
            body.biometric_consent_content,
            body.biometric_consent_version,
            body.biometric_published,
        )
        changed = True
    if not changed:
        raise HTTPException(400, "No legal default fields to update")


def legal_settings_payload(db: Session, business: Business) -> dict:
    ensure_legal_page_url(business)
    effective = public_legal_payload(db, business)
    defaults = platform_legal_payload(db)
    custom = {
        "terms_content": business.terms_content,
        "privacy_content": business.privacy_content,
        "biometric_consent_content": business.biometric_consent_content,
        "terms_version": business.terms_version,
        "privacy_version": business.privacy_version,
        "biometric_consent_version": business.biometric_consent_version,
        "legal_updated_at": business.legal_updated_at,
        "terms_published": section_published(
            business.terms_content, business.terms_version
        ),
        "privacy_published": section_published(
            business.privacy_content, business.privacy_version
        ),
        "biometric_published": section_published(
            business.biometric_consent_content, business.biometric_consent_version
        ),
    }
    return {
        "business_name": business.name,
        "business_code": business.business_code,
        "legal_page_url": business.legal_page_url or legal_page_path(business.business_code),
        "use_custom_consents": bool(getattr(business, "use_custom_consents", False)),
        "effective": {
            "updated_at": effective["updated_at"],
            "terms": effective["terms"],
            "privacy": effective["privacy"],
            "biometric": effective["biometric"],
        },
        "defaults": defaults,
        "custom": custom,
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

    if getattr(body, "use_custom_consents", None) is not None:
        business.use_custom_consents = bool(body.use_custom_consents)

    assign_text("terms_content", body.terms_content)
    assign_text("privacy_content", body.privacy_content)
    assign_text("biometric_consent_content", body.biometric_consent_content)
    assign_version("terms_version", body.terms_version)
    assign_version("privacy_version", body.privacy_version)
    assign_version("biometric_consent_version", body.biometric_consent_version)
    if any(
        value is not None
        for value in (
            getattr(body, "use_custom_consents", None),
            body.terms_content,
            body.privacy_content,
            body.biometric_consent_content,
            body.terms_version,
            body.privacy_version,
            body.biometric_consent_version,
        )
    ):
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
