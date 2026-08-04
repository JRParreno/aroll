from datetime import date, time
from uuid import UUID

from pydantic import BaseModel, Field


class ScheduleAssignmentResponse(BaseModel):
    id: str
    shift_id: str
    employee_id: str
    work_date: date
    employee_name: str
    shift_name: str
    shift_start_time: time
    shift_end_time: time
    shift_color: str | None
    is_rest_day_work: bool = False
    on_leave: bool = False
    assigned_during_leave: bool = False
    leave_pending: bool = False


class WeeklyScheduleResponse(BaseModel):
    week_start: date
    week_end: date
    assignments: list[ScheduleAssignmentResponse]


class ScheduleAssignRequest(BaseModel):
    shift_id: str
    work_date: date
    employee_ids: list[str] = Field(min_length=1)
    is_rest_day_work: bool = False
    override_leave: bool = False


class ScheduleAssignResponse(BaseModel):
    created: int
    assignments: list[ScheduleAssignmentResponse]


class ScheduleAssignmentUpdateRequest(BaseModel):
    shift_id: str
    work_date: date
    is_rest_day_work: bool | None = None
    override_leave: bool = False


class EmployeeLeaveAvailabilityItem(BaseModel):
    employee_id: UUID
    on_leave: bool = False
    leave_pending: bool = False


class EmployeeLeaveAvailabilityResponse(BaseModel):
    work_date: date
    employees: list[EmployeeLeaveAvailabilityItem]
