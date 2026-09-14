"""Consent document catalog: platform defaults or business overrides."""

from __future__ import annotations

import hashlib
import html
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.business import Business
from app.models.consent_document import (
    SCOPE_BUSINESS,
    SCOPE_PLATFORM,
    ConsentDocument,
)
from app.models.consent_record import ConsentRecord
from app.models.employee import Employee
from app.services.activity_logger import add_log
from app.services.legal_consent import (
    ACTION_ACCEPTED,
    ALL_TYPES,
    CONSENT_BIOMETRIC,
    CONTENT_SOURCE_ADMIN,
    CONTENT_SOURCE_CUSTOM,
    DEFAULT_VERSIONS,
    MAX_LEGAL_CHARS,
    SECTION_TITLES,
    content_hash,
    default_legal_content,
)

ALLOWED_CONSENT_FILES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
}
ALLOWED_CONSENT_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}
MAX_CONSENT_FILE_BYTES = 10 * 1024 * 1024
CONSENT_TYPES = ("terms", "privacy", "biometric", "custom")

PUBLIC_DOC_PREFIX = "/legal/c/"
PUBLIC_API_PREFIX = "/api/v1/public/consents/"


def _trimmed(value: str | None) -> str:
    return (value or "").strip()


def document_page_path(document_id: uuid.UUID) -> str:
    return f"{PUBLIC_DOC_PREFIX}{document_id}"


def document_api_page_path(document_id: uuid.UUID) -> str:
    return f"{PUBLIC_API_PREFIX}{document_id}/page"


def document_api_file_path(document_id: uuid.UUID) -> str:
    return f"{PUBLIC_API_PREFIX}{document_id}/file"


def new_document_version() -> str:
    return datetime.now(timezone.utc).strftime("v-%Y%m%d%H%M%S")


def document_source(document: ConsentDocument) -> str:
    if document.scope == SCOPE_BUSINESS:
        return CONTENT_SOURCE_CUSTOM
    return CONTENT_SOURCE_ADMIN


def document_has_body(document: ConsentDocument) -> bool:
    return bool(_trimmed(document.body_text) or document.file_stored_name)


def document_published(document: ConsentDocument) -> bool:
    return bool(
        document.is_active
        and _trimmed(document.version)
        and document_has_body(document)
    )


def document_snapshot(document: ConsentDocument) -> str | None:
    text = _trimmed(document.body_text)
    if text:
        return text
    if document.file_stored_name:
        name = document.original_filename or document.file_stored_name
        return f"[file:{name}:{document.file_content_type or 'application/octet-stream'}]"
    return None


def stored_file_path(document: ConsentDocument) -> Path | None:
    if not document.file_stored_name:
        return None
    return Path(settings.consent_upload_dir) / str(document.id) / document.file_stored_name


def document_content_hash(document: ConsentDocument) -> str | None:
    snapshot = document_snapshot(document)
    file_path = stored_file_path(document)
    if file_path is not None and file_path.exists():
        digest = hashlib.sha256(file_path.read_bytes())
        if snapshot:
            digest.update(snapshot.encode("utf-8"))
        return digest.hexdigest()
    return content_hash(snapshot)


def _consent_upload_dir(document_id: uuid.UUID) -> Path:
    target = Path(settings.consent_upload_dir) / str(document_id)
    target.mkdir(parents=True, exist_ok=True)
    return target


def require_business_custom(business: Business) -> None:
    if not getattr(business, "use_custom_consents", False):
        raise HTTPException(400, "Enable custom workplace consents first")


def catalog_query(db: Session, *, scope: str, business_id: uuid.UUID | None):
    query = db.query(ConsentDocument).filter(ConsentDocument.scope == scope)
    if scope == SCOPE_BUSINESS:
        query = query.filter(ConsentDocument.business_id == business_id)
    else:
        query = query.filter(ConsentDocument.business_id.is_(None))
    return query.order_by(ConsentDocument.position.asc(), ConsentDocument.created_at.asc())


def list_catalog_documents(
    db: Session, *, scope: str, business_id: uuid.UUID | None, active_only: bool = False
) -> list[ConsentDocument]:
    query = catalog_query(db, scope=scope, business_id=business_id)
    if active_only:
        query = query.filter(ConsentDocument.is_active.is_(True))
    return query.all()


def effective_documents(db: Session, business: Business) -> list[ConsentDocument]:
    if getattr(business, "use_custom_consents", False):
        return list_catalog_documents(
            db, scope=SCOPE_BUSINESS, business_id=business.id, active_only=False
        )
    return list_catalog_documents(
        db, scope=SCOPE_PLATFORM, business_id=None, active_only=False
    )


def published_effective_documents(
    db: Session, business: Business
) -> list[ConsentDocument]:
    return [doc for doc in effective_documents(db, business) if document_published(doc)]


def required_published_documents(
    db: Session,
    business: Business,
    *,
    biometric: bool | None = None,
) -> list[ConsentDocument]:
    docs = [
        doc
        for doc in published_effective_documents(db, business)
        if doc.is_required
    ]
    if biometric is True:
        return [doc for doc in docs if doc.consent_type == CONSENT_BIOMETRIC]
    if biometric is False:
        return [doc for doc in docs if doc.consent_type != CONSENT_BIOMETRIC]
    return docs


def document_by_type(
    db: Session, business: Business, consent_type: str
) -> ConsentDocument | None:
    for doc in effective_documents(db, business):
        if doc.consent_type == consent_type:
            return doc
    return None


def get_document(db: Session, document_id: uuid.UUID) -> ConsentDocument:
    document = db.get(ConsentDocument, document_id)
    if document is None:
        raise HTTPException(404, "Consent document not found")
    return document


def assert_document_in_scope(document: ConsentDocument, business: Business) -> None:
    if getattr(business, "use_custom_consents", False):
        if document.scope != SCOPE_BUSINESS or document.business_id != business.id:
            raise HTTPException(404, "Consent document not found")
        return
    if document.scope != SCOPE_PLATFORM:
        raise HTTPException(404, "Consent document not found")


def latest_document_record(
    db: Session, employee_id: uuid.UUID, document: ConsentDocument
) -> ConsentRecord | None:
    return (
        db.query(ConsentRecord)
        .filter(ConsentRecord.employee_id == employee_id)
        .filter(
            (ConsentRecord.document_id == document.id)
            | (
                (ConsentRecord.document_id.is_(None))
                & (ConsentRecord.consent_type == document.consent_type)
            )
        )
        .order_by(ConsentRecord.created_at.desc())
        .first()
    )


def document_satisfied(
    db: Session, employee: Employee, business: Business, document: ConsentDocument
) -> bool:
    if not document_published(document):
        return False
    record = latest_document_record(db, employee.id, document)
    if record is None or record.action != ACTION_ACCEPTED:
        return False
    if record.policy_version != document.version:
        return False
    source = document_source(document)
    if record.content_source and record.content_source != source:
        return False
    return True


def legal_docs_satisfied(db: Session, employee: Employee, business: Business) -> bool:
    docs = required_published_documents(db, business, biometric=False)
    if not docs:
        return False
    return all(document_satisfied(db, employee, business, doc) for doc in docs)


def biometric_docs_satisfied(
    db: Session, employee: Employee, business: Business
) -> bool:
    docs = required_published_documents(db, business, biometric=True)
    if not docs:
        return False
    return all(document_satisfied(db, employee, business, doc) for doc in docs)


def consents_completed(db: Session, employee: Employee, business: Business) -> bool:
    if getattr(business, "is_demo", False):
        return True
    docs = required_published_documents(db, business)
    if not docs:
        return False
    return all(document_satisfied(db, employee, business, doc) for doc in docs)


def employee_consent_items(
    db: Session, employee: Employee, business: Business
) -> list[dict]:
    items = []
    for doc in published_effective_documents(db, business):
        items.append(
            {
                "id": str(doc.id),
                "title": doc.title,
                "position": doc.position,
                "url": document_api_page_path(doc.id),
                "file_url": document_api_file_path(doc.id)
                if doc.file_stored_name
                else None,
                "web_path": document_page_path(doc.id),
                "required": doc.is_required,
                "accepted": document_satisfied(db, employee, business, doc),
                "consent_type": doc.consent_type,
                "version": doc.version,
                "content_source": document_source(doc),
            }
        )
    return items


def catalog_item_payload(document: ConsentDocument) -> dict:
    return {
        "id": str(document.id),
        "scope": document.scope,
        "business_id": str(document.business_id) if document.business_id else None,
        "title": document.title,
        "position": document.position,
        "is_active": document.is_active,
        "is_required": document.is_required,
        "consent_type": document.consent_type,
        "body_text": document.body_text,
        "has_file": bool(document.file_stored_name),
        "original_filename": document.original_filename,
        "file_content_type": document.file_content_type,
        "version": document.version,
        "published": document_published(document),
        "url": document_api_page_path(document.id),
        "file_url": document_api_file_path(document.id)
        if document.file_stored_name
        else None,
        "web_path": document_page_path(document.id),
        "updated_at": document.updated_at,
        "updated_by": str(document.updated_by) if document.updated_by else None,
    }


def _validate_consent_type(value: str | None) -> str:
    key = (value or "custom").strip().lower()
    if key not in CONSENT_TYPES:
        raise HTTPException(400, f"Unknown consent type: {value}")
    return key


def _next_position(db: Session, *, scope: str, business_id: uuid.UUID | None) -> int:
    rows = list_catalog_documents(db, scope=scope, business_id=business_id)
    if not rows:
        return 1
    return max(row.position for row in rows) + 1


def create_document(
    db: Session,
    *,
    scope: str,
    business_id: uuid.UUID | None,
    title: str,
    body_text: str | None,
    consent_type: str | None,
    position: int | None,
    is_active: bool,
    is_required: bool,
    version: str | None,
    updated_by: uuid.UUID | None,
) -> ConsentDocument:
    title_value = _trimmed(title)
    if not title_value:
        raise HTTPException(400, "Title is required")
    text = _trimmed(body_text) or None
    if text and len(text) > MAX_LEGAL_CHARS:
        raise HTTPException(400, f"body_text exceeds {MAX_LEGAL_CHARS} characters")
    now = datetime.now(timezone.utc)
    document = ConsentDocument(
        scope=scope,
        business_id=business_id,
        title=title_value,
        position=position
        if position is not None
        else _next_position(db, scope=scope, business_id=business_id),
        is_active=is_active,
        is_required=is_required,
        consent_type=_validate_consent_type(consent_type),
        body_text=text,
        version=_trimmed(version) or new_document_version(),
        updated_at=now,
        updated_by=updated_by,
    )
    db.add(document)
    db.flush()
    return document


def update_document(
    db: Session,
    document: ConsentDocument,
    *,
    title: str | None = None,
    body_text: str | None = None,
    consent_type: str | None = None,
    position: int | None = None,
    is_active: bool | None = None,
    is_required: bool | None = None,
    version: str | None = None,
    bump_version: bool = False,
    updated_by: uuid.UUID | None = None,
) -> ConsentDocument:
    content_changed = False
    if title is not None:
        title_value = _trimmed(title)
        if not title_value:
            raise HTTPException(400, "Title is required")
        document.title = title_value
    if body_text is not None:
        text = _trimmed(body_text)
        if len(text) > MAX_LEGAL_CHARS:
            raise HTTPException(400, f"body_text exceeds {MAX_LEGAL_CHARS} characters")
        if (document.body_text or "") != (text or None):
            content_changed = True
        document.body_text = text or None
    if consent_type is not None:
        document.consent_type = _validate_consent_type(consent_type)
    if position is not None:
        document.position = position
    if is_active is not None:
        document.is_active = is_active
    if is_required is not None:
        document.is_required = is_required
    if version is not None:
        document.version = _trimmed(version) or document.version
    elif bump_version or content_changed:
        document.version = new_document_version()
    document.updated_at = datetime.now(timezone.utc)
    document.updated_by = updated_by
    return document


def reorder_documents(
    db: Session,
    *,
    scope: str,
    business_id: uuid.UUID | None,
    ordered_ids: list[uuid.UUID],
    updated_by: uuid.UUID | None,
) -> list[ConsentDocument]:
    rows = list_catalog_documents(db, scope=scope, business_id=business_id)
    by_id = {row.id: row for row in rows}
    if set(ordered_ids) != set(by_id):
        raise HTTPException(400, "Reorder list must include every document once")
    now = datetime.now(timezone.utc)
    for index, document_id in enumerate(ordered_ids, start=1):
        row = by_id[document_id]
        row.position = index
        row.updated_at = now
        row.updated_by = updated_by
    return list_catalog_documents(db, scope=scope, business_id=business_id)


def delete_document(db: Session, document: ConsentDocument) -> None:
    path = stored_file_path(document)
    if path is not None and path.exists():
        path.unlink()
        parent = path.parent
        if parent.exists() and not any(parent.iterdir()):
            parent.rmdir()
    db.delete(document)


def save_document_file(
    db: Session,
    document: ConsentDocument,
    file: UploadFile,
    *,
    updated_by: uuid.UUID | None,
) -> ConsentDocument:
    if not file.filename:
        raise HTTPException(400, "Filename is required")
    extension = Path(file.filename).suffix.lower()
    if (
        file.content_type not in ALLOWED_CONSENT_FILES
        and extension not in ALLOWED_CONSENT_EXTENSIONS
    ):
        raise HTTPException(400, "File must be PDF, JPG, JPEG, or PNG")
    content = file.file.read()
    if not content:
        raise HTTPException(400, "Uploaded file is empty")
    if len(content) > MAX_CONSENT_FILE_BYTES:
        raise HTTPException(400, "File exceeds 10MB limit")
    stored_name = f"consent{extension or '.bin'}"
    target = _consent_upload_dir(document.id) / stored_name
    old = stored_file_path(document)
    target.write_bytes(content)
    if old is not None and old.exists() and old != target:
        old.unlink()
    document.file_stored_name = stored_name
    document.file_content_type = file.content_type or "application/octet-stream"
    document.original_filename = file.filename
    document.version = new_document_version()
    document.updated_at = datetime.now(timezone.utc)
    document.updated_by = updated_by
    db.flush()
    return document


def render_document_html(document: ConsentDocument) -> HTMLResponse:
    title = html.escape(document.title)
    version = html.escape(document.version)
    if not document_published(document):
        body = html.escape("This consent document is not published.")
    elif _trimmed(document.body_text):
        body = html.escape(document.body_text or "").replace("\n", "<br>\n")
    elif document.file_stored_name:
        file_url = html.escape(document_api_file_path(document.id))
        content_type = (document.file_content_type or "").lower()
        if content_type.startswith("image/"):
            body = f'<img src="{file_url}" alt="{title}" style="max-width:100%;height:auto;" />'
        elif content_type == "application/pdf":
            body = (
                f'<iframe src="{file_url}" title="{title}" '
                'style="width:100%;min-height:70vh;border:0;"></iframe>'
                f'<p><a href="{file_url}">Open file</a></p>'
            )
        else:
            body = f'<p><a href="{file_url}">Open attached file</a></p>'
    else:
        body = html.escape("No content.")
    markup = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <style>
    body {{ margin: 0; font-family: system-ui, sans-serif; background: #F4F6F8; color: #111827; }}
    main {{ max-width: 42rem; margin: 0 auto; padding: 1.5rem 1.25rem 3rem; }}
    .card {{ background: #fff; border: 1px solid #E5E7EB; border-radius: 1.25rem; padding: 1.5rem; }}
    h1 {{ margin: 0 0 0.5rem; font-size: 1.35rem; }}
    .meta {{ margin: 0 0 1rem; color: #6B7280; font-size: 0.875rem; }}
    .body {{ font-size: 0.95rem; line-height: 1.7; }}
  </style>
</head>
<body>
  <main>
    <section class="card">
      <h1>{title}</h1>
      <p class="meta">Version {version}</p>
      <div class="body">{body}</div>
    </section>
  </main>
</body>
</html>
"""
    return HTMLResponse(markup)


def file_response(document: ConsentDocument) -> FileResponse:
    path = stored_file_path(document)
    if path is None or not path.exists():
        raise HTTPException(404, "File not found")
    return FileResponse(
        path=path,
        media_type=document.file_content_type or "application/octet-stream",
        filename=document.original_filename or path.name,
    )


def accept_document(
    db: Session,
    *,
    employee: Employee,
    business: Business,
    document: ConsentDocument,
    user_id: uuid.UUID,
    client: str | None,
    request,
) -> ConsentRecord:
    from app.core.request_meta import audit_meta_from_request
    from app.services.legal_consent import _normalize_client

    assert_document_in_scope(document, business)
    if not document_published(document):
        raise HTTPException(
            400,
            detail={
                "code": "legal_content_unpublished",
                "message": f"{document.title} has not been published yet.",
            },
        )
    if document_satisfied(db, employee, business, document):
        record = latest_document_record(db, employee.id, document)
        assert record is not None
        return record
    meta = audit_meta_from_request(request)
    client_value = (
        _normalize_client(client)
        or _normalize_client(meta.get("platform"))
        or "mobile"
    )
    snapshot = document_snapshot(document)
    row = ConsentRecord(
        business_id=business.id,
        employee_id=employee.id,
        user_id=user_id,
        consent_type=document.consent_type,
        policy_version=document.version,
        action=ACTION_ACCEPTED,
        client=client_value,
        ip_address=meta.get("ip_address"),
        device=meta.get("device"),
        platform=meta.get("platform"),
        legal_page_url=document_page_path(document.id),
        content_source=document_source(document),
        accepted_content_hash=document_content_hash(document),
        content_snapshot=snapshot,
        document_id=document.id,
        created_at=datetime.now(timezone.utc),
    )
    db.add(row)
    add_log(
        db,
        user_id,
        "consent_accepted",
        f"{employee.full_name} accepted {document.title} {document.version}",
        new_value=document.version,
        platform=meta.get("platform"),
        device=meta.get("device"),
        ip_address=meta.get("ip_address"),
    )
    return row


def ensure_platform_consent_documents(
    db: Session, *, force: bool = False, updated_by: uuid.UUID | None = None
) -> None:
    existing = {
        row.consent_type: row
        for row in list_catalog_documents(db, scope=SCOPE_PLATFORM, business_id=None)
        if row.consent_type in ALL_TYPES
    }
    now = datetime.now(timezone.utc)
    for index, consent_type in enumerate(ALL_TYPES, start=1):
        content = default_legal_content("Aroll+", consent_type)
        version = DEFAULT_VERSIONS[consent_type]
        row = existing.get(consent_type)
        if row is None:
            db.add(
                ConsentDocument(
                    scope=SCOPE_PLATFORM,
                    title=SECTION_TITLES[consent_type],
                    position=index,
                    is_active=True,
                    is_required=True,
                    consent_type=consent_type,
                    body_text=content,
                    version=version,
                    updated_at=now,
                    updated_by=updated_by,
                )
            )
            continue
        if force or not document_published(row):
            row.body_text = content
            row.version = version
            row.is_active = True
            row.is_required = True
            row.title = SECTION_TITLES[consent_type]
            row.position = index
            row.updated_at = now
            if updated_by is not None:
                row.updated_by = updated_by


def document_by_type_platform(db: Session, consent_type: str) -> ConsentDocument | None:
    for row in list_catalog_documents(db, scope=SCOPE_PLATFORM, business_id=None):
        if row.consent_type == consent_type:
            return row
    return None


def sync_typed_platform_document(
    db: Session,
    consent_type: str,
    *,
    content: str | None,
    version: str | None,
    published: bool | None,
    updated_by: uuid.UUID | None,
) -> ConsentDocument | None:
    if all(value is None for value in (content, version, published)):
        return None
    row = document_by_type_platform(db, consent_type)
    if row is None:
        return create_document(
            db,
            scope=SCOPE_PLATFORM,
            business_id=None,
            title=SECTION_TITLES.get(consent_type, consent_type.title()),
            body_text=content,
            consent_type=consent_type,
            position=None,
            is_active=True if published is None else published,
            is_required=True,
            version=version,
            updated_by=updated_by,
        )
    return update_document(
        db,
        row,
        body_text=content,
        version=version,
        is_active=published,
        bump_version=False,
        updated_by=updated_by,
    )


def sync_typed_business_document(
    db: Session,
    business: Business,
    consent_type: str,
    *,
    content: str | None,
    version: str | None,
    updated_by: uuid.UUID | None,
) -> ConsentDocument | None:
    if content is None and version is None:
        return None
    existing = None
    for row in list_catalog_documents(
        db, scope=SCOPE_BUSINESS, business_id=business.id
    ):
        if row.consent_type == consent_type:
            existing = row
            break
    if existing is None:
        if not _trimmed(content) and not _trimmed(version):
            return None
        return create_document(
            db,
            scope=SCOPE_BUSINESS,
            business_id=business.id,
            title=SECTION_TITLES.get(consent_type, consent_type.title()),
            body_text=content,
            consent_type=consent_type,
            position=None,
            is_active=True,
            is_required=True,
            version=version,
            updated_by=updated_by,
        )
    return update_document(
        db,
        existing,
        body_text=content,
        version=version,
        bump_version=False,
        updated_by=updated_by,
    )
