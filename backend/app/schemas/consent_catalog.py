from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class ConsentDocumentPayload(BaseModel):
    id: str
    scope: str
    business_id: str | None = None
    title: str
    position: int
    is_active: bool
    is_required: bool
    consent_type: str
    body_text: str | None = None
    has_file: bool = False
    original_filename: str | None = None
    file_content_type: str | None = None
    version: str
    published: bool
    url: str
    file_url: str | None = None
    web_path: str
    updated_at: datetime | None = None
    updated_by: str | None = None


class ConsentDocumentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body_text: str | None = None
    consent_type: str | None = "custom"
    position: int | None = None
    is_active: bool = True
    is_required: bool = True
    version: str | None = Field(default=None, max_length=80)


class ConsentDocumentUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=200)
    body_text: str | None = None
    consent_type: str | None = None
    position: int | None = None
    is_active: bool | None = None
    is_required: bool | None = None
    version: str | None = Field(default=None, max_length=80)


class ConsentDocumentReorder(BaseModel):
    ordered_ids: list[UUID] = Field(min_length=1)


class ConsentCatalogResponse(BaseModel):
    use_custom_consents: bool = False
    can_edit: bool = True
    documents: list[ConsentDocumentPayload]


class EmployeeConsentItem(BaseModel):
    id: str
    title: str
    position: int
    url: str
    required: bool
    accepted: bool
    file_url: str | None = None
    web_path: str | None = None
    consent_type: str | None = None
    version: str | None = None
    content_source: str | None = None


class EmployeeConsentsResponse(BaseModel):
    items: list[EmployeeConsentItem]
    consents_completed: bool


class EmployeeConsentAcceptRequest(BaseModel):
    client: str = "mobile"
