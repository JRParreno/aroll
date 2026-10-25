"""Business leave allowances, calendar-day balances, and advance notice."""

import inspect
import uuid
from datetime import date, datetime, time
from unittest.mock import patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.api.owner_reports import _calculate_employee_payslip
from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.attendance import AttendanceRecord
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import (
    EmployeeStatus,
    EmploymentType,
    HolidayType,
    LeaveRequestStatus,
    LeaveType,
    UserRole,
)
from app.models.holiday import Holiday
from app.models.leave_allowance import BusinessLeaveAllowance
from app.models.leave_entitlement import EmployeeLeaveEntitlement
from app.models.leave_policy import BusinessLeavePolicy
from app.models.leave_request import LeaveRequest
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.schemas.schedule_reuse import ScheduleConflictMode, ScheduleReuseSource
from app.services.leave_entitlements import list_balances, request_balance_preview
from app.services.leave_policy import replace_leave_allowances
from app.services.leave_requests import (
    approve_leave_cancellation,
    approve_leave_request,
    cancel_leave_request,
    create_leave_request,
    edit_leave_request,
    reject_leave_request,
)
from app.services.schedule_reuse import apply_reuse, build_preview


@pytest.fixture(autouse=True)
def _schedule_clock_before_leave_assignment_dates(monkeypatch):
    """Leave assignment fixtures use September 2026 dates.

    Freeze only the schedule-window clock so those tests still exercise
    leave conflicts. Other "today" calculations keep the real clock.
    """
    monkeypatch.setattr(
        "app.services.schedule_overlap.business_now",
        lambda tz_name: datetime(2026, 9, 1, 8, 0),
    )


def _headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


def _item(balances: list[dict], leave_type: str) -> dict:
    return next(row for row in balances if row["leave_type"] == leave_type)


class World:
    def __init__(self) -> None:
        self.db = SessionLocal()
        self.business = Business(
            business_code=f"LV-{uuid.uuid4().hex[:6].upper()}",
            name="Leave Entitlement Biz",
            timezone="Asia/Manila",
        )
        self.db.add(self.business)
        self.db.flush()
        self.owner = User(
            business_id=self.business.id,
            email=f"owner-{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("OwnerPass123!"),
            role=UserRole.owner,
            must_change_password=False,
            is_active=True,
        )
        self.db.add(self.owner)
        self.employee_user = User(
            business_id=self.business.id,
            email=f"emp-{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("EmpPass123!"),
            role=UserRole.employee,
            must_change_password=False,
            is_active=True,
        )
        self.db.add(self.employee_user)
        self.db.flush()
        self.employee = Employee(
            business_id=self.business.id,
            user_id=self.employee_user.id,
            full_name="Maria Santos",
            employment_type=EmploymentType.full_time,
            status=EmployeeStatus.active,
            is_active=True,
        )
        self.db.add(self.employee)
        self.db.flush()
        self.shift = Shift(
            business_id=self.business.id,
            name="Day",
            start_time=time(9, 0),
            end_time=time(17, 0),
        )
        self.db.add(self.shift)
        self.db.commit()

    def close(self) -> None:
        self.db.close()

    def assign(self, *work_dates: date, shift: Shift | None = None) -> None:
        chosen = shift or self.shift
        for work_date in work_dates:
            self.db.add(
                ShiftAssignment(
                    shift_id=chosen.id,
                    employee_id=self.employee.id,
                    work_date=work_date,
                )
            )
        self.db.commit()

    def set_allowance(
        self,
        leave_type: LeaveType,
        year: int,
        days: int | None,
        *,
        enabled: bool = True,
    ) -> None:
        replace_leave_allowances(
            self.db,
            business_id=self.business.id,
            year=year,
            items=[
                {
                    "leave_type": leave_type,
                    "enabled": enabled,
                    "allowance_days": days if enabled else None,
                }
            ],
            actor=self.owner,
        )

    def balances(self, year: int) -> list[dict]:
        return list_balances(self.db, employee_id=self.employee.id, year=year)

    def request(
        self,
        leave_type: LeaveType,
        start: date,
        end: date,
        *,
        reason: str = "Family trip",
    ) -> LeaveRequest:
        return create_leave_request(
            self.db,
            employee=self.employee,
            business_id=self.business.id,
            leave_type=leave_type,
            start_date=start,
            end_date=end,
            reason=reason,
            supporting_document=None,
            actor=self.employee_user,
        )

    def approve(self, request: LeaveRequest) -> LeaveRequest:
        return approve_leave_request(
            self.db,
            request=request,
            reviewer=self.owner,
            remarks=None,
        )


def test_create_entitlement_and_prevent_duplicates():
    world = World()
    try:
        replace_leave_allowances(
            world.db,
            business_id=world.business.id,
            year=2026,
            items=[
                {
                    "leave_type": LeaveType.vacation,
                    "enabled": True,
                    "allowance_days": 15,
                }
            ],
            actor=world.owner,
        )
        saved = list_balances(world.db, employee_id=world.employee.id, year=2026)
        vacation = _item(saved, "vacation")
        assert vacation["allocated_days"] == 15
        assert vacation["used_days"] == 0
        assert vacation["remaining_days"] == 15
        assert vacation["configured"] is True

        replace_leave_allowances(
            world.db,
            business_id=world.business.id,
            year=2026,
            items=[
                {
                    "leave_type": LeaveType.vacation,
                    "enabled": True,
                    "allowance_days": 12,
                }
            ],
            actor=world.owner,
        )
        updated = list_balances(world.db, employee_id=world.employee.id, year=2026)
        assert _item(updated, "vacation")["allocated_days"] == 12
        count = (
            world.db.query(BusinessLeaveAllowance)
            .filter(
                BusinessLeaveAllowance.business_id == world.business.id,
                BusinessLeaveAllowance.leave_type == LeaveType.vacation,
                BusinessLeaveAllowance.year == 2026,
            )
            .count()
        )
        assert count == 1
        assert (
            world.db.query(EmployeeLeaveEntitlement)
            .filter(EmployeeLeaveEntitlement.business_id == world.business.id)
            .count()
            == 0
        )

        world.db.add(
            BusinessLeaveAllowance(
                business_id=world.business.id,
                leave_type=LeaveType.vacation,
                year=2026,
                enabled=True,
                allowance_days=1,
            )
        )
        with pytest.raises(IntegrityError):
            world.db.commit()
        world.db.rollback()
    finally:
        world.close()


def test_owner_can_manage_and_employee_sees_only_own_balance():
    world = World()
    client = TestClient(app)
    try:
        other_user = User(
            business_id=world.business.id,
            email=f"emp2-{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("EmpPass123!"),
            role=UserRole.employee,
            must_change_password=False,
            is_active=True,
        )
        world.db.add(other_user)
        world.db.flush()
        other = Employee(
            business_id=world.business.id,
            user_id=other_user.id,
            full_name="Juan Cruz",
            employment_type=EmploymentType.full_time,
            status=EmployeeStatus.active,
            is_active=True,
        )
        world.db.add(other)
        world.db.commit()

        owner_headers = _headers(world.owner)
        saved = client.put(
            "/api/v1/businesses/me/leave-policy/allowances",
            json={
                "year": 2026,
                "items": [
                    {
                        "leave_type": "vacation",
                        "enabled": True,
                        "allowance_days": 15,
                    },
                    {"leave_type": "sick", "enabled": True, "allowance_days": 10},
                ],
            },
            headers=owner_headers,
        )
        assert saved.status_code == 200
        body = saved.json()
        assert _item(body["items"], "vacation")["allowance_days"] == 15
        assert _item(body["items"], "sick")["enabled"] is True

        listed = client.get(
            f"/api/v1/owner/employees/{world.employee.id}/leave-balances",
            params={"year": 2026},
            headers=owner_headers,
        )
        assert listed.status_code == 200
        assert listed.json()["employee_id"] == str(world.employee.id)

        denied = client.put(
            "/api/v1/businesses/me/leave-policy/allowances",
            json={
                "year": 2026,
                "items": [
                    {
                        "leave_type": "vacation",
                        "enabled": True,
                        "allowance_days": 1,
                    }
                ],
            },
            headers=_headers(world.employee_user),
        )
        assert denied.status_code == 403
        removed = client.put(
            f"/api/v1/owner/employees/{world.employee.id}/leave-entitlements",
            json={
                "year": 2026,
                "items": [{"leave_type": "vacation", "allocated_days": 1}],
            },
            headers=owner_headers,
        )
        assert removed.status_code == 404

        own = client.get(
            "/api/v1/employee/leave-balances",
            params={"year": 2026},
            headers=_headers(world.employee_user),
        )
        assert own.status_code == 200
        assert own.json()["employee_id"] == str(world.employee.id)
        assert _item(own.json()["items"], "vacation")["allocated_days"] == 15

        other_view = client.get(
            "/api/v1/employee/leave-balances",
            params={"year": 2026},
            headers=_headers(other_user),
        )
        assert other_view.status_code == 200
        assert other_view.json()["employee_id"] == str(other.id)
        shared = _item(other_view.json()["items"], "vacation")
        assert shared["configured"] is True
        assert shared["allocated_days"] == 15
        assert shared["used_days"] == 0
    finally:
        world.close()


def test_pending_and_rejected_do_not_consume_approved_does():
    world = World()
    try:
        world.set_allowance(LeaveType.vacation, 2026, 15)
        world.assign(date(2026, 10, 2), date(2026, 10, 5))
        pending = world.request(LeaveType.vacation, date(2026, 10, 2), date(2026, 10, 5))
        assert _item(world.balances(2026), "vacation")["used_days"] == 0
        assert _item(world.balances(2026), "vacation")["remaining_days"] == 15

        rejected = world.request(
            LeaveType.sick, date(2026, 10, 6), date(2026, 10, 6), reason="Fever today"
        )
        world.assign(date(2026, 10, 6))
        world.set_allowance(LeaveType.sick, 2026, 10)
        reject_leave_request(
            world.db, request=rejected, reviewer=world.owner, remarks=None
        )
        assert _item(world.balances(2026), "sick")["used_days"] == 0

        world.approve(pending)
        vacation = _item(world.balances(2026), "vacation")
        assert vacation["used_days"] == 4
        assert vacation["remaining_days"] == 11
    finally:
        world.close()


def test_cancellation_and_edit_release_then_reapproval_consumes():
    world = World()
    try:
        world.set_allowance(LeaveType.vacation, 2026, 15)
        world.assign(date(2026, 10, 7), date(2026, 10, 8), date(2026, 10, 9))
        first = world.approve(
            world.request(LeaveType.vacation, date(2026, 10, 7), date(2026, 10, 8))
        )
        assert _item(world.balances(2026), "vacation")["used_days"] == 2

        waiting = cancel_leave_request(
            world.db, request=first, employee=world.employee, actor=world.employee_user
        )
        assert waiting.status == LeaveRequestStatus.cancellation_pending
        assert _item(world.balances(2026), "vacation")["used_days"] == 2

        approve_leave_cancellation(
            world.db, request=waiting, reviewer=world.owner, remarks=None
        )
        assert _item(world.balances(2026), "vacation")["remaining_days"] == 15

        second = world.approve(
            world.request(LeaveType.vacation, date(2026, 10, 7), date(2026, 10, 8))
        )
        assert _item(world.balances(2026), "vacation")["used_days"] == 2
        edited = edit_leave_request(
            world.db,
            request=second,
            employee=world.employee,
            leave_type=LeaveType.vacation,
            start_date=date(2026, 10, 9),
            end_date=date(2026, 10, 9),
            reason="Moved to Friday",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert edited.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "vacation")["used_days"] == 0
        world.approve(edited)
        assert _item(world.balances(2026), "vacation")["used_days"] == 1
        assert _item(world.balances(2026), "vacation")["remaining_days"] == 14
    finally:
        world.close()


def test_insufficient_balance_blocks_approval_and_second_request():
    world = World()
    try:
        world.set_allowance(LeaveType.vacation, 2026, 2)
        world.assign(
            date(2026, 10, 12),
            date(2026, 10, 13),
            date(2026, 10, 14),
            date(2026, 10, 15),
        )
        first = world.request(LeaveType.vacation, date(2026, 10, 12), date(2026, 10, 13))
        second = world.request(LeaveType.vacation, date(2026, 10, 14), date(2026, 10, 15))
        assert _item(world.balances(2026), "vacation")["used_days"] == 0
        world.approve(first)
        assert _item(world.balances(2026), "vacation")["remaining_days"] == 0
        with pytest.raises(HTTPException) as exc:
            world.approve(second)
        world.db.rollback()
        assert exc.value.status_code == 400
        assert "2026" in str(exc.value.detail)
        assert "Vacation" in str(exc.value.detail)
        world.db.refresh(second)
        assert second.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "vacation")["used_days"] == 2
    finally:
        world.close()


def test_calendar_days_count_weekends_holidays_and_shifts_once():
    world = World()
    try:
        evening = Shift(
            business_id=world.business.id,
            name="Evening",
            start_time=time(18, 0),
            end_time=time(22, 0),
        )
        world.db.add(evening)
        world.db.commit()
        friday = date(2026, 10, 2)
        monday = date(2026, 10, 5)
        world.assign(friday)
        world.assign(friday, shift=evening)
        world.assign(monday)
        holiday = date(2026, 10, 6)
        world.db.add(
            Holiday(
                business_id=world.business.id,
                name="Unscheduled Holiday",
                holiday_date=holiday,
                is_paid=True,
                pay_multiplier=2,
                holiday_type=HolidayType.company,
            )
        )
        scheduled_holiday = date(2026, 10, 7)
        world.db.add(
            Holiday(
                business_id=world.business.id,
                name="Scheduled Holiday",
                holiday_date=scheduled_holiday,
                is_paid=True,
                pay_multiplier=2,
                holiday_type=HolidayType.company,
            )
        )
        world.db.commit()
        world.assign(scheduled_holiday)
        world.set_allowance(LeaveType.vacation, 2026, 10)
        world.set_allowance(LeaveType.sick, 2026, 5)
        world.set_allowance(LeaveType.emergency, 2026, 5)

        weekend_span = world.approve(
            world.request(LeaveType.vacation, friday, monday)
        )
        assert weekend_span.leave_days == 4
        assert _item(world.balances(2026), "vacation")["used_days"] == 4

        world.approve(
            world.request(LeaveType.sick, holiday, holiday, reason="Holiday off")
        )
        assert _item(world.balances(2026), "sick")["used_days"] == 1

        world.approve(
            world.request(
                LeaveType.emergency,
                scheduled_holiday,
                scheduled_holiday,
                reason="Scheduled holiday",
            )
        )
        assert _item(world.balances(2026), "emergency")["used_days"] == 1
    finally:
        world.close()


def test_cross_year_request_uses_each_year_entitlement():
    world = World()
    try:
        world.set_allowance(LeaveType.vacation, 2026, 10)
        world.set_allowance(LeaveType.vacation, 2027, 15)
        world.approve(
            world.request(LeaveType.vacation, date(2026, 12, 30), date(2027, 1, 2))
        )
        assert _item(world.balances(2026), "vacation")["used_days"] == 2
        assert _item(world.balances(2026), "vacation")["remaining_days"] == 8
        assert _item(world.balances(2027), "vacation")["used_days"] == 2
        assert _item(world.balances(2027), "vacation")["remaining_days"] == 13
    finally:
        world.close()


def test_advance_notice_blocks_and_allows_by_start_date():
    world = World()
    try:
        policy = BusinessLeavePolicy(
            business_id=world.business.id,
            treatments={},
            config_json={},
            minimum_advance_notice_days=3,
        )
        world.db.add(policy)
        world.db.commit()
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=date(2026, 9, 27),
        ):
            with pytest.raises(HTTPException) as too_soon:
                world.request(LeaveType.vacation, date(2026, 9, 28), date(2026, 9, 28))
            assert too_soon.value.status_code == 400
            assert "earliest start date is 2026-09-30" in str(too_soon.value.detail)
            created = world.request(
                LeaveType.vacation, date(2026, 9, 30), date(2026, 9, 30)
            )
            assert created.status == LeaveRequestStatus.pending
    finally:
        world.close()


_NOTICE_TODAY = date(2026, 9, 27)
_NON_EMERGENCY_TYPES = (
    LeaveType.sick,
    LeaveType.vacation,
    LeaveType.maternity,
    LeaveType.paternity,
    LeaveType.other,
)


def _require_three_day_notice(world: World) -> None:
    world.db.add(
        BusinessLeavePolicy(
            business_id=world.business.id,
            treatments={},
            config_json={},
            minimum_advance_notice_days=3,
        )
    )
    world.db.commit()


def _file(
    world: World,
    leave_type: LeaveType,
    start: date,
    end: date | None = None,
    *,
    reason: str = "Family trip",
) -> LeaveRequest:
    return create_leave_request(
        world.db,
        employee=world.employee,
        business_id=world.business.id,
        leave_type=leave_type,
        start_date=start,
        end_date=end or start,
        reason=reason,
        supporting_document=None,
        actor=world.employee_user,
        other_leave_specification=(
            "Bereavement Leave" if leave_type == LeaveType.other else None
        ),
    )


def test_emergency_is_exempt_from_advance_notice():
    world = World()
    try:
        _require_three_day_notice(world)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            for start in (
                date(2026, 9, 27),
                date(2026, 9, 28),
                date(2026, 9, 29),
                date(2026, 9, 30),
            ):
                created = _file(world, LeaveType.emergency, start)
                assert created.status == LeaveRequestStatus.pending
                assert created.is_paid is False
                assert created.policy_is_paid is False
    finally:
        world.close()


@pytest.mark.parametrize("leave_type", _NON_EMERGENCY_TYPES)
def test_non_emergency_tomorrow_still_requires_notice(leave_type: LeaveType):
    world = World()
    try:
        _require_three_day_notice(world)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            with pytest.raises(HTTPException) as exc:
                _file(world, leave_type, date(2026, 9, 28))
        assert exc.value.status_code == 400
        assert "earliest start date is 2026-09-30" in str(exc.value.detail)
    finally:
        world.close()


@pytest.mark.parametrize("leave_type", _NON_EMERGENCY_TYPES)
def test_non_emergency_three_days_out_is_allowed(leave_type: LeaveType):
    world = World()
    try:
        _require_three_day_notice(world)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            created = _file(world, leave_type, date(2026, 9, 30))
        assert created.status == LeaveRequestStatus.pending
    finally:
        world.close()


def test_emergency_preview_skips_notice_but_not_allowance():
    world = World()
    try:
        _require_three_day_notice(world)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            emergency = request_balance_preview(
                world.db,
                employee=world.employee,
                leave_type=LeaveType.emergency,
                start_date=date(2026, 9, 27),
                end_date=date(2026, 9, 27),
            )
            vacation = request_balance_preview(
                world.db,
                employee=world.employee,
                leave_type=LeaveType.vacation,
                start_date=date(2026, 9, 28),
                end_date=date(2026, 9, 28),
            )
        assert emergency["advance_notice_met"] is True
        assert emergency["balance_sufficient"] is False
        assert emergency["sufficient"] is False
        assert vacation["advance_notice_met"] is False
        assert vacation["sufficient"] is False
    finally:
        world.close()


def test_emergency_notice_exemption_still_blocks_disabled_type():
    world = World()
    try:
        _require_three_day_notice(world)
        world.set_allowance(LeaveType.emergency, 2026, None, enabled=False)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            with pytest.raises(HTTPException) as exc:
                _file(world, LeaveType.emergency, date(2026, 9, 27))
        assert exc.value.status_code == 400
        assert "not available in 2026" in str(exc.value.detail)
    finally:
        world.close()


def test_emergency_without_allowance_stays_pending_until_blocked_approval():
    world = World()
    try:
        _require_three_day_notice(world)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            created = _file(world, LeaveType.emergency, date(2026, 9, 27))
        assert created.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "emergency")["used_days"] == 0
        with pytest.raises(HTTPException) as exc:
            world.approve(created)
        world.db.rollback()
        assert "allowance is set" in str(exc.value.detail)
        world.db.refresh(created)
        assert created.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "emergency")["used_days"] == 0
    finally:
        world.close()


def test_emergency_insufficient_allowance_blocks_approval_only():
    world = World()
    try:
        _require_three_day_notice(world)
        world.set_allowance(LeaveType.emergency, 2026, 1)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            created = _file(
                world,
                LeaveType.emergency,
                date(2026, 9, 27),
                date(2026, 9, 28),
            )
        assert created.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "emergency")["used_days"] == 0
        with pytest.raises(HTTPException) as exc:
            world.approve(created)
        world.db.rollback()
        assert exc.value.status_code == 400
        assert "Not enough 2026" in str(exc.value.detail)
        world.db.refresh(created)
        assert created.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "emergency")["used_days"] == 0
    finally:
        world.close()


def test_approved_emergency_consumes_calendar_days():
    world = World()
    try:
        _require_three_day_notice(world)
        world.set_allowance(LeaveType.emergency, 2026, 3)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            created = _file(
                world,
                LeaveType.emergency,
                date(2026, 9, 27),
                date(2026, 9, 28),
            )
        assert created.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "emergency")["used_days"] == 0
        world.approve(created)
        assert created.status == LeaveRequestStatus.approved
        assert _item(world.balances(2026), "emergency")["used_days"] == 2
        assert _item(world.balances(2026), "emergency")["remaining_days"] == 1
    finally:
        world.close()


def test_editing_to_emergency_drops_notice_and_leaving_it_restores_notice():
    world = World()
    try:
        _require_three_day_notice(world)
        world.set_allowance(LeaveType.emergency, 2026, 5)
        world.set_allowance(LeaveType.vacation, 2026, 5)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            emergency = world.approve(
                _file(world, LeaveType.emergency, date(2026, 9, 30))
            )
            kept = edit_leave_request(
                world.db,
                request=emergency,
                employee=world.employee,
                leave_type=LeaveType.emergency,
                start_date=date(2026, 9, 27),
                end_date=date(2026, 9, 27),
                reason="Still an emergency",
                supporting_document=None,
                actor=world.employee_user,
            )
            assert kept.status == LeaveRequestStatus.pending
            assert kept.leave_type == LeaveType.emergency
            assert kept.start_date == date(2026, 9, 27)

            vacation = _file(world, LeaveType.vacation, date(2026, 10, 5))
            switched = edit_leave_request(
                world.db,
                request=vacation,
                employee=world.employee,
                leave_type=LeaveType.emergency,
                start_date=date(2026, 9, 28),
                end_date=date(2026, 9, 28),
                reason="This is now emergency",
                supporting_document=None,
                actor=world.employee_user,
            )
            assert switched.leave_type == LeaveType.emergency
            assert switched.start_date == date(2026, 9, 28)

            far_emergency = _file(world, LeaveType.emergency, date(2026, 10, 8))
            with pytest.raises(HTTPException) as exc:
                edit_leave_request(
                    world.db,
                    request=far_emergency,
                    employee=world.employee,
                    leave_type=LeaveType.vacation,
                    start_date=date(2026, 9, 28),
                    end_date=date(2026, 9, 28),
                    reason="Changed to vacation",
                    supporting_document=None,
                    actor=world.employee_user,
                )
        assert exc.value.status_code == 400
        assert "earliest start date is 2026-09-30" in str(exc.value.detail)
        world.db.refresh(far_emergency)
        assert far_emergency.leave_type == LeaveType.emergency
        assert far_emergency.start_date == date(2026, 10, 8)
    finally:
        world.close()


def test_emergency_still_rejects_short_reason_and_overlap():
    world = World()
    try:
        _require_three_day_notice(world)
        with patch(
            "app.services.leave_entitlements.business_today",
            return_value=_NOTICE_TODAY,
        ):
            with pytest.raises(HTTPException) as short_reason:
                _file(
                    world,
                    LeaveType.emergency,
                    date(2026, 9, 27),
                    reason="No",
                )
            assert short_reason.value.status_code == 400
            assert "short reason" in str(short_reason.value.detail)

            _file(world, LeaveType.emergency, date(2026, 9, 27))
            with pytest.raises(HTTPException) as overlap:
                _file(world, LeaveType.emergency, date(2026, 9, 27))
        assert overlap.value.status_code == 400
        assert "overlaps" in str(overlap.value.detail)
    finally:
        world.close()


def test_existing_approved_leave_counts_toward_balance():
    world = World()
    try:
        work_date = date(2026, 11, 2)
        historical = LeaveRequest(
            business_id=world.business.id,
            employee_id=world.employee.id,
            leave_type=LeaveType.vacation,
            start_date=work_date,
            end_date=work_date,
            leave_days=1,
            reason="Already approved before entitlements",
            status=LeaveRequestStatus.approved,
            policy_is_paid=True,
            is_paid=True,
            is_paid_overridden=False,
        )
        world.db.add(historical)
        world.db.commit()
        world.set_allowance(LeaveType.vacation, 2026, 10)
        vacation = _item(world.balances(2026), "vacation")
        assert vacation["used_days"] == 1
        assert vacation["remaining_days"] == 9
    finally:
        world.close()


def test_employee_specific_rows_are_ignored():
    world = World()
    try:
        world.db.add(
            EmployeeLeaveEntitlement(
                business_id=world.business.id,
                employee_id=world.employee.id,
                leave_type=LeaveType.vacation,
                year=2026,
                allocated_days=99,
            )
        )
        world.db.commit()
        vacation = _item(world.balances(2026), "vacation")
        assert vacation["configured"] is False
        assert vacation["enabled"] is False
        assert vacation["disabled"] is False
        assert vacation["allocated_days"] is None
    finally:
        world.close()


def test_disabled_type_blocks_new_use_and_keeps_history():
    world = World()
    try:
        work_date = date(2026, 11, 3)
        world.assign(work_date, date(2026, 11, 4))
        world.set_allowance(LeaveType.vacation, 2026, 10)
        historical = world.approve(
            world.request(LeaveType.vacation, work_date, work_date)
        )
        pending = world.request(
            LeaveType.vacation, date(2026, 11, 4), date(2026, 11, 4)
        )
        world.set_allowance(LeaveType.vacation, 2026, None, enabled=False)
        world.db.refresh(historical)
        assert historical.status == LeaveRequestStatus.approved
        assert _item(world.balances(2026), "vacation")["used_days"] == 1
        assert _item(world.balances(2026), "vacation")["disabled"] is True
        assert _item(world.balances(2026), "vacation")["configured"] is False

        with pytest.raises(HTTPException) as created:
            world.request(LeaveType.vacation, date(2026, 11, 5), date(2026, 11, 5))
        assert created.value.status_code == 400
        assert "not available in 2026" in str(created.value.detail)

        with pytest.raises(HTTPException) as approved:
            world.approve(pending)
        world.db.rollback()
        assert approved.value.status_code == 400
        world.db.refresh(pending)
        assert pending.status == LeaveRequestStatus.pending
        world.db.refresh(historical)
        assert historical.status == LeaveRequestStatus.approved
    finally:
        world.close()


def test_missing_allowance_blocks_scheduled_approval():
    world = World()
    try:
        world.assign(date(2026, 11, 6))
        pending = world.request(LeaveType.sick, date(2026, 11, 6), date(2026, 11, 6))
        sick = _item(world.balances(2026), "sick")
        assert sick["configured"] is False
        assert sick["disabled"] is False
        with pytest.raises(HTTPException) as exc:
            world.approve(pending)
        world.db.rollback()
        assert exc.value.status_code == 400
        assert "Leave Policy" in str(exc.value.detail)
        world.db.refresh(pending)
        assert pending.status == LeaveRequestStatus.pending
    finally:
        world.close()


def test_years_are_independent_and_cross_year_checks_each_year():
    world = World()
    try:
        world.set_allowance(LeaveType.vacation, 2026, 15)
        world.set_allowance(LeaveType.vacation, 2027, 18)
        assert _item(world.balances(2026), "vacation")["allocated_days"] == 15
        assert _item(world.balances(2027), "vacation")["allocated_days"] == 18
        world.set_allowance(LeaveType.vacation, 2027, 20)
        assert _item(world.balances(2026), "vacation")["allocated_days"] == 15
        assert _item(world.balances(2027), "vacation")["allocated_days"] == 20

        world.set_allowance(LeaveType.vacation, 2027, None, enabled=False)
        with pytest.raises(HTTPException) as blocked:
            world.request(LeaveType.vacation, date(2026, 12, 30), date(2027, 1, 2))
        assert blocked.value.status_code == 400
        assert "not available in 2027" in str(blocked.value.detail)
    finally:
        world.close()


def _activate_for_schedule(world: World) -> None:
    world.employee.face_registration_status = "completed"
    world.employee_user.must_change_password = False
    world.db.commit()


def test_no_schedule_leave_consumes_calendar_days():
    world = World()
    try:
        world.set_allowance(LeaveType.vacation, 2026, 15)
        created = world.request(
            LeaveType.vacation, date(2026, 9, 28), date(2026, 9, 30)
        )
        assert created.status == LeaveRequestStatus.pending
        assert created.leave_days == 3
        preview = request_balance_preview(
            world.db,
            employee=world.employee,
            leave_type=LeaveType.vacation,
            start_date=date(2026, 9, 28),
            end_date=date(2026, 9, 30),
        )
        assert preview["leave_days"] == 3
        assert preview["calendar_days"] == 3
        assert preview["years"][0]["leave_days"] == 3
        approved = world.approve(created)
        assert approved.status == LeaveRequestStatus.approved
        vacation = _item(world.balances(2026), "vacation")
        assert vacation["used_days"] == 3
        assert vacation["remaining_days"] == 12
        assert (
            world.db.query(AttendanceRecord)
            .filter(AttendanceRecord.employee_id == world.employee.id)
            .count()
            == 0
        )
        world.db.refresh(approved)
        assert approved.start_date == date(2026, 9, 28)
        assert approved.end_date == date(2026, 9, 30)
    finally:
        world.close()


def test_missing_allowance_blocks_approval_without_a_schedule():
    world = World()
    try:
        pending = world.request(LeaveType.sick, date(2026, 9, 28), date(2026, 9, 30))
        with pytest.raises(HTTPException) as exc:
            world.approve(pending)
        world.db.rollback()
        assert exc.value.status_code == 400
        assert "Leave Policy" in str(exc.value.detail)
        world.db.refresh(pending)
        assert pending.status == LeaveRequestStatus.pending
        assert _item(world.balances(2026), "sick")["used_days"] == 0
    finally:
        world.close()


def _assign_via_api(world: World, work_date: date, *, override_leave: bool = False):
    client = TestClient(app)
    payload = {
        "shift_id": str(world.shift.id),
        "work_date": work_date.isoformat(),
        "employee_ids": [str(world.employee.id)],
    }
    if override_leave:
        payload["override_leave"] = True
    return client.post(
        "/api/v1/schedules/assign",
        json=payload,
        headers=_headers(world.owner),
    )


def test_approved_leave_blocks_a_later_shift_assignment():
    world = World()
    try:
        _activate_for_schedule(world)
        world.set_allowance(LeaveType.vacation, 2026, 15)
        world.approve(
            world.request(LeaveType.vacation, date(2026, 9, 28), date(2026, 9, 30))
        )
        response = _assign_via_api(world, date(2026, 9, 29))
        assert response.status_code == 409
        assert response.json()["detail"]["code"] == "approved_leave"
        assert "approved leave" in response.json()["detail"]["message"]
        assert (
            world.db.query(ShiftAssignment)
            .filter(
                ShiftAssignment.employee_id == world.employee.id,
                ShiftAssignment.work_date == date(2026, 9, 29),
            )
            .count()
            == 0
        )
    finally:
        world.close()


def test_cancellation_pending_still_blocks_shift_assignment():
    world = World()
    try:
        _activate_for_schedule(world)
        world.set_allowance(LeaveType.vacation, 2026, 15)
        approved = world.approve(
            world.request(LeaveType.vacation, date(2026, 9, 29), date(2026, 9, 29))
        )
        waiting = cancel_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            actor=world.employee_user,
        )
        assert waiting.status == LeaveRequestStatus.cancellation_pending
        response = _assign_via_api(world, date(2026, 9, 29))
        assert response.status_code == 409
        assert response.json()["detail"]["code"] == "approved_leave"
        assert (
            world.db.query(ShiftAssignment)
            .filter(ShiftAssignment.employee_id == world.employee.id)
            .count()
            == 0
        )
    finally:
        world.close()


def test_override_leave_cannot_assign_during_protected_leave():
    world = World()
    try:
        _activate_for_schedule(world)
        world.set_allowance(LeaveType.vacation, 2026, 15)
        world.approve(
            world.request(LeaveType.vacation, date(2026, 9, 29), date(2026, 9, 29))
        )
        response = _assign_via_api(world, date(2026, 9, 29), override_leave=True)
        assert response.status_code == 409
        assert (
            world.db.query(ShiftAssignment)
            .filter(ShiftAssignment.employee_id == world.employee.id)
            .count()
            == 0
        )
    finally:
        world.close()


def test_schedule_reuse_skips_protected_leave_dates():
    world = World()
    try:
        _activate_for_schedule(world)
        world.set_allowance(LeaveType.vacation, 2026, 15)
        source_monday = date(2026, 9, 21)
        source_tuesday = date(2026, 9, 22)
        target_monday = date(2026, 9, 28)
        world.assign(source_monday, source_tuesday)
        world.approve(
            world.request(LeaveType.vacation, target_monday, target_monday)
        )
        preview = build_preview(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            target_monday,
        )
        leave_items = [
            item for item in preview.items if item.work_date == target_monday
        ]
        other_items = [
            item for item in preview.items if item.work_date == date(2026, 9, 29)
        ]
        assert leave_items
        assert leave_items[0].status == "conflict"
        assert "approved leave" in (leave_items[0].conflict_reason or "")
        assert other_items
        assert other_items[0].status == "new"
        result = apply_reuse(
            world.db,
            world.business.id,
            ScheduleReuseSource.previous_week,
            target_monday,
            ScheduleConflictMode.merge,
        )
        assert result.created == 1
        copied = (
            world.db.query(ShiftAssignment)
            .filter(ShiftAssignment.employee_id == world.employee.id)
            .all()
        )
        copied_dates = {row.work_date for row in copied}
        assert target_monday not in copied_dates
        assert date(2026, 9, 29) in copied_dates
    finally:
        world.close()


def test_updating_leave_policy_does_not_reset_allowances():
    world = World()
    client = TestClient(app)
    try:
        world.set_allowance(LeaveType.vacation, 2026, 15)
        world.set_allowance(LeaveType.sick, 2026, 10)
        owner_headers = _headers(world.owner)

        updated = client.put(
            "/api/v1/businesses/me/leave-policy",
            json={
                "treatments": {"vacation": False, "sick": True},
                "minimum_advance_notice_days": 3,
            },
            headers=owner_headers,
        )
        assert updated.status_code == 200
        assert updated.json()["treatments"]["vacation"] is False
        assert updated.json()["minimum_advance_notice_days"] == 3

        listed = client.get(
            "/api/v1/businesses/me/leave-policy/allowances",
            params={"year": 2026},
            headers=owner_headers,
        )
        assert listed.status_code == 200
        assert _item(listed.json()["items"], "vacation")["allowance_days"] == 15
        assert _item(listed.json()["items"], "vacation")["enabled"] is True
        assert _item(listed.json()["items"], "sick")["allowance_days"] == 10
        assert _item(listed.json()["items"], "sick")["enabled"] is True
    finally:
        world.close()


def test_entitlement_layer_does_not_change_payroll_calculation():
    source = inspect.getsource(_calculate_employee_payslip)
    assert "leave_entitlement" not in source
    assert "allocated_days" not in source
    assert "business_leave_allowance" not in source
    assert "allowance_days" not in source
    assert "leave_pay" in source
    assert "EmployeeLeaveEntitlement" not in source
