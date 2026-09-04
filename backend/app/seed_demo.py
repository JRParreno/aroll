"""Idempotent seed for AROLL+ Demo Café (DEMO01).

Research/defense tenant only. Simulated employees, attendance, payroll inputs,
fictional worksite, and synthetic face embeddings. Never mix with DEVTEST.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

import numpy as np
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.core.timezone import get_business_tz
from app.db.session import SessionLocal
from app.models.attendance import AttendanceRecord
from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business, BusinessLocation
from app.models.employee import Employee
from app.models.enums import (
    AttendanceStatus,
    BusinessStatus,
    EmployeeStatus,
    EmploymentType,
    PayBasis,
    PayPeriodType,
    ShiftType,
    UserRole,
    Weekday,
)
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.leave_policy import BusinessLeavePolicy
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift, ShiftAssignment
from app.models.user import User
from app.services.leave_policy import default_treatments
from app.services.pay_period import resolve_pay_period

logger = logging.getLogger("aroll.seed.demo")

DEMO_BUSINESS_CODE = "DEMO01"
DEMO_BUSINESS_NAME = "AROLL+ Demo Café"
DEMO_TIMEZONE = "Asia/Manila"
# Fictional pin — not a participating workplace.
DEMO_LATITUDE = 14.5500000
DEMO_LONGITUDE = 121.0000000
DEMO_GEOFENCE_M = 75
DEMO_ADDRESS = "100 Demo Street, Sample City (fictional pin — not a real workplace)"

DEMO_OWNER_EMAIL = "owner.demo@example.com"
DEMO_MANAGER_EMAIL = "manager.demo@example.com"
DEMO_EMPLOYEE_01_EMAIL = "employee.demo01@example.com"
DEMO_EMPLOYEE_02_EMAIL = "employee.demo02@example.com"

# Local-development seed password (not a real person credential).
DEMO_SEED_PASSWORD = "DemoCafe!23"

ASSETS_DIR = Path(__file__).resolve().parent / "seed_assets" / "demo_faces"


def seed_demo(db: Session | None = None) -> Business:
    own_session = db is None
    if own_session:
        db = SessionLocal()
    try:
        business = _upsert_business(db)
        _upsert_policies(db, business)
        location = _upsert_location(db, business)
        positions = _upsert_positions(db, business)
        owner = _upsert_user(
            db,
            business,
            email=DEMO_OWNER_EMAIL,
            role=UserRole.owner,
        )
        _upsert_user(
            db,
            business,
            email=DEMO_MANAGER_EMAIL,
            role=UserRole.manager,
        )
        hannah = _upsert_employee(
            db,
            business,
            email=DEMO_EMPLOYEE_01_EMAIL,
            full_name="Hannah Cruz",
            position=positions["barista"],
            pay_basis=PayBasis.daily,
            daily_rate=650.00,
            hourly_rate=None,
            employee_code="DEMO-01",
        )
        luis = _upsert_employee(
            db,
            business,
            email=DEMO_EMPLOYEE_02_EMAIL,
            full_name="Luis Mercado",
            position=positions["cook"],
            pay_basis=PayBasis.hourly,
            daily_rate=None,
            hourly_rate=95.00,
            employee_code="DEMO-02",
        )
        shifts = _upsert_shifts(db, business)
        _seed_schedule_and_attendance(
            db,
            business,
            location=location,
            hannah=hannah,
            luis=luis,
            shifts=shifts,
        )
        _seed_payroll_adjustments(db, business, owner=owner, hannah=hannah, luis=luis)
        _seed_synthetic_faces(db, owner=owner, hannah=hannah, luis=luis)
        db.commit()
        db.refresh(business)
        logger.info("Seeded demo tenant %s (%s)", business.name, business.business_code)
        return business
    except Exception:
        db.rollback()
        raise
    finally:
        if own_session:
            db.close()


def _upsert_business(db: Session) -> Business:
    business = (
        db.query(Business)
        .filter(func.upper(Business.business_code) == DEMO_BUSINESS_CODE)
        .first()
    )
    now = datetime.now(timezone.utc)
    if business is None:
        business = Business(
            business_code=DEMO_BUSINESS_CODE,
            name=DEMO_BUSINESS_NAME,
            status=BusinessStatus.active,
            timezone=DEMO_TIMEZONE,
            business_type="Food & Beverage (demo)",
            setup_completed_at=now,
            is_demo=True,
            is_internal_test=False,
        )
        db.add(business)
        db.flush()
        return business
    business.name = DEMO_BUSINESS_NAME
    business.status = BusinessStatus.active
    business.timezone = DEMO_TIMEZONE
    business.is_demo = True
    business.is_internal_test = False
    if business.setup_completed_at is None:
        business.setup_completed_at = now
    db.flush()
    return business


def _upsert_policies(db: Session, business: Business) -> None:
    if db.get(BusinessPayrollConfig, business.id) is None:
        db.add(
            BusinessPayrollConfig(
                business_id=business.id,
                pay_period_type=PayPeriodType.monthly,
                monthly_payday_day=30,
                late_deduction_enabled=True,
                overtime_enabled=True,
            )
        )
    if db.get(BusinessAttendancePolicy, business.id) is None:
        db.add(BusinessAttendancePolicy(business_id=business.id))
    if db.get(BusinessRestDayPolicy, business.id) is None:
        db.add(
            BusinessRestDayPolicy(
                business_id=business.id,
                weekly_rest_day=Weekday.sunday,
            )
        )
    if db.get(BusinessLeavePolicy, business.id) is None:
        db.add(
            BusinessLeavePolicy(
                business_id=business.id,
                treatments=default_treatments(),
                config_json={},
            )
        )
    db.flush()


def _upsert_location(db: Session, business: Business) -> BusinessLocation:
    location = (
        db.query(BusinessLocation)
        .filter(
            BusinessLocation.business_id == business.id,
            BusinessLocation.is_primary.is_(True),
        )
        .first()
    )
    if location is None:
        location = BusinessLocation(
            business_id=business.id,
            label="Demo Café (fictional)",
            address=DEMO_ADDRESS,
            latitude=DEMO_LATITUDE,
            longitude=DEMO_LONGITUDE,
            geofence_radius_m=DEMO_GEOFENCE_M,
            is_primary=True,
        )
        db.add(location)
        db.flush()
        return location
    location.address = DEMO_ADDRESS
    location.latitude = DEMO_LATITUDE
    location.longitude = DEMO_LONGITUDE
    location.geofence_radius_m = DEMO_GEOFENCE_M
    db.flush()
    return location


def _upsert_positions(db: Session, business: Business) -> dict[str, Position]:
    barista = _upsert_position(
        db, business, title="Barista", daily_rate=650.00, hourly_rate=None
    )
    cook = _upsert_position(
        db, business, title="Cook", daily_rate=760.00, hourly_rate=95.00
    )
    return {"barista": barista, "cook": cook}


def _upsert_position(
    db: Session,
    business: Business,
    *,
    title: str,
    daily_rate: float,
    hourly_rate: float | None,
) -> Position:
    row = (
        db.query(Position)
        .filter(Position.business_id == business.id, Position.title == title)
        .first()
    )
    if row is None:
        row = Position(
            business_id=business.id,
            title=title,
            daily_rate=daily_rate,
            hourly_rate=hourly_rate,
            description=f"Demo {title} role",
            is_active=True,
        )
        db.add(row)
        db.flush()
    return row


def _upsert_user(
    db: Session,
    business: Business,
    *,
    email: str,
    role: UserRole,
) -> User:
    user = (
        db.query(User)
        .filter(User.business_id == business.id, User.role == role)
        .first()
        if role in (UserRole.owner, UserRole.manager)
        else (
            db.query(User)
            .filter(
                User.business_id == business.id,
                func.lower(User.email) == email.lower(),
                User.role == role,
            )
            .first()
        )
    )
    if user is None:
        user = User(
            business_id=business.id,
            email=email.lower(),
            password_hash=hash_password(DEMO_SEED_PASSWORD),
            role=role,
            is_active=True,
            must_change_password=False,
            pending_temporary_password=None,
        )
        db.add(user)
        db.flush()
        return user
    user.email = email.lower()
    user.is_active = True
    user.must_change_password = False
    user.pending_temporary_password = None
    db.flush()
    return user


def _upsert_employee(
    db: Session,
    business: Business,
    *,
    email: str,
    full_name: str,
    position: Position,
    pay_basis: PayBasis,
    daily_rate: float | None,
    hourly_rate: float | None,
    employee_code: str,
) -> Employee:
    employee = (
        db.query(Employee)
        .filter(
            Employee.business_id == business.id,
            Employee.employee_code == employee_code,
        )
        .first()
    )
    if employee is None:
        user = _upsert_user(db, business, email=email, role=UserRole.employee)
        employee = db.query(Employee).filter(Employee.user_id == user.id).first()
    else:
        user = db.get(User, employee.user_id)
        if user is not None:
            user.email = email.lower()
            user.is_active = True
            user.must_change_password = False
            user.pending_temporary_password = None
    if employee is None:
        employee = Employee(
            business_id=business.id,
            user_id=user.id,
            position_id=position.id,
            employee_code=employee_code,
            full_name=full_name,
            position_title=position.title,
            employment_type=EmploymentType.full_time,
            pay_basis=pay_basis,
            daily_rate=daily_rate,
            hourly_rate=hourly_rate,
            monthly_salary=None,
            status=EmployeeStatus.active,
            is_active=True,
            hire_date=date.today() - timedelta(days=120),
            face_registration_status="not_registered",
        )
        db.add(employee)
        db.flush()
        return employee
    employee.full_name = full_name
    employee.position_id = position.id
    employee.position_title = position.title
    employee.status = EmployeeStatus.active
    employee.is_active = True
    db.flush()
    return employee


def _upsert_shifts(db: Session, business: Business) -> dict[str, Shift]:
    morning = _upsert_shift(
        db,
        business,
        name="Morning",
        shift_type=ShiftType.morning,
        start_time=time(7, 0),
        end_time=time(15, 0),
        color="#F59E0B",
    )
    afternoon = _upsert_shift(
        db,
        business,
        name="Afternoon",
        shift_type=ShiftType.afternoon,
        start_time=time(15, 0),
        end_time=time(22, 0),
        color="#3B82F6",
    )
    return {"morning": morning, "afternoon": afternoon}


def _upsert_shift(
    db: Session,
    business: Business,
    *,
    name: str,
    shift_type: ShiftType,
    start_time: time,
    end_time: time,
    color: str,
) -> Shift:
    row = (
        db.query(Shift)
        .filter(Shift.business_id == business.id, Shift.name == name)
        .first()
    )
    if row is None:
        row = Shift(
            business_id=business.id,
            name=name,
            shift_type=shift_type,
            start_time=start_time,
            end_time=end_time,
            break_minutes=60,
            employee_capacity=4,
            color=color,
            is_active=True,
        )
        db.add(row)
        db.flush()
        return row
    row.start_time = start_time
    row.end_time = end_time
    row.is_active = True
    db.flush()
    return row


def _recent_weekdays(count: int = 12) -> list[date]:
    days: list[date] = []
    cursor = date.today() - timedelta(days=1)
    while len(days) < count:
        if cursor.weekday() < 5:
            days.append(cursor)
        cursor -= timedelta(days=1)
    days.reverse()
    return days


def _utc_at(work_date: date, local_time: time) -> datetime:
    tz = get_business_tz(DEMO_TIMEZONE)
    local = datetime.combine(work_date, local_time, tzinfo=tz)
    return local.astimezone(timezone.utc)


def _upsert_assignment(
    db: Session, *, shift: Shift, employee: Employee, work_date: date
) -> ShiftAssignment:
    row = (
        db.query(ShiftAssignment)
        .filter(
            ShiftAssignment.shift_id == shift.id,
            ShiftAssignment.employee_id == employee.id,
            ShiftAssignment.work_date == work_date,
        )
        .first()
    )
    if row is None:
        row = ShiftAssignment(
            shift_id=shift.id,
            employee_id=employee.id,
            work_date=work_date,
        )
        db.add(row)
        db.flush()
    return row


def _upsert_attendance(
    db: Session,
    *,
    business: Business,
    employee: Employee,
    assignment: ShiftAssignment,
    location: BusinessLocation,
    status: AttendanceStatus,
    time_in: datetime | None,
    time_out: datetime | None,
    face_score: float | None = 0.72,
) -> AttendanceRecord:
    row = (
        db.query(AttendanceRecord)
        .filter(AttendanceRecord.shift_assignment_id == assignment.id)
        .first()
    )
    if row is None:
        row = AttendanceRecord(
            business_id=business.id,
            employee_id=employee.id,
            shift_assignment_id=assignment.id,
        )
        db.add(row)
    row.status = status
    row.time_in = time_in
    row.time_out = time_out
    row.latitude_in = float(location.latitude) if time_in else None
    row.longitude_in = float(location.longitude) if time_in else None
    row.latitude_out = float(location.latitude) if time_out else None
    row.longitude_out = float(location.longitude) if time_out else None
    row.face_match_score = face_score if time_in else None
    row.face_match_score_out = face_score if time_out else None
    row.liveness_passed = True if time_in else None
    db.flush()
    return row


def _seed_schedule_and_attendance(
    db: Session,
    business: Business,
    *,
    location: BusinessLocation,
    hannah: Employee,
    luis: Employee,
    shifts: dict[str, Shift],
) -> None:
    workdays = _recent_weekdays(12)
    morning = shifts["morning"]
    afternoon = shifts["afternoon"]
    today = date.today()

    for index, work_date in enumerate(workdays):
        hannah_assignment = _upsert_assignment(
            db, shift=morning, employee=hannah, work_date=work_date
        )
        luis_shift = afternoon if index % 5 == 4 else morning
        luis_assignment = _upsert_assignment(
            db, shift=luis_shift, employee=luis, work_date=work_date
        )
        # Leave today open so live demo Time In/Out can run.
        if work_date == today:
            continue

        # Hannah: mostly on-time; one late; one absent.
        if index == 3:
            _upsert_attendance(
                db,
                business=business,
                employee=hannah,
                assignment=hannah_assignment,
                location=location,
                status=AttendanceStatus.absent,
                time_in=None,
                time_out=None,
                face_score=None,
            )
        elif index == 7:
            _upsert_attendance(
                db,
                business=business,
                employee=hannah,
                assignment=hannah_assignment,
                location=location,
                status=AttendanceStatus.late,
                time_in=_utc_at(work_date, time(7, 25)),
                time_out=_utc_at(work_date, time(15, 5)),
            )
        else:
            _upsert_attendance(
                db,
                business=business,
                employee=hannah,
                assignment=hannah_assignment,
                location=location,
                status=AttendanceStatus.complete,
                time_in=_utc_at(work_date, time(6, 55)),
                time_out=_utc_at(work_date, time(15, 2)),
            )

        # Luis: on-time, one late, one OT close, one absent.
        if index == 5:
            _upsert_attendance(
                db,
                business=business,
                employee=luis,
                assignment=luis_assignment,
                location=location,
                status=AttendanceStatus.absent,
                time_in=None,
                time_out=None,
                face_score=None,
            )
        elif index == 2:
            start = luis_shift.start_time
            late = (
                datetime.combine(work_date, start) + timedelta(minutes=18)
            ).time()
            end = luis_shift.end_time
            _upsert_attendance(
                db,
                business=business,
                employee=luis,
                assignment=luis_assignment,
                location=location,
                status=AttendanceStatus.late,
                time_in=_utc_at(work_date, late),
                time_out=_utc_at(work_date, end),
            )
        elif index == 8:
            # Completed with overtime past shift end.
            _upsert_attendance(
                db,
                business=business,
                employee=luis,
                assignment=luis_assignment,
                location=location,
                status=AttendanceStatus.complete,
                time_in=_utc_at(work_date, luis_shift.start_time),
                time_out=_utc_at(
                    work_date,
                    (
                        datetime.combine(work_date, luis_shift.end_time)
                        + timedelta(minutes=45)
                    ).time(),
                ),
            )
        else:
            _upsert_attendance(
                db,
                business=business,
                employee=luis,
                assignment=luis_assignment,
                location=location,
                status=AttendanceStatus.complete,
                time_in=_utc_at(work_date, luis_shift.start_time),
                time_out=_utc_at(work_date, luis_shift.end_time),
            )

    _upsert_assignment(db, shift=morning, employee=hannah, work_date=today)
    _upsert_assignment(db, shift=afternoon, employee=luis, work_date=today)
    _clear_today_attendance(db, business=business, work_date=today)


def _clear_today_attendance(
    db: Session, *, business: Business, work_date: date
) -> None:
    """Keep today's demo shifts punchable for live Time In/Out."""
    assignment_ids = [
        row.id
        for row in (
            db.query(ShiftAssignment)
            .join(Shift, ShiftAssignment.shift_id == Shift.id)
            .filter(
                Shift.business_id == business.id,
                ShiftAssignment.work_date == work_date,
            )
            .all()
        )
    ]
    if not assignment_ids:
        return
    db.query(AttendanceRecord).filter(
        AttendanceRecord.business_id == business.id,
        AttendanceRecord.shift_assignment_id.in_(assignment_ids),
    ).delete(synchronize_session=False)


def _seed_payroll_adjustments(
    db: Session,
    business: Business,
    *,
    owner: User,
    hannah: Employee,
    luis: Employee,
) -> None:
    config = db.get(BusinessPayrollConfig, business.id)
    period_start, period_end = resolve_pay_period(config, today=date.today())
    _upsert_adjustment(
        db,
        business=business,
        employee=hannah,
        owner=owner,
        period_start=period_start,
        period_end=period_end,
        kind="deduction",
        type_key="broken_equipment",
        amount=50.00,
        description="Demo sample deduction — broken cup (fictional)",
    )
    _upsert_adjustment(
        db,
        business=business,
        employee=luis,
        owner=owner,
        period_start=period_start,
        period_end=period_end,
        kind="allowance",
        type_key="meal_allowance",
        amount=150.00,
        description="Demo sample meal allowance (fictional)",
    )


def _upsert_adjustment(
    db: Session,
    *,
    business: Business,
    employee: Employee,
    owner: User,
    period_start: date,
    period_end: date,
    kind: str,
    type_key: str,
    amount: float,
    description: str,
) -> PayrollAdjustment:
    row = (
        db.query(PayrollAdjustment)
        .filter(
            PayrollAdjustment.business_id == business.id,
            PayrollAdjustment.employee_id == employee.id,
            PayrollAdjustment.period_start == period_start,
            PayrollAdjustment.period_end == period_end,
            PayrollAdjustment.kind == kind,
            PayrollAdjustment.type_key == type_key,
            PayrollAdjustment.deleted_at.is_(None),
        )
        .first()
    )
    if row is None:
        row = PayrollAdjustment(
            business_id=business.id,
            employee_id=employee.id,
            period_start=period_start,
            period_end=period_end,
            kind=kind,
            type_key=type_key,
            amount=amount,
            description=description,
            created_by=owner.id,
        )
        db.add(row)
        db.flush()
        return row
    row.amount = amount
    row.description = description
    db.flush()
    return row


def _synthetic_face_jpeg(*, identity: int, sample: int) -> bytes:
    """Draw a face-like JPEG. Not a photograph of a real person.

    YuNet often does not detect these drawings. DEMO01 attendance must not
    depend on this JPEG going through the live face pipeline (see demo_tenant).
    """
    import cv2

    rng = np.random.default_rng(identity * 17 + sample)
    size = 320
    img = np.full((size, size, 3), 210, dtype=np.uint8)
    skin = (
        90 + identity * 25,
        140 + identity * 15,
        180 + identity * 10,
    )
    cv2.ellipse(
        img,
        (size // 2, size // 2 + 8),
        (88, 112),
        0,
        0,
        360,
        skin,
        -1,
    )
    eye_y = size // 2 - 18 + sample
    cv2.circle(img, (size // 2 - 28, eye_y), 10, (35, 35, 40), -1)
    cv2.circle(img, (size // 2 + 28, eye_y), 10, (35, 35, 40), -1)
    cv2.circle(img, (size // 2 - 28, eye_y), 3, (220, 220, 220), -1)
    cv2.circle(img, (size // 2 + 28, eye_y), 3, (220, 220, 220), -1)
    cv2.ellipse(
        img,
        (size // 2, size // 2 + 10),
        (12, 18),
        0,
        0,
        360,
        (80, 90, 120),
        -1,
    )
    cv2.ellipse(
        img,
        (size // 2, size // 2 + 48),
        (32, 14),
        0,
        20,
        160,
        (40, 40, 80),
        3,
    )
    noise = rng.integers(0, 12, img.shape, dtype=np.uint8)
    img = cv2.add(img, noise)
    ok, buf = cv2.imencode(".jpg", img)
    if not ok:
        raise RuntimeError("Failed to encode synthetic demo face JPEG")
    return buf.tobytes()


def _write_face_assets() -> list[tuple[str, bytes]]:
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    written: list[tuple[str, bytes]] = []
    for identity, prefix in ((1, "hannah"), (2, "luis")):
        for sample in range(1, 4):
            name = f"{prefix}_{sample}.jpg"
            path = ASSETS_DIR / name
            payload = _synthetic_face_jpeg(identity=identity, sample=sample)
            if not path.exists() or path.stat().st_size == 0:
                path.write_bytes(payload)
            else:
                payload = path.read_bytes()
            written.append((name, payload))
    return written


def _seed_synthetic_faces(
    db: Session,
    *,
    owner: User,
    hannah: Employee,
    luis: Employee,
) -> None:
    assets = {name: data for name, data in _write_face_assets()}
    _enroll_or_insert(
        db,
        employee=hannah,
        enrolled_by=owner.id,
        payloads=[assets["hannah_1.jpg"], assets["hannah_2.jpg"], assets["hannah_3.jpg"]],
        rng_seed=11,
    )
    _enroll_or_insert(
        db,
        employee=luis,
        enrolled_by=owner.id,
        payloads=[assets["luis_1.jpg"], assets["luis_2.jpg"], assets["luis_3.jpg"]],
        rng_seed=22,
    )


def _enroll_or_insert(
    db: Session,
    *,
    employee: Employee,
    enrolled_by,
    payloads: list[bytes],
    rng_seed: int,
) -> None:
    existing = (
        db.query(EmployeeFaceEmbedding)
        .filter(EmployeeFaceEmbedding.employee_id == employee.id)
        .count()
    )
    if existing >= 3 and employee.face_registration_status == "completed":
        return

    from app.services.face_embedding import MODEL_VERSION
    from app.services.face_enrollment import enroll_face_sample_bytes

    try:
        enroll_face_sample_bytes(
            db,
            employee,
            payloads,
            enrolled_by=enrolled_by,
            allow_demo_seed=True,
        )
        logger.info(
            "Demo face enrolled via pipeline employee_id=%s", employee.id
        )
        return
    except Exception as exc:
        logger.warning(
            "Demo face pipeline enroll skipped for %s (%s); "
            "inserting synthetic embedding vectors instead.",
            employee.full_name,
            exc,
        )

    db.query(EmployeeFaceEmbedding).filter(
        EmployeeFaceEmbedding.employee_id == employee.id
    ).delete(synchronize_session=False)
    rng = np.random.default_rng(rng_seed)
    now = datetime.now(timezone.utc)
    for index in range(1, 4):
        vec = rng.normal(size=512)
        vec = vec / np.linalg.norm(vec)
        db.add(
            EmployeeFaceEmbedding(
                employee_id=employee.id,
                embedding=vec.astype(float).tolist(),
                model_version=MODEL_VERSION,
                sample_index=index,
                enrolled_by=enrolled_by,
                enrolled_at=now,
            )
        )
    employee.face_registration_status = "completed"
    employee.face_registered_at = now
    db.flush()
