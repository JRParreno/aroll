from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.business import BusinessRegistration
from app.models.enums import ApplicationStatus, RegistrationDocumentType, RegistrationStatus
from app.models.registration_document import RegistrationDocument

ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
}
ALLOWED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}
REQUIRED_DOCUMENT_TYPES = frozenset(RegistrationDocumentType)
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024


def _validate_upload(file: UploadFile) -> None:
    if not file.filename:
        raise HTTPException(400, "Filename is required")

    extension = Path(file.filename).suffix.lower()
    if file.content_type not in ALLOWED_CONTENT_TYPES and extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, "File must be PDF, JPG, JPEG, or PNG")


def _registration_upload_dir(registration_id: UUID) -> Path:
    base = Path(settings.registration_upload_dir)
    target = base / str(registration_id)
    target.mkdir(parents=True, exist_ok=True)
    return target


def save_registration_document(
    db: Session,
    registration: BusinessRegistration,
    document_type: RegistrationDocumentType,
    file: UploadFile,
) -> RegistrationDocument:
    if registration.application_status not in (
        ApplicationStatus.draft,
        ApplicationStatus.rejected,
    ):
        raise HTTPException(400, "Documents cannot be modified for this application")

    _validate_upload(file)

    content = file.file.read()
    if not content:
        raise HTTPException(400, "Uploaded file is empty")
    if len(content) > MAX_FILE_SIZE_BYTES:
        raise HTTPException(400, "File exceeds 10MB limit")

    extension = Path(file.filename or "").suffix.lower() or ".bin"
    stored_filename = f"{document_type.value}_{uuid4().hex}{extension}"
    file_path = _registration_upload_dir(registration.id) / stored_filename
    file_path.write_bytes(content)

    existing = (
        db.query(RegistrationDocument)
        .filter(
            RegistrationDocument.registration_id == registration.id,
            RegistrationDocument.document_type == document_type,
        )
        .first()
    )
    if existing:
        old_path = _registration_upload_dir(registration.id) / existing.stored_filename
        if old_path.exists():
            old_path.unlink()
        existing.original_filename = file.filename or stored_filename
        existing.stored_filename = stored_filename
        existing.content_type = file.content_type or "application/octet-stream"
        existing.file_size = len(content)
        document = existing
    else:
        document = RegistrationDocument(
            registration_id=registration.id,
            document_type=document_type,
            original_filename=file.filename or stored_filename,
            stored_filename=stored_filename,
            content_type=file.content_type or "application/octet-stream",
            file_size=len(content),
        )
        db.add(document)

    db.commit()
    db.refresh(document)
    return document


def missing_required_documents(db: Session, registration_id: UUID) -> list[str]:
    uploaded = {
        row.document_type
        for row in db.query(RegistrationDocument.document_type)
        .filter(RegistrationDocument.registration_id == registration_id)
        .all()
    }
    return [
        doc_type.value
        for doc_type in REQUIRED_DOCUMENT_TYPES
        if doc_type not in uploaded
    ]


def submit_registration_application(
    db: Session, registration: BusinessRegistration
) -> datetime:
    if registration.application_status != ApplicationStatus.draft:
        raise HTTPException(400, "Registration has already been submitted")

    missing = missing_required_documents(db, registration.id)
    if missing:
        raise HTTPException(
            400,
            {
                "message": "Missing required documents",
                "missing_documents": missing,
            },
        )

    submitted_at = datetime.now(timezone.utc)
    registration.application_status = ApplicationStatus.pending
    registration.status = RegistrationStatus.pending
    registration.submitted_at = submitted_at
    db.commit()
    db.refresh(registration)
    return submitted_at


def resubmit_registration_application(
    db: Session, registration: BusinessRegistration
) -> datetime:
    if registration.application_status != ApplicationStatus.rejected:
        raise HTTPException(400, "Only rejected applications can be resubmitted")

    missing = missing_required_documents(db, registration.id)
    if missing:
        raise HTTPException(
            400,
            {
                "message": "Missing required documents",
                "missing_documents": missing,
            },
        )

    submitted_at = datetime.now(timezone.utc)
    registration.application_status = ApplicationStatus.pending
    registration.status = RegistrationStatus.pending
    registration.rejection_reason = None
    registration.reviewed_by = None
    registration.reviewed_at = None
    registration.submitted_at = submitted_at
    db.commit()
    db.refresh(registration)
    return submitted_at


def get_document_file_path(document: RegistrationDocument) -> Path:
    return _registration_upload_dir(document.registration_id) / document.stored_filename
