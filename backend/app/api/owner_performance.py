from collections import defaultdict
from datetime import date, datetime, time, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, EmployeeStatus, UserRole
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.schemas.owner_performance import (
    EmployeePerformanceItem,
    OwnerPerformanceResponse,
    OwnerPerformanceSummary,
    OwnerPerformanceTrendItem,
)

router = APIRouter(prefix="/owner/performance", tags=["owner-performance"])


def _percent(numerator: int | float, denominator: int | float) -> float:
    if denominator <= 0:
        return 0.0
    return round((numerator / denominator) * 100, 1)


def _combine(work_date: date, value: time) -> datetime:
    return datetime.combine(work_date, value)


def _shift_end_at(work_date: date, shift: Shift) -> datetime:
    end_at = _combine(work_date, shift.end_time)
    if shift.end_time <= shift.start_time:
        end_at += timedelta(days=1)
    return end_at


def _employee_reasons(
    assigned: int,
    absent: int,
    undertime: int,
    late: int,
    on_time: int,
    completed: int,
) -> list[str]:
    reasons: list[str] = []
    if assigned == 0:
        return ["No scheduled shifts in the selected period"]
    if absent == 0:
        reasons.append("No absences")
    if undertime == 0:
        reasons.append("No undertime or early logouts")
    if late == 0 and on_time > 0:
        reasons.append("Consistent on-time clock-ins")
    if completed == assigned:
        reasons.append("Completed all assigned shifts")
    if not reasons:
        reasons.append("Performance is based on actual attendance records")
    return reasons


@router.get("", response_model=OwnerPerformanceResponse)
def get_owner_performance(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    days: Annotated[int, Query(ge=1, le=366)] = 30,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    today = date.today()
    start_date = today - timedelta(days=days - 1)

    policy = db.get(BusinessAttendancePolicy, user.business_id)
    grace_minutes = policy.on_time_grace_minutes if policy else 10
    overtime_minimum = policy.overtime_minimum_minutes if policy else 30

    employees = (
        db.query(Employee)
        .filter(
            Employee.business_id == user.business_id,
            Employee.status != EmployeeStatus.inactive,
        )
        .order_by(Employee.full_name)
        .all()
    )
    employee_ids = [employee.id for employee in employees]

    assignments = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            Shift.business_id == user.business_id,
            ShiftAssignment.work_date >= start_date,
            ShiftAssignment.work_date <= today,
        )
        .all()
    )

    assignment_ids = [assignment.id for assignment, _shift in assignments]
    attendance_rows = (
        db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.business_id == user.business_id,
            AttendanceRecord.shift_assignment_id.in_(assignment_ids),
        )
        .all()
        if assignment_ids
        else []
    )
    attendance_by_assignment = {
        record.shift_assignment_id: record for record in attendance_rows
    }

    stats = defaultdict(
        lambda: {
            "assigned": 0,
            "attended": 0,
            "completed": 0,
            "on_time": 0,
            "late": 0,
            "absent": 0,
            "undertime": 0,
            "overtime_minutes": 0.0,
            "overtime_shifts": 0,
        }
    )
    trend = defaultdict(lambda: {"on_time": 0, "late": 0, "undertime": 0, "overtime": 0, "absent": 0})

    for assignment, shift in assignments:
        employee_stat = stats[assignment.employee_id]
        employee_stat["assigned"] += 1
        label = assignment.work_date.strftime("%b %d")

        record = attendance_by_assignment.get(assignment.id)
        if record is None or record.status == AttendanceStatus.absent or record.time_in is None:
            employee_stat["absent"] += 1
            trend[label]["absent"] += 1
            continue

        employee_stat["attended"] += 1
        scheduled_start = _combine(assignment.work_date, shift.start_time)
        scheduled_end = _shift_end_at(assignment.work_date, shift)

        if record.time_in.replace(tzinfo=None) <= scheduled_start + timedelta(minutes=grace_minutes):
            employee_stat["on_time"] += 1
            trend[label]["on_time"] += 1
        else:
            employee_stat["late"] += 1
            trend[label]["late"] += 1

        if record.status == AttendanceStatus.complete and record.time_out is not None:
            employee_stat["completed"] += 1
            time_out = record.time_out.replace(tzinfo=None)
            if time_out < scheduled_end:
                employee_stat["undertime"] += 1
                trend[label]["undertime"] += 1
            overtime_minutes = max((time_out - scheduled_end).total_seconds() / 60, 0)
            if overtime_minutes >= overtime_minimum:
                employee_stat["overtime_minutes"] += overtime_minutes
                employee_stat["overtime_shifts"] += 1
                trend[label]["overtime"] += 1

    employee_items: list[EmployeePerformanceItem] = []
    for employee in employees:
        item = stats[employee.id]
        assigned = int(item["assigned"])
        attended = int(item["attended"])
        completed = int(item["completed"])
        on_time = int(item["on_time"])
        late = int(item["late"])
        absent = int(item["absent"])
        undertime = int(item["undertime"])
        overtime_hours = round(float(item["overtime_minutes"]) / 60, 2)
        attendance_rate = _percent(attended, assigned)
        punctuality_rate = _percent(on_time, attended)
        completion_rate = _percent(completed, assigned)
        overtime_bonus = min(overtime_hours * 2, 10)
        penalty = min((late + absent + undertime) * 3, 30)
        productivity_score = round(
            max(
                0,
                min(
                    100,
                    attendance_rate * 0.35
                    + punctuality_rate * 0.3
                    + completion_rate * 0.25
                    + overtime_bonus
                    - penalty,
                ),
            ),
            1,
        )

        employee_items.append(
            EmployeePerformanceItem(
                employee_id=str(employee.id),
                full_name=employee.full_name,
                position_title=employee.position_title,
                phone=employee.phone,
                employment_type=employee.employment_type.value,
                assigned_shifts=assigned,
                attended_shifts=attended,
                completed_shifts=completed,
                on_time_clock_ins=on_time,
                late_clock_ins=late,
                absent_shifts=absent,
                undertime_shifts=undertime,
                overtime_hours=overtime_hours,
                attendance_rate=attendance_rate,
                punctuality_rate=punctuality_rate,
                productivity_score=productivity_score,
                reasons=_employee_reasons(
                    assigned, absent, undertime, late, on_time, completed
                ),
            )
        )

    employee_items.sort(
        key=lambda item: (item.productivity_score, item.attended_shifts),
        reverse=True,
    )

    total_assigned = sum(int(item["assigned"]) for item in stats.values())
    total_attended = sum(int(item["attended"]) for item in stats.values())
    total_completed = sum(int(item["completed"]) for item in stats.values())
    total_on_time = sum(int(item["on_time"]) for item in stats.values())
    total_late = sum(int(item["late"]) for item in stats.values())
    total_absent = sum(int(item["absent"]) for item in stats.values())
    total_undertime = sum(int(item["undertime"]) for item in stats.values())
    total_overtime_minutes = sum(float(item["overtime_minutes"]) for item in stats.values())
    total_overtime_shifts = sum(int(item["overtime_shifts"]) for item in stats.values())
    average_productivity = (
        round(
            sum(item.productivity_score for item in employee_items) / len(employee_items),
            1,
        )
        if employee_items
        else 0.0
    )

    trend_items = [
        OwnerPerformanceTrendItem(
            label=label,
            on_time=values["on_time"],
            late=values["late"],
            undertime=values["undertime"],
            overtime=values["overtime"],
            absent=values["absent"],
        )
        for label, values in sorted(trend.items())
    ]

    return OwnerPerformanceResponse(
        summary=OwnerPerformanceSummary(
            has_performance_data=len(attendance_rows) > 0,
            assigned_shifts=total_assigned,
            attended_shifts=total_attended,
            completed_shifts=total_completed,
            on_time_clock_ins=total_on_time,
            late_clock_ins=total_late,
            absent_shifts=total_absent,
            undertime_shifts=total_undertime,
            overtime_shifts=total_overtime_shifts,
            attendance_rate=_percent(total_attended, total_assigned),
            punctuality_rate=_percent(total_on_time, total_attended),
            total_overtime_hours=round(total_overtime_minutes / 60, 2),
            productivity_score=average_productivity,
        ),
        trend=trend_items,
        employees=employee_items,
    )
