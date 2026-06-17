from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class RegistrationCreate(BaseModel):
    business_name: str = Field(min_length=2, max_length=200)
    owner_name: str = Field(min_length=2, max_length=200)
    owner_email: EmailStr
    owner_phone: str | None = None
    proposed_address: str | None = None
    business_type: str | None = Field(default=None, max_length=100)


class RegistrationDocumentResponse(BaseModel):
    id: str
    document_type: str
    original_filename: str
    content_type: str
    file_size: int
    uploaded_at: datetime

    class Config:
        from_attributes = True


class RegistrationResponse(BaseModel):
    id: str
    business_name: str
    owner_name: str
    owner_email: str
    owner_phone: str | None = None
    proposed_address: str | None = None
    business_type: str | None = None
    status: str
    application_status: str
    submitted_at: datetime | None = None
    reviewed_at: datetime | None = None
    rejection_reason: str | None = None
    documents: list[RegistrationDocumentResponse] = []

    class Config:
        from_attributes = True


class RegistrationReject(BaseModel):
    rejection_reason: str = Field(min_length=3)


class RegistrationApproveResponse(BaseModel):
    business_id: str
    business_code: str
    owner_email: str
