"""Schemas for face enrollment, verification, and liveness."""

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
    """Identity-only diagnostic verify (no liveness)."""

    employee_id: str
    match_score: float = Field(..., ge=0, le=1)
    passed: bool
    threshold: float
    model_version: str
    message: str
    liveness_checked: bool = False


class LivenessChallengeCreateRequest(BaseModel):
    employee_id: str | None = None


class LivenessChallengeResponse(BaseModel):
    challenge_id: str
    employee_id: str
    direction: str
    instruction: str
    expires_at: str
    ttl_seconds: int


class LivenessPoseMetrics(BaseModel):
    center_yaw: float
    turn_yaw: float
    return_yaw: float
    continuity_center_turn: float
    continuity_turn_return: float


class FaceLivenessVerifyResponse(BaseModel):
    employee_id: str
    challenge_id: str
    direction: str
    match_score: float = Field(..., ge=0, le=1)
    passed: bool
    liveness_passed: bool
    threshold: float
    model_version: str
    pose: LivenessPoseMetrics
    message: str


class LivenessPoseObserveResponse(BaseModel):
    """Soft pose guidance for auto-capture. Does not consume the challenge."""

    challenge_id: str
    employee_id: str
    step: str
    direction: str
    ready: bool
    face_detected: bool
    face_count: int
    yaw: float | None = None
    detection_score: float | None = None
    guidance: str
    reason_code: str | None = None
    expires_at: str
