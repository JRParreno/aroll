"""Employee leave allowances and calendar-day balance.

Used days are distinct calendar dates covered by approved leave requests and
by requests waiting on cancellation approval. Pending, rejected, and cancelled
requests do not consume allowance.

A calendar date counts once even when the employee has several shifts that
day. Weekends, holidays, and dates with no schedule still count. Usage does
not read shift assignments.
"""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.timezone import business_today
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import LeaveRequestStatus, LeaveType
from app.models.leave_allowance import BusinessLeaveAllowance
from app.models.leave_request import LeaveRequest
from app.services.leave_policy import get_or_create_leave_policy
from app.services.leave_requests import leave_type_label

# cancellation_pending still holds the days until the owner approves the
# cancellation. Releasing them earlier would let a second approval use the
# same allowance, then restoring the original leave would double-consume.
CONSUMING_STATUSES = (
    LeaveRequestStatus.approved,
    LeaveRequestStatus.cancellation_pending,
)


def calendar_leave_dates(start_date: date, end_date: date) -> set[date]:
    """Inclusive calendar dates. One date counts once."""
    if end_date < start_date:
        return set()
    days: set[date] = set()
    current = start_date
    while current <= end_date:
        days.add(current)
        current += timedelta(days=1)
    return days


def _year_bounds(year: int) -> tuple[date, date]:
    return date(year, 1, 1), date(year, 12, 31)


def _dates_by_year(days: set[date]) -> dict[int, list[date]]:
    grouped: dict[int, list[date]] = {}
    for day in days:
        grouped.setdefault(day.year, []).append(day)
    return {year: sorted(items) for year, items in grouped.items()}


def _years_in_range(start_date: date, end_date: date) -> list[int]:
    return list(range(start_date.year, end_date.year + 1))


def _request_dates_in_year(request: LeaveRequest, year: int) -> set[date]:
    year_start, year_end = _year_bounds(year)
    span_start = max(request.start_date, year_start)
    span_end = min(request.end_date, year_end)
    return calendar_leave_dates(span_start, span_end)


def consuming_calendar_dates(
    db: Session,
    *,
    employee_id: uuid.UUID,
    leave_type: LeaveType,
    year: int,
    exclude_request_id: uuid.UUID | None = None,
) -> set[date]:
    year_start, year_end = _year_bounds(year)
    query = db.query(LeaveRequest).filter(
        LeaveRequest.employee_id == employee_id,
        LeaveRequest.leave_type == leave_type,
        LeaveRequest.status.in_(list(CONSUMING_STATUSES)),
        LeaveRequest.start_date <= year_end,
        LeaveRequest.end_date >= year_start,
    )
    if exclude_request_id is not None:
        query = query.filter(LeaveRequest.id != exclude_request_id)
    used: set[date] = set()
    for request in query.all():
        used |= _request_dates_in_year(request, year)
    return used


def _allowance_row(
    db: Session,
    *,
    business_id: uuid.UUID,
    leave_type: LeaveType,
    year: int,
    for_update: bool = False,
) -> BusinessLeaveAllowance | None:
    query = db.query(BusinessLeaveAllowance).filter(
        BusinessLeaveAllowance.business_id == business_id,
        BusinessLeaveAllowance.leave_type == leave_type,
        BusinessLeaveAllowance.year == year,
    )
    if for_update:
        query = query.with_for_update()
    return query.one_or_none()


def _business_id_for_employee(db: Session, employee_id: uuid.UUID) -> uuid.UUID:
    employee = db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(404, "Employee not found.")
    return employee.business_id


def balance_item(
    db: Session,
    *,
    employee_id: uuid.UUID,
    leave_type: LeaveType,
    year: int,
    business_id: uuid.UUID | None = None,
    exclude_request_id: uuid.UUID | None = None,
) -> dict:
    resolved_business_id = business_id or _business_id_for_employee(db, employee_id)
    row = _allowance_row(
        db,
        business_id=resolved_business_id,
        leave_type=leave_type,
        year=year,
    )
    used = len(
        consuming_calendar_dates(
            db,
            employee_id=employee_id,
            leave_type=leave_type,
            year=year,
            exclude_request_id=exclude_request_id,
        )
    )
    enabled = row is not None and bool(row.enabled)
    disabled = row is not None and not bool(row.enabled)
    allocated = int(row.allowance_days) if enabled and row.allowance_days is not None else None
    remaining = None if allocated is None else allocated - used
    return {
        "leave_type": leave_type.value,
        "leave_type_label": leave_type_label(leave_type),
        "year": year,
        "allocated_days": allocated,
        "used_days": used,
        "remaining_days": remaining,
        "configured": enabled,
        "enabled": enabled,
        "disabled": disabled,
    }


def list_balances(
    db: Session,
    *,
    employee_id: uuid.UUID,
    year: int,
) -> list[dict]:
    business_id = _business_id_for_employee(db, employee_id)
    return [
        balance_item(
            db,
            employee_id=employee_id,
            leave_type=leave_type,
            year=year,
            business_id=business_id,
        )
        for leave_type in LeaveType
    ]


def assert_leave_type_available(
    db: Session,
    *,
    business_id: uuid.UUID,
    leave_type: LeaveType,
    start_date: date,
    end_date: date,
) -> None:
    """Reject a new or edited request when the type is explicitly disabled."""
    label = leave_type_label(leave_type)
    problems: list[str] = []
    for year in _years_in_range(start_date, end_date):
        row = _allowance_row(
            db, business_id=business_id, leave_type=leave_type, year=year
        )
        if row is not None and not row.enabled:
            problems.append(f"{label} is not available in {year}.")
    if problems:
        raise HTTPException(400, " ".join(problems))


def assert_entitlement_for_approval(db: Session, request: LeaveRequest) -> None:
    """Block approval when a year is disabled or calendar days exceed the allowance.

    Every valid request covers at least one calendar day, including when the
    employee has no shift. A missing business allowance blocks approval.
    """
    label = leave_type_label(request.leave_type)
    problems: list[str] = []
    for year in _years_in_range(request.start_date, request.end_date):
        row = _allowance_row(
            db,
            business_id=request.business_id,
            leave_type=request.leave_type,
            year=year,
            for_update=True,
        )
        if row is not None and not row.enabled:
            problems.append(f"{label} is not available in {year}.")
    if problems:
        raise HTTPException(400, " ".join(problems))

    for year in _years_in_range(request.start_date, request.end_date):
        row = _allowance_row(
            db,
            business_id=request.business_id,
            leave_type=request.leave_type,
            year=year,
            for_update=True,
        )
        needed = len(_request_dates_in_year(request, year))
        if needed <= 0:
            continue
        if row is None or not row.enabled or row.allowance_days is None:
            problems.append(
                f"No {year} {label} allowance is set in Leave Policy."
            )
            continue
        used = len(
            consuming_calendar_dates(
                db,
                employee_id=request.employee_id,
                leave_type=request.leave_type,
                year=year,
                exclude_request_id=request.id,
            )
        )
        remaining = int(row.allowance_days) - used
        if needed > remaining:
            problems.append(
                f"Not enough {year} {label}. This request uses {needed} "
                f"leave day(s), but only {remaining} day(s) remain "
                f"({int(row.allowance_days)} allocated, {used} already used)."
            )
    if problems:
        raise HTTPException(400, " ".join(problems))


def advance_notice_status(
    db: Session,
    *,
    business_id: uuid.UUID,
    start_date: date,
    leave_type: LeaveType,
) -> dict:
    policy = get_or_create_leave_policy(db, business_id)
    minimum = int(policy.minimum_advance_notice_days or 0)
    business = db.get(Business, business_id)
    today = business_today(business.timezone if business is not None else None)
    earliest = today + timedelta(days=minimum) if minimum > 0 else None
    # Emergency may start inside the notice window. Every other type keeps
    # the calendar-day rule: start_date >= business today + N.
    if leave_type == LeaveType.emergency or minimum <= 0:
        met = True
    else:
        met = start_date >= earliest
    return {
        "minimum_advance_notice_days": minimum,
        "today": today,
        "earliest_start_date": earliest,
        "advance_notice_met": met,
    }


def assert_advance_notice(
    db: Session,
    *,
    business_id: uuid.UUID,
    start_date: date,
    leave_type: LeaveType,
) -> None:
    status = advance_notice_status(
        db,
        business_id=business_id,
        start_date=start_date,
        leave_type=leave_type,
    )
    if status["advance_notice_met"]:
        return
    minimum = status["minimum_advance_notice_days"]
    earliest = status["earliest_start_date"]
    raise HTTPException(
        400,
        f"Leave must start at least {minimum} day(s) after today. "
        f"The earliest start date is {earliest.isoformat()}.",
    )


def request_balance_preview(
    db: Session,
    *,
    employee: Employee,
    leave_type: LeaveType,
    start_date: date,
    end_date: date,
) -> dict:
    if end_date < start_date:
        raise HTTPException(400, "End date must be on or after the start date.")
    covered = calendar_leave_dates(start_date, end_date)
    by_year_days = _dates_by_year(covered)
    years = _years_in_range(start_date, end_date)
    year_rows = []
    sufficient = True
    for year in years:
        needed = len(by_year_days.get(year, []))
        item = balance_item(
            db,
            employee_id=employee.id,
            leave_type=leave_type,
            year=year,
        )
        remaining = item["remaining_days"]
        if item["disabled"] or needed <= 0:
            year_ok = False
        else:
            year_ok = (
                item["configured"]
                and remaining is not None
                and needed <= remaining
            )
        if not year_ok:
            sufficient = False
        year_rows.append(
            {
                **item,
                "scheduled_days": needed,
                "leave_days": needed,
                "sufficient": year_ok,
            }
        )
    notice = advance_notice_status(
        db,
        business_id=employee.business_id,
        start_date=start_date,
        leave_type=leave_type,
    )
    day_count = len(covered)
    return {
        "leave_type": leave_type.value,
        "leave_type_label": leave_type_label(leave_type),
        "start_date": start_date,
        "end_date": end_date,
        "calendar_days": day_count,
        "scheduled_days": day_count,
        "leave_days": day_count,
        "sufficient": sufficient and notice["advance_notice_met"],
        "balance_sufficient": sufficient,
        "years": year_rows,
        "minimum_advance_notice_days": notice["minimum_advance_notice_days"],
        "earliest_start_date": notice["earliest_start_date"],
        "advance_notice_met": notice["advance_notice_met"],
    }
