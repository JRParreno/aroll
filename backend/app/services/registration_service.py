from app.models.business import BusinessRegistration
from app.models.registration_document import RegistrationDocument
from app.schemas.registration import RegistrationDocumentResponse, RegistrationResponse


def document_response(doc: RegistrationDocument) -> RegistrationDocumentResponse:
    return RegistrationDocumentResponse(
        id=str(doc.id),
        document_type=doc.document_type.value,
        original_filename=doc.original_filename,
        content_type=doc.content_type,
        file_size=doc.file_size,
        uploaded_at=doc.uploaded_at,
    )


def registration_response(reg: BusinessRegistration) -> RegistrationResponse:
    return RegistrationResponse(
        id=str(reg.id),
        business_name=reg.business_name,
        owner_name=reg.owner_name,
        owner_email=reg.owner_email,
        owner_phone=reg.owner_phone,
        proposed_address=reg.proposed_address,
        business_type=reg.business_type,
        status=reg.status.value,
        application_status=reg.application_status.value,
        submitted_at=reg.submitted_at,
        reviewed_at=reg.reviewed_at,
        rejection_reason=reg.rejection_reason,
        documents=[document_response(doc) for doc in reg.documents],
    )
