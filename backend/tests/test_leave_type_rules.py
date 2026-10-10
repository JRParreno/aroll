"""New leave requests cannot use Unpaid. Other requires its own specification."""

from datetime import date

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import app
from app.models.enums import LeaveRequestStatus, LeaveType
from app.models.leave_allowance import BusinessLeaveAllowance
from app.models.leave_request import LeaveRequest
from app.services.leave_policy import get_or_create_leave_policy, update_leave_policy
from app.services.leave_requests import (
    create_leave_request,
    edit_leave_request,
    serialize_leave_request,
)
from test_leave_entitlements import World, _headers

START = date(2026, 11, 10)
END = date(2026, 11, 12)


def _detail(exc: HTTPException) -> str:
    detail = exc.detail
    return detail if isinstance(detail, str) else str(detail)


def _insert(
    world: World,
    leave_type: LeaveType,
    *,
    specification: str | None = None,
    status: LeaveRequestStatus = LeaveRequestStatus.pending,
    is_paid: bool = True,
) -> LeaveRequest:
    row = LeaveRequest(
        business_id=world.business.id,
        employee_id=world.employee.id,
        leave_type=leave_type,
        start_date=START,
        end_date=END,
        leave_days=3,
        reason="Historical request",
        other_leave_specification=specification,
        policy_is_paid=is_paid,
        is_paid=is_paid,
        status=status,
    )
    world.db.add(row)
    world.db.commit()
    world.db.refresh(row)
    return row


def test_creating_unpaid_leave_is_rejected():
    world = World()
    try:
        with pytest.raises(HTTPException) as exc:
            create_leave_request(
                world.db,
                employee=world.employee,
                business_id=world.business.id,
                leave_type=LeaveType.unpaid,
                start_date=START,
                end_date=END,
                reason="Need time off",
                supporting_document=None,
                actor=world.employee_user,
            )
        assert exc.value.status_code == 400
        assert "Unpaid Leave is not available" in _detail(exc.value)
    finally:
        world.close()


def test_existing_unpaid_request_still_serializes():
    world = World()
    try:
        row = _insert(world, LeaveType.unpaid, is_paid=False)
        payload = serialize_leave_request(row, employee=world.employee)
        assert payload["leave_type"] == LeaveType.unpaid
        assert payload["leave_type_label"] == "Unpaid Leave"
        assert payload["is_paid"] is False
        assert payload["reason"] == "Historical request"
    finally:
        world.close()


def test_existing_unpaid_request_can_still_be_viewed():
    world = World()
    try:
        row = _insert(world, LeaveType.unpaid, is_paid=False)
        client = TestClient(app)
        response = client.get(
            f"/api/v1/employee/leave-requests/{row.id}",
            headers=_headers(world.employee_user),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["leave_type"] == "unpaid"
        assert body["leave_type_label"] == "Unpaid Leave"
        assert body["is_paid"] is False
    finally:
        world.close()


def test_editing_existing_unpaid_request_can_keep_unpaid():
    world = World()
    try:
        row = _insert(world, LeaveType.unpaid, is_paid=False)
        edited = edit_leave_request(
            world.db,
            request=row,
            employee=world.employee,
            leave_type=LeaveType.unpaid,
            start_date=START,
            end_date=END,
            reason="Still unpaid leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert edited.leave_type == LeaveType.unpaid
        assert edited.reason == "Still unpaid leave"
    finally:
        world.close()


def test_changing_another_type_to_unpaid_is_rejected():
    world = World()
    try:
        created = world.request(LeaveType.vacation, START, END)
        with pytest.raises(HTTPException) as exc:
            edit_leave_request(
                world.db,
                request=created,
                employee=world.employee,
                leave_type=LeaveType.unpaid,
                start_date=START,
                end_date=END,
                reason="Switch to unpaid",
                supporting_document=None,
                actor=world.employee_user,
            )
        assert exc.value.status_code == 400
        assert "Unpaid Leave is not available" in _detail(exc.value)
        world.db.refresh(created)
        assert created.leave_type == LeaveType.vacation
    finally:
        world.close()


def test_creating_other_without_specification_is_rejected():
    world = World()
    try:
        with pytest.raises(HTTPException) as exc:
            create_leave_request(
                world.db,
                employee=world.employee,
                business_id=world.business.id,
                leave_type=LeaveType.other,
                start_date=START,
                end_date=END,
                reason="Need time off",
                other_leave_specification="   ",
                supporting_document=None,
                actor=world.employee_user,
            )
        assert exc.value.status_code == 400
        assert "Please specify the type of leave you want to file." in _detail(
            exc.value
        )
    finally:
        world.close()


def test_creating_other_with_specification_succeeds_and_is_returned():
    world = World()
    try:
        created = create_leave_request(
            world.db,
            employee=world.employee,
            business_id=world.business.id,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="  Bereavement Leave  ",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert created.other_leave_specification == "Bereavement Leave"
        payload = serialize_leave_request(created, employee=world.employee)
        assert payload["leave_type"] == LeaveType.other
        assert payload["other_leave_specification"] == "Bereavement Leave"
        assert payload["reason"] == "Family matter"
    finally:
        world.close()


def test_editing_other_without_specification_is_rejected():
    world = World()
    try:
        created = create_leave_request(
            world.db,
            employee=world.employee,
            business_id=world.business.id,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="Bereavement Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        with pytest.raises(HTTPException) as exc:
            edit_leave_request(
                world.db,
                request=created,
                employee=world.employee,
                leave_type=LeaveType.other,
                start_date=START,
                end_date=END,
                reason="Family matter",
                other_leave_specification=" ",
                supporting_document=None,
                actor=world.employee_user,
            )
        assert exc.value.status_code == 400
        world.db.refresh(created)
        assert created.other_leave_specification == "Bereavement Leave"
    finally:
        world.close()


def test_editing_other_with_specification_succeeds():
    world = World()
    try:
        created = create_leave_request(
            world.db,
            employee=world.employee,
            business_id=world.business.id,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="Bereavement Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        edited = edit_leave_request(
            world.db,
            request=created,
            employee=world.employee,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="Study Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert edited.other_leave_specification == "Study Leave"
        assert edited.leave_type == LeaveType.other
    finally:
        world.close()


def test_changing_other_to_another_type_clears_specification():
    world = World()
    try:
        created = create_leave_request(
            world.db,
            employee=world.employee,
            business_id=world.business.id,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="Bereavement Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        edited = edit_leave_request(
            world.db,
            request=created,
            employee=world.employee,
            leave_type=LeaveType.vacation,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="Bereavement Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert edited.leave_type == LeaveType.vacation
        assert edited.other_leave_specification is None
    finally:
        world.close()


def test_non_other_request_cannot_retain_specification():
    world = World()
    try:
        created = create_leave_request(
            world.db,
            employee=world.employee,
            business_id=world.business.id,
            leave_type=LeaveType.sick,
            start_date=START,
            end_date=END,
            reason="Fever",
            other_leave_specification="Bereavement Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert created.other_leave_specification is None
        payload = serialize_leave_request(created, employee=world.employee)
        assert payload["other_leave_specification"] is None
    finally:
        world.close()


def test_previous_version_preserves_other_specification():
    world = World()
    try:
        world.set_allowance(LeaveType.other, 2026, 5)
        created = create_leave_request(
            world.db,
            employee=world.employee,
            business_id=world.business.id,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Family matter",
            other_leave_specification="Bereavement Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        approved = world.approve(created)
        edited = edit_leave_request(
            world.db,
            request=approved,
            employee=world.employee,
            leave_type=LeaveType.other,
            start_date=START,
            end_date=END,
            reason="Dates still needed",
            other_leave_specification="Study Leave",
            supporting_document=None,
            actor=world.employee_user,
        )
        assert edited.previous_reason == "Family matter"
        assert edited.previous_other_leave_specification == "Bereavement Leave"
        payload = serialize_leave_request(edited, employee=world.employee)
        previous = payload["previous_request"]
        assert previous["reason"] == "Family matter"
        assert previous["other_leave_specification"] == "Bereavement Leave"
        assert payload["other_leave_specification"] == "Study Leave"
        assert payload["reason"] == "Dates still needed"
    finally:
        world.close()


def test_historical_other_with_null_specification_remains_readable():
    world = World()
    try:
        row = _insert(world, LeaveType.other, specification=None)
        payload = serialize_leave_request(row, employee=world.employee)
        assert payload["leave_type"] == LeaveType.other
        assert payload["other_leave_specification"] is None
        client = TestClient(app)
        response = client.get(
            f"/api/v1/employee/leave-requests/{row.id}",
            headers=_headers(world.employee_user),
        )
        assert response.status_code == 200
        body = response.json()
        assert body["leave_type"] == "other"
        assert body["leave_type_label"] == "Other"
        assert body["other_leave_specification"] is None
        assert body["reason"] == "Historical request"
    finally:
        world.close()


def test_omitting_unpaid_from_policy_save_keeps_stored_treatment():
    world = World()
    try:
        update_leave_policy(
            world.db,
            business_id=world.business.id,
            treatments={"unpaid": True},
            actor=world.owner,
        )
        update_leave_policy(
            world.db,
            business_id=world.business.id,
            treatments={"vacation": False},
            actor=world.owner,
        )
        policy = get_or_create_leave_policy(world.db, world.business.id)
        assert policy.treatments["unpaid"] is True
        assert policy.treatments["vacation"] is False
    finally:
        world.close()


def test_omitting_unpaid_from_allowance_save_keeps_stored_row():
    world = World()
    try:
        world.set_allowance(LeaveType.unpaid, 2026, 4)
        world.set_allowance(LeaveType.vacation, 2026, 10)
        row = (
            world.db.query(BusinessLeaveAllowance)
            .filter(
                BusinessLeaveAllowance.business_id == world.business.id,
                BusinessLeaveAllowance.leave_type == LeaveType.unpaid,
                BusinessLeaveAllowance.year == 2026,
            )
            .one()
        )
        assert row.enabled is True
        assert row.allowance_days == 4
    finally:
        world.close()
