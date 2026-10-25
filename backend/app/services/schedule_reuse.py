"""Schedule reuse helpers — copy/preview/apply assignment patterns only.

Does not modify attendance, payroll, or leave records.
Conflict rules mirror existing assign overlap + capacity checks.
Approved and cancellation-pending leave dates are not copied.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.business import Business
from app.models.employee import Employee
from app.models.schedule_template import ScheduleTemplate, ScheduleTemplateEntry
from app.models.scheduling import Shift, ShiftAssignment
from app.schemas.schedule_reuse import (
    ScheduleConflictMode,
    ScheduleReuseApplyResponse,
    ScheduleReuseConflictSummary,
    ScheduleReusePreviewItem,
    ScheduleReusePreviewResponse,
    ScheduleReuseSource,
    ScheduleReuseSuggestionsResponse,
    ScheduleTemplateDetailResponse,
    ScheduleTemplateSummary,
)
from app.services.leave_requests import blocking_leave_dates_for_employees
from app.services.schedule_overlap import (
    assert_shifts_still_assignable,
    shifts_times_overlap,
)

_LEAVE_CONFLICT = (
    "This employee is currently on approved leave for the selected date(s)."
)


def _times_overlap(first: Shift, second: Shift) -> bool:
    return shifts_times_overlap(first, second)


def monday_of(value: date) -> date:
    """Normalize any calendar date to the application's Monday week start."""
    return value - timedelta(days=value.weekday())


_RANGE_ERROR = "End date must be the same as or later than the start date."


def validate_apply_range(start_date: date, end_date: date) -> None:
    if end_date < start_date:
        raise HTTPException(400, _RANGE_ERROR)


def expand_template_dates(
    entries: list[ScheduleTemplateEntry],
    start_date: date,
    end_date: date,
) -> list[tuple[uuid.UUID, uuid.UUID, date, bool]]:
    """Repeat the template's unique shift/employee set on every selected date.

    Rest-day premium is not carried from the template; the owner sets it
    when assigning an employee. Weekday offsets stay on the saved template
    for week-style apply without an explicit range.
    """
    validate_apply_range(start_date, end_date)
    pattern: list[tuple[uuid.UUID, uuid.UUID]] = []
    seen: set[tuple[uuid.UUID, uuid.UUID]] = set()
    for entry in entries:
        if entry.day_offset < 0 or entry.day_offset > 6:
            continue
        key = (entry.shift_id, entry.employee_id)
        if key in seen:
            continue
        seen.add(key)
        pattern.append(key)
    planned: list[tuple[uuid.UUID, uuid.UUID, date, bool]] = []
    day = start_date
    while day <= end_date:
        for shift_id, employee_id in pattern:
            planned.append((shift_id, employee_id, day, False))
        day += timedelta(days=1)
    return planned


def _assignment_rows_for_range(
    db: Session,
    business_id: uuid.UUID,
    start_date: date,
    end_date: date,
) -> list[tuple[ShiftAssignment, Employee, Shift]]:
    return (
        db.query(ShiftAssignment, Employee, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .filter(
            Shift.business_id == business_id,
            Employee.business_id == business_id,
            ShiftAssignment.work_date >= start_date,
            ShiftAssignment.work_date <= end_date,
        )
        .order_by(Employee.full_name, ShiftAssignment.work_date, Shift.start_time)
        .all()
    )


def _assignment_rows_for_week(
    db: Session,
    business_id: uuid.UUID,
    week_start: date,
) -> list[tuple[ShiftAssignment, Employee, Shift]]:
    week_start = monday_of(week_start)
    return _assignment_rows_for_range(
        db, business_id, week_start, week_start + timedelta(days=6)
    )


def _find_last_schedule_week(
    db: Session,
    business_id: uuid.UUID,
    before: date | None = None,
) -> date | None:
    # Find the most recent assignment date, then normalize to Monday.
    latest = (
        db.query(func.max(ShiftAssignment.work_date))
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .filter(Shift.business_id == business_id)
    )
    if before is not None:
        latest = latest.filter(ShiftAssignment.work_date < before)
    latest_date = latest.scalar()
    if latest_date is None:
        return None
    return latest_date - timedelta(days=latest_date.weekday())


def _source_week_start(
    db: Session,
    business_id: uuid.UUID,
    source: ScheduleReuseSource,
    target_week_start: date,
    source_week_start: date | None,
    template_id: str | None,
    start_date: date | None = None,
    end_date: date | None = None,
) -> tuple[date | None, str, list[tuple[uuid.UUID, uuid.UUID, date, bool]]]:
    """Return (source_week, label, planned rows as shift/employee/date/rest)."""
    target_week_start = monday_of(target_week_start)
    if source_week_start is not None:
        source_week_start = monday_of(source_week_start)
    if source == ScheduleReuseSource.template:
        if not template_id:
            raise HTTPException(400, "template_id is required for template source")
        template = db.get(ScheduleTemplate, uuid.UUID(template_id))
        if template is None or template.business_id != business_id:
            raise HTTPException(404, "Schedule template not found")
        entries = (
            db.query(ScheduleTemplateEntry)
            .filter(ScheduleTemplateEntry.template_id == template.id)
            .all()
        )
        if start_date is not None or end_date is not None:
            range_start = start_date or target_week_start
            range_end = end_date or range_start
            validate_apply_range(range_start, range_end)
            planned = expand_template_dates(entries, range_start, range_end)
        else:
            planned = []
            for entry in entries:
                if entry.day_offset < 0 or entry.day_offset > 6:
                    continue
                planned.append(
                    (
                        entry.shift_id,
                        entry.employee_id,
                        target_week_start + timedelta(days=entry.day_offset),
                        False,
                    )
                )
        if not planned:
            raise HTTPException(400, "This template has no assignments to apply")
        return None, template.name, planned

    if source == ScheduleReuseSource.previous_week:
        src_start = target_week_start - timedelta(days=7)
        label = "Previous week"
    elif source == ScheduleReuseSource.week:
        if source_week_start is None:
            raise HTTPException(400, "source_week_start is required")
        src_start = source_week_start
        label = f"Week of {src_start.isoformat()}"
    elif source == ScheduleReuseSource.last_schedule:
        src_start = _find_last_schedule_week(
            db, business_id, before=target_week_start
        )
        if src_start is None:
            raise HTTPException(404, "No previous schedule found")
        label = "Last schedule"
    else:
        raise HTTPException(400, "Unsupported reuse source")

    if src_start == target_week_start:
        raise HTTPException(400, "Source week and target week must be different")

    rows = _assignment_rows_for_week(db, business_id, src_start)
    if not rows:
        raise HTTPException(404, "No schedule assignments found for the selected source")
    day_delta = (target_week_start - src_start).days
    planned = [
        (
            assignment.shift_id,
            assignment.employee_id,
            assignment.work_date + timedelta(days=day_delta),
            bool(assignment.is_rest_day_work),
        )
        for assignment, _employee, _shift in rows
    ]
    return src_start, label, planned


def _target_span(
    source: ScheduleReuseSource,
    target_week_start: date,
    start_date: date | None,
    end_date: date | None,
) -> tuple[date, date]:
    if source == ScheduleReuseSource.template and (
        start_date is not None or end_date is not None
    ):
        range_start = start_date or target_week_start
        range_end = end_date or range_start
        validate_apply_range(range_start, range_end)
        return range_start, range_end
    monday = monday_of(target_week_start)
    return monday, monday + timedelta(days=6)


def build_preview(
    db: Session,
    business_id: uuid.UUID,
    source: ScheduleReuseSource,
    target_week_start: date,
    source_week_start: date | None = None,
    template_id: str | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
) -> ScheduleReusePreviewResponse:
    span_start, span_end = _target_span(
        source, target_week_start, start_date, end_date
    )
    src_week, label, planned = _source_week_start(
        db,
        business_id,
        source,
        target_week_start,
        source_week_start,
        template_id,
        start_date=start_date,
        end_date=end_date,
    )

    employees = {
        emp.id: emp
        for emp in db.query(Employee)
        .filter(Employee.business_id == business_id)
        .all()
    }
    shifts = {
        shift.id: shift
        for shift in db.query(Shift).filter(Shift.business_id == business_id).all()
    }

    existing_rows = _assignment_rows_for_range(
        db, business_id, span_start, span_end
    )
    existing_by_employee_date: dict[tuple[uuid.UUID, date], list[tuple[ShiftAssignment, Shift]]] = (
        defaultdict(list)
    )
    existing_same_shift: set[tuple[uuid.UUID, uuid.UUID, date]] = set()
    for assignment, _emp, shift in existing_rows:
        existing_by_employee_date[(assignment.employee_id, assignment.work_date)].append(
            (assignment, shift)
        )
        existing_same_shift.add(
            (assignment.employee_id, assignment.shift_id, assignment.work_date)
        )

    items: list[ScheduleReusePreviewItem] = []
    conflict_count = 0
    duplicate_count = 0
    skipped_count = 0
    creatable_count = 0
    employee_ids: set[str] = set()
    working_dates: set[date] = set()

    # Track planned adds for merge capacity / self-overlap preview
    planned_adds: dict[tuple[uuid.UUID, date], list[Shift]] = defaultdict(list)
    capacity_counts: dict[tuple[uuid.UUID, date], int] = defaultdict(int)
    for assignment, _emp, shift in existing_rows:
        capacity_counts[(assignment.shift_id, assignment.work_date)] += 1

    protected_leave = blocking_leave_dates_for_employees(
        db,
        business_id=business_id,
        employee_ids=list(employees.keys()),
        start_date=span_start,
        end_date=span_end,
    )

    for shift_id, employee_id, work_date, is_rest in planned:
        employee = employees.get(employee_id)
        shift = shifts.get(shift_id)
        employee_name = employee.full_name if employee else "Unknown employee"
        shift_name = shift.name if shift else "Missing shift"

        base = ScheduleReusePreviewItem(
            employee_id=str(employee_id),
            employee_name=employee_name,
            shift_id=str(shift_id),
            shift_name=shift_name,
            shift_start_time=shift.start_time if shift else time(0, 0),
            shift_end_time=shift.end_time if shift else time(0, 0),
            shift_color=shift.color if shift else None,
            work_date=work_date,
            is_rest_day_work=is_rest,
            status="new",
            conflict_reason=None,
        )

        if shift is None or not shift.is_active:
            base.status = "skipped_missing_shift"
            base.conflict_reason = "Shift is missing or inactive"
            skipped_count += 1
            items.append(base)
            continue

        if employee is None or not employee.is_active:
            base.status = "skipped_inactive"
            base.conflict_reason = "Employee is inactive or missing"
            skipped_count += 1
            items.append(base)
            continue

        employee_ids.add(str(employee_id))
        working_dates.add(work_date)

        if work_date in protected_leave.get(employee_id, set()):
            base.status = "conflict"
            base.conflict_reason = _LEAVE_CONFLICT
            conflict_count += 1
            items.append(base)
            continue

        if (employee_id, shift_id, work_date) in existing_same_shift:
            base.status = "duplicate"
            base.conflict_reason = "Already assigned to this shift on this day"
            duplicate_count += 1
            items.append(base)
            continue

        conflict_reason = None
        for existing_assignment, existing_shift in existing_by_employee_date.get(
            (employee_id, work_date), []
        ):
            if existing_assignment.shift_id == shift_id or _times_overlap(
                existing_shift, shift
            ):
                conflict_reason = (
                    f"Conflicts with {existing_shift.name} on {work_date.isoformat()}"
                )
                break

        if conflict_reason is None:
            for planned_shift in planned_adds[(employee_id, work_date)]:
                if planned_shift.id == shift.id or _times_overlap(planned_shift, shift):
                    conflict_reason = (
                        "Conflicts with another assignment in this reuse batch"
                    )
                    break

        next_capacity = capacity_counts[(shift_id, work_date)] + 1
        if conflict_reason is None and next_capacity > shift.employee_capacity:
            conflict_reason = (
                f"Shift capacity exceeded (max {shift.employee_capacity})"
            )

        if conflict_reason:
            base.status = "conflict"
            base.conflict_reason = conflict_reason
            conflict_count += 1
            items.append(base)
            continue

        base.status = "new"
        creatable_count += 1
        planned_adds[(employee_id, work_date)].append(shift)
        capacity_counts[(shift_id, work_date)] = next_capacity
        items.append(base)

    return ScheduleReusePreviewResponse(
        source=source,
        source_label=label,
        source_week_start=src_week,
        target_week_start=span_start,
        target_week_end=span_end,
        employee_count=len(employee_ids),
        working_day_count=len(working_dates),
        items=items,
        conflicts=ScheduleReuseConflictSummary(
            existing_assignment_count=len(existing_rows),
            conflict_count=conflict_count,
            duplicate_count=duplicate_count,
            skipped_count=skipped_count,
            creatable_count=creatable_count,
        ),
    )


def apply_reuse(
    db: Session,
    business_id: uuid.UUID,
    source: ScheduleReuseSource,
    target_week_start: date,
    conflict_mode: ScheduleConflictMode,
    source_week_start: date | None = None,
    template_id: str | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
) -> ScheduleReuseApplyResponse:
    span_start, span_end = _target_span(
        source, target_week_start, start_date, end_date
    )
    preview = build_preview(
        db,
        business_id,
        source,
        target_week_start,
        source_week_start,
        template_id,
        start_date=start_date,
        end_date=end_date,
    )
    removed = 0
    protected_leave = blocking_leave_dates_for_employees(
        db,
        business_id=business_id,
        employee_ids=[uuid.UUID(item.employee_id) for item in preview.items],
        start_date=span_start,
        end_date=span_end,
    )

    def _blocked_by_leave(item: ScheduleReusePreviewItem) -> bool:
        return item.work_date in protected_leave.get(uuid.UUID(item.employee_id), set())

    business = db.get(Business, business_id)
    tz_name = business.timezone if business is not None else None
    shifts_by_id = {
        shift.id: shift
        for shift in db.query(Shift).filter(Shift.business_id == business_id).all()
    }

    def _will_create(item: ScheduleReusePreviewItem) -> bool:
        if _blocked_by_leave(item):
            return False
        if conflict_mode == ScheduleConflictMode.replace:
            return item.status not in ("skipped_inactive", "skipped_missing_shift")
        return item.status == "new"

    assert_shifts_still_assignable(
        [
            (item.work_date, shifts_by_id.get(uuid.UUID(item.shift_id)))
            for item in preview.items
            if _will_create(item)
        ],
        tz_name=tz_name,
    )
    if conflict_mode == ScheduleConflictMode.replace:
        existing_before_replace = _assignment_rows_for_range(
            db, business_id, span_start, span_end
        )
        assert_shifts_still_assignable(
            [
                (assignment.work_date, shift_row)
                for assignment, _employee, shift_row in existing_before_replace
            ],
            tz_name=tz_name,
        )

    removed_snapshots: list[dict] = []
    created_snapshots: list[dict] = []
    if conflict_mode == ScheduleConflictMode.replace:
        existing = _assignment_rows_for_range(db, business_id, span_start, span_end)
        for assignment, emp, shift_row in existing:
            removed_snapshots.append(
                {
                    "assignment_id": assignment.id,
                    "employee": emp,
                    "shift": shift_row,
                    "work_date": assignment.work_date,
                }
            )
            db.delete(assignment)
            removed += 1
        db.flush()
        # After replace, recreate from all non-skipped source items
        creatable_items = [
            item
            for item in preview.items
            if item.status
            not in ("skipped_inactive", "skipped_missing_shift")
            and not _blocked_by_leave(item)
        ]
    else:
        # merge: only create items marked new in preview
        creatable_items = [
            item
            for item in preview.items
            if item.status == "new" and not _blocked_by_leave(item)
        ]

    created = 0
    skipped = len(preview.items) - len(creatable_items)

    # Re-validate capacity after replace wipe
    if conflict_mode == ScheduleConflictMode.replace:
        capacity_counts: dict[tuple[uuid.UUID, date], int] = defaultdict(int)
        employee_day_shifts: dict[tuple[uuid.UUID, date], list[Shift]] = defaultdict(
            list
        )
        shifts = {
            shift.id: shift
            for shift in db.query(Shift).filter(Shift.business_id == business_id).all()
        }
        for item in creatable_items:
            shift = shifts.get(uuid.UUID(item.shift_id))
            if shift is None or not shift.is_active:
                skipped += 1
                continue
            employee_id = uuid.UUID(item.employee_id)
            key = (employee_id, item.work_date)
            conflict = False
            for existing_shift in employee_day_shifts[key]:
                if existing_shift.id == shift.id or _times_overlap(existing_shift, shift):
                    conflict = True
                    break
            if conflict:
                skipped += 1
                continue
            cap_key = (shift.id, item.work_date)
            if capacity_counts[cap_key] + 1 > shift.employee_capacity:
                skipped += 1
                continue
            assignment = ShiftAssignment(
                shift_id=shift.id,
                employee_id=employee_id,
                work_date=item.work_date,
                is_rest_day_work=item.is_rest_day_work,
            )
            db.add(assignment)
            created_snapshots.append(
                {
                    "assignment": assignment,
                    "employee_id": employee_id,
                    "shift": shift,
                    "work_date": item.work_date,
                }
            )
            employee_day_shifts[key].append(shift)
            capacity_counts[cap_key] += 1
            created += 1
    else:
        shifts = {
            shift.id: shift
            for shift in db.query(Shift).filter(Shift.business_id == business_id).all()
        }
        for item in creatable_items:
            assignment = ShiftAssignment(
                shift_id=uuid.UUID(item.shift_id),
                employee_id=uuid.UUID(item.employee_id),
                work_date=item.work_date,
                is_rest_day_work=item.is_rest_day_work,
            )
            db.add(assignment)
            created_snapshots.append(
                {
                    "assignment": assignment,
                    "employee_id": uuid.UUID(item.employee_id),
                    "shift": shifts.get(uuid.UUID(item.shift_id)),
                    "work_date": item.work_date,
                }
            )
            created += 1

    db.commit()
    try:
        from app.services.activity_notifications import notify_schedule_reuse_applied

        ready = [
            item
            for item in created_snapshots
            if item.get("assignment") is not None and item.get("shift") is not None
        ]
        notify_schedule_reuse_applied(
            db, removed=removed_snapshots, created=ready
        )
    except Exception:
        pass
    return ScheduleReuseApplyResponse(
        created=created,
        removed=removed,
        skipped=skipped,
        target_week_start=span_start,
        target_week_end=span_end,
    )


def list_templates(db: Session, business_id: uuid.UUID) -> list[ScheduleTemplateSummary]:
    templates = (
        db.query(ScheduleTemplate)
        .filter(ScheduleTemplate.business_id == business_id)
        .order_by(ScheduleTemplate.name)
        .all()
    )
    result: list[ScheduleTemplateSummary] = []
    for template in templates:
        entries = (
            db.query(ScheduleTemplateEntry)
            .filter(ScheduleTemplateEntry.template_id == template.id)
            .all()
        )
        result.append(
            ScheduleTemplateSummary(
                id=str(template.id),
                name=template.name,
                entry_count=len(entries),
                employee_count=len({e.employee_id for e in entries}),
                created_at=template.created_at.date() if template.created_at else None,
            )
        )
    return result


def get_template_detail(
    db: Session, business_id: uuid.UUID, template_id: uuid.UUID
) -> ScheduleTemplateDetailResponse:
    template = db.get(ScheduleTemplate, template_id)
    if template is None or template.business_id != business_id:
        raise HTTPException(404, "Schedule template not found")

    entries = (
        db.query(ScheduleTemplateEntry, Employee, Shift)
        .join(Employee, ScheduleTemplateEntry.employee_id == Employee.id)
        .join(Shift, ScheduleTemplateEntry.shift_id == Shift.id)
        .filter(ScheduleTemplateEntry.template_id == template.id)
        .order_by(ScheduleTemplateEntry.day_offset, Employee.full_name)
        .all()
    )
    # Use a reference Monday for display dates in detail
    ref_monday = date(2000, 1, 3)
    items = [
        ScheduleReusePreviewItem(
            employee_id=str(employee.id),
            employee_name=employee.full_name,
            shift_id=str(shift.id),
            shift_name=shift.name,
            shift_start_time=shift.start_time,
            shift_end_time=shift.end_time,
            shift_color=shift.color,
            work_date=ref_monday + timedelta(days=entry.day_offset),
            is_rest_day_work=bool(entry.is_rest_day_work),
            status="new",
        )
        for entry, employee, shift in entries
    ]
    return ScheduleTemplateDetailResponse(
        id=str(template.id),
        name=template.name,
        entry_count=len(items),
        employee_count=len({item.employee_id for item in items}),
        created_at=template.created_at.date() if template.created_at else None,
        entries=items,
    )


def create_template_from_week(
    db: Session,
    business_id: uuid.UUID,
    name: str,
    week_start: date,
    created_by: uuid.UUID | None,
) -> ScheduleTemplateSummary:
    week_start = monday_of(week_start)
    clean_name = name.strip()
    if not clean_name:
        raise HTTPException(400, "Template name is required")

    existing = (
        db.query(ScheduleTemplate)
        .filter(
            ScheduleTemplate.business_id == business_id,
            ScheduleTemplate.name == clean_name,
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(400, "A template with this name already exists")

    rows = _assignment_rows_for_week(db, business_id, week_start)
    if not rows:
        raise HTTPException(400, "No schedule assignments found in that week")

    template = ScheduleTemplate(
        business_id=business_id,
        name=clean_name,
        created_by=created_by,
    )
    db.add(template)
    db.flush()

    for assignment, _employee, _shift in rows:
        day_offset = (assignment.work_date - week_start).days
        if day_offset < 0 or day_offset > 6:
            continue
        db.add(
            ScheduleTemplateEntry(
                template_id=template.id,
                shift_id=assignment.shift_id,
                employee_id=assignment.employee_id,
                day_offset=day_offset,
                is_rest_day_work=False,
            )
        )

    db.commit()
    db.refresh(template)
    summaries = list_templates(db, business_id)
    for summary in summaries:
        if summary.id == str(template.id):
            return summary
    raise HTTPException(500, "Failed to create schedule template")


def rename_template(
    db: Session,
    business_id: uuid.UUID,
    template_id: uuid.UUID,
    name: str,
) -> ScheduleTemplateSummary:
    clean_name = name.strip()
    if not clean_name:
        raise HTTPException(400, "Template name is required")

    template = db.get(ScheduleTemplate, template_id)
    if template is None or template.business_id != business_id:
        raise HTTPException(404, "Schedule template not found")

    clash = (
        db.query(ScheduleTemplate)
        .filter(
            ScheduleTemplate.business_id == business_id,
            ScheduleTemplate.name == clean_name,
            ScheduleTemplate.id != template.id,
        )
        .first()
    )
    if clash is not None:
        raise HTTPException(400, "A template with this name already exists")

    template.name = clean_name
    template.updated_at = datetime.now(timezone.utc)
    db.commit()
    summaries = list_templates(db, business_id)
    for summary in summaries:
        if summary.id == str(template.id):
            return summary
    raise HTTPException(500, "Failed to rename schedule template")


def delete_template(
    db: Session, business_id: uuid.UUID, template_id: uuid.UUID
) -> None:
    template = db.get(ScheduleTemplate, template_id)
    if template is None or template.business_id != business_id:
        raise HTTPException(404, "Schedule template not found")
    db.query(ScheduleTemplateEntry).filter(
        ScheduleTemplateEntry.template_id == template.id
    ).delete()
    db.delete(template)
    db.commit()


def reuse_suggestions(
    db: Session, business_id: uuid.UUID, target_week_start: date
) -> ScheduleReuseSuggestionsResponse:
    target_week_start = monday_of(target_week_start)
    previous_week_start = target_week_start - timedelta(days=7)
    previous_count = len(_assignment_rows_for_week(db, business_id, previous_week_start))
    last_week = _find_last_schedule_week(db, business_id, before=target_week_start)
    last_count = (
        len(_assignment_rows_for_week(db, business_id, last_week))
        if last_week is not None
        else 0
    )
    templates = list_templates(db, business_id)
    target_count = len(_assignment_rows_for_week(db, business_id, target_week_start))
    suggest = target_count == 0 and (previous_count > 0 or last_count > 0)

    return ScheduleReuseSuggestionsResponse(
        target_week_start=target_week_start,
        previous_week_start=previous_week_start if previous_count > 0 else None,
        previous_week_assignment_count=previous_count,
        last_schedule_week_start=last_week if last_count > 0 else None,
        last_schedule_assignment_count=last_count,
        templates=templates,
        suggest_previous=suggest,
    )
