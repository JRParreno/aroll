"""Phase 2: finalized payroll reads Payslip snapshots; unfinalized stays live."""

from datetime import date
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.api.employee_mobile import _payroll_response, _simple_payslip_pdf, payslip as mobile_payslip
from app.api.employee_mobile import payroll as mobile_payroll
from app.api.employee_mobile import payslip_pdf
from app.api.owner_reports import employee_payslip, my_payslip, payroll_report
from app.models.employee import Employee
from app.models.enums import PayBasis, PayrollRunStatus, UserRole
from app.models.payroll import BusinessPayrollConfig, Payslip, PayrollRun
from app.models.user import User
from app.services.payroll_snapshot import (
    PAYSLIP_SNAPSHOT_VERSION,
    freeze_payslip_dict,
    load_period_payroll,
    load_period_payslip,
    load_period_payslip_for_employee_id,
    require_loaded_slip,
    resolve_view_period,
)


def _slip(*, employee_id, name="Ana", **overrides):
    base = {
        "employee_id": str(employee_id),
        "employee_name": name,
        "position_title": "Cashier",
        "employment_type": "full_time",
        "period_start": "2026-09-01",
        "period_end": "2026-09-15",
        "daily_rate": 730.0,
        "pay_basis": PayBasis.daily.value,
        "hourly_rate": 91.25,
        "monthly_salary": None,
        "worked_days": 1.0,
        "hours_worked": 8.0,
        "half_day_days": 0,
        "overtime_minutes": 30.48,
        "overtime_hours": 0.51,
        "overtime_pay": 30.48,
        "late_minutes": 20.0,
        "early_out_minutes": 0.0,
        "undertime_minutes": 0.0,
        "holiday_pay": 100.0,
        "rest_day_pay": 0.0,
        "deductions": 19.22,
        "late_deductions": 19.22,
        "undertime_deductions": 0.0,
        "absent_days": 0,
        "paid_leave_days": 0,
        "unpaid_leave_days": 0,
        "regular_pay": 730.0,
        "leave_pay": 0.0,
        "gross_pay": 760.48,
        "net_pay": 741.26,
        "base_net_pay": 741.26,
        "final_net_pay": 741.26,
        "payroll_adjustments": [],
        "payroll_adjustments_total": 0.0,
        "payroll_adjustments_deduction_total": 0.0,
        "payroll_adjustments_allowance_total": 0.0,
        "adjustments_editable": True,
        "attendance_records": [{"date": "2026-09-01", "earned": 730.0}],
        "pending_attendance_count": 0,
        "pending_work_dates": [],
    }
    base.update(overrides)
    return base


class _Query:
    def __init__(self, rows):
        self._rows = list(rows)

    def filter(self, *args, **kwargs):
        rows = self._rows
        for expr in args:
            key, value = _clause_key_value(expr)
            if key is None:
                continue
            rows = [row for row in rows if getattr(row, key, None) == value]
        return _Query(rows)

    def order_by(self, *args, **kwargs):
        return self

    def all(self):
        return self._rows

    def first(self):
        return self._rows[0] if self._rows else None


def _clause_key_value(expr):
    left = getattr(expr, "left", None)
    right = getattr(expr, "right", None)
    key = getattr(left, "key", None)
    if key is None:
        return None, None
    if hasattr(right, "value"):
        return key, right.value
    return key, right


class FakeDB:
    def __init__(self):
        self.runs = []
        self.payslips = []
        self.employees = []
        self.added = []
        self.committed = False
        self.rolled_back = False
        self.config = SimpleNamespace(
            pay_period_type=SimpleNamespace(value="semi_monthly")
        )

    def get(self, model, key):
        if model is BusinessPayrollConfig:
            return self.config
        if model is Employee:
            return next((emp for emp in self.employees if emp.id == key), None)
        return None

    def query(self, model):
        if model is PayrollRun:
            return _Query(self.runs)
        if model is Payslip:
            return _Query(self.payslips)
        if model is Employee:
            q = MagicMock()
            active = [emp for emp in self.employees if emp.is_active]
            q.filter.return_value.order_by.return_value.all.return_value = active
            q.filter.return_value.first.return_value = (
                self.employees[0] if self.employees else None
            )
            q.filter.return_value.all.return_value = active
            return q
        return _Query([])

    def add(self, obj):
        self.added.append(obj)

    def commit(self):
        self.committed = True

    def rollback(self):
        self.rolled_back = True

    def refresh(self, obj):
        return obj


def _employee(*, name="Ana", active=True):
    return SimpleNamespace(
        id=uuid4(),
        business_id=uuid4(),
        full_name=name,
        position_title="Cashier",
        is_active=active,
        user_id=uuid4(),
        profile_image_url=None,
        daily_rate=730.0,
    )


def _run(*, business_id, version=PAYSLIP_SNAPSHOT_VERSION):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        period_start=date(2026, 9, 1),
        period_end=date(2026, 9, 15),
        status=PayrollRunStatus.finalized,
        snapshot_version=version,
        created_at=date(2026, 9, 15),
        finalized_at=date(2026, 9, 15),
    )


def _row(*, run, employee_id, slip):
    return SimpleNamespace(
        payroll_run_id=run.id,
        employee_id=employee_id,
        breakdown_json=freeze_payslip_dict(slip),
        regular_hours=8.0,
        overtime_hours=0.51,
        gross_pay=760.48,
        total_deductions=19.22,
        net_pay=741.26,
    )


def _live_changed_slip(employee_id):
    return _slip(
        employee_id=employee_id,
        name="Ana",
        daily_rate=800.0,
        gross_pay=900.0,
        late_deductions=50.0,
        deductions=50.0,
        net_pay=850.0,
        final_net_pay=850.0,
        base_net_pay=850.0,
        overtime_hours=2.0,
        overtime_pay=100.0,
        hours_worked=7.0,
        holiday_pay=0.0,
    )


def test_finalized_snapshot_is_used_when_settings_would_change_live():
    employee = _employee()
    frozen = _slip(employee_id=employee.id)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.from_snapshot is True
    assert loaded.slip["gross_pay"] == 760.48
    assert loaded.slip["late_deductions"] == 19.22
    assert loaded.slip["final_net_pay"] == 741.26
    assert loaded.slip["adjustments_editable"] is False
    calc.assert_not_called()


def test_ot_balancing_change_does_not_affect_finalized_payroll():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, overtime_pay=30.48, late_deductions=19.22)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(
        return_value=_slip(
            employee_id=employee.id,
            overtime_pay=80.0,
            late_deductions=40.0,
            gross_pay=810.0,
            final_net_pay=770.0,
        )
    )
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.slip["overtime_pay"] == 30.48
    assert loaded.slip["late_deductions"] == 19.22
    calc.assert_not_called()


def test_paid_breaktime_change_does_not_affect_finalized_hours():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, hours_worked=8.0)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(return_value=_slip(employee_id=employee.id, hours_worked=7.42))
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.slip["hours_worked"] == 8.0
    calc.assert_not_called()


def test_employee_rate_change_does_not_affect_finalized_payroll():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, daily_rate=730.0, regular_pay=730.0)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(
        return_value=_slip(employee_id=employee.id, daily_rate=800.0, regular_pay=800.0)
    )
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.slip["daily_rate"] == 730.0
    assert loaded.slip["regular_pay"] == 730.0
    calc.assert_not_called()


def test_holiday_change_does_not_affect_finalized_payroll():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, holiday_pay=100.0, gross_pay=760.48)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(
        return_value=_slip(employee_id=employee.id, holiday_pay=200.0, gross_pay=860.48)
    )
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.slip["holiday_pay"] == 100.0
    assert loaded.slip["gross_pay"] == 760.48
    calc.assert_not_called()


def test_adjustments_are_frozen_on_snapshot_retrieval():
    employee = _employee()
    frozen = _slip(
        employee_id=employee.id,
        payroll_adjustments=[
            {"display_name": "Meal Allowance", "kind": "allowance", "amount": 50.0}
        ],
        payroll_adjustments_allowance_total=50.0,
        final_net_pay=791.26,
        base_net_pay=741.26,
    )
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(return_value=_slip(employee_id=employee.id, final_net_pay=741.26))
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.slip["final_net_pay"] == 791.26
    assert loaded.slip["payroll_adjustments"][0]["amount"] == 50.0
    assert loaded.slip["adjustments_editable"] is False
    calc.assert_not_called()


def test_unfinalized_payroll_still_uses_live_calculation():
    employee = _employee()
    db = FakeDB()
    db.employees = [employee]
    live = _live_changed_slip(employee.id)
    calc = MagicMock(return_value=live)
    with patch(
        "app.services.payroll_snapshot.resolve_pay_period",
        return_value=(date(2026, 9, 16), date(2026, 9, 30)),
    ):
        loaded = load_period_payslip(
            db, employee, as_of=date(2026, 9, 20), calculate_payslip=calc
        )
    assert loaded.from_snapshot is False
    assert loaded.slip["gross_pay"] == 900.0
    assert loaded.slip["daily_rate"] == 800.0
    calc.assert_called_once()


def test_owner_employee_and_mobile_return_same_frozen_values():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, final_net_pay=741.26, gross_pay=760.48)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    owner_user = User(
        id=uuid4(),
        business_id=employee.business_id,
        role=UserRole.owner,
        is_active=True,
    )
    emp_user = User(
        id=employee.user_id,
        business_id=employee.business_id,
        role=UserRole.employee,
        is_active=True,
    )
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    with (
        patch(
            "app.api.owner_reports._calculate_employee_payslip",
            calc,
        ),
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=0,
        ),
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=0,
        ),
        patch(
            "app.api.employee_mobile._current_employee",
            return_value=(employee, SimpleNamespace(name="Cafe", id=employee.business_id)),
        ),
        patch(
            "app.api.employee_mobile._branding_response",
            return_value={},
        ),
        patch(
            "app.api.employee_mobile._calculate_employee_payslip",
            calc,
        ),
    ):
        owner = employee_payslip(
            employee_id=employee.id,
            db=db,
            user=owner_user,
            as_of=date(2026, 9, 10),
        )
        mine = my_payslip(db=db, user=emp_user, as_of=date(2026, 9, 10))
        mobile = mobile_payslip(db=db, user=emp_user, as_of=date(2026, 9, 10))
    assert owner["gross_pay"] == mine["gross_pay"] == mobile["gross_pay"] == 760.48
    assert (
        owner["final_net_pay"]
        == mine["final_net_pay"]
        == mobile["final_net_pay"]
        == 741.26
    )
    calc.assert_not_called()


def test_pdf_uses_snapshot_values():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, final_net_pay=741.26, gross_pay=760.48)
    pdf = _simple_payslip_pdf({"business_name": "Cafe", **freeze_payslip_dict(frozen)})
    assert b"760.48" in pdf
    assert b"741.26" in pdf

    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    with (
        patch(
            "app.api.employee_mobile._current_employee",
            return_value=(employee, SimpleNamespace(name="Cafe", id=employee.business_id)),
        ),
        patch("app.api.employee_mobile.business_is_demo", return_value=False),
        patch("app.api.employee_mobile._calculate_employee_payslip", calc),
    ):
        response = payslip_pdf(db=db, user=MagicMock(), as_of=date(2026, 9, 10))
    assert b"760.48" in response.body
    assert b"741.26" in response.body
    assert b"850.00" not in response.body
    calc.assert_not_called()


def test_inactive_employee_remains_on_finalized_owner_report():
    employee = _employee(active=False)
    frozen = _slip(employee_id=employee.id, final_net_pay=741.26)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    loaded = load_period_payroll(
        db,
        business_id=employee.business_id,
        as_of=date(2026, 9, 10),
        calculate_payslip=calc,
    )
    assert loaded.from_snapshot is True
    assert len(loaded.entries) == 1
    assert loaded.entries[0][1]["final_net_pay"] == 741.26
    calc.assert_not_called()

    owner = User(
        id=uuid4(),
        business_id=employee.business_id,
        role=UserRole.owner,
        is_active=True,
    )
    with (
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=0,
        ),
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=0,
        ),
        patch("app.api.owner_reports._calculate_employee_payslip", calc),
    ):
        report = payroll_report(db=db, user=owner, as_of=date(2026, 9, 10))
    assert len(report["items"]) == 1
    assert report["items"][0]["total_salary"] == 741.26
    assert report["is_finalized"] is True


def test_historical_as_of_finds_snapshot_despite_current_period_config():
    employee = _employee()
    frozen = _slip(employee_id=employee.id)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    with patch(
        "app.services.payroll_snapshot.resolve_pay_period",
        return_value=(date(2026, 9, 8), date(2026, 9, 14)),
    ):
        period_start, period_end, found, snapshot_mode = resolve_view_period(
            db, business_id=employee.business_id, as_of=date(2026, 9, 10)
        )
        loaded = load_period_payslip(
            db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
        )
    assert snapshot_mode is True
    assert period_start == date(2026, 9, 1)
    assert period_end == date(2026, 9, 15)
    assert found is run
    assert loaded.slip["gross_pay"] == 760.48
    calc.assert_not_called()


def test_legacy_finalized_run_without_snapshot_uses_live_calculation():
    employee = _employee()
    legacy = _run(business_id=employee.business_id, version=None)
    db = FakeDB()
    db.runs = [legacy]
    db.employees = [employee]
    live = _live_changed_slip(employee.id)
    calc = MagicMock(return_value=live)
    with patch(
        "app.services.payroll_snapshot.resolve_pay_period",
        return_value=(date(2026, 9, 1), date(2026, 9, 15)),
    ):
        loaded = load_period_payslip(
            db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
        )
    assert loaded.from_snapshot is False
    assert loaded.slip["gross_pay"] == 900.0
    calc.assert_called_once()


def test_deleted_employee_snapshot_still_matches_by_json_id():
    employee = _employee()
    frozen = _slip(employee_id=employee.id)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=None, slip=frozen)]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.from_snapshot is True
    assert loaded.slip["employee_id"] == str(employee.id)
    calc.assert_not_called()


def test_missing_snapshot_does_not_live_calculate():
    employee = _employee()
    other = _employee()
    other.business_id = employee.business_id
    frozen = _slip(employee_id=other.id, name="Ben")
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=other.id, slip=frozen)]
    db.employees = [employee]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    loaded = load_period_payslip(
        db, employee, as_of=date(2026, 9, 10), calculate_payslip=calc
    )
    assert loaded.from_snapshot is True
    assert loaded.slip is None
    calc.assert_not_called()
    with pytest.raises(HTTPException) as exc:
        require_loaded_slip(loaded)
    assert exc.value.status_code == 404
    assert exc.value.detail["code"] == "payslip_snapshot_unavailable"


def test_deleted_employee_owner_list_and_detail_return_snapshot():
    employee = _employee()
    employee_id = employee.id
    frozen = _slip(employee_id=employee_id, final_net_pay=741.26, gross_pay=760.48)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=None, slip=frozen)]
    db.employees = []
    calc = MagicMock(return_value=_live_changed_slip(employee_id))
    owner = User(
        id=uuid4(),
        business_id=employee.business_id,
        role=UserRole.owner,
        is_active=True,
    )
    with (
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=0,
        ),
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=0,
        ),
        patch("app.api.owner_reports._calculate_employee_payslip", calc),
    ):
        report = payroll_report(db=db, user=owner, as_of=date(2026, 9, 10))
        detail = employee_payslip(
            employee_id=employee_id,
            db=db,
            user=owner,
            as_of=date(2026, 9, 10),
        )
    assert len(report["items"]) == 1
    assert report["items"][0]["employee_id"] == str(employee_id)
    assert report["items"][0]["employee_name"] == "Ana"
    assert report["items"][0]["total_salary"] == 741.26
    assert detail["gross_pay"] == 760.48
    assert detail["final_net_pay"] == 741.26
    assert detail["employee_name"] == "Ana"
    assert detail["adjustments_editable"] is False
    calc.assert_not_called()


def test_other_business_cannot_access_deleted_employee_snapshot():
    employee = _employee()
    frozen = _slip(employee_id=employee.id)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=None, slip=frozen)]
    db.employees = []
    other_owner = User(
        id=uuid4(),
        business_id=uuid4(),
        role=UserRole.owner,
        is_active=True,
    )
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    with (
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=0,
        ),
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=0,
        ),
        patch("app.api.owner_reports._calculate_employee_payslip", calc),
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 16), date(2026, 9, 30)),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            employee_payslip(
                employee_id=employee.id,
                db=db,
                user=other_owner,
                as_of=date(2026, 9, 10),
            )
        report = payroll_report(db=db, user=other_owner, as_of=date(2026, 9, 10))
    assert exc.value.status_code == 404
    assert report["items"] == []
    calc.assert_not_called()


def test_missing_snapshot_owner_employee_mobile_and_pdf_do_not_live_calculate():
    employee = _employee()
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = []
    db.employees = [employee]
    owner = User(
        id=uuid4(),
        business_id=employee.business_id,
        role=UserRole.owner,
        is_active=True,
    )
    emp_user = User(
        id=employee.user_id,
        business_id=employee.business_id,
        role=UserRole.employee,
        is_active=True,
    )
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    with (
        patch("app.api.owner_reports._calculate_employee_payslip", calc),
        patch("app.api.employee_mobile._calculate_employee_payslip", calc),
        patch(
            "app.api.employee_mobile._current_employee",
            return_value=(employee, SimpleNamespace(name="Cafe", id=employee.business_id)),
        ),
        patch("app.api.employee_mobile._branding_response", return_value={}),
        patch("app.api.employee_mobile.business_is_demo", return_value=False),
        patch(
            "app.api.owner_reports.count_incomplete_attendance_in_period",
            return_value=0,
        ),
        patch(
            "app.api.owner_reports.count_unresolved_scheduled_assignments_in_period",
            return_value=0,
        ),
    ):
        with pytest.raises(HTTPException) as owner_exc:
            employee_payslip(
                employee_id=employee.id,
                db=db,
                user=owner,
                as_of=date(2026, 9, 10),
            )
        with pytest.raises(HTTPException) as mine_exc:
            my_payslip(db=db, user=emp_user, as_of=date(2026, 9, 10))
        with pytest.raises(HTTPException) as mobile_exc:
            mobile_payslip(db=db, user=emp_user, as_of=date(2026, 9, 10))
        with pytest.raises(HTTPException) as pdf_exc:
            payslip_pdf(db=db, user=emp_user, as_of=date(2026, 9, 10))
        with pytest.raises(HTTPException) as payroll_exc:
            mobile_payroll(db=db, user=emp_user, as_of=date(2026, 9, 10))
        report = payroll_report(db=db, user=owner, as_of=date(2026, 9, 10))
    for exc in (owner_exc, mine_exc, mobile_exc, pdf_exc, payroll_exc):
        assert exc.value.status_code == 404
        assert exc.value.detail["code"] == "payslip_snapshot_unavailable"
    assert report["items"] == []
    calc.assert_not_called()


def test_dashboard_payroll_does_not_404_when_snapshot_missing():
    employee = _employee()
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = []
    db.employees = [employee]
    calc = MagicMock(return_value=_live_changed_slip(employee.id))
    business = SimpleNamespace(name="Cafe", id=employee.business_id)
    with (
        patch("app.api.employee_mobile._calculate_employee_payslip", calc),
        patch("app.api.employee_mobile._branding_response", return_value={}),
    ):
        payload = _payroll_response(
            db,
            employee,
            business,
            as_of=date(2026, 9, 10),
            require_slip=False,
        )
        with pytest.raises(HTTPException) as exc:
            _payroll_response(
                db, employee, business, as_of=date(2026, 9, 10)
            )
    assert payload["summary"]["period_start"] == "2026-09-01"
    assert payload["summary"]["period_end"] == "2026-09-15"
    assert payload["summary"]["net_pay"] == 0
    assert payload["rows"] == []
    assert exc.value.status_code == 404
    assert exc.value.detail["code"] == "payslip_snapshot_unavailable"
    calc.assert_not_called()


def test_payroll_history_skips_missing_snapshot_without_live_calc():
    employee = _employee()
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = []
    db.employees = [employee]
    live = _live_changed_slip(employee.id)
    live["period_start"] = "2026-09-16"
    live["period_end"] = "2026-09-30"
    live["attendance_records"] = []
    calc = MagicMock(return_value=live)
    emp_user = User(
        id=employee.user_id,
        business_id=employee.business_id,
        role=UserRole.employee,
        is_active=True,
    )
    with (
        patch(
            "app.api.employee_mobile._current_employee",
            return_value=(employee, SimpleNamespace(name="Cafe", id=employee.business_id)),
        ),
        patch("app.api.employee_mobile._branding_response", return_value={}),
        patch("app.api.employee_mobile._calculate_employee_payslip", calc),
        patch(
            "app.services.pay_period.list_pay_periods",
            return_value=[
                (date(2026, 9, 16), date(2026, 9, 30)),
                (date(2026, 9, 1), date(2026, 9, 15)),
            ],
        ),
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 16), date(2026, 9, 30)),
        ),
    ):
        payload = mobile_payroll(
            db=db, user=emp_user, as_of=date(2026, 9, 20), history_limit=6
        )
    history_windows = [
        (item["period_start"], item["period_end"]) for item in payload["history"]
    ]
    assert ("2026-09-01", "2026-09-15") not in history_windows
    assert payload["summary"]["gross_pay"] == 900.0
    assert calc.call_count >= 1
    for args in calc.call_args_list:
        period_start = args.args[2] if len(args.args) > 2 else args.kwargs.get("period_start")
        assert period_start != date(2026, 9, 1)


def test_deleted_employee_id_helper_uses_json_identity():
    employee_id = uuid4()
    business_id = uuid4()
    frozen = _slip(employee_id=employee_id)
    run = _run(business_id=business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=None, slip=frozen)]
    calc = MagicMock(return_value=_live_changed_slip(employee_id))
    loaded = load_period_payslip_for_employee_id(
        db,
        business_id=business_id,
        employee_id=employee_id,
        as_of=date(2026, 9, 10),
        calculate_payslip=calc,
        employee=None,
    )
    assert loaded.from_snapshot is True
    assert loaded.slip["employee_id"] == str(employee_id)
    assert loaded.slip["final_net_pay"] == 741.26
    calc.assert_not_called()
