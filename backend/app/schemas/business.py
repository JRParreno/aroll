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
