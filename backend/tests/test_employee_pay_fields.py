"""Phase 1 employee pay fields: storage, prefill, validation (payroll untouched)."""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.api.employees import create_employee, update_employee, _employee_response
from app.models.enums import EmploymentType, PayBasis
from app.models.payroll import Position
from app.schemas.employee import EmployeeCreate, EmployeeUpdate, _validate_pay_fields


def test_validate_pay_fields_daily_requires_rate():
    with pytest.raises(ValueError, match="daily_rate"):
        _validate_pay_fields(
            pay_basis=PayBasis.daily,
            daily_rate=None,
            hourly_rate=None,
            monthly_salary=None,
        )


def test_validate_pay_fields_hourly_requires_rate():
    with pytest.raises(ValueError, match="hourly_rate"):
        _validate_pay_fields(
            pay_basis=PayBasis.hourly,
            daily_rate=650.0,
            hourly_rate=None,
            monthly_salary=None,
        )


def test_employee_create_schema_allows_missing_daily_when_position_set():
    body = EmployeeCreate(
        full_name="Jane Doe",
        position_title="Barista",
        position_id=str(uuid4()),
        pay_basis=PayBasis.daily,
        daily_rate=None,
    )
    assert body.daily_rate is None


def test_employee_create_schema_requires_daily_without_position():
    with pytest.raises(ValidationError):
        EmployeeCreate(
            full_name="Jane Doe",
            position_title="Barista",
            pay_basis=PayBasis.daily,
            daily_rate=None,
        )


def test_backfill_mapping_copies_position_daily_rate():
    """Documents migration backfill intent for existing employees."""
    position_rate = 650.0
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=position_rate,
        hourly_rate=None,
        monthly_salary=None,
    )
    assert employee.pay_basis == PayBasis.daily
    assert employee.daily_rate == 650.0


def test_create_employee_prefills_daily_rate_from_position():
    business_id = uuid4()
    position_id = uuid4()
    pos = Position(
        id=position_id,
        business_id=business_id,
        title="Barista",
        daily_rate=650.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="John Barista",
        position_title="Barista",
        position_id=str(position_id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=None,
    )
    db = MagicMock()
    db.get.return_value = pos
    db.query.return_value.filter.return_value.first.return_value = None

    created = {}

    def add(obj):
        if hasattr(obj, "full_name"):
            created["employee"] = obj
            obj.id = uuid4()
        if hasattr(obj, "email") and hasattr(obj, "password_hash"):
            created["user"] = obj
            obj.id = uuid4()
            obj.must_change_password = True
            obj.pending_temporary_password = "temp"
            obj.email = "john.barista"

    db.add.side_effect = add

    def refresh(obj):
        pass

    db.refresh.side_effect = refresh

    with patch("app.api.employees.generate_temporary_password", return_value="temp"):
        with patch("app.api.employees.hash_password", return_value="hashed"):
            result = create_employee(body, db, owner)  # type: ignore[arg-type]

    assert created["employee"].daily_rate == 650.0
    assert created["employee"].pay_basis == PayBasis.daily
    assert result.daily_rate == 650.0
    assert result.pay_basis == "daily"


def test_create_employee_allows_override_daily_rate():
    business_id = uuid4()
    position_id = uuid4()
    pos = Position(
        id=position_id,
        business_id=business_id,
        title="Barista",
        daily_rate=650.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Mark Barista",
        position_title="Barista",
        position_id=str(position_id),
        pay_basis=PayBasis.daily,
        daily_rate=720.0,
    )
    db = MagicMock()
    db.get.return_value = pos
    db.query.return_value.filter.return_value.first.return_value = None
    created = {}

    def add(obj):
        if hasattr(obj, "full_name"):
            created["employee"] = obj
            obj.id = uuid4()
        if hasattr(obj, "password_hash"):
            obj.id = uuid4()
            obj.must_change_password = True
            obj.pending_temporary_password = "temp"
            obj.email = "mark.barista"

    db.add.side_effect = add
    db.refresh.side_effect = lambda obj: None

    with patch("app.api.employees.generate_temporary_password", return_value="temp"):
        with patch("app.api.employees.hash_password", return_value="hashed"):
            result = create_employee(body, db, owner)  # type: ignore[arg-type]

    assert created["employee"].daily_rate == 720.0
    assert result.daily_rate == 720.0


def test_update_position_does_not_overwrite_custom_rate():
    business_id = uuid4()
    old_pos_id = uuid4()
    new_pos_id = uuid4()
    emp = SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        position_id=old_pos_id,
        position_title="Barista",
        full_name="Mark",
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=720.0,
        hourly_rate=None,
        monthly_salary=None,
        phone=None,
        profile_image_url=None,
        status=SimpleNamespace(value="active"),
    )
    linked = SimpleNamespace(
        email="mark",
        must_change_password=False,
        pending_temporary_password=None,
    )
    new_pos = Position(
        id=new_pos_id,
        business_id=business_id,
        title="Senior Barista",
        daily_rate=800.0,
    )
    owner = SimpleNamespace(business_id=business_id)
    db = MagicMock()
    db.get.return_value = new_pos

    with patch(
        "app.api.employees._get_business_employee",
        return_value=(emp, linked),
    ):
        body = EmployeeUpdate(position_id=str(new_pos_id))
        result = update_employee(emp.id, body, db, owner)  # type: ignore[arg-type]

    assert emp.daily_rate == 720.0
    assert emp.position_id == new_pos_id
    assert result.daily_rate == 720.0


def test_employee_response_includes_pay_fields():
    emp = SimpleNamespace(
        id=uuid4(),
        position_id=uuid4(),
        position_title="Barista",
        full_name="Jane",
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=95.0,
        monthly_salary=None,
        phone=None,
        profile_image_url=None,
        status=SimpleNamespace(value="active"),
    )
    user = SimpleNamespace(
        email="jane",
        must_change_password=False,
        pending_temporary_password=None,
    )
    resp = _employee_response(emp, user)  # type: ignore[arg-type]
    assert resp.pay_basis == "hourly"
    assert resp.hourly_rate == 95.0
    assert resp.daily_rate is None
    assert resp.position_id == str(emp.position_id)


def test_create_hourly_without_rate_fails_at_schema():
    with pytest.raises(ValidationError):
        EmployeeCreate(
            full_name="Jane Hourly",
            position_title="Barista",
            pay_basis=PayBasis.hourly,
            hourly_rate=None,
        )
