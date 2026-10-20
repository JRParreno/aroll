"""Unfinalize payroll: reopen a finalized snapshot without changing payroll math."""

from datetime import date
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.api.owner_reports import (
    payroll_report,
    unfinalize_payroll,
)
from app.models.enums import PayrollRunStatus, UserRole
from app.models.user import User
from app.services.payroll_snapshot import (
    load_period_payroll,
    mark_payroll_run_unfinalized,
    unfinalize_period_for_as_of,
)
from tests.test_payroll_finalize_snapshot import (
    _db_for_finalize,
    _employee as _finalize_employee,
    _run_finalize,
    _slip as _finalize_slip,
)
from tests.test_payroll_snapshot_retrieval import (
    FakeDB,
    _employee,
    _live_changed_slip,
    _row,
    _run,
    _slip,
)


def _owner(business_id, *, role=UserRole.owner):
    return User(
        id=uuid4(),
        business_id=business_id,
        role=role,
        is_active=True,
    )


def _unfinalize(db, user, as_of=date(2026, 9, 10)):
    with patch("app.api.owner_reports.add_log") as add_log:
        result = unfinalize_payroll(db=db, user=user, as_of=as_of)
    return result, add_log


def test_unfinalize_role_checker_rejects_non_owners():
    from app.core.deps import require_roles

    checker = require_roles(UserRole.owner)
    for role in (UserRole.manager, UserRole.employee):
        with pytest.raises(HTTPException) as exc:
            checker(_owner(uuid4(), role=role))
        assert exc.value.status_code == 403
        assert exc.value.detail == "Insufficient permissions"


def test_mark_payroll_run_unfinalized_uses_existing_cancelled_status():
    run = _run(business_id=uuid4())
    mark_payroll_run_unfinalized(run)
    assert run.status == PayrollRunStatus.cancelled


def test_owner_unfinalizes_own_finalized_payroll():
    employee = _employee(name="Ana")
    frozen = _slip(employee_id=employee.id, final_net_pay=741.26)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    owner = _owner(employee.business_id)

    result, add_log = _unfinalize(db, owner)

    assert result["status"] == "unfinalized"
    assert result["previous_status"] == "finalized"
    assert result["new_status"] == "open"
    assert result["payroll_run_id"] == str(run.id)
    assert run.status == PayrollRunStatus.cancelled
    assert db.committed is True
    add_log.assert_called_once()
    kwargs = add_log.call_args
    assert kwargs.kwargs["action"] == "payroll_unfinalized"
    assert kwargs.kwargs["previous_value"] == "finalized"
    assert kwargs.kwargs["new_value"] == "open"
    assert kwargs.args[1] == owner.id


def _auth_headers(user: User) -> dict[str, str]:
    from app.core.security import create_access_token

    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def test_manager_cannot_unfinalize_via_http():
    from fastapi.testclient import TestClient

    from app.main import app
    from tests.test_owner_business_apis import _create_business_with_users

    db, _business, _owner_user, manager = _create_business_with_users()
    client = TestClient(app)
    try:
        response = client.post(
            "/api/v1/owner/reports/payroll/unfinalize",
            params={"as_of": "2026-09-10"},
            headers=_auth_headers(manager),
        )
        assert response.status_code == 403
        assert response.json()["detail"] == "Insufficient permissions"
    finally:
        db.close()


def test_employee_cannot_unfinalize_via_http():
    from fastapi.testclient import TestClient

    from app.core.security import hash_password
    from app.main import app
    from tests.test_owner_business_apis import _create_business_with_users

    db, business, _owner_user, _manager = _create_business_with_users()
    employee_user = User(
        business_id=business.id,
        email=f"emp-{uuid4().hex[:8]}@example.com",
        password_hash=hash_password("EmpPass123!"),
        role=UserRole.employee,
        must_change_password=False,
        is_active=True,
    )
    db.add(employee_user)
    db.commit()
    db.refresh(employee_user)
    client = TestClient(app)
    try:
        response = client.post(
            "/api/v1/owner/reports/payroll/unfinalize",
            params={"as_of": "2026-09-10"},
            headers=_auth_headers(employee_user),
        )
        assert response.status_code == 403
    finally:
        db.close()


def test_other_business_cannot_unfinalize_foreign_payroll():
    employee = _employee(name="Ana")
    frozen = _slip(employee_id=employee.id)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    other = _owner(uuid4())

    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 1), date(2026, 9, 15)),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        _unfinalize(db, other)
    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "payroll_not_finalized"
    assert run.status == PayrollRunStatus.finalized
    assert db.committed is False
    assert db.rolled_back is True


def test_unfinalize_already_open_period_fails():
    employee = _employee()
    db = FakeDB()
    db.employees = [employee]
    owner = _owner(employee.business_id)
    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 1), date(2026, 9, 15)),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        _unfinalize(db, owner)
    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "payroll_not_finalized"
    assert db.rolled_back is True


def test_unfinalize_missing_payroll_returns_not_finalized():
    employee = _employee()
    cancelled = _run(business_id=employee.business_id)
    cancelled.status = PayrollRunStatus.cancelled
    db = FakeDB()
    db.runs = [cancelled]
    db.employees = [employee]
    owner = _owner(employee.business_id)
    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 1), date(2026, 9, 15)),
        ),
        pytest.raises(HTTPException) as exc,
    ):
        unfinalize_period_for_as_of(
            db, business_id=employee.business_id, as_of=date(2026, 9, 10)
        )
    assert exc.value.status_code == 400
    assert exc.value.detail["code"] == "payroll_not_finalized"


def test_unfinalize_does_not_delete_snapshot_rows():
    employee = _employee()
    frozen = _slip(employee_id=employee.id)
    run = _run(business_id=employee.business_id)
    row = _row(run=run, employee_id=employee.id, slip=frozen)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [row]
    db.employees = [employee]
    _unfinalize(db, _owner(employee.business_id))
    assert db.payslips == [row]
    assert row.payroll_run_id == run.id
    assert row.breakdown_json["hours_worked"] == 8.0


def test_owner_report_uses_live_calculation_after_unfinalize():
    employee = _employee(name="Ana")
    frozen = _slip(employee_id=employee.id, final_net_pay=741.26, gross_pay=760.48)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    owner = _owner(employee.business_id)
    live = _live_changed_slip(employee.id)
    calc = MagicMock(return_value=live)

    before = load_period_payroll(
        db,
        business_id=employee.business_id,
        as_of=date(2026, 9, 10),
        calculate_payslip=calc,
    )
    assert before.from_snapshot is True
    assert before.entries[0][1]["gross_pay"] == 760.48
    calc.assert_not_called()

    _unfinalize(db, owner)

    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 1), date(2026, 9, 15)),
        ),
        patch(
            "app.services.payroll_snapshot.list_active_adjustments_for_employees",
            return_value={},
        ),
    ):
        after = load_period_payroll(
            db,
            business_id=employee.business_id,
            as_of=date(2026, 9, 10),
            calculate_payslip=calc,
        )
    assert after.from_snapshot is False
    assert after.entries[0][1]["gross_pay"] == 900.0
    calc.assert_called()

    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 9, 1), date(2026, 9, 15)),
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
            "app.services.payroll_snapshot.list_active_adjustments_for_employees",
            return_value={},
        ),
        patch("app.api.owner_reports._calculate_employee_payslip", calc),
    ):
        report = payroll_report(db=db, user=owner, as_of=date(2026, 9, 10))
    assert report["is_finalized"] is False
    assert report["items"][0]["gross_pay"] == 900.0


def test_paula_post_finalize_attendance_appears_after_unfinalize_and_refinalize():
    """Completed attendance after an early finalize is included once reopened."""
    employee = _employee(name="Paula")
    frozen = _slip(
        employee_id=employee.id,
        name="Paula",
        hours_worked=2.62,
        gross_pay=300.0,
        net_pay=299.46,
        final_net_pay=299.46,
        attendance_records=[{"date": "2026-09-17", "earned": 300.0}],
    )
    run = _run(business_id=employee.business_id)
    run.period_start = date(2026, 8, 31)
    run.period_end = date(2026, 9, 30)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    db.employees = [employee]
    owner = _owner(employee.business_id)
    calc = MagicMock(return_value=frozen)

    loaded = load_period_payroll(
        db,
        business_id=employee.business_id,
        as_of=date(2026, 9, 18),
        calculate_payslip=calc,
    )
    assert loaded.from_snapshot is True
    dates = [row["date"] for row in loaded.entries[0][1]["attendance_records"]]
    assert "2026-09-18" not in dates
    calc.assert_not_called()

    _unfinalize(db, owner, as_of=date(2026, 9, 18))
    assert run.status == PayrollRunStatus.cancelled

    live = _slip(
        employee_id=employee.id,
        name="Paula",
        hours_worked=3.94,
        gross_pay=431.67,
        net_pay=431.67,
        final_net_pay=431.67,
        attendance_records=[
            {"date": "2026-09-17", "earned": 300.0},
            {"date": "2026-09-18", "earned": 131.67},
        ],
    )
    calc = MagicMock(return_value=live)
    with (
        patch(
            "app.services.payroll_snapshot.resolve_pay_period",
            return_value=(date(2026, 8, 31), date(2026, 9, 30)),
        ),
        patch(
            "app.services.payroll_snapshot.list_active_adjustments_for_employees",
            return_value={},
        ),
    ):
        reopened = load_period_payroll(
            db,
            business_id=employee.business_id,
            as_of=date(2026, 9, 18),
            calculate_payslip=calc,
        )
    assert reopened.from_snapshot is False
    live_dates = [row["date"] for row in reopened.entries[0][1]["attendance_records"]]
    assert "2026-09-18" in live_dates
    assert reopened.entries[0][1]["hours_worked"] == 3.94

    second = _run(business_id=employee.business_id)
    second.id = uuid4()
    second.period_start = date(2026, 8, 31)
    second.period_end = date(2026, 9, 30)
    second.created_at = date(2026, 9, 18)
    second.status = PayrollRunStatus.finalized
    db.runs.append(second)
    db.payslips.append(_row(run=second, employee_id=employee.id, slip=live))
    later = MagicMock(return_value=_live_changed_slip(employee.id))
    refrozen = load_period_payroll(
        db,
        business_id=employee.business_id,
        as_of=date(2026, 9, 18),
        calculate_payslip=later,
    )
    assert refrozen.from_snapshot is True
    assert refrozen.payroll_run.id == second.id
    refrozen_dates = [
        row["date"] for row in refrozen.entries[0][1]["attendance_records"]
    ]
    assert "2026-09-18" in refrozen_dates
    assert refrozen.entries[0][1]["hours_worked"] == 3.94
    later.assert_not_called()


def test_second_finalization_snapshot_is_immutable_to_later_live_changes():
    employee = _finalize_employee(name="Ana")
    live = _finalize_slip(employee_id=employee.id, name="Ana", final_net_pay=741.26)
    db, user, captured = _db_for_finalize(employees=[employee])
    first = _run_finalize(db, user, slips_by_employee={employee.id: live})
    assert first["status"] == "finalized"
    existing = captured["run"]

    existing.status = PayrollRunStatus.cancelled
    db2, user2, captured2 = _db_for_finalize(employees=[employee])
    second_live = _finalize_slip(
        employee_id=employee.id,
        name="Ana",
        hours_worked=9.05,
        overtime_hours=0.51,
        overtime_pay=30.48,
        gross_pay=860.48,
        net_pay=841.26,
        final_net_pay=841.26,
        attendance_records=[{"date": "2026-08-04", "earned": 730.0}],
    )
    second = _run_finalize(db2, user2, slips_by_employee={employee.id: second_live})
    assert second["status"] == "finalized"
    assert second["payroll_run_id"] != str(existing.id)
    row = captured2["payslips"][0]
    assert row.breakdown_json["hours_worked"] == 9.05
    assert row.breakdown_json["gross_pay"] == 860.48

    frozen_db = FakeDB()
    frozen_run = captured2["run"]
    frozen_db.runs = [existing, frozen_run]
    frozen_db.payslips = [row]
    frozen_db.employees = [employee]
    later = MagicMock(return_value=_live_changed_slip(employee.id))
    loaded = load_period_payroll(
        frozen_db,
        business_id=employee.business_id,
        as_of=date(2026, 8, 10),
        calculate_payslip=later,
    )
    assert loaded.from_snapshot is True
    assert loaded.entries[0][1]["hours_worked"] == 9.05
    later.assert_not_called()


def test_unfinalize_does_not_duplicate_adjustments_on_refinalize():
    employee = _finalize_employee(name="Ana")
    allowance = SimpleNamespace(
        id=uuid4(),
        employee_id=employee.id,
        period_start=date(2026, 8, 1),
        period_end=date(2026, 8, 15),
        kind="allowance",
        type_key="meal_allowance",
        custom_name=None,
        description=None,
        amount=500.0,
        created_by=None,
        created_at=None,
        updated_by=None,
        updated_at=None,
        previous_amount=None,
    )
    live = _finalize_slip(employee_id=employee.id, name="Ana")
    db, user, captured = _db_for_finalize(employees=[employee])
    first = _run_finalize(
        db,
        user,
        slips_by_employee={employee.id: live},
        adjustments={employee.id: [allowance]},
    )
    assert first["status"] == "finalized"
    first_row = captured["payslips"][0]
    assert first_row.breakdown_json["payroll_adjustments_allowance_total"] == 500.0
    assert first_row.breakdown_json["final_net_pay"] == 1241.26
    assert len(first_row.breakdown_json["payroll_adjustments"]) == 1

    captured["run"].status = PayrollRunStatus.cancelled
    db2, user2, captured2 = _db_for_finalize(employees=[employee])
    second = _run_finalize(
        db2,
        user2,
        slips_by_employee={employee.id: live},
        adjustments={employee.id: [allowance]},
    )
    assert second["status"] == "finalized"
    second_row = captured2["payslips"][0]
    assert second_row.breakdown_json["payroll_adjustments_allowance_total"] == 500.0
    assert second_row.breakdown_json["final_net_pay"] == 1241.26
    assert len(second_row.breakdown_json["payroll_adjustments"]) == 1
    assert second_row.breakdown_json["payroll_adjustments"][0]["amount"] == 500.0


def test_unfinalize_audit_log_does_not_store_pay_amounts():
    employee = _employee()
    frozen = _slip(employee_id=employee.id, final_net_pay=741.26)
    run = _run(business_id=employee.business_id)
    db = FakeDB()
    db.runs = [run]
    db.payslips = [_row(run=run, employee_id=employee.id, slip=frozen)]
    captured = {}

    def _capture_log(_db, user_id, action, description=None, **kwargs):
        captured.update(
            {
                "user_id": user_id,
                "action": action,
                "description": description,
                **kwargs,
            }
        )
        return SimpleNamespace(id=uuid4())

    with patch("app.api.owner_reports.add_log", side_effect=_capture_log):
        unfinalize_payroll(
            db=db,
            user=_owner(employee.business_id),
            as_of=date(2026, 9, 10),
        )
    assert captured["action"] == "payroll_unfinalized"
    blob = " ".join(str(value) for value in captured.values())
    assert "741.26" not in blob
    assert "760.48" not in blob
