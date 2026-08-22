"""Schedule reuse helpers — copy/preview/apply assignment patterns only.

Does not touch attendance, payroll, leave, or productivity records.
Conflict rules mirror existing assign overlap + capacity checks.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

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


def _times_overlap(first: Shift, second: Shift) -> bool:
    return first.start_time < second.end_time and second.start_time < first.end_time


def _assignment_rows_for_week(
    db: Session,
    business_id: uuid.UUID,
    week_start: date,
) -> list[tuple[ShiftAssignment, Employee, Shift]]:
    week_end = week_start + timedelta(days=6)
    return (
        db.query(ShiftAssignment, Employee, Shift)
        .join(Shift, ShiftAssignment.shift_id == Shift.id)
        .join(Employee, ShiftAssignment.employee_id == Employee.id)
        .filter(
            Shift.business_id == business_id,
            Employee.business_id == business_id,
            ShiftAssignment.work_date >= week_start,
            ShiftAssignment.work_date <= week_end,
        )
        .order_by(Employee.full_name, ShiftAssignment.work_date, Shift.start_time)
        .all()
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
) -> tuple[date | None, str, list[tuple[uuid.UUID, uuid.UUID, date, bool]]]:
    """Return (source_week, label, planned rows as shift/employee/date/rest)."""
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
        planned: list[tuple[uuid.UUID, uuid.UUID, date, bool]] = []
        for entry in entries:
            if entry.day_offset < 0 or entry.day_offset > 6:
                continue
            planned.append(
                (
                    entry.shift_id,
                    entry.employee_id,
                    target_week_start + timedelta(days=entry.day_offset),
                    bool(entry.is_rest_day_work),
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


def build_preview(
    db: Session,
    business_id: uuid.UUID,
    source: ScheduleReuseSource,
    target_week_start: date,
    source_week_start: date | None = None,
    template_id: str | None = None,
) -> ScheduleReusePreviewResponse:
    src_week, label, planned = _source_week_start(
        db,
        business_id,
        source,
        target_week_start,
        source_week_start,
        template_id,
    )
    target_end = target_week_start + timedelta(days=6)

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

    existing_rows = _assignment_rows_for_week(db, business_id, target_week_start)
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
        target_week_start=target_week_start,
        target_week_end=target_end,
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
) -> ScheduleReuseApplyResponse:
    preview = build_preview(
        db,
        business_id,
        source,
        target_week_start,
        source_week_start,
        template_id,
    )
    target_end = target_week_start + timedelta(days=6)
    removed = 0

    if conflict_mode == ScheduleConflictMode.replace:
        existing = _assignment_rows_for_week(db, business_id, target_week_start)
        for assignment, _emp, _shift in existing:
            db.delete(assignment)
            removed += 1
        db.flush()
        # After replace, recreate from all non-skipped source items
        creatable_items = [
            item
            for item in preview.items
            if item.status
            not in ("skipped_inactive", "skipped_missing_shift")
        ]
    else:
        # merge: only create items marked new in preview
        creatable_items = [item for item in preview.items if item.status == "new"]

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
            db.add(
                ShiftAssignment(
                    shift_id=shift.id,
                    employee_id=employee_id,
                    work_date=item.work_date,
                    is_rest_day_work=item.is_rest_day_work,
                )
            )
            employee_day_shifts[key].append(shift)
            capacity_counts[cap_key] += 1
            created += 1
    else:
        for item in creatable_items:
            db.add(
                ShiftAssignment(
                    shift_id=uuid.UUID(item.shift_id),
                    employee_id=uuid.UUID(item.employee_id),
                    work_date=item.work_date,
                    is_rest_day_work=item.is_rest_day_work,
                )
            )
            created += 1

    db.commit()
    return ScheduleReuseApplyResponse(
        created=created,
        removed=removed,
        skipped=skipped,
        target_week_start=target_week_start,
        target_week_end=target_end,
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
                is_rest_day_work=bool(assignment.is_rest_day_work),
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
