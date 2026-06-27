from pydantic import BaseModel


class OwnerPerformanceSummary(BaseModel):
    has_performance_data: bool
    assigned_shifts: int
    attended_shifts: int
    completed_shifts: int
    on_time_clock_ins: int
    late_clock_ins: int
    absent_shifts: int
    undertime_shifts: int
    overtime_shifts: int
    attendance_rate: float
    punctuality_rate: float
    total_overtime_hours: float
    productivity_score: float


class OwnerPerformanceTrendItem(BaseModel):
    label: str
    on_time: int
    late: int
    undertime: int
    overtime: int
    absent: int


class EmployeePerformanceItem(BaseModel):
    employee_id: str
    full_name: str
    position_title: str | None
    phone: str | None
    employment_type: str
    assigned_shifts: int
    attended_shifts: int
    completed_shifts: int
    on_time_clock_ins: int
    late_clock_ins: int
    absent_shifts: int
    undertime_shifts: int
    overtime_hours: float
    attendance_rate: float
    punctuality_rate: float
    productivity_score: float
    reasons: list[str]


class OwnerPerformanceResponse(BaseModel):
    summary: OwnerPerformanceSummary
    trend: list[OwnerPerformanceTrendItem]
    employees: list[EmployeePerformanceItem]
