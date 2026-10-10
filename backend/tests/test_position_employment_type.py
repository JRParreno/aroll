"""Position employment_type / pay_basis templates and employee create wiring."""

from __future__ import annotations

import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from app.api import employees as employees_api
from app.api import positions as positions_api
from app.models.enums import EmploymentType, PayBasis, UserRole
from app.models.payroll import Position
from app.schemas.employee import EmployeeCreate
from app.schemas.owner_setup import PositionCreate, _validate_position_rates


def test_position_rates_daily_requires_daily_amount():
    with pytest.raises(ValueError, match="daily_rate"):
        _validate_position_rates(
            pay_basis=PayBasis.daily, daily_rate=None, hourly_rate=80.0
        )


def test_position_rates_hourly_requires_hourly_amount():
    with pytest.raises(ValueError, match="hourly_rate"):
        _validate_position_rates(
            pay_basis=PayBasis.hourly, daily_rate=650.0, hourly_rate=None
        )


def test_position_create_schema_rejects_monthly_basis():
    with pytest.raises(ValueError, match="daily or hourly"):
        PositionCreate(
            title="Cashier",
            employment_type=EmploymentType.full_time,
            pay_basis=PayBasis.monthly,
            daily_rate=650,
        )


def test_position_create_schema_hourly_ok_without_daily():
    body = PositionCreate(
        title="Cashier",
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=80,
    )
    assert body.daily_rate is None
    assert body.hourly_rate == 80


def test_list_positions_filter_excludes_null_by_querying_classified_only():
    business_id = uuid.uuid4()
    user = SimpleNamespace(business_id=business_id, role=UserRole.owner)

    classified = SimpleNamespace(
        id=uuid.uuid4(),
        title="Cashier",
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=650.0,
        hourly_rate=None,
        description=None,
        is_active=True,
        business_id=business_id,
    )

    db = MagicMock()
    query = MagicMock()
    db.query.return_value = query
    query.options.return_value = query
    query.filter.return_value = query
    query.order_by.return_value = query
    query.all.return_value = [classified]

    result = positions_api.list_positions(
        db=db, user=user, employment_type=EmploymentType.full_time
    )
    assert len(result) == 1
    assert result[0].employment_type == EmploymentType.full_time
    assert query.filter.call_count >= 2


def test_create_employee_rejects_mismatched_employment_type(monkeypatch):
    business_id = uuid.uuid4()
    pos_id = uuid.uuid4()
    user = SimpleNamespace(business_id=business_id, role=UserRole.owner)
    pos = Position(
        id=pos_id,
        business_id=business_id,
        title="Cashier",
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=650.0,
        hourly_rate=None,
    )

    monkeypatch.setattr(
        employees_api,
        "_generate_employee_username",
        lambda *_a, **_k: "cashier01",
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )

    body = EmployeeCreate(
        full_name="Ana Cruz",
        position_title="Cashier",
        position_id=str(pos_id),
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.daily,
        daily_rate=650,
    )
    with pytest.raises(HTTPException) as exc:
        employees_api.create_employee(body=body, db=MagicMock(), user=user)
    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "employment_type_mismatch"


def test_employee_create_allows_omitting_hourly_when_position_id_set():
    """Schema allows omitting hourly_rate when position_id is provided."""
    body = EmployeeCreate(
        full_name="Ben Lee",
        position_title="Cashier",
        position_id=str(uuid.uuid4()),
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=None,
    )
    assert body.position_id is not None
    assert body.hourly_rate is None
