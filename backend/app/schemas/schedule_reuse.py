from datetime import date, time
from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field


class ScheduleReuseSource(str, Enum):
    previous_week = "previous_week"
    week = "week"
    last_schedule = "last_schedule"
    template = "template"


class ScheduleConflictMode(str, Enum):
    replace = "replace"
    merge = "merge"


class ScheduleReusePreviewItem(BaseModel):
    employee_id: str
    employee_name: str
    shift_id: str
    shift_name: str
    shift_start_time: time
    shift_end_time: time
    shift_color: str | None = None
    work_date: date
    is_rest_day_work: bool = False
    status: Literal["new", "conflict", "duplicate", "skipped_inactive", "skipped_missing_shift"]
    conflict_reason: str | None = None


class ScheduleReuseConflictSummary(BaseModel):
    existing_assignment_count: int
    conflict_count: int
    duplicate_count: int
    skipped_count: int
    creatable_count: int


class ScheduleReusePreviewResponse(BaseModel):
    source: ScheduleReuseSource
    source_label: str
    source_week_start: date | None = None
    target_week_start: date
    target_week_end: date
    employee_count: int
    working_day_count: int
    items: list[ScheduleReusePreviewItem]
    conflicts: ScheduleReuseConflictSummary


class ScheduleReusePreviewRequest(BaseModel):
    source: ScheduleReuseSource
    target_week_start: date
    source_week_start: date | None = None
    template_id: str | None = None


class ScheduleReuseApplyRequest(BaseModel):
    source: ScheduleReuseSource
    target_week_start: date
    conflict_mode: ScheduleConflictMode
    source_week_start: date | None = None
    template_id: str | None = None


class ScheduleReuseApplyResponse(BaseModel):
    created: int
    removed: int
    skipped: int
    target_week_start: date
    target_week_end: date


class ScheduleTemplateSummary(BaseModel):
    id: str
    name: str
    entry_count: int
    employee_count: int
    created_at: date | None = None


class ScheduleReuseSuggestionsResponse(BaseModel):
    target_week_start: date
    previous_week_start: date | None = None
    previous_week_assignment_count: int = 0
    last_schedule_week_start: date | None = None
    last_schedule_assignment_count: int = 0
    templates: list[ScheduleTemplateSummary]
    suggest_previous: bool = False


class ScheduleTemplateCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    week_start: date


class ScheduleTemplateRenameRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class ScheduleTemplateDetailResponse(BaseModel):
    id: str
    name: str
    entry_count: int
    employee_count: int
    created_at: date | None = None
    entries: list[ScheduleReusePreviewItem]
