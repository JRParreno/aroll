"""Cancellation-pending leave keeps its stored payroll treatment."""

from datetime import date, datetime, timezone

from app.api.owner_reports import _calculate_employee_payslip
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.attendance import AttendanceRecord
from app.models.enums import (
    AttendanceStatus,
    HolidayType,
    LeaveRequestStatus,
    LeaveType,
    PayBasis,
    PayrollRunStatus,
)
from app.models.holiday import Holiday
from app.models.payroll import PayrollRun
from app.services.leave_requests import (
    approve_leave_cancellation,
    approve_leave_request,
    cancel_leave_request,
    employee_on_approved_leave,
    employee_on_payroll_active_leave,
    reject_leave_cancellation,
)
from app.services.payroll_snapshot import (
    PAYSLIP_SNAPSHOT_VERSION,
    create_finalized_payslip_snapshots,
    load_period_payslip,
)
from test_leave_entitlements import World

WORK = date(2026, 9, 1)
PERIOD_START = date(2026, 9, 1)
PERIOD_END = date(2026, 9, 15)


def _daily(world: World) -> None:
    world.employee.pay_basis = PayBasis.daily
    world.employee.daily_rate = 800
    world.db.add(
        BusinessAttendancePolicy(
            business_id=world.business.id,
            on_time_grace_minutes=10,
            maximum_overtime_minutes=180,
        )
    )
    world.db.commit()
    world.set_allowance(LeaveType.vacation, 2026, 5)


def _holiday(world: World) -> None:
    world.db.add(
        Holiday(
            business_id=world.business.id,
            name="Regular Holiday",
            holiday_date=WORK,
            is_paid=True,
            pay_multiplier=2,
            holiday_type=HolidayType.regular,
            is_active=True,
        )
    )
    world.db.commit()


def _on_leave_count(world: World) -> int:
    return (
        world.db.query(AttendanceRecord)
        .filter(
            AttendanceRecord.employee_id == world.employee.id,
            AttendanceRecord.status == AttendanceStatus.on_leave,
        )
        .count()
    )


def _approve(world: World, *, paid: bool, assign_first: bool):
    if assign_first:
        world.assign(WORK)
    request = world.request(LeaveType.vacation, WORK, WORK)
    approved = approve_leave_request(
        world.db,
        request=request,
        reviewer=world.owner,
        remarks=None,
        is_paid=paid,
    )
    if not assign_first:
        world.assign(WORK)
    return approved


def _slip(world: World) -> dict:
    return _calculate_employee_payslip(
        world.db, world.employee, PERIOD_START, PERIOD_END
    )


def test_paid_cancellation_pending_with_on_leave_keeps_leave_pay_not_holiday():
    world = World()
    try:
        _daily(world)
        _holiday(world)
        approved = _approve(world, paid=True, assign_first=True)
        assert approved.is_paid is True
        assert _on_leave_count(world) == 1
        waiting = cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )
        assert waiting.status == LeaveRequestStatus.cancellation_pending
        assert waiting.is_paid is True
        assert _on_leave_count(world) == 1
        slip = _slip(world)
        assert slip["leave_pay"] == 800.0
        assert slip["holiday_pay"] == 0.0
        assert slip["regular_pay"] == 0.0
        assert slip["gross_pay"] == 800.0
        assert slip["paid_leave_days"] == 1
    finally:
        world.close()


def test_unpaid_cancellation_pending_with_on_leave_does_not_become_paid():
    world = World()
    try:
        _daily(world)
        _holiday(world)
        approved = _approve(world, paid=False, assign_first=True)
        assert approved.is_paid is False
        waiting = cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )
        assert waiting.is_paid is False
        assert employee_on_approved_leave(
            world.db, employee_id=world.employee.id, work_date=WORK
        ) is False
        assert employee_on_payroll_active_leave(
            world.db, employee_id=world.employee.id, work_date=WORK
        ) is True
        slip = _slip(world)
        assert slip["leave_pay"] == 0.0
        assert slip["holiday_pay"] == 0.0
        assert slip["regular_pay"] == 0.0
        assert slip["gross_pay"] == 0.0
        assert slip["paid_leave_days"] == 0
        assert slip["unpaid_leave_days"] == 1
    finally:
        world.close()


def test_paid_cancellation_pending_without_on_leave_still_pays_leave():
    world = World()
    try:
        _daily(world)
        approved = _approve(world, paid=True, assign_first=False)
        assert _on_leave_count(world) == 0
        cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )
        slip = _slip(world)
        assert slip["leave_pay"] == 800.0
        assert slip["regular_pay"] == 0.0
        assert slip["holiday_pay"] == 0.0
        assert slip["paid_leave_days"] == 1
        assert slip["absent_days"] == 0
    finally:
        world.close()


def test_unpaid_cancellation_pending_without_on_leave_pays_nothing():
    world = World()
    try:
        _daily(world)
        _holiday(world)
        approved = _approve(world, paid=False, assign_first=False)
        assert _on_leave_count(world) == 0
        cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )
        slip = _slip(world)
        assert slip["leave_pay"] == 0.0
        assert slip["holiday_pay"] == 0.0
        assert slip["regular_pay"] == 0.0
        assert slip["gross_pay"] == 0.0
        assert slip["paid_leave_days"] == 0
        assert slip["unpaid_leave_days"] == 1
        assert slip["absent_days"] == 0
    finally:
        world.close()


def test_approved_cancellation_stops_live_leave_pay():
    world = World()
    try:
        _daily(world)
        approved = _approve(world, paid=True, assign_first=True)
        waiting = cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )
        cancelled = approve_leave_cancellation(
            world.db, request=waiting, reviewer=world.owner, remarks=None
        )
        assert cancelled.status == LeaveRequestStatus.cancelled
        assert _on_leave_count(world) == 0
        slip = _slip(world)
        assert slip["leave_pay"] == 0.0
        assert slip["paid_leave_days"] == 0
        assert slip["holiday_pay"] == 0.0
    finally:
        world.close()


def test_rejected_cancellation_keeps_original_paid_and_unpaid_treatment():
    world = World()
    try:
        _daily(world)
        paid = _approve(world, paid=True, assign_first=True)
        waiting = cancel_leave_request(
            world.db, request=paid, employee=world.employee, actor=world.employee_user
        )
        restored = reject_leave_cancellation(
            world.db, request=waiting, reviewer=world.owner, remarks=None
        )
        assert restored.status == LeaveRequestStatus.approved
        assert restored.is_paid is True
        paid_slip = _slip(world)
        assert paid_slip["leave_pay"] == 800.0
        assert paid_slip["holiday_pay"] == 0.0

        world.set_allowance(LeaveType.sick, 2026, 5)
        world.assign(date(2026, 9, 2))
        sick = world.request(LeaveType.sick, date(2026, 9, 2), date(2026, 9, 2))
        unpaid = approve_leave_request(
            world.db,
            request=sick,
            reviewer=world.owner,
            remarks=None,
            is_paid=False,
        )
        waiting_unpaid = cancel_leave_request(
            world.db,
            request=unpaid,
            employee=world.employee,
            actor=world.employee_user,
        )
        restored_unpaid = reject_leave_cancellation(
            world.db, request=waiting_unpaid, reviewer=world.owner, remarks=None
        )
        assert restored_unpaid.status == LeaveRequestStatus.approved
        assert restored_unpaid.is_paid is False
        both = _slip(world)
        assert both["leave_pay"] == 800.0
        assert both["unpaid_leave_days"] == 1
        assert both["paid_leave_days"] == 1
    finally:
        world.close()


def test_finalized_payslip_ignores_later_cancellation_request():
    world = World()
    try:
        _daily(world)
        approved = _approve(world, paid=True, assign_first=True)
        live = _slip(world)
        assert live["leave_pay"] == 800.0
        run = PayrollRun(
            business_id=world.business.id,
            period_start=PERIOD_START,
            period_end=PERIOD_END,
            status=PayrollRunStatus.finalized,
            snapshot_version=PAYSLIP_SNAPSHOT_VERSION,
            finalized_at=datetime.now(timezone.utc),
            run_by=world.owner.id,
        )
        world.db.add(run)
        world.db.commit()
        world.db.refresh(run)
        create_finalized_payslip_snapshots(
            world.db,
            run=run,
            employees=[world.employee],
            period_start=PERIOD_START,
            period_end=PERIOD_END,
            calculate_payslip=_calculate_employee_payslip,
        )
        world.db.commit()
        cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )

        def _must_not_calculate(*_args, **_kwargs):
            raise AssertionError("finalized payslip was recalculated")

        loaded = load_period_payslip(
            world.db,
            world.employee,
            as_of=WORK,
            calculate_payslip=_must_not_calculate,
        )
        assert loaded.from_snapshot is True
        assert loaded.slip["leave_pay"] == 800.0
        assert loaded.slip["holiday_pay"] == 0.0
    finally:
        world.close()
