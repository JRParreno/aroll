"""Schedule assignment requires a fully activated employee account."""

from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.services.employee_activation import (
    is_employee_fully_activated,
    raise_if_not_activated_for_schedule,
)


def _employee(*, name="Alex", face_status="completed"):
    return SimpleNamespace(
        id=uuid4(),
        full_name=name,
        face_registration_status=face_status,
        user_id=uuid4(),
    )


def _user(*, must_change_password=False):
    return SimpleNamespace(must_change_password=must_change_password)


def test_activated_employee_is_eligible():
    assert is_employee_fully_activated(
        _employee(face_status="completed"),
        _user(must_change_password=False),
    )


def test_pending_password_change_is_not_activated():
    assert not is_employee_fully_activated(
        _employee(face_status="completed"),
        _user(must_change_password=True),
    )


def test_missing_face_registration_is_not_activated():
    assert not is_employee_fully_activated(
        _employee(face_status="not_registered"),
        _user(must_change_password=False),
    )


def test_missing_user_is_not_activated():
    assert not is_employee_fully_activated(_employee(), None)


def test_raise_if_not_activated_blocks_unready_employees():
    employee = _employee(name="Pending Crew", face_status="not_registered")
    user = _user(must_change_password=False)
    with pytest.raises(HTTPException) as error:
        raise_if_not_activated_for_schedule([(employee, user)])
    assert error.value.status_code == 400
    assert "fully activated" in error.value.detail
    assert "Pending Crew" in error.value.detail


def test_raise_if_not_activated_allows_ready_employees():
    employee = _employee(face_status="completed")
    user = _user(must_change_password=False)
    raise_if_not_activated_for_schedule([(employee, user)])
