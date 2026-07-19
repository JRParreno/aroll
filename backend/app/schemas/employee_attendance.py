"""Employee attendance clock-in/out request and response schemas."""

from uuid import UUID

from pydantic import BaseModel, Field


class WorksiteResponse(BaseModel):
    label: str
    address: str
    latitude: float
    longitude: float
    geofence_radius_m: int


class ClockLocationRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    shift_assignment_id: UUID | None = None


class GeofenceStatusResponse(BaseModel):
    inside_geofence: bool
    distance_m: float
    allowed_radius_m: float


class AttendanceActionResponse(BaseModel):
    id: str
    status: str
    time_in: str | None = None
    time_out: str | None = None
    geofence: GeofenceStatusResponse
    shift_name: str | None = None
    message: str
    face_match_score: float | None = None
    liveness_passed: bool | None = None
    is_rest_day: bool = False
    rest_day_work_authorized: bool | None = None
