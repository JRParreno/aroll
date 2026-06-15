import enum


class UserRole(str, enum.Enum):
    platform_admin = "platform_admin"
    owner = "owner"
    manager = "manager"
    employee = "employee"


class RegistrationStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class BusinessStatus(str, enum.Enum):
    active = "active"
    inactive = "inactive"
    suspended = "suspended"


class PayPeriodType(str, enum.Enum):
    weekly = "weekly"
    bi_weekly = "bi_weekly"
    semi_monthly = "semi_monthly"
    monthly = "monthly"


class EmploymentType(str, enum.Enum):
    full_time = "full_time"
    part_time = "part_time"


class PayrollRunStatus(str, enum.Enum):
    draft = "draft"
    finalized = "finalized"
    cancelled = "cancelled"


class AttendanceStatus(str, enum.Enum):
    in_progress = "in_progress"
    complete = "complete"
    late = "late"
    absent = "absent"
    incomplete = "incomplete"


class ShiftType(str, enum.Enum):
    morning = "morning"
    afternoon = "afternoon"
    evening = "evening"
    night = "night"


class HolidayType(str, enum.Enum):
    regular = "regular"
    special_non_working = "special_non_working"
    company = "company"


class MissingClockOutPolicy(str, enum.Enum):
    auto_clock_out = "auto_clock_out"
    require_manager_approval = "require_manager_approval"


class Weekday(str, enum.Enum):
    monday = "monday"
    tuesday = "tuesday"
    wednesday = "wednesday"
    thursday = "thursday"
    friday = "friday"
    saturday = "saturday"
    sunday = "sunday"
