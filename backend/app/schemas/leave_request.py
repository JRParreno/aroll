from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import LeaveRequestStatus, LeaveType


class LeaveRequestCreate(BaseModel):
    leave_type: LeaveType
    start_date: date
    end_date: date
    reason: str = Field(min_length=3, max_length=2000)
    supporting_document: str | None = None


class LeaveRequestUpdate(BaseModel):
    leave_type: LeaveType
    start_date: date
    end_date: date
    reason: str = Field(min_length=3, max_length=2000)
    supporting_document: str | None = None


class LeaveRequestReviewRequest(BaseModel):
    remarks: str | None = Field(default=None, max_length=500)
    # Owner override of company Leave Policy (defaults to policy when omitted).
    is_paid: bool | None = None
    override_reason: str | None = Field(default=None, max_length=500)


class LeaveRequestPreviousVersion(BaseModel):
    leave_type: LeaveType
    leave_type_label: str
    start_date: date
    end_date: date | None = None
    leave_days: int
    reason: str
    has_supporting_document: bool = False
    supporting_document: str | None = None
    is_paid: bool


class LeaveRequestResponse(BaseModel):
    id: UUID
    business_id: UUID
    employee_id: UUID
    employee_name: str | None = None
    employee_position: str | None = None
    employee_profile_image_url: str | None = None
    leave_type: LeaveType
    leave_type_label: str
    start_date: date
    end_date: date
    leave_days: int
    reason: str
    supporting_document: str | None = None
    has_supporting_document: bool = False
    status: LeaveRequestStatus
    policy_is_paid: bool
    is_paid: bool
    is_paid_overridden: bool = False
    has_pending_changes: bool = False
    previous_request: LeaveRequestPreviousVersion | None = None
    owner_remarks: str | None = None
    reviewed_by: UUID | None = None
    reviewed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
