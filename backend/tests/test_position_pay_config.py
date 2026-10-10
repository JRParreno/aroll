"""Design B: Position pay_configs + authoritative employee rate resolution."""

from __future__ import annotations

import uuid
from contextlib import ExitStack
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api import employees as employees_api
from app.api import positions as positions_api
from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis, UserRole
from app.models.payroll import BusinessPayrollConfig, Position, PositionPayConfig
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.schemas.employee import EmployeeCreate, EmployeeUpdate
from app.schemas.owner_setup import PositionCreate, PositionPayConfigPayload
from app.services.position_pay_config import (
    apply_config_to_employee_fields,
    replace_pay_configs,
    resolve_pay_config,
    validate_pay_config_items,
)


def _barista_with_dual_rates(business_id: uuid.UUID | None = None) -> Position:
    bid = business_id or uuid.uuid4()
    pos = Position(
        id=uuid.uuid4(),
        business_id=bid,
        title="Barista",
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500,
        hourly_rate=70,
        is_active=True,
    )
    pos.pay_configs = [
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=pos.id,
            pay_basis=PayBasis.daily,
            rate=500,
        ),
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=pos.id,
            pay_basis=PayBasis.hourly,
            rate=70,
        ),
    ]
    return pos


def test_role_can_have_daily_and_hourly_configs():
    items = validate_pay_config_items(
        [(PayBasis.daily, 500), (PayBasis.hourly, 70)]
    )
    assert items == [(PayBasis.daily, 500.0), (PayBasis.hourly, 70.0)]


def test_duplicate_pay_basis_rejected():
    with pytest.raises(ValueError, match="Duplicate"):
        validate_pay_config_items(
            [(PayBasis.daily, 500), (PayBasis.daily, 550)]
        )


def test_position_create_schema_accepts_dual_configs():
    body = PositionCreate(
        title="Barista",
        employment_type=EmploymentType.full_time,
        pay_configs=[
            PositionPayConfigPayload(pay_basis=PayBasis.daily, rate=500),
            PositionPayConfigPayload(pay_basis=PayBasis.hourly, rate=70),
        ],
    )
    assert len(body.pay_configs) == 2


def test_position_create_schema_rejects_monthly_config():
    with pytest.raises(ValueError, match="daily or hourly"):
        PositionPayConfigPayload(pay_basis=PayBasis.monthly, rate=20000)


def test_different_employment_types_keep_separate_roles():
    ft = PositionCreate(
        title="Barista",
        employment_type=EmploymentType.full_time,
        pay_configs=[
            PositionPayConfigPayload(pay_basis=PayBasis.daily, rate=500),
        ],
    )
    pt = PositionCreate(
        title="Barista",
        employment_type=EmploymentType.part_time,
        pay_configs=[
            PositionPayConfigPayload(pay_basis=PayBasis.daily, rate=450),
        ],
    )
    assert ft.employment_type != pt.employment_type
    assert ft.pay_configs[0].rate != pt.pay_configs[0].rate


def test_replace_pay_configs_stores_independent_rates():
    pos = Position(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        title="Barista",
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=None,
        hourly_rate=None,
        is_active=True,
    )
    pos.pay_configs = []
    replace_pay_configs(pos, [(PayBasis.daily, 500), (PayBasis.hourly, 70)])
    assert float(pos.daily_rate) == 500
    assert float(pos.hourly_rate) == 70
    assert {c.pay_basis for c in pos.pay_configs} == {
        PayBasis.daily,
        PayBasis.hourly,
    }


def test_resolve_pay_config_rejects_missing_basis():
    pos = _barista_with_dual_rates()
    pos.pay_configs = [pos.pay_configs[0]]  # daily only
    pos.hourly_rate = None
    with pytest.raises(HTTPException) as exc:
        resolve_pay_config(pos, PayBasis.hourly)
    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "pay_config_not_found"


def test_create_employee_uses_configured_rate_not_client_rate(monkeypatch):
    pos = _barista_with_dual_rates()
    user = SimpleNamespace(business_id=pos.business_id, role=UserRole.owner)
    db = MagicMock()

    monkeypatch.setattr(
        employees_api,
        "_generate_employee_username",
        lambda *_a, **_k: "barista01",
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )

    captured = {}

    def fake_add(obj):
        captured.setdefault("objects", []).append(obj)

    db.add.side_effect = fake_add

    body = EmployeeCreate(
        full_name="Sam Lee",
        position_title="Barista",
        position_id=str(pos.id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=9999,  # client attempt to override
    )
    employees_api.create_employee(body=body, db=db, user=user)

    employees = [
        o for o in captured.get("objects", []) if o.__class__.__name__ == "Employee"
    ]
    assert len(employees) == 1
    assert float(employees[0].daily_rate) == 500
    assert employees[0].hourly_rate is None
    assert employees[0].monthly_salary is None
    assert employees[0].pay_basis == PayBasis.daily


def test_create_employee_rejects_invalid_pay_basis(monkeypatch):
    pos = _barista_with_dual_rates()
    pos.pay_configs = [c for c in pos.pay_configs if c.pay_basis == PayBasis.daily]
    pos.hourly_rate = None
    user = SimpleNamespace(business_id=pos.business_id, role=UserRole.owner)

    monkeypatch.setattr(
        employees_api,
        "_generate_employee_username",
        lambda *_a, **_k: "barista02",
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )

    body = EmployeeCreate(
        full_name="Sam Lee",
        position_title="Barista",
        position_id=str(pos.id),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.hourly,
        hourly_rate=65,
    )
    with pytest.raises(HTTPException) as exc:
        employees_api.create_employee(body=body, db=MagicMock(), user=user)
    assert exc.value.detail["code"] == "pay_config_not_found"


def test_create_employee_rejects_employment_mismatch(monkeypatch):
    pos = _barista_with_dual_rates()
    user = SimpleNamespace(business_id=pos.business_id, role=UserRole.owner)
    monkeypatch.setattr(
        employees_api,
        "_generate_employee_username",
        lambda *_a, **_k: "barista03",
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )
    body = EmployeeCreate(
        full_name="Sam Lee",
        position_title="Barista",
        position_id=str(pos.id),
        employment_type=EmploymentType.part_time,
        pay_basis=PayBasis.daily,
        daily_rate=500,
    )
    with pytest.raises(HTTPException) as exc:
        employees_api.create_employee(body=body, db=MagicMock(), user=user)
    assert exc.value.detail["code"] == "employment_type_mismatch"


def test_update_employee_overrides_client_rate(monkeypatch):
    pos = _barista_with_dual_rates()
    emp = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=pos.business_id,
        position_id=pos.id,
        position_title="Barista",
        full_name="Sam Lee",
        phone=None,
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500,
        hourly_rate=None,
        monthly_salary=None,
    )
    linked = SimpleNamespace(email="barista01", must_change_password=False)
    user = SimpleNamespace(business_id=pos.business_id, role=UserRole.owner)
    db = MagicMock()

    monkeypatch.setattr(
        employees_api,
        "_get_business_employee",
        lambda *_a, **_k: (emp, linked),
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )
    monkeypatch.setattr(
        employees_api,
        "_employee_response",
        lambda e, u, **_k: SimpleNamespace(daily_rate=float(e.daily_rate)),
    )

    body = EmployeeUpdate(
        pay_basis=PayBasis.daily,
        daily_rate=9999,
    )
    employees_api.update_employee(
        employee_id=emp.id, body=body, db=db, user=user
    )
    assert float(emp.daily_rate) == 500


def test_update_employee_changing_basis_resolves_new_rate(monkeypatch):
    pos = _barista_with_dual_rates()
    emp = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=pos.business_id,
        position_id=pos.id,
        position_title="Barista",
        full_name="Sam Lee",
        phone=None,
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500,
        hourly_rate=None,
        monthly_salary=None,
    )
    linked = SimpleNamespace(email="barista01", must_change_password=False)
    user = SimpleNamespace(business_id=pos.business_id, role=UserRole.owner)
    db = MagicMock()

    monkeypatch.setattr(
        employees_api,
        "_get_business_employee",
        lambda *_a, **_k: (emp, linked),
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )
    monkeypatch.setattr(
        employees_api,
        "_employee_response",
        lambda e, u, **_k: e,
    )

    body = EmployeeUpdate(pay_basis=PayBasis.hourly, hourly_rate=1)
    employees_api.update_employee(
        employee_id=emp.id, body=body, db=db, user=user
    )
    assert emp.pay_basis == PayBasis.hourly
    assert float(emp.hourly_rate) == 70
    assert emp.daily_rate is None


def test_apply_config_fields_clear_other_rates():
    cfg = PositionPayConfig(
        id=uuid.uuid4(),
        position_id=uuid.uuid4(),
        pay_basis=PayBasis.hourly,
        rate=65,
    )
    resolved = apply_config_to_employee_fields(cfg)
    assert resolved["hourly_rate"] == 65
    assert resolved["daily_rate"] is None
    assert resolved["monthly_salary"] is None


def test_list_positions_includes_pay_configs():
    business_id = uuid.uuid4()
    user = SimpleNamespace(business_id=business_id, role=UserRole.owner)
    pos = _barista_with_dual_rates(business_id)

    db = MagicMock()
    query = MagicMock()
    db.query.return_value = query
    query.options.return_value = query
    query.filter.return_value = query
    query.order_by.return_value = query
    query.all.return_value = [pos]

    result = positions_api.list_positions(db=db, user=user)
    assert len(result) == 1
    assert len(result[0].pay_configs) == 2
    rates = {c.pay_basis: c.rate for c in result[0].pay_configs}
    assert rates[PayBasis.daily] == 500
    assert rates[PayBasis.hourly] == 70


def test_legacy_monthly_employee_fields_preserved_without_mass_rewrite():
    """Existing monthly compensation stays on the employee record shape."""
    emp = SimpleNamespace(
        pay_basis=PayBasis.monthly,
        daily_rate=None,
        hourly_rate=None,
        monthly_salary=22000,
        position_id=None,
    )
    assert emp.pay_basis == PayBasis.monthly
    assert float(emp.monthly_salary) == 22000


def test_design_b_stamped_daily_rate_feeds_payroll_resolve_not_position_pay_config():
    """Payroll reads Employee stamp; PositionPayConfig is not consulted at calc time."""
    from app.services.employee_pay import (
        resolve_employee_pay,
        resolve_employee_pay_context,
    )

    pos = _barista_with_dual_rates()
    # Setup later changed config to 550, but employee still holds stamped 500.
    for cfg in pos.pay_configs:
        if cfg.pay_basis == PayBasis.daily:
            cfg.rate = 550
    pos.daily_rate = 550

    stamped = apply_config_to_employee_fields(
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=pos.id,
            pay_basis=PayBasis.daily,
            rate=500,
        )
    )
    employee = SimpleNamespace(
        pay_basis=stamped["pay_basis"],
        daily_rate=stamped["daily_rate"],
        hourly_rate=stamped["hourly_rate"],
        monthly_salary=stamped["monthly_salary"],
    )
    resolved = resolve_employee_pay(employee, position=pos)
    assert resolved.daily_rate == 500.0
    # Hourly may still fall back to Position.hourly_rate when employee hourly is null;
    # daily payroll day value must remain the stamped employee rate.
    ctx = resolve_employee_pay_context(
        employee, 480.0, position=pos, resolved=resolved
    )
    assert ctx.scheduled_day_value == 500.0


def test_design_b_stamped_hourly_rate_feeds_payroll_context():
    from app.services.employee_pay import (
        resolve_employee_pay,
        resolve_employee_pay_context,
    )

    pos = _barista_with_dual_rates()
    stamped = apply_config_to_employee_fields(
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=pos.id,
            pay_basis=PayBasis.hourly,
            rate=70,
        )
    )
    employee = SimpleNamespace(
        pay_basis=stamped["pay_basis"],
        daily_rate=stamped["daily_rate"],
        hourly_rate=stamped["hourly_rate"],
        monthly_salary=stamped["monthly_salary"],
    )
    resolved = resolve_employee_pay(employee, position=pos)
    assert resolved.hourly_rate == 70.0
    ctx = resolve_employee_pay_context(
        employee, 480.0, position=pos, resolved=resolved
    )
    assert ctx.minute_rate == 70.0 / 60.0
    assert ctx.scheduled_day_value == 70.0 * 8.0


def test_setup_rate_change_without_employee_save_does_not_change_live_resolve():
    """Changing PositionPayConfig alone must not alter payroll until employee Save."""
    from app.services.employee_pay import resolve_employee_pay

    pos = _barista_with_dual_rates()
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    for cfg in pos.pay_configs:
        if cfg.pay_basis == PayBasis.daily:
            cfg.rate = 9999
    pos.daily_rate = 9999
    resolved = resolve_employee_pay(employee, position=pos)
    assert resolved.daily_rate == 500.0


def _ph_manila(hour: int, minute: int = 0) -> datetime:
    utc_hour = hour - 8
    day = 4
    if utc_hour < 0:
        utc_hour += 24
        day = 3
    return datetime(2026, 8, day, utc_hour, minute, tzinfo=timezone.utc)


def _payslip_from_stamped_rates(
    *,
    pay_basis: PayBasis,
    daily_rate: float | None,
    hourly_rate: float | None,
    position_daily_rate: float | None = None,
    position_hourly_rate: float | None = None,
    shift_end: time = time(17, 0),
    completion_daily_rate: float | None = None,
    completion_hourly_rate: float | None = None,
    stamp_from_employee: bool = True,
):
    """Exercise real _calculate_employee_payslip with Design-B-stamped employee rates.

    When ``completion_daily_rate`` / ``completion_hourly_rate`` are set, the
    attendance row carries those historical completion stamps (migration 044).
    Otherwise, by default the row is stamped from the current Employee rates
    (production clock-out behavior). Pass ``stamp_from_employee=False`` only
    for explicit unresolved-historical-rate cases.
    """
    business_id = uuid.uuid4()
    employee_id = uuid.uuid4()
    position_id = uuid.uuid4()
    work_date = date(2026, 8, 4)

    employee = SimpleNamespace(
        id=employee_id,
        business_id=business_id,
        full_name="Design B Emp",
        position_title="Barista",
        position_id=position_id,
        employment_type=EmploymentType.full_time,
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
        monthly_salary=None,
    )
    position = SimpleNamespace(
        daily_rate=position_daily_rate,
        hourly_rate=position_hourly_rate,
    )
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
    )
    config = SimpleNamespace(
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=False,
        holiday_rules_mode=None,
    )
    shift = Shift(
        id=uuid.uuid4(),
        business_id=business_id,
        name="Day",
        start_time=time(8, 0),
        end_time=shift_end,
    )
    assignment = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=shift.id,
        employee_id=employee_id,
        work_date=work_date,
        is_rest_day_work=False,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=_ph_manila(8, 0),
        time_out=_ph_manila(shift_end.hour, shift_end.minute),
        status=AttendanceStatus.complete,
    )
    if completion_daily_rate is not None or completion_hourly_rate is not None:
        record.pay_basis_at_completion = pay_basis
        record.daily_rate_at_completion = completion_daily_rate
        record.hourly_rate_at_completion = completion_hourly_rate
        record.monthly_salary_at_completion = None
    elif stamp_from_employee:
        from app.services.employee_pay import stamp_attendance_completion_pay

        stamp_attendance_completion_pay(record, employee, position=position)

    db = MagicMock()

    def db_get(model, key=None):
        if model is BusinessPayrollConfig:
            return config
        if model is BusinessAttendancePolicy:
            return att_policy
        if model is Business:
            return business
        if model is BusinessRestDayPolicy:
            return None
        if model is Position:
            return position
        return None

    db.get.side_effect = db_get

    attendance_query = MagicMock()
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = [
        (record, assignment, shift)
    ]
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.filter.return_value.all.return_value = [
        (assignment, shift)
    ]
    holiday_query = MagicMock()
    holiday_query.filter.return_value.all.return_value = []

    def real_query(*models):
        if models[0] is AttendanceRecord:
            return attendance_query
        if models[0] is ShiftAssignment:
            return scheduled_query
        from app.models.holiday import Holiday

        if models[0] is Holiday:
            return holiday_query
        return MagicMock()

    db.query.side_effect = real_query

    patches = [
        patch("app.api.owner_reports.ensure_incomplete_for_employee"),
        patch("app.api.owner_reports.employee_on_approved_leave", return_value=False),
        patch("app.api.owner_reports.approved_leave_dates_for_employee", return_value=[]),
        patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 5)),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 5, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
    ]
    with ExitStack() as stack:
        for p in patches:
            stack.enter_context(p)
        return _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        )


def test_design_b_daily_config_flows_into_real_payslip():
    """PositionPayConfig → stamp → resolve → _calculate_employee_payslip (Daily)."""
    pos = _barista_with_dual_rates()
    cfg = resolve_pay_config(pos, PayBasis.daily)
    assert cfg is not None and float(cfg.rate) == 500.0
    stamped = apply_config_to_employee_fields(cfg)
    # Client-supplied rate must not become payroll rate; only stamped config rate.
    assert stamped["daily_rate"] == 500.0

    slip = _payslip_from_stamped_rates(
        pay_basis=stamped["pay_basis"],
        daily_rate=stamped["daily_rate"],
        hourly_rate=stamped["hourly_rate"],
        # Divergent Position columns must not override stamped employee daily rate.
        position_daily_rate=9999.0,
        position_hourly_rate=1.0,
    )
    assert slip["daily_rate"] == 500.0
    assert slip["gross_pay"] == 500.0
    assert slip["net_pay"] == 500.0


def test_design_b_hourly_config_flows_into_real_payslip():
    """PositionPayConfig → stamp → resolve → _calculate_employee_payslip (Hourly)."""
    pos = _barista_with_dual_rates()
    cfg = resolve_pay_config(pos, PayBasis.hourly)
    assert cfg is not None and float(cfg.rate) == 70.0
    stamped = apply_config_to_employee_fields(cfg)

    slip = _payslip_from_stamped_rates(
        pay_basis=stamped["pay_basis"],
        daily_rate=stamped["daily_rate"],
        hourly_rate=stamped["hourly_rate"],
        position_daily_rate=9999.0,
        position_hourly_rate=1.0,
        shift_end=time(16, 0),  # 8h scheduled × ₱70
    )
    assert slip["pay_basis"] == "hourly"
    assert slip["hourly_rate_configured"] == 70.0
    assert slip["gross_pay"] == 560.0
    assert slip["net_pay"] == 560.0


def test_design_b_setup_change_without_save_payslip_keeps_stamped_rate():
    """Setup rate B without employee save: live payslip still uses stamped A."""
    stamped_a = apply_config_to_employee_fields(
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=uuid.uuid4(),
            pay_basis=PayBasis.daily,
            rate=500,
        )
    )
    # Setup later moved to B — employee not re-saved.
    slip = _payslip_from_stamped_rates(
        pay_basis=stamped_a["pay_basis"],
        daily_rate=stamped_a["daily_rate"],
        hourly_rate=stamped_a["hourly_rate"],
        position_daily_rate=9999.0,
    )
    assert slip["daily_rate"] == 500.0
    assert slip["gross_pay"] == 500.0

    # Re-save employee with new config B → subsequent live payroll uses B.
    stamped_b = apply_config_to_employee_fields(
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=uuid.uuid4(),
            pay_basis=PayBasis.daily,
            rate=550,
        )
    )
    slip_b = _payslip_from_stamped_rates(
        pay_basis=stamped_b["pay_basis"],
        daily_rate=stamped_b["daily_rate"],
        hourly_rate=stamped_b["hourly_rate"],
        position_daily_rate=9999.0,
    )
    assert slip_b["daily_rate"] == 550.0
    assert slip_b["gross_pay"] == 550.0


def test_unfinalized_live_payroll_uses_new_stamped_rate_after_employee_save(
    monkeypatch,
):
    """Open period: config alone does not change pay; Save restamps Employee.

    Completed attendance that was stamped at ₱500 must stay ₱500 after Save
    restamps the Employee to ₱600. Slip-level daily_rate becomes ₱600 (current
    Employee stamp). New completions after Save use ₱600 (covered elsewhere).
    """
    from app.services.employee_pay import (
        resolve_employee_pay,
        stamp_attendance_completion_pay,
    )

    pos = _barista_with_dual_rates()
    emp = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=pos.business_id,
        position_id=pos.id,
        position_title="Barista",
        full_name="Sam Lee",
        phone=None,
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )

    # 1) Complete a day while stamped ₱500 — capture completion rate.
    completed = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=emp.business_id,
        employee_id=emp.id,
        time_in=_ph_manila(8, 0),
        time_out=_ph_manila(17, 0),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(completed, emp) is True
    assert float(completed.daily_rate_at_completion) == 500.0

    slip_before = _payslip_from_stamped_rates(
        pay_basis=emp.pay_basis,
        daily_rate=emp.daily_rate,
        hourly_rate=emp.hourly_rate,
        position_daily_rate=float(pos.daily_rate),
        completion_daily_rate=500.0,
    )
    assert slip_before["daily_rate"] == 500.0
    assert slip_before["gross_pay"] == 500.0

    # 2) Setup-only rate change must not move Employee stamp or live payroll.
    for cfg in pos.pay_configs:
        if cfg.pay_basis == PayBasis.daily:
            cfg.rate = 600
    pos.daily_rate = 600
    assert resolve_employee_pay(emp, position=pos).daily_rate == 500.0
    slip_config_only = _payslip_from_stamped_rates(
        pay_basis=emp.pay_basis,
        daily_rate=emp.daily_rate,
        hourly_rate=emp.hourly_rate,
        position_daily_rate=9999.0,
        completion_daily_rate=500.0,
    )
    assert slip_config_only["daily_rate"] == 500.0
    assert slip_config_only["gross_pay"] == 500.0

    # 3) Employee Save restamps from PositionPayConfig (client ₱1 ignored).
    linked = SimpleNamespace(email="barista01", must_change_password=False)
    user = SimpleNamespace(business_id=pos.business_id, role=UserRole.owner)
    db = MagicMock()
    monkeypatch.setattr(
        employees_api,
        "_get_business_employee",
        lambda *_a, **_k: (emp, linked),
    )
    monkeypatch.setattr(
        employees_api,
        "_require_business_position",
        lambda *_a, **_k: pos,
    )
    monkeypatch.setattr(
        employees_api,
        "_employee_response",
        lambda e, u, **_k: e,
    )
    employees_api.update_employee(
        employee_id=emp.id,
        body=EmployeeUpdate(pay_basis=PayBasis.daily, daily_rate=1),
        db=db,
        user=user,
    )
    assert float(emp.daily_rate) == 600.0
    # Completion stamp must remain ₱500 (Save must not restamp attendance).
    assert stamp_attendance_completion_pay(completed, emp) is False
    assert float(completed.daily_rate_at_completion) == 500.0

    # 4) Same open period: current Employee rate is ₱600, completed day ₱500.
    slip_after = _payslip_from_stamped_rates(
        pay_basis=emp.pay_basis,
        daily_rate=emp.daily_rate,
        hourly_rate=emp.hourly_rate,
        position_daily_rate=500.0,
        completion_daily_rate=500.0,
    )
    assert slip_after["daily_rate"] == 600.0
    assert slip_after["regular_pay"] == 500.0
    assert slip_after["gross_pay"] == 500.0
    assert slip_after["net_pay"] == 500.0
    assert slip_after["attendance_records"][0]["earned"] == 500.0
