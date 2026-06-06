from datetime import datetime

from pydantic import BaseModel


class BusinessLocationResponse(BaseModel):
    id: str
    label: str
    address: str
    latitude: float | None = None
    longitude: float | None = None
    geofence_radius_m: int
    is_primary: bool


class BusinessOwnerResponse(BaseModel):
    name: str
    email: str
    phone: str | None = None


class BusinessListResponse(BaseModel):
    id: str
    business_code: str
    name: str
    status: str
    timezone: str
    created_at: datetime
    employee_count: int
    location_count: int


class BusinessDetailResponse(BaseModel):
    id: str
    business_code: str
    name: str
    status: str
    timezone: str
    created_at: datetime
    employee_count: int
    owner: BusinessOwnerResponse | None = None
    registration_submitted_at: datetime | None = None
    locations: list[BusinessLocationResponse]
