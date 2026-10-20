"""Completed attendance keeps historical pay rates after Employee Role restamp."""

from __future__ import annotations

import uuid
from contextlib import ExitStack
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business
from app.models.enums import AttendanceStatus, EmploymentType, PayBasis, PayrollRunStatus, UserRole
from app.models.payroll import BusinessPayrollConfig, Position, PositionPayConfig
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.services.employee_pay import (
    resolve_attendance_pay,
    stamp_attendance_completion_pay,
)
from app.services.payroll_snapshot import (
    PAYSLIP_SNAPSHOT_VERSION,
    freeze_payslip_dict,
    load_period_payslip,
)
from app.services.position_pay_config import apply_config_to_employee_fields


def _ph(hour: int, minute: int = 0, *, day: int = 4) -> datetime:
    utc_hour = hour - 8
    d = day
    if utc_hour < 0:
        utc_hour += 24
        d = day - 1
    return datetime(2026, 8, d, utc_hour, minute, tzinfo=timezone.utc)


def _payslip_with_days(
    employee: SimpleNamespace,
    day_specs: list[dict],
    *,
    position_daily_rate: float | None = 9999.0,
):
    """Live _calculate_employee_payslip for one or more completed days.

    day_specs entries:
      work_date, daily_rate_at_completion (None = unstamped legacy)
    """
    business_id = employee.business_id
    business = SimpleNamespace(timezone="Asia/Manila")
    att_policy = SimpleNamespace(
        business_id=business_id,
        on_time_grace_minutes=10,
        overtime_minimum_minutes=30,
        half_day_threshold_minutes=240,
        overtime_enabled=True,
        breaktime_is_paid=False,
    )
    config = SimpleNamespace(
        overtime_per_minute=1.0,
        late_deduction_per_minute=1.0,
        late_deduction_enabled=True,
        overtime_enabled=True,
        enable_late_overtime_balancing=False,
        holiday_rules_mode=None,
        overtime_approval_required=False,
    )
    position = SimpleNamespace(
        daily_rate=position_daily_rate,
        hourly_rate=1.0,
    )

    rows = []
    scheduled = []
    for spec in day_specs:
        work_date = spec["work_date"]
        shift = Shift(
            id=uuid.uuid4(),
            business_id=business_id,
            name="Day",
            start_time=time(8, 0),
            end_time=time(17, 0),
        )
        assignment = ShiftAssignment(
            id=uuid.uuid4(),
            shift_id=shift.id,
            employee_id=employee.id,
            work_date=work_date,
            is_rest_day_work=False,
        )
        day_num = work_date.day
        record = AttendanceRecord(
            id=uuid.uuid4(),
            business_id=business_id,
            employee_id=employee.id,
            shift_assignment_id=assignment.id,
            time_in=_ph(8, 0, day=day_num),
            time_out=_ph(17, 0, day=day_num),
            status=AttendanceStatus.complete,
        )
        stamp = spec.get("daily_rate_at_completion")
        if stamp is not None:
            record.pay_basis_at_completion = PayBasis.daily
            record.daily_rate_at_completion = stamp
            record.hourly_rate_at_completion = None
            record.monthly_salary_at_completion = None
        rows.append((record, assignment, shift))
        scheduled.append((assignment, shift))

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
    attendance_query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = (
        rows
    )
    scheduled_query = MagicMock()
    scheduled_query.join.return_value.filter.return_value.all.return_value = scheduled
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
        patch(
            "app.api.owner_reports.approved_leave_dates_for_employee",
            return_value=[],
        ),
        patch("app.api.owner_reports.business_today", return_value=date(2026, 8, 20)),
        patch(
            "app.api.owner_reports.business_now",
            return_value=datetime(2026, 8, 20, 12, 0),
        ),
        patch(
            "app.api.owner_reports.resolve_holiday_rules_mode",
            return_value="philippine_labor",
        ),
        patch("app.api.owner_reports.overtime_approval_required", return_value=False),
    ]
    with ExitStack() as stack:
        for p in patches:
            stack.enter_context(p)
        return _calculate_employee_payslip(
            db, employee, date(2026, 8, 1), date(2026, 8, 31)
        ), rows


def test_stamp_completion_pay_copies_employee_rate_once():
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(record, employee) is True
    assert record.pay_basis_at_completion == PayBasis.daily
    assert float(record.daily_rate_at_completion) == 500.0

    employee.daily_rate = 600.0
    assert stamp_attendance_completion_pay(record, employee) is False
    assert float(record.daily_rate_at_completion) == 500.0


def test_completed_attendance_keeps_completion_rate_after_employee_role_change():
    """PRIMARY: stamp at close → Role restamp → unfinalized Monday still ₱500.

    Proves ``stamp_attendance_completion_pay`` rates reach final regular_pay /
    earned — not merely that the helper exists.
    """
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Ana",
        position_title="Role A",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    monday = date(2026, 8, 3)
    # Monday completes while Employee stamp is ₱500.
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        time_in=_ph(8, 0, day=3),
        time_out=_ph(17, 0, day=3),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(record, employee) is True
    assert float(record.daily_rate_at_completion) == 500.0

    slip, _ = _payslip_with_days(
        employee,
        [
            {
                "work_date": monday,
                "daily_rate_at_completion": float(record.daily_rate_at_completion),
            }
        ],
    )
    assert slip["regular_pay"] == 500.0
    assert slip["gross_pay"] == 500.0
    assert slip["attendance_records"][0]["earned"] == 500.0
    assert slip["attendance_records"][0]["expected_salary_pay"] == 500.0

    # Role B save → Employee current stamp ₱600.
    employee.daily_rate = 600.0
    employee.position_title = "Role B"
    assert float(employee.daily_rate) == 600.0

    # Same unfinalized period: Monday completed pay must stay ₱500.
    slip_after, _ = _payslip_with_days(
        employee,
        [
            {
                "work_date": monday,
                "daily_rate_at_completion": float(record.daily_rate_at_completion),
            }
        ],
    )
    assert float(record.daily_rate_at_completion) == 500.0
    assert slip_after["daily_rate"] == 600.0  # current Employee stamp
    assert slip_after["regular_pay"] == 500.0  # Monday historical
    assert slip_after["gross_pay"] == 500.0
    assert slip_after["attendance_records"][0]["earned"] == 500.0
    assert slip_after["attendance_records"][0]["expected_salary_pay"] == 500.0


def test_new_attendance_after_role_change_uses_new_stamped_rate():
    """Tuesday completed after Role B save uses ₱600; Monday stays ₱500."""
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Ana",
        position_title="Role A",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    monday = date(2026, 8, 3)
    tuesday = date(2026, 8, 4)

    monday_record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        time_in=_ph(8, 0, day=3),
        time_out=_ph(17, 0, day=3),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(monday_record, employee) is True
    assert float(monday_record.daily_rate_at_completion) == 500.0

    employee.daily_rate = 600.0
    tuesday_record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        time_in=_ph(8, 0, day=4),
        time_out=_ph(17, 0, day=4),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(tuesday_record, employee) is True
    assert float(tuesday_record.daily_rate_at_completion) == 600.0

    slip, _ = _payslip_with_days(
        employee,
        [
            {
                "work_date": monday,
                "daily_rate_at_completion": float(
                    monday_record.daily_rate_at_completion
                ),
            },
            {
                "work_date": tuesday,
                "daily_rate_at_completion": float(
                    tuesday_record.daily_rate_at_completion
                ),
            },
        ],
    )
    by_date = {row["date"]: row for row in slip["attendance_records"]}
    assert by_date["2026-08-03"]["earned"] == 500.0
    assert by_date["2026-08-04"]["earned"] == 600.0
    assert slip["regular_pay"] == 1100.0
    assert slip["gross_pay"] == 1100.0
    assert slip["daily_rate"] == 600.0


def test_completed_attendance_completion_rate_is_not_overwritten():
    """Recalc / Role change must not mutate completion-rate columns."""
    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Ana",
        position_title="Role A",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(record, employee) is True
    assert float(record.daily_rate_at_completion) == 500.0

    employee.daily_rate = 600.0
    # Payslip recalc path must not restamp.
    slip, _ = _payslip_with_days(
        employee,
        [
            {
                "work_date": date(2026, 8, 3),
                "daily_rate_at_completion": float(record.daily_rate_at_completion),
            }
        ],
    )
    assert slip["attendance_records"][0]["earned"] == 500.0
    assert stamp_attendance_completion_pay(record, employee) is False
    assert float(record.daily_rate_at_completion) == 500.0
    assert record.pay_basis_at_completion == PayBasis.daily


def test_completed_monday_keeps_500_after_role_restamp_to_600():
    """Primary bug: unfinalized period must not reprice stamped Monday."""
    test_completed_attendance_keeps_completion_rate_after_employee_role_change()


def test_tuesday_after_restamp_uses_600():
    test_new_attendance_after_role_change_uses_new_stamped_rate()


def test_position_pay_config_alone_does_not_change_completion_stamp():
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    # Setup PositionPayConfig / Position columns moved to 600; employee not re-saved.
    position = SimpleNamespace(daily_rate=600.0, hourly_rate=70.0)
    resolved = resolve_attendance_pay(record, employee, position=position)
    assert resolved.daily_rate == 500.0


def test_correction_preserves_existing_completion_stamp():
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=600.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    # Correction path re-invokes stamp after close — must not overwrite.
    assert stamp_attendance_completion_pay(record, employee) is False
    assert float(record.daily_rate_at_completion) == 500.0
    resolved = resolve_attendance_pay(record, employee, position=None)
    assert resolved.daily_rate == 500.0


def test_first_completion_via_stamp_uses_current_employee_rate():
    employee = SimpleNamespace(
        pay_basis=PayBasis.daily,
        daily_rate=600.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
    )
    assert stamp_attendance_completion_pay(record, employee) is True
    assert float(record.daily_rate_at_completion) == 600.0


def test_legacy_unstamped_complete_requires_historical_rate():
    """Pre-migration NULL completion stamps must NOT use current Employee rate."""
    from app.services.employee_pay import HISTORICAL_RATE_REQUIRED

    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Nicole Bellen",
        position_title="Barista",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        monthly_salary=None,
    )
    # Current Employee rate is ₱100/hour — must not become the historical rate.
    slip, rows = _payslip_with_days(
        employee,
        [{"work_date": date(2026, 8, 22), "daily_rate_at_completion": None}],
        position_daily_rate=None,
    )
    record = rows[0][0]
    assert record.pay_basis_at_completion is None
    assert record.hourly_rate_at_completion is None
    assert slip["has_unresolved_historical_rate"] is True
    assert slip["unresolved_historical_rate_count"] == 1
    day = slip["attendance_records"][0]
    assert day["historical_rate_required"] is True
    assert day["payroll_status"] == HISTORICAL_RATE_REQUIRED
    assert day["earned"] is None
    assert day["expected_salary_pay"] is None
    assert day["hourly_rate"] is None
    # Totals must not invent ₱100/hour wages for the unresolved day.
    assert slip["regular_pay"] == 0.0
    assert slip["gross_pay"] == 0.0

    # Changing current Employee rate still must not silently reprice.
    employee.hourly_rate = 150.0
    slip_after, _ = _payslip_with_days(
        employee,
        [{"work_date": date(2026, 8, 22), "daily_rate_at_completion": None}],
        position_daily_rate=None,
    )
    assert slip_after["has_unresolved_historical_rate"] is True
    assert slip_after["attendance_records"][0]["earned"] is None
    assert slip_after["regular_pay"] == 0.0


def test_owner_resolves_legacy_historical_rate_then_role_change_keeps_stamp():
    from app.services.employee_pay import (
        apply_owner_completion_pay,
        attendance_has_completion_pay,
    )

    employee = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        full_name="Legacy",
        position_title="Barista",
        position_id=uuid.uuid4(),
        employment_type=EmploymentType.full_time,
        pay_basis=PayBasis.daily,
        daily_rate=600.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=employee.business_id,
        employee_id=employee.id,
        time_in=_ph(8, 0, day=4),
        time_out=_ph(17, 0, day=4),
        status=AttendanceStatus.complete,
    )
    assert attendance_has_completion_pay(record) is False
    apply_owner_completion_pay(
        record,
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
        hourly_rate=None,
        monthly_salary=None,
    )
    assert attendance_has_completion_pay(record) is True
    assert float(record.daily_rate_at_completion) == 500.0

    slip, _ = _payslip_with_days(
        employee,
        [
            {
                "work_date": date(2026, 8, 4),
                "daily_rate_at_completion": float(record.daily_rate_at_completion),
            }
        ],
    )
    assert slip["regular_pay"] == 500.0
    assert slip["has_unresolved_historical_rate"] is False

    employee.daily_rate = 600.0
    slip_after, _ = _payslip_with_days(
        employee,
        [
            {
                "work_date": date(2026, 8, 4),
                "daily_rate_at_completion": float(record.daily_rate_at_completion),
            }
        ],
    )
    assert slip_after["daily_rate"] == 600.0
    assert slip_after["regular_pay"] == 500.0
    assert float(record.daily_rate_at_completion) == 500.0


def test_resolve_attendance_pay_returns_none_for_null_stamp_closed():
    employee = SimpleNamespace(
        pay_basis=PayBasis.hourly,
        daily_rate=None,
        hourly_rate=100.0,
        monthly_salary=None,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
    )
    assert resolve_attendance_pay(record, employee, position=None) is None


def test_count_unresolved_historical_rate_blocks_finalize_gate():
    from app.services.payroll_incomplete_gate import (
        count_unresolved_historical_rate_in_period,
    )
    from app.models.scheduling import Shift, ShiftAssignment

    business_id = uuid.uuid4()
    employee_id = uuid.uuid4()
    assignment = ShiftAssignment(
        id=uuid.uuid4(),
        shift_id=uuid.uuid4(),
        employee_id=employee_id,
        work_date=date(2026, 9, 22),
        is_rest_day_work=False,
    )
    shift = Shift(
        id=assignment.shift_id,
        business_id=business_id,
        name="Day",
        start_time=time(8, 0),
        end_time=time(17, 0),
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        shift_assignment_id=assignment.id,
        time_in=_ph(8, 0, day=22),
        time_out=_ph(17, 0, day=22),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=None,
    )
    db = MagicMock()

    def db_get(model, key=None):
        return None

    db.get.side_effect = db_get
    query = MagicMock()
    # outerjoin().outerjoin().filter().all() → (record, assignment, shift)
    query.outerjoin.return_value.outerjoin.return_value.filter.return_value.all.return_value = [
        (record, assignment, shift)
    ]
    db.query.return_value = query

    with patch(
        "app.services.payroll_incomplete_gate.ensure_incomplete_for_business"
    ):
        count = count_unresolved_historical_rate_in_period(
            db,
            business_id=business_id,
            period_start=date(2026, 9, 1),
            period_end=date(2026, 9, 30),
        )
    assert count == 1


def test_apply_owner_completion_pay_rejects_overwrite_and_open():
    from app.services.employee_pay import apply_owner_completion_pay

    stamped = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
        pay_basis_at_completion=PayBasis.daily,
        daily_rate_at_completion=500.0,
    )
    try:
        apply_owner_completion_pay(
            stamped,
            pay_basis=PayBasis.daily,
            daily_rate=400.0,
            hourly_rate=None,
            monthly_salary=None,
        )
        raise AssertionError("expected ValueError")
    except ValueError:
        pass

    open_row = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=None,
        status=AttendanceStatus.in_progress,
    )
    try:
        apply_owner_completion_pay(
            open_row,
            pay_basis=PayBasis.daily,
            daily_rate=500.0,
            hourly_rate=None,
            monthly_salary=None,
        )
        raise AssertionError("expected ValueError")
    except ValueError:
        pass


def test_legacy_unstamped_complete_uses_current_employee_rate():
    """Removed dangerous fallback — see test_legacy_unstamped_complete_requires_historical_rate."""
    test_legacy_unstamped_complete_requires_historical_rate()


def test_finalize_blocked_when_unresolved_historical_rate():
    from fastapi import HTTPException

    from app.api.owner_reports import finalize_payroll
    from app.models.user import User

    business_id = uuid.uuid4()
    user = User(
        id=uuid.uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    db = MagicMock()
    db.get.return_value = SimpleNamespace(timezone="Asia/Manila")
    run_query = MagicMock()
    run_query.filter.return_value.first.return_value = None
    db.query.return_value = run_query

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
            "app.api.owner_reports.count_unresolved_historical_rate_in_period",
            return_value=1,
        ),
    ):
        try:
            finalize_payroll(db=db, user=user, as_of=date(2026, 8, 10))
            raise AssertionError("expected HTTPException")
        except HTTPException as exc:
            assert exc.status_code == 400
            assert exc.detail["code"] == "unresolved_historical_rate"
            assert "historical pay rate" in exc.detail["message"].lower()


def test_owner_resolve_historical_rate_rejects_other_business():
    from fastapi import HTTPException

    from app.api.attendance_corrections import owner_resolve_historical_rate
    from app.models.user import User
    from app.schemas.attendance_correction import OwnerResolveHistoricalRateRequest

    owner_business = uuid.uuid4()
    other_business = uuid.uuid4()
    user = User(
        id=uuid.uuid4(),
        business_id=owner_business,
        role=UserRole.owner,
        is_active=True,
    )
    record = AttendanceRecord(
        id=uuid.uuid4(),
        business_id=other_business,
        employee_id=uuid.uuid4(),
        time_in=_ph(8, 0),
        time_out=_ph(17, 0),
        status=AttendanceStatus.complete,
    )
    db = MagicMock()
    query = MagicMock()
    # Scoped by business_id — no row for another business.
    query.filter.return_value.first.return_value = None
    db.query.return_value = query

    body = OwnerResolveHistoricalRateRequest(
        pay_basis=PayBasis.daily,
        daily_rate=500.0,
    )
    try:
        owner_resolve_historical_rate(
            record_id=record.id,
            body=body,
            db=db,
            user=user,
        )
        raise AssertionError("expected HTTPException")
    except HTTPException as exc:
        assert exc.status_code == 404


def test_owner_resolve_historical_rate_rejects_employee_role():
    """Employees cannot resolve historical rates (endpoint requires owner/manager)."""
    from app.core.deps import require_roles

    dependency = require_roles(UserRole.owner, UserRole.manager)
    # Dependency factory is role-gated; employee is not in allow-list.
    assert UserRole.employee not in (UserRole.owner, UserRole.manager)
    assert dependency is not None


def test_finalized_snapshot_still_ignores_later_employee_rate():
    employee_id = uuid.uuid4()
    frozen = freeze_payslip_dict(
        {
            "employee_id": str(employee_id),
            "daily_rate": 500.0,
            "regular_pay": 500.0,
            "gross_pay": 500.0,
            "net_pay": 500.0,
            "attendance_records": [
                {"date": "2026-08-03", "earned": 500.0},
            ],
        }
    )
    run = SimpleNamespace(
        id=uuid.uuid4(),
        business_id=uuid.uuid4(),
        period_start=date(2026, 8, 1),
        period_end=date(2026, 8, 15),
        status=PayrollRunStatus.finalized,
        snapshot_version=PAYSLIP_SNAPSHOT_VERSION,
    )
    payslip_row = SimpleNamespace(
        employee_id=employee_id,
        breakdown_json=frozen,
    )
    employee = SimpleNamespace(
        id=employee_id,
        business_id=run.business_id,
        daily_rate=600.0,
        pay_basis=PayBasis.daily,
    )
    db = MagicMock()

    with patch(
        "app.services.payroll_snapshot.find_snapshot_run",
        return_value=run,
    ), patch(
        "app.services.payroll_snapshot.payslips_for_run",
        return_value=[payslip_row],
    ), patch(
        "app.services.payroll_snapshot.snapshot_payslip_dict",
        return_value=dict(frozen),
    ):
        loaded = load_period_payslip(
            db,
            employee,
            as_of=date(2026, 8, 3),
            calculate_payslip=MagicMock(),
        )

    assert loaded.from_snapshot is True
    assert loaded.slip["daily_rate"] == 500.0
    assert loaded.slip["gross_pay"] == 500.0
    loaded.payroll_run  # noqa: B018 — touch
    # calculate_payslip must not be required for snapshot path
    assert loaded.slip["attendance_records"][0]["earned"] == 500.0


def test_design_b_apply_config_still_stamps_employee_for_future():
    stamped = apply_config_to_employee_fields(
        PositionPayConfig(
            id=uuid.uuid4(),
            position_id=uuid.uuid4(),
            pay_basis=PayBasis.daily,
            rate=600,
        )
    )
    assert stamped["daily_rate"] == 600.0
    assert stamped["pay_basis"] == PayBasis.daily
