from datetime import datetime

from pydantic import BaseModel, Field


class LegalConsentStatusResponse(BaseModel):
    accepted: bool
    accepted_at: datetime | None = None
    business_name: str
    business_code: str
    legal_consent_url: str
    legal_consent_page_url: str
    content: str
    is_demo: bool = False
    is_internal_test: bool = False


class LegalConsentAcceptRequest(BaseModel):
    accepted: bool = Field(description="Must be true to record consent")


class PublicLegalPageResponse(BaseModel):
    business_name: str
    business_code: str
    legal_consent_url: str
    content: str
    updated_at: datetime | None = None
    is_demo: bool = False
