from pydantic import BaseModel, Field


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


class AccountSettingsUpdate(BaseModel):
    business_name: str = Field(min_length=2, max_length=200)
    owner_name: str = Field(min_length=2, max_length=200)
    contact_phone: str | None = Field(default=None, max_length=50)
    address: str = Field(min_length=5)
    business_type: str | None = Field(default=None, max_length=100)
