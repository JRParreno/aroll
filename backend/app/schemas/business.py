from pydantic import BaseModel, Field

from app.schemas.registration import RegistrationDocumentResponse


class ScheduleTableColors(BaseModel):
    header: str = "#1E3A5F"
    row1: str = "#FFE5A3"
    row2: str = "#FFB166"
    row3: str = "#B8F28C"
    row4: str = "#B9D8F7"
    row5: str = "#F2A7EA"
    off: str = "#F8B4B4"
    text: str = "#111827"


class ScheduleDisplaySettings(BaseModel):
    default_start: str = "09:00"
    default_end: str = "17:00"
    visible_days: list[str] = Field(
        default_factory=lambda: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    )


class BusinessThemeSettings(BaseModel):
    primary_color: str = "#1E3A5F"
    secondary_color: str = "#284B73"
    sidebar_color: str = "#1E3A5F"
    accent_color: str = "#3B82F6"
    button_color: str = "#1E3A5F"
    card_style: str = "soft"
    font_size: str = "comfortable"
    color_mode: str = "light"
    layout_density: str = "rounded"
    schedule_colors: ScheduleTableColors | None = None
    schedule_display: ScheduleDisplaySettings | None = None


class BusinessBrandingSettings(BaseModel):
    logo_url: str | None = None
    owner_profile_image_url: str | None = None
    display_image_url: str | None = None
    theme: BusinessThemeSettings = Field(default_factory=BusinessThemeSettings)


class LocationUpdate(BaseModel):
    label: str = "Main"
    address: str = Field(min_length=5)
    latitude: float | None = None
    longitude: float | None = None
    geofence_radius_m: int = Field(default=75, ge=20, le=200)


class LocationResponse(BaseModel):
    label: str
    address: str
    latitude: float | None
    longitude: float | None
    geofence_radius_m: int


class AccountSettingsResponse(BaseModel):
    business_name: str
    owner_name: str | None = None
    email: str
    contact_phone: str | None = None
    address: str = ""
    business_type: str | None = None
    branding: BusinessBrandingSettings = Field(default_factory=BusinessBrandingSettings)


class AccountSettingsUpdate(BaseModel):
    business_name: str = Field(min_length=2, max_length=200)
    owner_name: str = Field(min_length=2, max_length=200)
    contact_phone: str | None = Field(default=None, max_length=50)
    address: str = Field(min_length=5)
    business_type: str | None = Field(default=None, max_length=100)
    branding: BusinessBrandingSettings | None = None


class BusinessSettingsResponse(BaseModel):
    business_name: str
    business_type: str | None = None
    business_code: str
    address: str = ""
    owner_name: str | None = None
    owner_email: str
    owner_phone: str | None = None
    registration_id: str | None = None
    application_status: str | None = None
    registration_documents: list[RegistrationDocumentResponse] = Field(default_factory=list)
    branding: BusinessBrandingSettings = Field(default_factory=BusinessBrandingSettings)


class BusinessSettingsUpdate(BaseModel):
    business_name: str = Field(min_length=2, max_length=200)
    business_type: str | None = Field(default=None, max_length=100)
    address: str = Field(min_length=5)
    branding: BusinessBrandingSettings | None = None
