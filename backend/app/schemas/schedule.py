from datetime import date, time

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


class WeeklyScheduleResponse(BaseModel):
    week_start: date
    week_end: date
    assignments: list[ScheduleAssignmentResponse]


class ScheduleAssignRequest(BaseModel):
    shift_id: str
    work_date: date
    employee_ids: list[str] = Field(min_length=1)


class ScheduleAssignResponse(BaseModel):
    created: int
    assignments: list[ScheduleAssignmentResponse]


class ScheduleAssignmentUpdateRequest(BaseModel):
    shift_id: str
    work_date: date
