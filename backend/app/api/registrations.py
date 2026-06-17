import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.business import BusinessRegistration
from app.models.enums import (
    ApplicationStatus,
    RegistrationDocumentType,
    RegistrationStatus,
)
from app.models.registration_document import RegistrationDocument
from app.schemas.registration import (
    RegistrationCreate,
    RegistrationDocumentResponse,
    RegistrationResponse,
)
from app.services.registration_documents import (
    get_document_file_path,
    resubmit_registration_application,
    save_registration_document,
    submit_registration_application,
)
from app.services.registration_service import document_response, registration_response

router = APIRouter(prefix="/registrations", tags=["registrations"])


def _get_registration_or_404(
    db: Session, registration_id: uuid.UUID
) -> BusinessRegistration:
    reg = db.get(BusinessRegistration, registration_id)
    if reg is None:
        raise HTTPException(404, "Registration not found")
    return reg


def _get_document_or_404(
    db: Session, registration_id: uuid.UUID, document_id: uuid.UUID
) -> RegistrationDocument:
    document = db.get(RegistrationDocument, document_id)
    if document is None or document.registration_id != registration_id:
        raise HTTPException(404, "Document not found")
    return document


@router.post("", response_model=RegistrationResponse, status_code=201)
def create_registration(
    body: RegistrationCreate,
    db: Annotated[Session, Depends(get_db)],
):
    email = body.owner_email.lower().strip()
    existing = (
        db.query(BusinessRegistration)
        .filter(
            BusinessRegistration.owner_email == email,
            BusinessRegistration.application_status.in_(
                [
                    ApplicationStatus.draft,
                    ApplicationStatus.pending,
                    ApplicationStatus.rejected,
                ]
            ),
        )
        .first()
    )
    if existing:
        if existing.application_status == ApplicationStatus.rejected:
            raise HTTPException(
                400,
                "A rejected application exists for this email. Please resubmit your documents.",
            )
        raise HTTPException(
            400,
            "An active registration already exists for this email",
        )

    reg = BusinessRegistration(
        business_name=body.business_name,
        owner_name=body.owner_name,
        owner_email=email,
        owner_phone=body.owner_phone,
        proposed_address=body.proposed_address,
        business_type=body.business_type,
        status=RegistrationStatus.pending,
        application_status=ApplicationStatus.draft,
        submitted_at=None,
    )
    db.add(reg)
    db.commit()
    db.refresh(reg)
    return registration_response(reg)


@router.post(
    "/{registration_id}/documents",
    response_model=RegistrationDocumentResponse,
    status_code=201,
)
async def upload_registration_document(
    registration_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    document_type: Annotated[RegistrationDocumentType, Form()],
    file: Annotated[UploadFile, File()],
):
    reg = _get_registration_or_404(db, registration_id)
    document = save_registration_document(db, reg, document_type, file)
    return document_response(document)


@router.get("/{registration_id}/documents/{document_id}/file")
def download_registration_document(
    registration_id: uuid.UUID,
    document_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
):
    document = _get_document_or_404(db, registration_id, document_id)
    file_path = get_document_file_path(document)
    if not file_path.exists():
        raise HTTPException(404, "File not found on server")
    return FileResponse(
        path=file_path,
        media_type=document.content_type,
        filename=document.original_filename,
    )


@router.post("/{registration_id}/submit", response_model=RegistrationResponse)
def submit_registration(
    registration_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
):
    reg = _get_registration_or_404(db, registration_id)
    submit_registration_application(db, reg)
    db.refresh(reg)
    return registration_response(reg)


@router.post("/{registration_id}/resubmit", response_model=RegistrationResponse)
def resubmit_registration(
    registration_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
):
    reg = _get_registration_or_404(db, registration_id)
    resubmit_registration_application(db, reg)
    db.refresh(reg)
    return registration_response(reg)


@router.get("/by-email/{email}", response_model=RegistrationResponse)
def get_registration_by_email(
    email: str,
    db: Annotated[Session, Depends(get_db)],
):
    normalized = email.lower().strip()
    reg = (
        db.query(BusinessRegistration)
        .filter(
            BusinessRegistration.owner_email == normalized,
            BusinessRegistration.application_status == ApplicationStatus.rejected,
        )
        .order_by(BusinessRegistration.reviewed_at.desc().nullslast())
        .first()
    )
    if reg is None:
        reg = (
            db.query(BusinessRegistration)
            .filter(
                BusinessRegistration.owner_email == normalized,
                BusinessRegistration.application_status == ApplicationStatus.draft,
            )
            .first()
        )
    if reg is None:
        reg = (
            db.query(BusinessRegistration)
            .filter(BusinessRegistration.owner_email == normalized)
            .order_by(BusinessRegistration.submitted_at.desc().nullslast())
            .first()
        )
    if reg is None:
        raise HTTPException(404, "Registration not found")
    return registration_response(reg)
