from datetime import datetime

from pydantic import BaseModel


class MonthlyRegistrationPoint(BaseModel):
    month: str
    count: int


class AttendanceSummary(BaseModel):
    present: int
    absent: int
    late: int
    present_rate: float
    has_data: bool


class RecentActivityItem(BaseModel):
    id: str
    description: str
    created_at: datetime


class DashboardStatsResponse(BaseModel):
    total_businesses: int
    active_businesses: int
    pending_requests: int
    total_employees: int
    monthly_registrations: list[MonthlyRegistrationPoint]
    attendance_summary: AttendanceSummary
    recent_activities: list[RecentActivityItem]
