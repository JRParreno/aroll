"""Schemas for missed clock-in/out correction requests."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class AttendanceCorrectionCreateRequest(BaseModel):
    shift_assignment_id: UUID
    requested_time_in: datetime | None = None
    requested_time_out: datetime | None = None
    reason: str = Field(..., min_length=5, max_length=1000)

    @field_validator("reason")
    @classmethod
    def _trim_reason(cls, value: str) -> str:
        cleaned = value.strip()
        if len(cleaned) < 5:
            raise ValueError("Reason must be at least 5 characters.")
        return cleaned

    @model_validator(mode="after")
    def _require_at_least_one_time(self):
        if self.requested_time_in is None and self.requested_time_out is None:
            raise ValueError("Provide at least a clock-in or clock-out time.")
        if (
            self.requested_time_in is not None
            and self.requested_time_out is not None
            and self.requested_time_out <= self.requested_time_in
        ):
            raise ValueError("Clock-out must be after clock-in.")
        return self


class AttendanceCorrectionRejectRequest(BaseModel):
    review_note: str = Field(..., min_length=3, max_length=500)

    @field_validator("review_note")
    @classmethod
    def _trim_note(cls, value: str) -> str:
        cleaned = value.strip()
        if len(cleaned) < 3:
            raise ValueError("Rejection reason must be at least 3 characters.")
        return cleaned


class AttendanceCorrectionResponse(BaseModel):
    id: str
    business_id: str
    employee_id: str
    employee_name: str
    shift_assignment_id: str
    attendance_record_id: str | None = None
    work_date: str
    shift_name: str | None = None
    shift_start: str | None = None
    shift_end: str | None = None
    recorded_time_in: str | None = None
    recorded_time_out: str | None = None
    requested_time_in: str | None = None
    requested_time_out: str | None = None
    reason: str
    status: str
    review_note: str | None = None
    reviewed_by: str | None = None
    reviewed_at: str | None = None
    created_at: str
