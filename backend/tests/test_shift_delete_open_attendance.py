"""Shift deletion is blocked only while an assigned employee is still timed in."""

from datetime import date, datetime, time, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.api.shifts import delete_shift, update_shift
from app.models.enums import ShiftType
from app.models.scheduling import Shift
from app.schemas.owner_setup import ShiftUpdate
from app.services.shift_versioning import (
    SHIFT_DELETE_BLOCKED_MESSAGE,
    ShiftDeleteBlockedError,
    apply_shift_updates,
    open_attendance_query,
)

ROOT = Path(__file__).resolve().parents[2]


def _shift(**overrides):
    base = dict(
        id=uuid4(),
        business_id=uuid4(),
        name="Morning",
        shift_type=ShiftType.morning,
        start_time=time(8, 0),
        end_time=time(17, 0),
        break_minutes=60,
        employee_capacity=6,
        color=None,
        is_active=True,
    )
    base.update(overrides)
    return Shift(**base)


class _Query:
    def __init__(self, row):
        self._row = row

    def join(self, *args, **kwargs):
        return self

    def filter(self, *args, **kwargs):
        return self

    def first(self):
        return self._row


class _Db:
    def __init__(self, shift, row):
        self.shift = shift
        self.row = row
        self.committed = False
        self.deleted = []

    def get(self, model, key):
        return self.shift if model is Shift else None

    def query(self, *args, **kwargs):
        return _Query(self.row)

    def commit(self):
        self.committed = True

    def delete(self, obj):
        self.deleted.append(obj)


def _owner(business_id):
    return SimpleNamespace(business_id=business_id, role="owner")


def _compiled_sql(*, shift_id=None) -> str:
    engine = create_engine("sqlite://")
    with Session(engine) as db:
        query = open_attendance_query(
            db, business_id=uuid4(), shift_id=shift_id or uuid4()
        )
        return str(query.statement.compile(compile_kwargs={"literal_binds": False}))


def test_open_attendance_query_matches_only_an_unfinished_punch():
    sql = _compiled_sql().lower()
    assert "time_in is not null" in sql
    assert "time_out is null" in sql
    assert "attendance_record.business_id" in sql
    assert "shift.business_id" in sql
    assert "attendance_record.employee_id" in sql
    assert "shift_assignment.employee_id" in sql
    assert "shift.id" in sql
    # Completed punches have time_out set, so they cannot match.
    assert "time_out is not null" not in sql
    # An older open session is still open. Do not limit this to today.
    assert "work_date" not in sql


def test_delete_is_rejected_while_an_assigned_employee_is_timed_in():
    shift = _shift()
    attendance = SimpleNamespace(
        id=uuid4(),
        time_in=datetime(2026, 10, 25, 1, 0, tzinfo=timezone.utc),
        time_out=None,
        status="in_progress",
    )
    db = _Db(shift, row=(attendance.id,))

    with pytest.raises(HTTPException) as exc:
        delete_shift(shift.id, db, _owner(shift.business_id))

    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "shift_delete_blocked"
    assert exc.value.detail["message"] == SHIFT_DELETE_BLOCKED_MESSAGE
    assert shift.is_active is True
    assert shift.name == "Morning"
    assert shift.start_time == time(8, 0)
    assert shift.end_time == time(17, 0)
    assert db.committed is False
    assert db.deleted == []
    assert attendance.time_in is not None
    assert attendance.time_out is None
    assert attendance.status == "in_progress"


def test_delete_succeeds_when_nobody_is_timed_in():
    shift = _shift()
    db = _Db(shift, row=None)

    result = delete_shift(shift.id, db, _owner(shift.business_id))

    assert result == {"status": "ok"}
    assert shift.is_active is False
    assert db.committed is True
    assert db.deleted == []


def test_deactivating_update_uses_the_same_guard_and_does_not_partially_change():
    shift = _shift()
    db = _Db(shift, row=(uuid4(),))

    with pytest.raises(ShiftDeleteBlockedError):
        apply_shift_updates(
            db,
            shift,
            {"is_active": False, "name": "Removed"},
            today=date(2026, 10, 25),
        )

    assert shift.is_active is True
    assert shift.name == "Morning"
    assert db.committed is False
    assert db.deleted == []


def test_direct_put_cannot_deactivate_a_shift_with_an_open_session():
    shift = _shift()
    user = _owner(shift.business_id)
    db = _Db(shift, row=(uuid4(),))
    db.get = lambda model, key: (
        shift if model is Shift else SimpleNamespace(timezone="Asia/Manila")
    )

    with pytest.raises(HTTPException) as exc:
        update_shift(shift.id, ShiftUpdate(is_active=False), db, user)

    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "shift_delete_blocked"
    assert shift.is_active is True
    assert db.committed is False


def test_setup_wizard_and_mobile_share_the_protected_delete_endpoint():
    api = (ROOT / "admin-web/src/lib/api.ts").read_text(encoding="utf-8")
    wizard = (
        ROOT / "admin-web/src/pages/owner/setup/OwnerSetupWizardPage.tsx"
    ).read_text(encoding="utf-8")
    schedule = (ROOT / "admin-web/src/pages/owner/OwnerSchedulePage.tsx").read_text(
        encoding="utf-8"
    )
    mobile_repo = (
        ROOT / "mobile/lib/data/repositories/owner_repository.dart"
    ).read_text(encoding="utf-8")
    mobile_wizard = (
        ROOT / "mobile/lib/presentation/owner/setup/owner_setup_wizard_screen.dart"
    ).read_text(encoding="utf-8")
    mobile_schedule = (
        ROOT / "mobile/lib/presentation/owner/owner_set_schedule_screen.dart"
    ).read_text(encoding="utf-8")
    endpoint = (ROOT / "backend/app/api/shifts.py").read_text(encoding="utf-8")

    assert 'api.delete(`/shifts/${id}`)' in api
    assert "deleteShift(" in wizard
    assert "deleteShift(" not in schedule
    assert "dio.delete" in mobile_repo and "/shifts/$shiftId" in mobile_repo
    assert "deleteShift(" in mobile_wizard
    assert "deleteShift(" not in mobile_schedule
    assert endpoint.count("def delete_shift") == 1
    assert "ensure_shift_deletable" in endpoint
