"""Phase 1: finalize writes immutable Payslip snapshots."""

from datetime import date
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest

from app.models.enums import PayBasis, UserRole
from app.models.payroll import Payslip, PayrollRun
from app.models.user import User
from app.services.payroll_snapshot import (
    PAYSLIP_SNAPSHOT_VERSION,
    freeze_payslip_dict,
    payslip_row_from_slip,
    payslip_summary_values,
)


def _slip(*, employee_id, name, **overrides):
    base = {
        "employee_id": str(employee_id),
        "employee_name": name,
        "position_title": "Cashier",
        "employment_type": "full_time",
        "period_start": "2026-08-01",
        "period_end": "2026-08-15",
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
        "unpaid_minutes": 0.0,
        "holiday_pay": 0.0,
        "rest_day_days": 0,
        "rest_day_premium_percent": 0.0,
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
        "attendance_records": [{"date": "2026-08-04", "earned": 730.0}],
        "grace_minutes_applied": 10,
        "overtime_minimum_minutes": 30,
    }
    base.update(overrides)
    return base


def _employee(*, name="Ana", daily_rate=730.0):
    emp_id = uuid4()
    return SimpleNamespace(
        id=emp_id,
        business_id=uuid4(),
        full_name=name,
        position_title="Cashier",
        employment_type=SimpleNamespace(value="full_time"),
        pay_basis=PayBasis.daily,
        daily_rate=daily_rate,
        hourly_rate=None,
        monthly_salary=None,
        is_active=True,
        user_id=uuid4(),
        profile_image_url=None,
    )


def _finalize_user(business_id):
    return User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )


def _db_for_finalize(*, employees, existing_run=None):
    from app.models.attendance_policy import BusinessAttendancePolicy
    from app.models.business import Business
    from app.models.employee import Employee
    from app.models.payroll import BusinessPayrollConfig
    from app.models.rest_day_policy import BusinessRestDayPolicy

    business_id = employees[0].business_id if employees else uuid4()
    for employee in employees:
        employee.business_id = business_id
    config = BusinessPayrollConfig(
        business_id=business_id,
        enable_late_overtime_balancing=True,
        overtime_enabled=True,
        overtime_per_minute=1.0,
        late_deduction_enabled=True,
        late_deduction_per_minute=1.0,
    )
    att_policy = SimpleNamespace(
        breaktime_is_paid=True,
        overtime_enabled=True,
        overtime_minimum_minutes=30,
        on_time_grace_minutes=10,
    )
    rest_policy = SimpleNamespace(rest_day_premium_percent=0.0)
    business = Business(id=business_id, timezone="Asia/Manila")
    db = MagicMock()

    def get_side_effect(model, key=None):
        if model is BusinessPayrollConfig:
            return config
        if model is Business:
            return business
        if model is BusinessAttendancePolicy:
            return att_policy
        if model is BusinessRestDayPolicy:
            return rest_policy
        return None

    db.get.side_effect = get_side_effect

    def query(*models):
        model = models[0] if models else None
        q = MagicMock()
        if model is PayrollRun:
            q.filter.return_value.first.return_value = existing_run
        elif model is Employee:
            q.filter.return_value.order_by.return_value.all.return_value = employees
            q.filter.return_value.all.return_value = []
        else:
            q.filter.return_value.first.return_value = None
            q.filter.return_value.all.return_value = []
        return q

    db.query.side_effect = query
    captured = {"added": []}

    def add_side_effect(obj):
        captured["added"].append(obj)
        if isinstance(obj, PayrollRun):
            obj.id = uuid4()
            captured["run"] = obj
        if isinstance(obj, Payslip):
            obj.id = uuid4()
            captured.setdefault("payslips", []).append(obj)

    db.add.side_effect = add_side_effect
    return db, _finalize_user(business_id), captured


def _run_finalize(db, user, *, slips_by_employee, adjustments=None):
    from app.api.owner_reports import finalize_payroll

    def calculate(_db, employee, _start, _end):
        return slips_by_employee[employee.id]

    with (
        patch(
            "app.api.owner_reports.resolve_pay_period",
            return_value=(date(2026, 8, 1), date(2026, 8, 15)),
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
            "app.api.owner_reports._calculate_employee_payslip",
            side_effect=calculate,
        ),
        patch(
            "app.services.payroll_snapshot.list_active_adjustments_for_employees",
            return_value=adjustments or {},
        ),
    ):
        return finalize_payroll(db=db, user=user, as_of=date(2026, 8, 10))


def test_payslip_summary_uses_existing_live_fields():
    employee_id = uuid4()
    slip = _slip(employee_id=employee_id, name="Ana", final_net_pay=741.26)
    summary = payslip_summary_values(slip)
    assert summary["regular_hours"] == 8.0
    assert summary["overtime_hours"] == 0.51
    assert summary["gross_pay"] == 760.48
    assert summary["total_deductions"] == 19.22
    assert summary["net_pay"] == 741.26


def test_freeze_payslip_dict_keeps_live_values_and_versions():
    employee_id = uuid4()
    slip = _slip(
        employee_id=employee_id,
        name="Ana",
        final_net_pay=741.26,
        payroll_adjustments=[{"display_name": "Meal Allowance", "amount": 50}],
        payroll_adjustments_allowance_total=50.0,
        payroll_adjustments_deduction_total=0.0,
        base_net_pay=741.26,
    )
    frozen = freeze_payslip_dict(slip)
    assert frozen["snapshot_version"] == PAYSLIP_SNAPSHOT_VERSION
    assert frozen["hours_worked"] == 8.0
    assert frozen["overtime_hours"] == 0.51
    assert frozen["overtime_pay"] == 30.48
    assert frozen["late_deductions"] == 19.22
    assert frozen["undertime_deductions"] == 0.0
    assert frozen["gross_pay"] == 760.48
    assert frozen["final_net_pay"] == 741.26
    assert frozen["payroll_adjustments"][0]["amount"] == 50
    assert frozen["employee_id"] == str(employee_id)


def test_finalize_creates_payslip_snapshots():
    employee = _employee(name="Ana")
    live = _slip(employee_id=employee.id, name="Ana", final_net_pay=741.26)
    db, user, captured = _db_for_finalize(employees=[employee])
    result = _run_finalize(db, user, slips_by_employee={employee.id: live})

    assert result["status"] == "finalized"
    assert db.commit.called
    run = captured["run"]
    assert isinstance(run, PayrollRun)
    assert run.snapshot_version == PAYSLIP_SNAPSHOT_VERSION
    assert run.calculation_config_json["enable_late_overtime_balancing"] is True
    assert run.calculation_config_json["breaktime_is_paid"] is True
    payslips = captured.get("payslips", [])
    assert len(payslips) == 1
    row = payslips[0]
    assert row.payroll_run_id == run.id
    assert row.employee_id == employee.id
    assert float(row.regular_hours) == 8.0
    assert float(row.overtime_hours) == 0.51
    assert float(row.gross_pay) == 760.48
    assert float(row.total_deductions) == 19.22
    assert float(row.net_pay) == 741.26
    assert row.breakdown_json["hours_worked"] == 8.0
    assert row.breakdown_json["snapshot_version"] == PAYSLIP_SNAPSHOT_VERSION


def test_snapshot_matches_live_calculation_before_finalize():
    employee = _employee(name="Ana")
    allowance = SimpleNamespace(
        id=uuid4(),
        employee_id=employee.id,
        period_start=date(2026, 8, 1),
        period_end=date(2026, 8, 15),
        kind="allowance",
        type_key="meal_allowance",
        custom_name=None,
        description=None,
        amount=50.0,
        created_by=None,
        created_at=None,
        updated_by=None,
        updated_at=None,
        previous_amount=None,
    )
    live = _slip(employee_id=employee.id, name="Ana")
    db, user, captured = _db_for_finalize(employees=[employee])
    _run_finalize(
        db,
        user,
        slips_by_employee={employee.id: live},
        adjustments={employee.id: [allowance]},
    )
    row = captured["payslips"][0]
    frozen = row.breakdown_json
    assert frozen["hours_worked"] == live["hours_worked"]
    assert frozen["overtime_hours"] == live["overtime_hours"]
    assert frozen["overtime_pay"] == live["overtime_pay"]
    assert frozen["late_deductions"] == live["late_deductions"]
    assert frozen["undertime_deductions"] == live["undertime_deductions"]
    assert frozen["gross_pay"] == live["gross_pay"]
    assert frozen["base_net_pay"] == live["net_pay"]
    assert frozen["final_net_pay"] == 791.26
    assert frozen["payroll_adjustments_allowance_total"] == 50.0
    assert float(row.net_pay) == 791.26


def test_finalize_two_employees_creates_two_payslips():
    ana = _employee(name="Ana")
    ben = _employee(name="Ben")
    ben.business_id = ana.business_id
    ana_slip = _slip(employee_id=ana.id, name="Ana", final_net_pay=741.26)
    ben_slip = _slip(
        employee_id=ben.id,
        name="Ben",
        hours_worked=7.5,
        overtime_hours=0.0,
        overtime_pay=0.0,
        late_deductions=0.0,
        deductions=0.0,
        gross_pay=730.0,
        net_pay=730.0,
        final_net_pay=730.0,
    )
    db, user, captured = _db_for_finalize(employees=[ana, ben])
    _run_finalize(
        db,
        user,
        slips_by_employee={ana.id: ana_slip, ben.id: ben_slip},
    )
    runs = [obj for obj in captured["added"] if isinstance(obj, PayrollRun)]
    payslips = captured.get("payslips", [])
    assert len(runs) == 1
    assert len(payslips) == 2
    by_name = {row.breakdown_json["employee_name"]: row for row in payslips}
    assert float(by_name["Ana"].net_pay) == 741.26
    assert float(by_name["Ben"].net_pay) == 730.0
    assert by_name["Ana"].payroll_run_id == runs[0].id
    assert by_name["Ben"].payroll_run_id == runs[0].id


def test_finalize_same_period_does_not_duplicate_payslips():
    employee = _employee(name="Ana")
    live = _slip(employee_id=employee.id, name="Ana", final_net_pay=741.26)
    db, user, captured = _db_for_finalize(employees=[employee])
    first = _run_finalize(db, user, slips_by_employee={employee.id: live})
    existing = captured["run"]
    db2, user2, captured2 = _db_for_finalize(
        employees=[employee], existing_run=existing
    )
    second = _run_finalize(db2, user2, slips_by_employee={employee.id: live})
    assert first["status"] == "finalized"
    assert second["status"] == "already_finalized"
    assert second["payroll_run_id"] == str(existing.id)
    assert captured2.get("payslips") is None
    assert db2.commit.called is False


def test_snapshot_failure_rolls_back_payroll_run():
    employee = _employee(name="Ana")
    live = _slip(employee_id=employee.id, name="Ana", final_net_pay=741.26)
    db, user, captured = _db_for_finalize(employees=[employee])

    def fail_snapshots(*_args, **_kwargs):
        raise RuntimeError("snapshot write failed")

    with (
        patch(
            "app.api.owner_reports.resolve_pay_period",
            return_value=(date(2026, 8, 1), date(2026, 8, 15)),
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
            "app.api.owner_reports._calculate_employee_payslip",
            return_value=live,
        ),
        patch(
            "app.api.owner_reports.create_finalized_payslip_snapshots",
            side_effect=fail_snapshots,
        ),
    ):
        with pytest.raises(RuntimeError, match="snapshot write failed"):
            from app.api.owner_reports import finalize_payroll

            finalize_payroll(db=db, user=user, as_of=date(2026, 8, 10))

    assert db.commit.called is False
    assert db.rollback.called
    assert captured.get("payslips") is None


def test_delete_employee_does_not_delete_payslip_snapshots():
    from app.api.employees import delete_employee
    from app.models.employee import Employee

    business_id = uuid4()
    employee = SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        user_id=uuid4(),
        is_active=True,
    )
    linked_user = SimpleNamespace(id=employee.user_id, is_active=True)
    owner = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    deleted_models = []

    def query(model):
        q = MagicMock()

        def _delete(**_kwargs):
            deleted_models.append(model)
            return 1

        q.filter.return_value.delete.side_effect = _delete
        return q

    db.query.side_effect = query
    with patch(
        "app.api.employees._get_business_employee",
        return_value=(employee, linked_user),
    ):
        result = delete_employee(
            employee_id=employee.id, db=db, user=owner
        )
    assert result["status"] == "ok"
    assert Payslip not in deleted_models
    assert Employee not in deleted_models
    db.delete.assert_any_call(employee)


def test_payslip_employee_id_is_nullable_for_set_null_fk():
    column = Payslip.__table__.c.employee_id
    assert column.nullable is True
    fks = list(column.foreign_keys)
    assert fks
    assert fks[0].ondelete == "SET NULL"


def test_payslip_row_from_slip_does_not_recalculate():
    employee_id = uuid4()
    slip = _slip(
        employee_id=employee_id,
        name="Ana",
        hours_worked=9.05,
        overtime_hours=0.51,
        overtime_pay=30.48,
        gross_pay=760.48,
        deductions=29.22,
        final_net_pay=731.26,
    )
    run_id = uuid4()
    row = payslip_row_from_slip(
        payroll_run_id=run_id, employee_id=employee_id, slip=slip
    )
    assert row.regular_hours == 9.05
    assert row.overtime_hours == 0.51
    assert row.gross_pay == 760.48
    assert row.total_deductions == 29.22
    assert row.net_pay == 731.26
    assert row.breakdown_json["overtime_pay"] == 30.48
    assert "hours_worked" in row.breakdown_json
