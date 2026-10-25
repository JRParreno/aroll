import uuid
from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.attendance import AttendanceRecord
from app.models.attendance_correction import AttendanceCorrectionRequest
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.schemas.schedule import (
    EmployeeLeaveAvailabilityResponse,
    ScheduleAssignRequest,
    ScheduleAssignResponse,
    ScheduleAssignmentUpdateRequest,
    ScheduleAssignmentResponse,
    WeeklyScheduleResponse,
)
from app.services.employee_activation import raise_if_not_activated_for_schedule
from app.services.leave_requests import (
    blocking_leave_dates_for_employees,
    leave_availability_for_date,
    pending_leave_dates_for_employees,
)
from app.services.schedule_overlap import (
    assert_shift_still_assignable,
    shifts_times_overlap,
)

router = APIRouter(prefix="/schedules", tags=["schedules"])

ASSIGNMENT_OPEN_ATTENDANCE_MESSAGE = (
    "This schedule cannot be removed because the employee is currently timed in. "
    "Ask them to complete Time Out, then try again."
)
ASSIGNMENT_ATTENDANCE_RECORDED_MESSAGE = (
    "This schedule cannot be removed because attendance has already been recorded "
    "for this assignment."
)
ASSIGNMENT_CORRECTION_MESSAGE = (
    "This schedule cannot be removed while a correction request is associated with it."
)


def _assignment_response(
    assignment: ShiftAssignment,
    employee: Employee,
    shift: Shift,
    *,
    on_leave: bool = False,
    leave_pending: bool = False,
) -> ScheduleAssignmentResponse:
    return ScheduleAssignmentResponse(
        id=str(assignment.id),
        shift_id=str(assignment.shift_id),
        employee_id=str(assignment.employee_id),
        work_date=assignment.work_date,
        employee_name=employee.full_name,
        shift_name=shift.name,
        shift_start_time=shift.start_time,
        shift_end_time=shift.end_time,
        shift_color=shift.color,
        is_rest_day_work=bool(assignment.is_rest_day_work),
        on_leave=on_leave,
        # Assignment exists during approved leave ⇒ override / scheduled during leave.
        assigned_during_leave=on_leave,
        leave_pending=leave_pending,
    )


def _week_bounds(week_start: date) -> tuple[date, date]:
    """Return the Monday–Sunday week that contains ``week_start``."""
    monday = week_start - timedelta(days=week_start.weekday())
    return monday, monday + timedelta(days=6)


def _times_overlap(first: Shift, second: Shift) -> bool:
    return shifts_times_overlap(first, second)


def _schedule_timezone(db: Session, business_id: uuid.UUID) -> str | None:
    business = db.get(Business, business_id)
    if business is None:
        return None
    return business.timezone

def _validate_employee_schedule_conflicts(
    db: Session,
    employee_ids: list[uuid.UUID],
    work_date: date,
    shift: Shift,
    exclude_assignment_id: uuid.UUID | None = None,
) -> None:
    query = (
        db.query(ShiftAssignment, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            Shift.business_id == shift.business_id,
            ShiftAssignment.employee_id.in_(employee_ids),
            ShiftAssignment.work_date == work_date,
        )
    )
    if exclude_assignment_id is not None:
        query = query.filter(ShiftAssignment.id != exclude_assignment_id)

    conflicts = query.all()
    for assignment, existing_shift in conflicts:
        if assignment.shift_id == shift.id or _times_overlap(existing_shift, shift):
            raise HTTPException(
                400,
                "Employee already has a schedule assignment that conflicts with this shift.",
            )


@router.get("/weekly", response_model=WeeklyScheduleResponse)
def get_weekly_schedule(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    week_start: Annotated[date, Query(description="Monday of the schedule week")],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    week_start_date, week_end_date = _week_bounds(week_start)

    rows = (
        db.query(ShiftAssignment, Employee, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .filter(
            Shift.business_id == user.business_id,
            Employee.business_id == user.business_id,
            ShiftAssignment.work_date >= week_start_date,
            ShiftAssignment.work_date <= week_end_date,
        )
        .order_by(Employee.full_name, ShiftAssignment.work_date)
        .all()
    )

    employee_ids = [employee.id for _assignment, employee, _shift in rows]
    leave_dates = blocking_leave_dates_for_employees(
        db,
        business_id=user.business_id,
        employee_ids=employee_ids,
        start_date=week_start_date,
        end_date=week_end_date,
    )
    pending_dates = pending_leave_dates_for_employees(
        db,
        business_id=user.business_id,
        employee_ids=employee_ids,
        start_date=week_start_date,
        end_date=week_end_date,
    )

    assignments = [
        _assignment_response(
            assignment,
            employee,
            shift,
            on_leave=assignment.work_date
            in leave_dates.get(employee.id, set()),
            leave_pending=assignment.work_date
            in pending_dates.get(employee.id, set()),
        )
        for assignment, employee, shift in rows
    ]

    return WeeklyScheduleResponse(
        week_start=week_start_date,
        week_end=week_end_date,
        assignments=assignments,
    )


@router.get(
    "/leave-availability",
    response_model=EmployeeLeaveAvailabilityResponse,
)
def get_leave_availability(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    work_date: Annotated[date, Query()],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    employees = (
        db.query(Employee)
        .filter(
            Employee.business_id == user.business_id,
            Employee.is_active.is_(True),
        )
        .all()
    )
    employee_ids = [employee.id for employee in employees]
    availability = leave_availability_for_date(
        db,
        business_id=user.business_id,
        employee_ids=employee_ids,
        work_date=work_date,
    )
    return {
        "work_date": work_date,
        "employees": [
            {
                "employee_id": eid,
                "on_leave": availability[eid]["on_leave"],
                "leave_pending": availability[eid]["leave_pending"],
            }
            for eid in employee_ids
        ],
    }


@router.post("/assign", response_model=ScheduleAssignResponse, status_code=201)
def assign_schedule(
    body: ScheduleAssignRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    shift = db.get(Shift, uuid.UUID(body.shift_id))
    if shift is None or shift.business_id != user.business_id or not shift.is_active:
        raise HTTPException(404, "Shift not found")

    employee_ids = [uuid.UUID(eid) for eid in body.employee_ids]

    rows = (
        db.query(Employee, User)
        .join(User, Employee.user_id == User.id)
        .filter(
            Employee.business_id == user.business_id,
            Employee.is_active.is_(True),
            Employee.id.in_(employee_ids),
        )
        .all()
    )
    if len(rows) != len(employee_ids):
        raise HTTPException(400, "One or more employees not found for this business")

    raise_if_not_activated_for_schedule(rows)
    employees = [employee for employee, _linked in rows]

    _validate_employee_schedule_conflicts(db, employee_ids, body.work_date, shift)

    leave_map = leave_availability_for_date(
        db,
        business_id=user.business_id,
        employee_ids=employee_ids,
        work_date=body.work_date,
    )
    blocked = [
        emp
        for emp in employees
        if leave_map.get(emp.id, {}).get("on_leave")
    ]
    if blocked:
        names = ", ".join(emp.full_name for emp in blocked)
        raise HTTPException(
            status_code=409,
            detail={
                "code": "approved_leave",
                "message": (
                    "This employee is currently on approved leave for the selected "
                    "date(s)."
                ),
                "employees": [
                    {"id": str(emp.id), "name": emp.full_name} for emp in blocked
                ],
                "names": names,
            },
        )

    assert_shift_still_assignable(
        body.work_date,
        shift,
        tz_name=_schedule_timezone(db, user.business_id),
    )

    existing_same_shift = (
        db.query(ShiftAssignment)
        .filter(
            ShiftAssignment.shift_id == shift.id,
            ShiftAssignment.work_date == body.work_date,
        )
        .all()
    )
    existing_same_shift_ids = {a.employee_id for a in existing_same_shift}

    new_employee_ids = [
        eid for eid in employee_ids if eid not in existing_same_shift_ids
    ]

    total_after = len(existing_same_shift_ids) + len(new_employee_ids)
    if total_after > shift.employee_capacity:
        raise HTTPException(
            400,
            f"Shift capacity exceeded. Maximum {shift.employee_capacity} employees allowed.",
        )

    created_assignments: list[ShiftAssignment] = []
    employee_map = {emp.id: emp for emp in employees}

    for employee_id in new_employee_ids:
        assignment = ShiftAssignment(
            shift_id=shift.id,
            employee_id=employee_id,
            work_date=body.work_date,
            is_rest_day_work=body.is_rest_day_work,
        )
        db.add(assignment)
        created_assignments.append(assignment)

    db.commit()

    for assignment in created_assignments:
        db.refresh(assignment)
        try:
            from app.services.activity_notifications import notify_schedule_assigned

            notify_schedule_assigned(
                db,
                assignment=assignment,
                shift=shift,
                employee=employee_map[assignment.employee_id],
            )
        except Exception:
            pass

    return ScheduleAssignResponse(
        created=len(created_assignments),
        assignments=[
            _assignment_response(
                assignment,
                employee_map[assignment.employee_id],
                shift,
                on_leave=leave_map.get(assignment.employee_id, {}).get(
                    "on_leave", False
                ),
                leave_pending=leave_map.get(assignment.employee_id, {}).get(
                    "leave_pending", False
                ),
            )
            for assignment in created_assignments
        ],
    )


@router.put(
    "/assignments/{assignment_id}",
    response_model=ScheduleAssignmentResponse,
)
def update_schedule_assignment(
    assignment_id: uuid.UUID,
    body: ScheduleAssignmentUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    assignment = db.get(ShiftAssignment, assignment_id)
    if assignment is None:
        raise HTTPException(404, "Schedule assignment not found")

    employee = db.get(Employee, assignment.employee_id)
    if employee is None or employee.business_id != user.business_id:
        raise HTTPException(404, "Schedule assignment not found")
    if not employee.is_active:
        raise HTTPException(400, "Employee is inactive")

    shift = db.get(Shift, uuid.UUID(body.shift_id))
    if shift is None or shift.business_id != user.business_id or not shift.is_active:
        raise HTTPException(404, "Shift not found")

    leave_map = leave_availability_for_date(
        db,
        business_id=user.business_id,
        employee_ids=[employee.id],
        work_date=body.work_date,
    )
    on_leave = leave_map.get(employee.id, {}).get("on_leave", False)
    if on_leave:
        raise HTTPException(
            status_code=409,
            detail={
                "code": "approved_leave",
                "message": (
                    "This employee is currently on approved leave for the selected "
                    "date(s)."
                ),
                "employees": [{"id": str(employee.id), "name": employee.full_name}],
            },
        )

    if assignment.shift_id != shift.id or assignment.work_date != body.work_date:
        assert_shift_still_assignable(
            body.work_date,
            shift,
            tz_name=_schedule_timezone(db, user.business_id),
        )

    _validate_employee_schedule_conflicts(
        db,
        [assignment.employee_id],
        body.work_date,
        shift,
        exclude_assignment_id=assignment.id,
    )

    existing_same_shift_count = (
        db.query(ShiftAssignment)
        .filter(
            ShiftAssignment.shift_id == shift.id,
            ShiftAssignment.work_date == body.work_date,
            ShiftAssignment.id != assignment.id,
        )
        .count()
    )
    if existing_same_shift_count >= shift.employee_capacity:
        raise HTTPException(
            400,
            f"Shift capacity exceeded. Maximum {shift.employee_capacity} employees allowed.",
        )

    previous_shift_id = assignment.shift_id
    previous_date = assignment.work_date
    previous_rest = bool(assignment.is_rest_day_work)
    assignment.shift_id = shift.id
    assignment.work_date = body.work_date
    if body.is_rest_day_work is not None:
        assignment.is_rest_day_work = body.is_rest_day_work
    db.commit()
    db.refresh(assignment)
    material = (
        previous_shift_id != assignment.shift_id
        or previous_date != assignment.work_date
        or previous_rest != bool(assignment.is_rest_day_work)
    )
    if material:
        try:
            from app.services.activity_notifications import notify_schedule_changed

            notify_schedule_changed(
                db, assignment=assignment, shift=shift, employee=employee
            )
        except Exception:
            pass

    return _assignment_response(
        assignment,
        employee,
        shift,
        on_leave=on_leave,
        leave_pending=leave_map.get(employee.id, {}).get("leave_pending", False),
    )


@router.delete("/assignments/{assignment_id}")
def delete_schedule_assignment(
    assignment_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    row = (
        db.query(ShiftAssignment, Employee, Shift)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(
            ShiftAssignment.id == assignment_id,
            Employee.business_id == user.business_id,
            Shift.business_id == user.business_id,
        )
        .first()
    )
    if row is None:
        raise HTTPException(404, "Schedule assignment not found")

    assignment, employee, shift = row
    assignment_id = assignment.id
    work_date = assignment.work_date
    _reject_assignment_delete_when_history_exists(
        db,
        assignment_id=assignment.id,
        business_id=user.business_id,
    )
    db.delete(assignment)
    db.commit()
    try:
        from app.services.activity_notifications import notify_schedule_cancelled

        notify_schedule_cancelled(
            db,
            employee=employee,
            work_date=work_date,
            shift=shift,
            assignment_id=assignment_id,
        )
    except Exception:
        pass
    return {"status": "ok"}


def _reject_assignment_delete_when_history_exists(
    db: Session,
    *,
    assignment_id: uuid.UUID,
    business_id: uuid.UUID,
) -> None:
    """Block removal while a punch or correction request still points here.

    Raises before any delete. An open Time In is reported first. Any other
    attendance row, including a completed punch, is reported next. A
    correction request is reported last so the database cascade cannot
    remove it. The shift row is never changed here.
    """
    open_punch = (
        db.query(AttendanceRecord.id)
        .filter(
            AttendanceRecord.shift_assignment_id == assignment_id,
            AttendanceRecord.business_id == business_id,
            AttendanceRecord.time_in.isnot(None),
            AttendanceRecord.time_out.is_(None),
        )
        .first()
    )
    if open_punch is not None:
        raise HTTPException(409, ASSIGNMENT_OPEN_ATTENDANCE_MESSAGE)

    attendance = (
        db.query(AttendanceRecord.id)
        .filter(
            AttendanceRecord.shift_assignment_id == assignment_id,
            AttendanceRecord.business_id == business_id,
        )
        .first()
    )
    if attendance is not None:
        raise HTTPException(409, ASSIGNMENT_ATTENDANCE_RECORDED_MESSAGE)

    correction = (
        db.query(AttendanceCorrectionRequest.id)
        .filter(
            AttendanceCorrectionRequest.shift_assignment_id == assignment_id,
            AttendanceCorrectionRequest.business_id == business_id,
        )
        .first()
    )
    if correction is not None:
        raise HTTPException(409, ASSIGNMENT_CORRECTION_MESSAGE)
