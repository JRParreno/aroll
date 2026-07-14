"""Schemas for face enrollment and verification."""

from pydantic import BaseModel, Field


class FaceStatusResponse(BaseModel):
    employee_id: str
    face_registration_status: str
    sample_count: int
    model_version: str | None = None
    face_registered_at: str | None = None
    threshold: float


class FaceEnrollResponse(BaseModel):
    employee_id: str
    face_registration_status: str
    sample_count: int
    model_version: str
    message: str


class FaceVerifyResponse(BaseModel):
    employee_id: str
    match_score: float = Field(..., ge=0, le=1)
    passed: bool
    threshold: float
    model_version: str
    message: str
