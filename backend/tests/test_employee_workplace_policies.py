"""Read-only employee workplace policy transparency."""

from fastapi.testclient import TestClient

from app.main import app
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.enums import MissingClockOutPolicy, OvertimeCalculationMethod
from app.models.payroll import BusinessPayrollConfig
from app.models.rest_day_policy import BusinessRestDayPolicy
from tests.test_legal_consent import _auth, _create_tenant


def test_employee_sees_own_business_policies_only():
    db, business, owner, employee_user, emp = _create_tenant()
    other_db, other_business, _other_owner, other_emp_user, other_emp = _create_tenant()
    client = TestClient(app)
    try:
        empty = client.get(
            "/api/v1/employee/workplace-policies",
            headers=_auth(employee_user),
        )
        assert empty.status_code == 200, empty.text
        body = empty.json()
        assert body["business_name"] == business.name
        assert body["attendance"] is None
        assert body["payroll"] is None
        assert body["rest_day"] is None
        assert body["your_pay"]["pay_basis"] in ("daily", "hourly", "monthly")

        denied = client.get(
            "/api/v1/employee/workplace-policies",
            headers=_auth(owner),
        )
        assert denied.status_code == 403

        db.add(
            BusinessAttendancePolicy(
                business_id=business.id,
                early_clock_in_minutes=20,
                on_time_grace_minutes=8,
                half_day_threshold_minutes=110,
                absent_threshold_minutes=220,
                absent_threshold_percent=30,
                half_day_threshold_percent=55,
                overtime_minimum_minutes=25,
                maximum_overtime_minutes=150,
                missing_clock_out_policy=MissingClockOutPolicy.auto_clock_out,
            )
        )
        db.add(
            BusinessPayrollConfig(
                business_id=business.id,
                late_deduction_enabled=True,
                late_deduction_per_minute=2.5,
                overtime_enabled=True,
                overtime_per_minute=3.25,
                overtime_calculation_method=OvertimeCalculationMethod.flat_per_minute,
                overtime_approval_required=True,
                enable_late_overtime_balancing=False,
            )
        )
        db.add(
            BusinessRestDayPolicy(
                business_id=business.id,
                rest_day_premium_percent=35,
            )
        )
        emp.daily_rate = 580
        emp.pay_basis = emp.pay_basis
        db.commit()

        other_db.add(
            BusinessPayrollConfig(
                business_id=other_business.id,
                late_deduction_per_minute=9.99,
                overtime_per_minute=9.99,
            )
        )
        other_emp.daily_rate = 10
        other_db.commit()

        shown = client.get(
            "/api/v1/employee/workplace-policies",
            headers=_auth(employee_user),
        )
        assert shown.status_code == 200, shown.text
        data = shown.json()
        assert data["attendance"]["early_clock_in_minutes"] == 20
        assert data["attendance"]["on_time_grace_minutes"] == 8
        assert data["payroll"]["late_deduction_per_minute"] == 2.5
        assert data["payroll"]["overtime_per_minute"] == 3.25
        assert data["payroll"]["overtime_approval_required"] is True
        assert data["rest_day"]["rest_day_premium_percent"] == 35
        assert data["your_pay"]["daily_rate"] == 580
        assert data["payroll"]["late_deduction_per_minute"] != 9.99

        other = client.get(
            "/api/v1/employee/workplace-policies",
            headers=_auth(other_emp_user),
        )
        assert other.status_code == 200
        assert other.json()["business_name"] == other_business.name
        assert other.json()["payroll"]["late_deduction_per_minute"] == 9.99
        assert other.json()["rest_day"] is None
        assert other.json()["your_pay"]["daily_rate"] == 10
    finally:
        db.close()
        other_db.close()


def test_disabled_overtime_hides_overtime_rate():
    db, _business, _owner, employee_user, emp = _create_tenant()
    client = TestClient(app)
    try:
        db.add(
            BusinessPayrollConfig(
                business_id=emp.business_id,
                overtime_enabled=False,
                overtime_per_minute=4.0,
                late_deduction_enabled=False,
                late_deduction_per_minute=1.5,
            )
        )
        db.commit()
        data = client.get(
            "/api/v1/employee/workplace-policies",
            headers=_auth(employee_user),
        ).json()
        assert data["payroll"]["overtime_enabled"] is False
        assert data["payroll"]["overtime_per_minute"] is None
        assert data["payroll"]["overtime_calculation_method"] is None
        assert data["payroll"]["late_deduction_enabled"] is False
        assert data["payroll"]["late_deduction_per_minute"] is None
    finally:
        db.close()
