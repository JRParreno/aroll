"""Assignment removal stops when attendance or a correction request is attached."""

import uuid
from datetime import datetime, time, timezone

from fastapi.testclient import TestClient

from app.api.schedules import (
    ASSIGNMENT_ATTENDANCE_RECORDED_MESSAGE,
    ASSIGNMENT_CORRECTION_MESSAGE,
    ASSIGNMENT_OPEN_ATTENDANCE_MESSAGE,
)
from app.core.security import create_access_token, hash_password
from app.db.session import SessionLocal
from app.main import app
from app.models.attendance import AttendanceRecord
from app.models.attendance_correction import AttendanceCorrectionRequest
from app.models.business import Business
from app.models.employee import Employee
from app.models.enums import (
    AttendanceCorrectionStatus,
    AttendanceStatus,
    EmployeeStatus,
    EmploymentType,
    UserRole,
)
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User


def _headers(user: User) -> dict[str, str]:
    token = create_access_token(
        str(user.id),
        extra={
            "role": user.role.value,
            "business_id": str(user.business_id) if user.business_id else None,
        },
    )
    return {"Authorization": f"Bearer {token}"}


class _World:
    def __init__(self) -> None:
        self.db = SessionLocal()
        self.business = Business(
            business_code=f"AD-{uuid.uuid4().hex[:6].upper()}",
            name="Assignment Delete Biz",
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
        self.db.flush()
        self.shift = Shift(
            business_id=self.business.id,
            name="Morning",
            start_time=time(8, 0),
            end_time=time(12, 0),
            employee_capacity=4,
            is_active=True,
        )
        self.db.add(self.shift)
        self.db.flush()
        self.employee = self._employee("Ana Cruz")
        self.assignment = ShiftAssignment(
            shift_id=self.shift.id,
            employee_id=self.employee.id,
            work_date=datetime(2026, 10, 25).date(),
        )
        self.db.add(self.assignment)
        self.db.commit()

    def close(self) -> None:
        self.db.close()

    def _employee(self, name: str) -> Employee:
        user = User(
            business_id=self.business.id,
            email=f"{uuid.uuid4().hex[:8]}@example.com",
            password_hash=hash_password("EmpPass123!"),
            role=UserRole.employee,
            must_change_password=False,
            is_active=True,
        )
        self.db.add(user)
        self.db.flush()
        employee = Employee(
            business_id=self.business.id,
            user_id=user.id,
            full_name=name,
            employment_type=EmploymentType.full_time,
            status=EmployeeStatus.active,
            is_active=True,
        )
        self.db.add(employee)
        self.db.flush()
        return employee

    def delete(self, client: TestClient):
        return client.delete(
            f"/api/v1/schedules/assignments/{self.assignment.id}",
            headers=_headers(self.owner),
        )


def test_open_attendance_blocks_assignment_removal():
    world = _World()
    client = TestClient(app)
    time_in = datetime(2026, 10, 25, 0, 5, tzinfo=timezone.utc)
    try:
        record = AttendanceRecord(
            business_id=world.business.id,
            employee_id=world.employee.id,
            shift_assignment_id=world.assignment.id,
            status=AttendanceStatus.in_progress,
            time_in=time_in,
            time_out=None,
        )
        world.db.add(record)
        world.db.commit()

        response = world.delete(client)

        assert response.status_code == 409
        assert response.json()["detail"] == ASSIGNMENT_OPEN_ATTENDANCE_MESSAGE
        world.db.expire_all()
        assert world.db.get(ShiftAssignment, world.assignment.id) is not None
        saved = world.db.get(AttendanceRecord, record.id)
        assert saved is not None
        assert saved.time_in == time_in
        assert saved.time_out is None
        assert world.db.get(Shift, world.shift.id).is_active is True
    finally:
        world.close()
        client.close()


def test_completed_attendance_blocks_assignment_removal():
    world = _World()
    client = TestClient(app)
    time_in = datetime(2026, 10, 25, 0, 0, tzinfo=timezone.utc)
    time_out = datetime(2026, 10, 25, 4, 0, tzinfo=timezone.utc)
    try:
        record = AttendanceRecord(
            business_id=world.business.id,
            employee_id=world.employee.id,
            shift_assignment_id=world.assignment.id,
            status=AttendanceStatus.complete,
            time_in=time_in,
            time_out=time_out,
        )
        world.db.add(record)
        world.db.commit()

        response = world.delete(client)

        assert response.status_code == 409
        assert response.json()["detail"] == ASSIGNMENT_ATTENDANCE_RECORDED_MESSAGE
        world.db.expire_all()
        assert world.db.get(ShiftAssignment, world.assignment.id) is not None
        saved = world.db.get(AttendanceRecord, record.id)
        assert saved is not None
        assert saved.time_in == time_in
        assert saved.time_out == time_out
        assert world.db.get(Shift, world.shift.id).is_active is True
    finally:
        world.close()
        client.close()


def test_correction_request_blocks_assignment_removal():
    world = _World()
    client = TestClient(app)
    try:
        request = AttendanceCorrectionRequest(
            business_id=world.business.id,
            employee_id=world.employee.id,
            shift_assignment_id=world.assignment.id,
            reason="Forgot to time in",
            status=AttendanceCorrectionStatus.pending,
        )
        world.db.add(request)
        world.db.commit()

        response = world.delete(client)

        assert response.status_code == 409
        assert response.json()["detail"] == ASSIGNMENT_CORRECTION_MESSAGE
        world.db.expire_all()
        assert world.db.get(ShiftAssignment, world.assignment.id) is not None
        assert world.db.get(AttendanceCorrectionRequest, request.id) is not None
        assert world.db.get(Shift, world.shift.id).is_active is True
    finally:
        world.close()
        client.close()


def test_assignment_without_history_is_removed_and_shift_stays_active():
    world = _World()
    client = TestClient(app)
    try:
        response = world.delete(client)
        assignment_id = world.assignment.id
        shift_id = world.shift.id

        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
        world.db.expire_all()
        assert world.db.get(ShiftAssignment, assignment_id) is None
        saved_shift = world.db.get(Shift, shift_id)
        assert saved_shift is not None
        assert saved_shift.is_active is True
        assert saved_shift.name == "Morning"
    finally:
        world.close()
        client.close()
