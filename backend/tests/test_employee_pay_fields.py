"""Employee pay fields + Design B authoritative PositionPayConfig resolution."""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.employees import create_employee, update_employee, _employee_response
from app.models.enums import EmploymentType, PayBasis
from app.models.payroll import Position, PositionPayConfig
from app.schemas.employee import EmployeeCreate, EmployeeUpdate, _validate_pay_fields


def _mock_db_with_position(pos: Position) -> MagicMock:
    db = MagicMock()
    query = MagicMock()
    db.query.return_value = query
    query.options.return_value = query
    query.filter.return_value = query
    query.order_by.return_value = query

    def _first(*_a, **_k):
        # Position lookups return the stub; username uniqueness checks return None.
        # Heuristic: joinedload path for Position uses .options(...).
        return pos

    # Username generation uses db.query(User).filter(...).first() without options.
    # Position load uses .options(joinedload).filter.first().
    # Make optionsless first() return None (available username), options path return pos.
    bare_query = MagicMock()
    options_query = MagicMock()

    def query_side_effect(*_a, **_k):
        return bare_query

    db.query.side_effect = query_side_effect
    bare_query.filter.return_value = bare_query
    bare_query.first.return_value = None  # username available / no user clash
    bare_query.options.return_value = options_query
    options_query.filter.return_value = options_query
    options_query.first.return_value = pos

    db.get.return_value = pos
    db.refresh.side_effect = lambda obj: None
    return db


def _position(
    *,
    business_id,
    position_id=None,
    title="Barista",
    employment_type=EmploymentType.full_time,
    daily_rate=None,
    hourly_rate=None,
    is_active=True,
) -> Position:
    pid = position_id or uuid4()
    configs = []
    if daily_rate is not None:
        configs.append(
            PositionPayConfig(
                id=uuid4(),
                position_id=pid,
                pay_basis=PayBasis.daily,
                rate=daily_rate,
            )
        )
    if hourly_rate is not None:
        configs.append(
            PositionPayConfig(
                id=uuid4(),
                position_id=pid,
                pay_basis=PayBasis.hourly,
                rate=hourly_rate,
            )
        )
    pos = Position(
        id=pid,
        business_id=business_id,
        title=title,
        employment_type=employment_type,
        pay_basis=(
            PayBasis.hourly
            if hourly_rate is not None and daily_rate is None
            else PayBasis.daily
        ),
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
        is_active=is_active,
    )
    pos.pay_configs = configs
    return pos


def _capture_add(db: MagicMock) -> dict:
    created: dict = {}

    def add(obj):
        if hasattr(obj, "full_name"):
            created["employee"] = obj
            obj.id = uuid4()
        if hasattr(obj, "password_hash"):
            created["user"] = obj
            obj.id = uuid4()
            obj.must_change_password = True
            obj.pending_temporary_password = "temp"
            if not getattr(obj, "email", None):
                obj.email = "employee01"

    db.add.side_effect = add
    return created


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
    pos = _position(
        business_id=business_id,
        position_id=position_id,
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
    db = _mock_db_with_position(pos)
    created = _capture_add(db)

    with patch("app.api.employees.generate_temporary_password", return_value="temp"):
        with patch("app.api.employees.hash_password", return_value="hashed"):
            result = create_employee(body, db, owner)  # type: ignore[arg-type]

    assert created["employee"].daily_rate == 650.0
    assert created["employee"].pay_basis == PayBasis.daily
    assert result.daily_rate == 650.0
    assert result.pay_basis == "daily"


def test_create_employee_ignores_client_override_daily_rate():
    """Design B: Setup Wizard rate is authoritative."""
    business_id = uuid4()
    position_id = uuid4()
    pos = _position(
        business_id=business_id,
        position_id=position_id,
        daily_rate=650.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Mark Barista",
        position_title="Barista",
        position_id=str(position_id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=720.0,
    )
    db = _mock_db_with_position(pos)
    created = _capture_add(db)

    with patch("app.api.employees.generate_temporary_password", return_value="temp"):
        with patch("app.api.employees.hash_password", return_value="hashed"):
            result = create_employee(body, db, owner)  # type: ignore[arg-type]

    assert created["employee"].daily_rate == 650.0
    assert result.daily_rate == 650.0


def test_update_position_resolves_configured_rate():
    """Changing Role applies the new Role's configured rate."""
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
        face_registration_status="not_registered",
    )
    linked = SimpleNamespace(
        email="mark",
        must_change_password=False,
        pending_temporary_password=None,
    )
    new_pos = _position(
        business_id=business_id,
        position_id=new_pos_id,
        title="Senior Barista",
        daily_rate=800.0,
    )
    owner = SimpleNamespace(business_id=business_id)
    db = _mock_db_with_position(new_pos)

    with patch(
        "app.api.employees._get_business_employee",
        return_value=(emp, linked),
    ):
        body = EmployeeUpdate(position_id=str(new_pos_id), pay_basis=PayBasis.daily)
        result = update_employee(emp.id, body, db, owner)  # type: ignore[arg-type]

    assert emp.daily_rate == 800.0
    assert emp.position_id == new_pos_id
    assert result.daily_rate == 800.0


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
        face_registration_status="not_registered",
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


def test_employee_create_schema_allows_missing_hourly_when_position_set():
    body = EmployeeCreate(
        full_name="Jane Doe",
        position_title="Barista",
        position_id=str(uuid4()),
        pay_basis=PayBasis.hourly,
        hourly_rate=None,
    )
    assert body.hourly_rate is None


def test_create_employee_prefills_hourly_rate_from_position():
    business_id = uuid4()
    position_id = uuid4()
    pos = _position(
        business_id=business_id,
        position_id=position_id,
        title="Server",
        employment_type=EmploymentType.part_time,
        hourly_rate=80.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Pat Server",
        position_title="Server",
        position_id=str(position_id),
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=None,
    )
    db = _mock_db_with_position(pos)
    created = _capture_add(db)

    with patch("app.api.employees.generate_temporary_password", return_value="temp"):
        with patch("app.api.employees.hash_password", return_value="hashed"):
            result = create_employee(body, db, owner)  # type: ignore[arg-type]

    assert created["employee"].hourly_rate == 80.0
    assert created["employee"].pay_basis == PayBasis.hourly
    assert result.hourly_rate == 80.0
    assert result.pay_basis == "hourly"


def test_create_employee_ignores_client_override_hourly_rate():
    business_id = uuid4()
    position_id = uuid4()
    pos = _position(
        business_id=business_id,
        position_id=position_id,
        title="Chef",
        hourly_rate=100.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Alex Chef",
        position_title="Chef",
        position_id=str(position_id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=120.0,
    )
    db = _mock_db_with_position(pos)
    created = _capture_add(db)

    with patch("app.api.employees.generate_temporary_password", return_value="temp"):
        with patch("app.api.employees.hash_password", return_value="hashed"):
            result = create_employee(body, db, owner)  # type: ignore[arg-type]

    assert created["employee"].hourly_rate == 100.0
    assert result.hourly_rate == 100.0


def test_create_hourly_without_configured_hourly_is_rejected():
    business_id = uuid4()
    position_id = uuid4()
    pos = _position(
        business_id=business_id,
        position_id=position_id,
        title="Server",
        daily_rate=650.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Sam Server",
        position_title="Server",
        position_id=str(position_id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=None,
    )
    db = _mock_db_with_position(pos)

    with pytest.raises(HTTPException) as exc_info:
        create_employee(body, db, owner)  # type: ignore[arg-type]
    assert exc_info.value.detail["code"] == "pay_config_not_found"


def test_update_position_resolves_configured_hourly_rate():
    business_id = uuid4()
    old_pos_id = uuid4()
    new_pos_id = uuid4()
    emp = SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        position_id=old_pos_id,
        position_title="Server",
        full_name="Pat",
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=95.0,
        monthly_salary=None,
        phone=None,
        profile_image_url=None,
        status=SimpleNamespace(value="active"),
        face_registration_status="not_registered",
    )
    linked = SimpleNamespace(
        email="pat",
        must_change_password=False,
        pending_temporary_password=None,
    )
    new_pos = _position(
        business_id=business_id,
        position_id=new_pos_id,
        title="Senior Server",
        employment_type=EmploymentType.part_time,
        hourly_rate=110.0,
    )
    owner = SimpleNamespace(business_id=business_id)
    db = _mock_db_with_position(new_pos)

    with patch(
        "app.api.employees._get_business_employee",
        return_value=(emp, linked),
    ):
        body = EmployeeUpdate(position_id=str(new_pos_id), pay_basis=PayBasis.hourly)
        result = update_employee(emp.id, body, db, owner)  # type: ignore[arg-type]

    assert emp.hourly_rate == 110.0
    assert emp.position_id == new_pos_id
    assert result.hourly_rate == 110.0


def test_create_employee_rejects_inactive_position():
    business_id = uuid4()
    position_id = uuid4()
    pos = _position(
        business_id=business_id,
        position_id=position_id,
        title="Chef",
        daily_rate=700.0,
        hourly_rate=100.0,
        is_active=False,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Alex Chef",
        position_title="Chef",
        position_id=str(position_id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=700.0,
    )
    db = _mock_db_with_position(pos)

    with pytest.raises(HTTPException) as exc:
        create_employee(body, db, owner)  # type: ignore[arg-type]

    assert exc.value.status_code == 400
    assert "Invalid position" in str(exc.value.detail)


def test_create_employee_rejects_hourly_when_role_has_no_hourly_config():
    business_id = uuid4()
    position_id = uuid4()
    pos = _position(
        business_id=business_id,
        position_id=position_id,
        title="Chef",
        daily_rate=700.0,
    )
    owner = SimpleNamespace(business_id=business_id, id=uuid4())
    body = EmployeeCreate(
        full_name="Alex Chef",
        position_title="Chef",
        position_id=str(position_id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=90.0,
    )
    db = _mock_db_with_position(pos)

    with pytest.raises(HTTPException) as exc:
        create_employee(body, db, owner)  # type: ignore[arg-type]
    assert exc.value.detail["code"] == "pay_config_not_found"
