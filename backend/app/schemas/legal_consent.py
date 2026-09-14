from datetime import datetime

from pydantic import BaseModel, Field


CONSENT_TYPES = ("terms", "privacy", "biometric")
LEGAL_TYPES = ("terms", "privacy")


class ConsentTypeStatus(BaseModel):
    consent_type: str
    published: bool
    satisfied: bool
    current_version: str | None = None
    accepted_version: str | None = None
    accepted_at: datetime | None = None
    last_action: str | None = None
    content_source: str | None = None


class LegalConsentStatusResponse(BaseModel):
    business_name: str
    business_code: str
    legal_page_url: str
    legal_page_api_path: str
    is_demo: bool = False
    use_custom_consents: bool = False
    legal_satisfied: bool
    biometric_satisfied: bool
    consents_completed: bool = False
    adult_acknowledged: bool = False
    terms: ConsentTypeStatus
    privacy: ConsentTypeStatus
    biometric: ConsentTypeStatus


class LegalConsentAcceptRequest(BaseModel):
    accepted: bool = Field(description="Must be true to record consent")
    types: list[str] = Field(min_length=1)
    versions: dict[str, str]
    client: str = Field(default="mobile")
    adult_acknowledged: bool = False


class LegalConsentWithdrawRequest(BaseModel):
    client: str = Field(default="web")


class PublicLegalSection(BaseModel):
    title: str
    consent_type: str
    content: str | None = None
    version: str | None = None
    published: bool
    content_source: str | None = None


class PublicLegalPageResponse(BaseModel):
    business_name: str
    business_code: str
    legal_page_url: str
    updated_at: datetime | None = None
    is_demo: bool = False
    use_custom_consents: bool = False
    terms: PublicLegalSection
    privacy: PublicLegalSection
    biometric: PublicLegalSection


class PlatformLegalSection(BaseModel):
    title: str
    consent_type: str
    content: str | None = None
    version: str | None = None
    published: bool
    updated_at: datetime | None = None
    updated_by: str | None = None


class PlatformLegalSettingsResponse(BaseModel):
    terms: PlatformLegalSection
    privacy: PlatformLegalSection
    biometric: PlatformLegalSection


class PlatformLegalSettingsUpdate(BaseModel):
    terms_content: str | None = None
    privacy_content: str | None = None
    biometric_consent_content: str | None = None
    terms_version: str | None = Field(default=None, max_length=80)
    privacy_version: str | None = Field(default=None, max_length=80)
    biometric_consent_version: str | None = Field(default=None, max_length=80)
    terms_published: bool | None = None
    privacy_published: bool | None = None
    biometric_published: bool | None = None


class EffectiveLegalBundle(BaseModel):
    updated_at: datetime | None = None
    terms: PublicLegalSection
    privacy: PublicLegalSection
    biometric: PublicLegalSection


class CustomLegalDraft(BaseModel):
    terms_content: str | None = None
    privacy_content: str | None = None
    biometric_consent_content: str | None = None
    terms_version: str | None = None
    privacy_version: str | None = None
    biometric_consent_version: str | None = None
    legal_updated_at: datetime | None = None
    terms_published: bool
    privacy_published: bool
    biometric_published: bool


class BusinessLegalSettingsResponse(BaseModel):
    business_name: str
    business_code: str
    legal_page_url: str
    use_custom_consents: bool
    effective: EffectiveLegalBundle
    defaults: PlatformLegalSettingsResponse
    custom: CustomLegalDraft


class BusinessLegalSettingsUpdate(BaseModel):
    use_custom_consents: bool | None = None
    terms_content: str | None = None
    privacy_content: str | None = None
    biometric_consent_content: str | None = None
    terms_version: str | None = Field(default=None, max_length=80)
    privacy_version: str | None = Field(default=None, max_length=80)
    biometric_consent_version: str | None = Field(default=None, max_length=80)


class EmployeeConsentSummary(BaseModel):
    terms_satisfied: bool = False
    privacy_satisfied: bool = False
    biometric_satisfied: bool = False
    terms_version: str | None = None
    privacy_version: str | None = None
    biometric_version: str | None = None
    terms_accepted_at: datetime | None = None
    privacy_accepted_at: datetime | None = None
    biometric_accepted_at: datetime | None = None
