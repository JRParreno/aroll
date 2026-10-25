"""New assignments cannot target a shift whose scheduled end has passed.

Historical rows, attendance, rest-day edits, leave conflicts, and overlap
checks stay in place. The clock is injected so the cases do not depend on
the machine date.
"""

import uuid
from datetime import date, datetime, time, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import AttendanceStatus, EmployeeStatus, EmploymentType, UserRole
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.schemas.schedule_reuse import ScheduleConflictMode, ScheduleReuseSource
from app.services.schedule_overlap import (
    PAST_SHIFT_ASSIGNMENT_MESSAGE,
    shift_has_ended,
)
from app.services.schedule_reuse import apply_reuse


def _headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _shift(start: time, end: time) -> SimpleNamespace:
    return SimpleNamespace(start_time=start, end_time=end)


class ScheduleWorld:
    def __init__(self) -> None:
        self.db = SessionLocal()
        self.business = Business(
            business_code=f"PS-{uuid.uuid4().hex[:6].upper()}",
            name="Past Shift Biz",
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
        self.morning = self._add_shift("Morning", time(8, 0), time(12, 0))
        self.afternoon = self._add_shift("Afternoon", time(13, 0), time(17, 0))
        self.db.commit()

    def close(self) -> None:
        self.db.close()

    def _add_shift(self, name: str, start: time, end: time) -> Shift:
        shift = Shift(
            business_id=self.business.id,
            name=name,
            start_time=start,
            end_time=end,
            employee_capacity=8,
        )
        self.db.add(shift)
        self.db.flush()
        return shift

    def add_employee(self, name: str) -> Employee:
        user = User(
            business_id=self.business.id,
            email=f"{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("EmpPass123!"),
            role=UserRole.employee,
            must_change_password=False,
            is_active=True,
        )
        self.db.add(user)
        self.db.flush()
        employee = Employee(
            business_id=self.business.id,
            user_id=user.id,
            full_name=name,
            employment_type=EmploymentType.full_time,
            status=EmployeeStatus.active,
            is_active=True,
            face_registration_status="completed",
        )
        self.db.add(employee)
        self.db.flush()
        return employee

    def assignment_count(self) -> int:
        return (
            self.db.query(ShiftAssignment)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(Shift.business_id == self.business.id)
            .count()
        )


def _freeze(monkeypatch, moment: datetime) -> None:
    monkeypatch.setattr(
        "app.services.schedule_overlap.business_now",
        lambda tz_name: moment,
    )


def _assign(client: TestClient, world: ScheduleWorld, work_date: date, shift: Shift, *employees: Employee):
    return client.post(
        "/api/v1/schedules/assign",
        json={
            "shift_id": str(shift.id),
            "work_date": work_date.isoformat(),
            "employee_ids": [str(employee.id) for employee in employees],
        },
        headers=_headers(world.owner),
    )


def test_shift_ended_yesterday_is_rejected():
    now = datetime(2026, 10, 21, 9, 0)
    assert shift_has_ended(
        date(2026, 10, 20),
        _shift(time(8, 0), time(12, 0)),
        tz_name="Asia/Manila",
        now=now,
    )


def test_shift_ended_earlier_today_is_rejected():
    now = datetime(2026, 10, 21, 14, 0)
    assert shift_has_ended(
        date(2026, 10, 21),
        _shift(time(8, 0), time(12, 0)),
        tz_name="Asia/Manila",
        now=now,
    )


def test_future_shift_is_assignable():
    now = datetime(2026, 10, 21, 14, 0)
    assert not shift_has_ended(
        date(2026, 10, 22),
        _shift(time(8, 0), time(12, 0)),
        tz_name="Asia/Manila",
        now=now,
    )


def test_ongoing_shift_is_assignable_until_the_scheduled_end():
    now = datetime(2026, 10, 21, 10, 0)
    assert not shift_has_ended(
        date(2026, 10, 21),
        _shift(time(8, 0), time(12, 0)),
        tz_name="Asia/Manila",
        now=now,
    )
    assert shift_has_ended(
        date(2026, 10, 21),
        _shift(time(8, 0), time(12, 0)),
        tz_name="Asia/Manila",
        now=datetime(2026, 10, 21, 12, 0),
    )


def test_shift_that_starts_later_today_is_assignable():
    now = datetime(2026, 10, 21, 10, 0)
    assert not shift_has_ended(
        date(2026, 10, 21),
        _shift(time(13, 0), time(17, 0)),
        tz_name="Asia/Manila",
        now=now,
    )


def test_overnight_shift_uses_the_next_morning_end():
    shift = _shift(time(22, 0), time(6, 0))
    assert not shift_has_ended(
        date(2026, 10, 21),
        shift,
        tz_name="Asia/Manila",
        now=datetime(2026, 10, 22, 5, 0),
    )
    assert shift_has_ended(
        date(2026, 10, 21),
        shift,
        tz_name="Asia/Manila",
        now=datetime(2026, 10, 22, 6, 0),
    )


def test_business_timezone_date_boundary_is_not_a_utc_date_check():
    """14:00 in Manila is still 23:00 the previous evening in Los Angeles."""
    now = datetime(2026, 10, 22, 6, 0, tzinfo=timezone.utc)
    late_evening = _shift(time(22, 0), time(23, 30))
    assert not shift_has_ended(
        date(2026, 10, 21),
        late_evening,
        tz_name="America/Los_Angeles",
        now=now,
    )
    assert shift_has_ended(
        date(2026, 10, 21),
        _shift(time(8, 0), time(12, 0)),
        tz_name="Asia/Manila",
        now=now,
    )
    before_midnight = datetime(2026, 10, 21, 15, 50, tzinfo=timezone.utc)
    at_end = datetime(2026, 10, 21, 16, 30, tzinfo=timezone.utc)
    early = _shift(time(0, 0), time(0, 30))
    assert not shift_has_ended(
        date(2026, 10, 22), early, tz_name="Asia/Manila", now=before_midnight
    )
    assert shift_has_ended(
        date(2026, 10, 22), early, tz_name="Asia/Manila", now=at_end
    )


def test_api_rejects_yesterday_and_saves_nobody(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 9, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Cruz")
        world.db.commit()
        response = _assign(client, world, date(2026, 10, 20), world.morning, ana, ben)
        assert response.status_code == 400
        assert response.json()["detail"] == PAST_SHIFT_ASSIGNMENT_MESSAGE
        world.db.expire_all()
        assert world.assignment_count() == 0
    finally:
        world.close()


def test_api_rejects_shift_that_ended_earlier_today(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 14, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        world.db.commit()
        response = _assign(client, world, date(2026, 10, 21), world.morning, ana)
        assert response.status_code == 400
        assert response.json()["detail"] == PAST_SHIFT_ASSIGNMENT_MESSAGE
        world.db.expire_all()
        assert world.assignment_count() == 0
    finally:
        world.close()


def test_api_allows_future_ongoing_and_later_today(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 10, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        world.db.commit()
        future = _assign(client, world, date(2026, 10, 22), world.morning, ana)
        ongoing = _assign(client, world, date(2026, 10, 21), world.morning, ana)
        later = _assign(client, world, date(2026, 10, 21), world.afternoon, ana)
        assert future.status_code == 201, future.text
        assert ongoing.status_code == 201, ongoing.text
        assert later.status_code == 201, later.text
        assert future.json()["created"] == 1
        assert ongoing.json()["created"] == 1
        assert later.json()["created"] == 1
    finally:
        world.close()


def test_api_direct_call_cannot_bypass_the_past_shift_rule(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 14, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        world.db.commit()
        response = client.post(
            "/api/v1/schedules/assign",
            json={
                "shift_id": str(world.morning.id),
                "work_date": "2026-10-20",
                "employee_ids": [str(ana.id)],
            },
            headers=_headers(world.owner),
        )
        assert response.status_code == 400
        assert response.json()["detail"] == PAST_SHIFT_ASSIGNMENT_MESSAGE
    finally:
        world.close()


def test_api_uses_the_business_timezone(monkeypatch):
    monkeypatch.setattr(
        "app.services.schedule_overlap.business_now",
        lambda tz_name: datetime(2026, 10, 22, 6, 0, tzinfo=timezone.utc),
    )
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        late = world._add_shift("Late", time(22, 0), time(23, 30))
        world.business.timezone = "America/Los_Angeles"
        world.db.commit()
        allowed = _assign(client, world, date(2026, 10, 21), late, ana)
        assert allowed.status_code == 201, allowed.text

        world.business.timezone = "Asia/Manila"
        world.db.commit()
        rejected = _assign(client, world, date(2026, 10, 21), world.morning, ana)
        assert rejected.status_code == 400
        assert rejected.json()["detail"] == PAST_SHIFT_ASSIGNMENT_MESSAGE
        world.db.expire_all()
        assert world.assignment_count() == 1
    finally:
        world.close()


def test_ongoing_shift_still_rejects_a_schedule_conflict(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 10, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        ben = world.add_employee("Ben Cruz")
        overlap = world._add_shift("Overlap", time(9, 0), time(11, 0))
        world.db.add(
            ShiftAssignment(
                shift_id=world.morning.id,
                employee_id=ana.id,
                work_date=date(2026, 10, 21),
            )
        )
        world.db.commit()
        conflict = _assign(client, world, date(2026, 10, 21), overlap, ana)
        assert conflict.status_code == 400
        assert "conflicts" in conflict.json()["detail"]
        allowed = _assign(client, world, date(2026, 10, 21), world.morning, ben)
        assert allowed.status_code == 201, allowed.text
    finally:
        world.close()


def test_employee_cannot_assign_and_missing_auth_stays_unauthorized(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 22, 8, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        world.db.commit()
        employee_user = world.db.get(User, ana.user_id)
        forbidden = client.post(
            "/api/v1/schedules/assign",
            json={
                "shift_id": str(world.morning.id),
                "work_date": "2026-10-22",
                "employee_ids": [str(ana.id)],
            },
            headers=_headers(employee_user),
        )
        missing = client.post(
            "/api/v1/schedules/assign",
            json={
                "shift_id": str(world.morning.id),
                "work_date": "2026-10-22",
                "employee_ids": [str(ana.id)],
            },
        )
        assert forbidden.status_code == 403
        assert missing.status_code == 401
        world.db.expire_all()
        assert world.assignment_count() == 0
    finally:
        world.close()


def test_historical_schedule_and_attendance_stay_readable(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 14, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        assignment = ShiftAssignment(
            shift_id=world.morning.id,
            employee_id=ana.id,
            work_date=date(2026, 10, 20),
        )
        world.db.add(assignment)
        world.db.flush()
        record = AttendanceRecord(
            business_id=world.business.id,
            employee_id=ana.id,
            shift_assignment_id=assignment.id,
            status=AttendanceStatus.complete,
            time_in=datetime(2026, 10, 20, 0, 0, tzinfo=timezone.utc),
            time_out=datetime(2026, 10, 20, 4, 0, tzinfo=timezone.utc),
        )
        world.db.add(record)
        world.db.commit()

        weekly = client.get(
            "/api/v1/schedules/weekly",
            params={"week_start": "2026-10-19"},
            headers=_headers(world.owner),
        )
        assert weekly.status_code == 200, weekly.text
        names = {row["employee_name"] for row in weekly.json()["assignments"]}
        assert names == {"Ana Cruz"}

        rejected = _assign(client, world, date(2026, 10, 20), world.morning, ana)
        assert rejected.status_code == 400
        world.db.expire_all()
        saved = world.db.get(AttendanceRecord, record.id)
        assert saved is not None
        assert saved.status == AttendanceStatus.complete
        assert saved.time_in is not None
        assert world.assignment_count() == 1
    finally:
        world.close()


def test_rest_day_edit_on_an_ended_assignment_is_still_allowed(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 14, 0))
    world = ScheduleWorld()
    client = TestClient(app)
    try:
        ana = world.add_employee("Ana Cruz")
        assignment = ShiftAssignment(
            shift_id=world.morning.id,
            employee_id=ana.id,
            work_date=date(2026, 10, 20),
            is_rest_day_work=False,
        )
        world.db.add(assignment)
        world.db.commit()
        updated = client.put(
            f"/api/v1/schedules/assignments/{assignment.id}",
            json={
                "shift_id": str(world.morning.id),
                "work_date": "2026-10-20",
                "is_rest_day_work": True,
            },
            headers=_headers(world.owner),
        )
        assert updated.status_code == 200, updated.text
        assert updated.json()["is_rest_day_work"] is True

        moved = client.put(
            f"/api/v1/schedules/assignments/{assignment.id}",
            json={
                "shift_id": str(world.morning.id),
                "work_date": "2026-10-19",
                "is_rest_day_work": True,
            },
            headers=_headers(world.owner),
        )
        assert moved.status_code == 400
        assert moved.json()["detail"] == PAST_SHIFT_ASSIGNMENT_MESSAGE
        world.db.expire_all()
        saved = world.db.get(ShiftAssignment, assignment.id)
        assert saved.work_date == date(2026, 10, 20)
    finally:
        world.close()


def test_reuse_of_a_mixed_range_commits_nothing(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 15, 0))
    world = ScheduleWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        world.db.add(
            ShiftAssignment(
                shift_id=world.morning.id,
                employee_id=ana.id,
                work_date=date(2026, 10, 12),
            )
        )
        world.db.add(
            ShiftAssignment(
                shift_id=world.morning.id,
                employee_id=ana.id,
                work_date=date(2026, 10, 16),
            )
        )
        world.db.commit()
        with pytest.raises(HTTPException) as exc:
            apply_reuse(
                world.db,
                world.business.id,
                ScheduleReuseSource.previous_week,
                date(2026, 10, 19),
                ScheduleConflictMode.merge,
            )
        assert exc.value.status_code == 400
        assert exc.value.detail == PAST_SHIFT_ASSIGNMENT_MESSAGE
        world.db.expire_all()
        copied = (
            world.db.query(ShiftAssignment)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(
                Shift.business_id == world.business.id,
                ShiftAssignment.work_date >= date(2026, 10, 19),
            )
            .count()
        )
        assert copied == 0
        assert world.assignment_count() == 2
    finally:
        world.close()


def test_reuse_replace_does_not_delete_an_ended_assignment(monkeypatch):
    _freeze(monkeypatch, datetime(2026, 10, 21, 15, 0))
    world = ScheduleWorld()
    try:
        ana = world.add_employee("Ana Cruz")
        past = ShiftAssignment(
            shift_id=world.morning.id,
            employee_id=ana.id,
            work_date=date(2026, 10, 20),
        )
        world.db.add(past)
        world.db.add(
            ShiftAssignment(
                shift_id=world.morning.id,
                employee_id=ana.id,
                work_date=date(2026, 10, 16),
            )
        )
        world.db.commit()
        with pytest.raises(HTTPException) as exc:
            apply_reuse(
                world.db,
                world.business.id,
                ScheduleReuseSource.previous_week,
                date(2026, 10, 19),
                ScheduleConflictMode.replace,
            )
        assert exc.value.status_code == 400
        world.db.expire_all()
        saved = world.db.get(ShiftAssignment, past.id)
        assert saved is not None
        assert saved.work_date == date(2026, 10, 20)
        future_copies = (
            world.db.query(ShiftAssignment)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(
                Shift.business_id == world.business.id,
                ShiftAssignment.work_date == date(2026, 10, 23),
            )
            .count()
        )
        assert future_copies == 0
    finally:
        world.close()
