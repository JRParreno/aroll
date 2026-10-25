"""Schedule Library apply: copy assignments, weekdays, and no duplicates."""

import uuid
from datetime import date, datetime, time, timedelta

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import EmployeeStatus, EmploymentType, UserRole
from app.models.schedule_template import ScheduleTemplateEntry
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.schemas.schedule_reuse import ScheduleConflictMode, ScheduleReuseSource
from app.services.schedule_reuse import (
    apply_reuse,
    build_preview,
    create_template_from_week,
    expand_template_dates,
    monday_of,
    reuse_suggestions,
)


def _headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


class LibraryWorld:
    def __init__(self) -> None:
        self.db = SessionLocal()
        self.business = Business(
            business_code=f"SL-{uuid.uuid4().hex[:6].upper()}",
            name="Schedule Library Biz",
            timezone="Asia/Manila",
        )
        self.db.add(self.business)
        self.db.flush()
        self.owner = User(
            business_id=self.business.id,
            email=f"owner-{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("OwnerPass123!"),
            role=UserRole.owner,
            must_change_password=False,
            is_active=True,
        )
        self.db.add(self.owner)
        self.db.flush()
        self.morning = Shift(
            business_id=self.business.id,
            name="Morning",
            start_time=time(8, 0),
            end_time=time(12, 0),
            employee_capacity=8,
        )
        self.afternoon = Shift(
            business_id=self.business.id,
            name="Afternoon",
            start_time=time(13, 0),
            end_time=time(17, 0),
            employee_capacity=8,
        )
        self.db.add_all([self.morning, self.afternoon])
        self.db.flush()
        self.employees: list[Employee] = []

    def close(self) -> None:
        self.db.close()

    def add_employee(
        self,
        name: str,
        *,
        activated: bool = True,
        active: bool = True,
        user_business_id=None,
    ) -> Employee:
        user = User(
            business_id=self.business.id if user_business_id is None else user_business_id,
            email=f"{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("EmpPass123!"),
            role=UserRole.employee,
            must_change_password=not activated,
            is_active=True,
        )
        self.db.add(user)
        self.db.flush()
        employee = Employee(
            business_id=self.business.id,
            user_id=user.id,
            full_name=name,
            employment_type=EmploymentType.full_time,
            status=EmployeeStatus.active if active else EmployeeStatus.inactive,
            is_active=active,
            face_registration_status="completed" if activated else "not_registered",
        )
        self.db.add(employee)
        self.db.flush()
        self.employees.append(employee)
        return employee

    def assign(
        self,
        employee: Employee,
        work_date: date,
        shift: Shift | None = None,
        *,
        is_rest_day_work: bool = False,
    ) -> ShiftAssignment:
        row = ShiftAssignment(
            shift_id=(shift or self.morning).id,
            employee_id=employee.id,
            work_date=work_date,
            is_rest_day_work=is_rest_day_work,
        )
        self.db.add(row)
        self.db.commit()
        self.db.refresh(row)
        return row

    def week_assignments(self, week_start: date) -> list[ShiftAssignment]:
        week_end = week_start + timedelta(days=6)
        return (
            self.db.query(ShiftAssignment)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(
                Shift.business_id == self.business.id,
                ShiftAssignment.work_date >= week_start,
                ShiftAssignment.work_date <= week_end,
            )
            .all()
        )


@pytest.fixture(autouse=True)
def _schedule_clock_before_library_dates(monkeypatch):
    """September 2026 library weeks are historical on a later machine clock.

    Freeze the assignment clock before those dates so the past-shift rule
    does not reject the existing copy and rest-day scenarios.
    """
    monkeypatch.setattr(
        "app.services.schedule_overlap.business_now",
        lambda tz_name: datetime(2026, 9, 1, 8, 0),
    )


SOURCE_MONDAY = date(2026, 9, 21)
TARGET_MONDAY = date(2026, 9, 28)
SOURCE_THURSDAY = date(2026, 9, 24)
TARGET_THURSDAY = date(2026, 10, 1)


def test_monday_of_normalizes_mid_week_and_year_boundary():
    assert monday_of(date(2026, 10, 1)) == date(2026, 9, 28)
    assert monday_of(date(2026, 9, 28)) == date(2026, 9, 28)
    assert monday_of(date(2027, 1, 1)) == date(2026, 12, 28)
    assert monday_of(date(2026, 12, 28)) == date(2026, 12, 28)


def test_apply_previous_week_copies_employees_and_weekdays():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Reyes")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        world.assign(ana, SOURCE_THURSDAY, world.afternoon)
        world.assign(ben, date(2026, 9, 22), world.afternoon)
        world.assign(ben, date(2026, 9, 27), world.morning, is_rest_day_work=True)

        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
        )
        assert preview.target_week_start == TARGET_MONDAY
        assert preview.target_week_end == date(2026, 10, 4)
        assert preview.conflicts.creatable_count == 4
        assert {item.work_date for item in preview.items} == {
            TARGET_MONDAY,
            date(2026, 9, 29),
            TARGET_THURSDAY,
            date(2026, 10, 4),
        }

        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
        )
        assert result.created == 4
        assert result.skipped == 0
        assert result.target_week_start == TARGET_MONDAY

        copied = world.week_assignments(TARGET_MONDAY)
        assert len(copied) == 4
        by_key = {
            (row.employee_id, row.work_date, row.shift_id): row for row in copied
        }
        assert (ana.id, TARGET_MONDAY, world.morning.id) in by_key
        assert (ana.id, TARGET_THURSDAY, world.afternoon.id) in by_key
        assert (ben.id, date(2026, 9, 29), world.afternoon.id) in by_key
        sunday = by_key[(ben.id, date(2026, 10, 4), world.morning.id)]
        assert sunday.is_rest_day_work is True
    finally:
        world.close()


def test_today_weekday_appears_on_weekly_schedule_after_apply():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Reyes")
        world.assign(ana, SOURCE_THURSDAY, world.morning)
        world.assign(ben, SOURCE_THURSDAY, world.afternoon)

        apply_body = client.post(
            "/api/v1/schedules/reuse/apply",
            json={
                "source": "previous_week",
                "target_week_start": TARGET_MONDAY.isoformat(),
                "conflict_mode": "merge",
            },
            headers=_headers(world.owner),
        )
        assert apply_body.status_code == 200, apply_body.text
        payload = apply_body.json()
        assert payload["created"] == 2
        assert payload["target_week_start"] == TARGET_MONDAY.isoformat()

        weekly = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": TARGET_MONDAY.isoformat()},
            headers=_headers(world.owner),
        )
        assert weekly.status_code == 200, weekly.text
        today_rows = [
            row
            for row in weekly.json()["assignments"]
            if row["work_date"] == TARGET_THURSDAY.isoformat()
        ]
        names = {row["employee_name"] for row in today_rows}
        assert names == {"Ana Cruz", "Ben Reyes"}
        shifts = {row["shift_name"] for row in today_rows}
        assert shifts == {"Morning", "Afternoon"}

        refresh = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": TARGET_MONDAY.isoformat()},
            headers=_headers(world.owner),
        )
        assert len(refresh.json()["assignments"]) == 2
        for row in refresh.json()["assignments"]:
            assert row["work_date"] == TARGET_THURSDAY.isoformat()
            assert "T" not in row["work_date"]
    finally:
        world.close()


def test_weekly_schedule_includes_every_covered_date_after_apply():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Reyes")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        world.assign(ana, SOURCE_THURSDAY, world.afternoon)
        world.assign(ben, date(2026, 9, 22), world.afternoon)

        applied = client.post(
            "/api/v1/schedules/reuse/apply",
            json={
                "source": "previous_week",
                "target_week_start": TARGET_THURSDAY.isoformat(),
                "conflict_mode": "merge",
            },
            headers=_headers(world.owner),
        )
        assert applied.status_code == 200, applied.text
        assert applied.json()["created"] == 3

        midweek = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": TARGET_THURSDAY.isoformat()},
            headers=_headers(world.owner),
        )
        assert midweek.status_code == 200, midweek.text
        body = midweek.json()
        assert body["week_start"] == TARGET_MONDAY.isoformat()
        assert body["week_end"] == date(2026, 10, 4).isoformat()

        by_date: dict[str, set[str]] = {}
        for row in body["assignments"]:
            by_date.setdefault(row["work_date"], set()).add(row["employee_name"])
        assert by_date[TARGET_MONDAY.isoformat()] == {"Ana Cruz"}
        assert by_date[date(2026, 9, 29).isoformat()] == {"Ben Reyes"}
        assert by_date[TARGET_THURSDAY.isoformat()] == {"Ana Cruz"}
        assert date(2026, 9, 30).isoformat() not in by_date

        monday_reload = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": TARGET_MONDAY.isoformat()},
            headers=_headers(world.owner),
        )
        assert {
            (row["employee_name"], row["work_date"])
            for row in monday_reload.json()["assignments"]
        } == {
            ("Ana Cruz", TARGET_MONDAY.isoformat()),
            ("Ben Reyes", date(2026, 9, 29).isoformat()),
            ("Ana Cruz", TARGET_THURSDAY.isoformat()),
        }
    finally:
        world.close()


def test_reapply_merge_does_not_duplicate_assignments():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        world.assign(ana, SOURCE_THURSDAY, world.afternoon)

        first = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
        )
        assert first.created == 2

        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
        )
        assert preview.conflicts.duplicate_count == 2
        assert preview.conflicts.creatable_count == 0
        assert all(item.status == "duplicate" for item in preview.items)
        assert all(item.conflict_reason for item in preview.items)

        second = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
        )
        assert second.created == 0
        assert second.skipped == 2
        assert len(world.week_assignments(TARGET_MONDAY)) == 2
    finally:
        world.close()


def test_mid_week_target_date_normalizes_to_monday():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        world.assign(ana, date(2026, 9, 23), world.afternoon)

        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_THURSDAY,
            ScheduleConflictMode.merge,
        )
        assert result.target_week_start == TARGET_MONDAY
        assert result.created == 2
        dates = {row.work_date for row in world.week_assignments(TARGET_MONDAY)}
        assert dates == {TARGET_MONDAY, date(2026, 9, 30)}
    finally:
        world.close()


def test_template_preserves_employees_across_month_and_year():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Reyes")
        dec_monday = date(2026, 12, 28)
        jan_monday = date(2027, 1, 4)
        world.assign(ana, dec_monday, world.morning)
        world.assign(ben, date(2027, 1, 1), world.afternoon)

        template = create_template_from_week(
            world.db,
            world.business.id,
            "Year-end week",
            date(2026, 12, 31),
            world.owner.id,
        )
        assert template.entry_count == 2
        assert template.employee_count == 2

        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            jan_monday,
            ScheduleConflictMode.merge,
            template_id=template.id,
        )
        assert result.created == 2
        copied = world.week_assignments(jan_monday)
        assert {(row.employee_id, row.work_date, row.shift_id) for row in copied} == {
            (ana.id, jan_monday, world.morning.id),
            (ben.id, date(2027, 1, 8), world.afternoon.id),
        }
    finally:
        world.close()


def test_unactivated_but_active_employee_is_copied():
    world = LibraryWorld()
    try:
        pending = world.add_employee("Pending Lopez", activated=False)
        world.assign(pending, SOURCE_THURSDAY, world.morning)

        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
        )
        assert result.created == 1
        copied = world.week_assignments(TARGET_MONDAY)
        assert len(copied) == 1
        assert copied[0].employee_id == pending.id
        assert copied[0].work_date == TARGET_THURSDAY
    finally:
        world.close()


def test_inactive_employee_is_reported_not_silently_omitted():
    world = LibraryWorld()
    try:
        gone = world.add_employee("Inactive Diaz", active=False)
        world.assign(gone, SOURCE_MONDAY, world.morning)

        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
        )
        assert preview.items[0].status == "skipped_inactive"
        assert preview.items[0].conflict_reason
        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
        )
        assert result.created == 0
        assert result.skipped == 1
        assert world.week_assignments(TARGET_MONDAY) == []
    finally:
        world.close()


def test_empty_source_week_fails_clearly():
    world = LibraryWorld()
    try:
        with pytest.raises(HTTPException) as exc:
            apply_reuse(
                world.db,
                world.business.id,
                ScheduleReuseSource.previous_week,
                TARGET_MONDAY,
                ScheduleConflictMode.merge,
            )
        assert exc.value.status_code == 404
        suggestions = reuse_suggestions(world.db, world.business.id, TARGET_MONDAY)
        assert suggestions.previous_week_start is None
        assert suggestions.previous_week_assignment_count == 0
    finally:
        world.close()


def test_weekly_schedule_returns_assigned_employee_even_if_inactive():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        gone = world.add_employee("Inactive Diaz", active=False)
        world.assign(gone, TARGET_THURSDAY, world.morning)
        weekly = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": TARGET_THURSDAY.isoformat()},
            headers=_headers(world.owner),
        )
        assert weekly.status_code == 200, weekly.text
        names = {row["employee_name"] for row in weekly.json()["assignments"]}
        assert "Inactive Diaz" in names
        assert weekly.json()["week_start"] == TARGET_MONDAY.isoformat()
    finally:
        world.close()


def test_apply_does_not_change_source_week_assignments():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        source_before = len(world.week_assignments(SOURCE_MONDAY))
        apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
        )
        assert len(world.week_assignments(SOURCE_MONDAY)) == source_before
    finally:
        world.close()


def test_template_apply_one_date_uses_matching_weekday():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        world.assign(ana, SOURCE_THURSDAY, world.afternoon)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Office week",
            SOURCE_MONDAY,
            world.owner.id,
        )
        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=TARGET_THURSDAY,
            end_date=TARGET_THURSDAY,
        )
        assert result.created == 2
        assert result.target_week_start == TARGET_THURSDAY
        assert result.target_week_end == TARGET_THURSDAY
        copied = world.week_assignments(TARGET_MONDAY)
        assert {(row.work_date, row.shift_id) for row in copied} == {
            (TARGET_THURSDAY, world.morning.id),
            (TARGET_THURSDAY, world.afternoon.id),
        }
        assert all(row.is_rest_day_work is False for row in copied)
    finally:
        world.close()


def test_template_apply_repeats_weekdays_across_range_and_boundaries():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Reyes")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        world.assign(ben, SOURCE_THURSDAY, world.afternoon)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Mon Thu",
            SOURCE_MONDAY,
            world.owner.id,
        )
        start = date(2026, 10, 15)
        end = date(2026, 10, 20)
        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            start,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=start,
            end_date=end,
        )
        assert result.created == 12
        copied = {
            (row.employee_id, row.work_date, row.shift_id)
            for row in world.week_assignments(date(2026, 10, 12))
        } | {
            (row.employee_id, row.work_date, row.shift_id)
            for row in world.week_assignments(date(2026, 10, 19))
        }
        for day in (
            date(2026, 10, 15),
            date(2026, 10, 16),
            date(2026, 10, 17),
            date(2026, 10, 18),
            date(2026, 10, 19),
            date(2026, 10, 20),
        ):
            assert (ana.id, day, world.morning.id) in copied
            assert (ben.id, day, world.afternoon.id) in copied

        year_start = date(2026, 12, 31)
        year_end = date(2027, 1, 4)
        year_result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            year_start,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=year_start,
            end_date=year_end,
        )
        assert year_result.created == 10
        year_copied = world.week_assignments(date(2026, 12, 28)) + world.week_assignments(
            date(2027, 1, 4)
        )
        year_dates = {
            date(2026, 12, 31),
            date(2027, 1, 1),
            date(2027, 1, 2),
            date(2027, 1, 3),
            date(2027, 1, 4),
        }
        assert {
            (row.employee_id, row.work_date) for row in year_copied
        } >= {
            (employee.id, day)
            for employee in (ana, ben)
            for day in year_dates
        }
    finally:
        world.close()


def test_template_apply_rejects_inverted_range():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Range check",
            SOURCE_MONDAY,
            world.owner.id,
        )
        response = client.post(
            "/api/v1/schedules/reuse/preview",
            json={
                "source": "template",
                "target_week_start": TARGET_MONDAY.isoformat(),
                "template_id": template.id,
                "start_date": TARGET_THURSDAY.isoformat(),
                "end_date": TARGET_MONDAY.isoformat(),
            },
            headers=_headers(world.owner),
        )
        assert response.status_code == 400
        assert "later than the start date" in response.json()["detail"]
    finally:
        world.close()


def test_template_merge_skips_duplicates_and_replace_stays_in_range():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        outsider = world.add_employee("Outside Lee")
        world.assign(ana, SOURCE_MONDAY, world.morning)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Monday only",
            SOURCE_MONDAY,
            world.owner.id,
        )
        world.assign(outsider, date(2026, 10, 2), world.afternoon)
        first = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=TARGET_MONDAY,
            end_date=TARGET_MONDAY,
        )
        assert first.created == 1
        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            TARGET_MONDAY,
            template_id=template.id,
            start_date=TARGET_MONDAY,
            end_date=TARGET_MONDAY,
        )
        assert preview.conflicts.duplicate_count == 1
        second = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=TARGET_MONDAY,
            end_date=TARGET_MONDAY,
        )
        assert second.created == 0
        apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            TARGET_MONDAY,
            ScheduleConflictMode.replace,
            template_id=template.id,
            start_date=TARGET_MONDAY,
            end_date=TARGET_MONDAY,
        )
        week = world.week_assignments(TARGET_MONDAY)
        assert any(
            row.employee_id == outsider.id and row.work_date == date(2026, 10, 2)
            for row in week
        )
        assert sum(1 for row in week if row.work_date == TARGET_MONDAY) == 1
    finally:
        world.close()


def test_single_weekday_template_repeats_on_every_date_nov_2_through_6():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Reyes")
        tuesday = date(2026, 10, 27)
        world.assign(ana, tuesday, world.morning)
        world.assign(ben, tuesday, world.afternoon)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Tuesday roster",
            tuesday,
            world.owner.id,
        )
        start = date(2026, 11, 2)
        end = date(2026, 11, 6)
        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            start,
            template_id=template.id,
            start_date=start,
            end_date=end,
        )
        assert {item.work_date for item in preview.items} == {
            date(2026, 11, 2),
            date(2026, 11, 3),
            date(2026, 11, 4),
            date(2026, 11, 5),
            date(2026, 11, 6),
        }
        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            start,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=start,
            end_date=end,
        )
        assert result.created == 10
        weekly = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": start.isoformat()},
            headers=_headers(world.owner),
        )
        assert weekly.status_code == 200, weekly.text
        by_date: dict[str, set[str]] = {}
        for row in weekly.json()["assignments"]:
            by_date.setdefault(row["work_date"], set()).add(row["employee_name"])
        expected_names = {"Ana Cruz", "Ben Reyes"}
        for day in (
            date(2026, 11, 2),
            date(2026, 11, 3),
            date(2026, 11, 4),
            date(2026, 11, 5),
            date(2026, 11, 6),
        ):
            assert by_date[day.isoformat()] == expected_names

        second = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            start,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=start,
            end_date=end,
        )
        assert second.created == 0
        assert second.skipped == 10
    finally:
        world.close()


def test_expand_template_dates_repeats_full_pattern_on_every_date():
    morning = uuid.uuid4()
    afternoon = uuid.uuid4()
    ana = uuid.uuid4()
    ben = uuid.uuid4()

    class Entry:
        def __init__(self, shift_id, employee_id, day_offset, is_rest_day_work=False):
            self.shift_id = shift_id
            self.employee_id = employee_id
            self.day_offset = day_offset
            self.is_rest_day_work = is_rest_day_work

    planned = expand_template_dates(
        [
            Entry(morning, ana, 1, is_rest_day_work=True),
            Entry(afternoon, ben, 3),
        ],
        date(2026, 11, 2),
        date(2026, 11, 6),
    )
    dates = [
        date(2026, 11, 2),
        date(2026, 11, 3),
        date(2026, 11, 4),
        date(2026, 11, 5),
        date(2026, 11, 6),
    ]
    assert {(row[1], row[2], row[0], row[3]) for row in planned} == {
        (employee, day, shift, False)
        for employee, shift in ((ana, morning), (ben, afternoon))
        for day in dates
    }


def test_multi_offset_template_fills_every_november_2_through_6_date():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Aina Bejer")
        ben = world.add_employee("Ali Cornal")
        world.assign(ana, date(2026, 10, 27), world.morning, is_rest_day_work=True)
        world.assign(ben, date(2026, 10, 27), world.afternoon, is_rest_day_work=True)
        world.assign(ana, date(2026, 10, 29), world.afternoon)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Regular Week",
            date(2026, 10, 26),
            world.owner.id,
        )
        saved = (
            world.db.query(ScheduleTemplateEntry)
            .filter(ScheduleTemplateEntry.template_id == template.id)
            .all()
        )
        assert {entry.day_offset for entry in saved} == {1, 3}
        assert all(entry.is_rest_day_work is False for entry in saved)

        start = date(2026, 11, 2)
        end = date(2026, 11, 6)
        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            start,
            template_id=template.id,
            start_date=start,
            end_date=end,
        )
        preview_dates = {item.work_date for item in preview.items}
        assert preview_dates == {
            date(2026, 11, 2),
            date(2026, 11, 3),
            date(2026, 11, 4),
            date(2026, 11, 5),
            date(2026, 11, 6),
        }
        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            start,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=start,
            end_date=end,
        )
        assert result.created == 15
        assert result.target_week_start == preview.target_week_start
        assert result.target_week_end == preview.target_week_end
        weekly = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": start.isoformat()},
            headers=_headers(world.owner),
        )
        assert weekly.status_code == 200, weekly.text
        by_date: dict[str, set[str]] = {}
        for row in weekly.json()["assignments"]:
            by_date.setdefault(row["work_date"], set()).add(row["employee_name"])
            assert row["is_rest_day_work"] is False
        expected = {"Aina Bejer", "Ali Cornal"}
        for day in (
            date(2026, 11, 2),
            date(2026, 11, 3),
            date(2026, 11, 4),
            date(2026, 11, 5),
            date(2026, 11, 6),
        ):
            assert by_date[day.isoformat()] == expected

        owner_premium = client.post(
            "/api/v1/schedules/assign",
            json={
                "shift_id": str(world.morning.id),
                "work_date": "2026-11-07",
                "employee_ids": [str(ana.id)],
                "is_rest_day_work": True,
            },
            headers=_headers(world.owner),
        )
        assert owner_premium.status_code == 201, owner_premium.text
        world.db.expire_all()
        created = (
            world.db.query(ShiftAssignment)
            .filter(
                ShiftAssignment.employee_id == ana.id,
                ShiftAssignment.work_date == date(2026, 11, 7),
            )
            .one()
        )
        assert created.is_rest_day_work is True
    finally:
        world.close()


def test_template_save_and_apply_do_not_lock_rest_day_premium():
    world = LibraryWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        world.assign(ana, SOURCE_MONDAY, world.morning, is_rest_day_work=True)
        template = create_template_from_week(
            world.db,
            world.business.id,
            "Premium source week",
            SOURCE_MONDAY,
            world.owner.id,
        )
        saved = (
            world.db.query(ScheduleTemplateEntry)
            .filter(ScheduleTemplateEntry.template_id == template.id)
            .all()
        )
        assert saved
        assert all(entry.is_rest_day_work is False for entry in saved)

        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.template,
            TARGET_MONDAY,
            ScheduleConflictMode.merge,
            template_id=template.id,
            start_date=TARGET_MONDAY,
            end_date=TARGET_MONDAY,
        )
        assert result.created == 1
        copied = world.week_assignments(TARGET_MONDAY)
        assert copied
        assert all(row.is_rest_day_work is False for row in copied)
    finally:
        world.close()


def test_assignment_update_changes_only_that_employee_rest_day():
    world = LibraryWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Aina Bejer")
        ali = world.add_employee("Ali Cornal")
        first = world.assign(ana, TARGET_MONDAY, world.morning)
        second = world.assign(ali, TARGET_MONDAY, world.morning)
        updated = client.put(
            f"/api/v1/schedules/assignments/{first.id}",
            json={
                "shift_id": str(world.morning.id),
                "work_date": TARGET_MONDAY.isoformat(),
                "is_rest_day_work": True,
            },
            headers=_headers(world.owner),
        )
        assert updated.status_code == 200, updated.text
        assert updated.json()["is_rest_day_work"] is True
        world.db.expire_all()
        assert world.db.get(ShiftAssignment, first.id).is_rest_day_work is True
        assert world.db.get(ShiftAssignment, second.id).is_rest_day_work is False

        cleared = client.put(
            f"/api/v1/schedules/assignments/{first.id}",
            json={
                "shift_id": str(world.morning.id),
                "work_date": TARGET_MONDAY.isoformat(),
                "is_rest_day_work": False,
            },
            headers=_headers(world.owner),
        )
        assert cleared.status_code == 200, cleared.text
        world.db.expire_all()
        assert world.db.get(ShiftAssignment, first.id).is_rest_day_work is False
        assert world.db.get(ShiftAssignment, second.id).is_rest_day_work is False
    finally:
        world.close()
