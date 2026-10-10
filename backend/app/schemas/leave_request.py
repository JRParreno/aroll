from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import LeaveRequestStatus, LeaveType


class LeaveRequestCreate(BaseModel):
    leave_type: LeaveType
    start_date: date
    end_date: date
    reason: str = Field(min_length=3, max_length=2000)
    other_leave_specification: str | None = Field(default=None, max_length=200)
    supporting_document: str | None = None


class LeaveRequestUpdate(BaseModel):
    leave_type: LeaveType
    start_date: date
    end_date: date
    reason: str = Field(min_length=3, max_length=2000)
    other_leave_specification: str | None = Field(default=None, max_length=200)
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
    other_leave_specification: str | None = None
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
    other_leave_specification: str | None = None
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


class LeaveBalanceItem(BaseModel):
    leave_type: LeaveType
    leave_type_label: str
    year: int
    allocated_days: int | None = None
    used_days: int
    remaining_days: int | None = None
    configured: bool
    enabled: bool = False
    disabled: bool = False


class LeaveBalanceResponse(BaseModel):
    employee_id: UUID
    year: int
    items: list[LeaveBalanceItem]


class LeaveEntitlementWriteItem(BaseModel):
    leave_type: LeaveType
    allocated_days: int | None = Field(default=None, ge=0, le=366)


class LeaveEntitlementUpdate(BaseModel):
    year: int = Field(ge=2000, le=2100)
    items: list[LeaveEntitlementWriteItem]


class LeaveBalanceYearPreview(LeaveBalanceItem):
    # scheduled_days is the calendar leave-day count for this year.
    scheduled_days: int
    leave_days: int
    sufficient: bool


class LeaveRequestPreviewResponse(BaseModel):
    leave_type: LeaveType
    leave_type_label: str
    start_date: date
    end_date: date
    calendar_days: int
    # scheduled_days matches calendar_days so existing clients keep a count.
    scheduled_days: int
    leave_days: int
    sufficient: bool
    balance_sufficient: bool
    years: list[LeaveBalanceYearPreview]
    minimum_advance_notice_days: int
    earliest_start_date: date | None = None
    advance_notice_met: bool
