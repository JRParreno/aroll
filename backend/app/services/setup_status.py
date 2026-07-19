from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.attendance_policy import BusinessAttendancePolicy
from app.models.business import Business, BusinessLocation
from app.models.enums import BusinessStatus
from app.models.holiday import Holiday
from app.models.payroll import BusinessPayrollConfig, Position
from app.models.rest_day_policy import BusinessRestDayPolicy
from app.models.scheduling import Shift
from app.schemas.owner_setup import SetupStatusResponse, SetupStepStatus

SETUP_STEPS = [
    ("shifts", "Business Schedules"),
    ("positions", "Positions & Salary Rates"),
    ("payroll", "Payroll Configuration"),
    ("attendance_policy", "Attendance Policy"),
    ("holidays", "Holiday Management"),
    ("location", "Business Location"),
    ("review", "Review & Complete"),
]

REQUIRED_SETUP_KEYS = frozenset({"shifts", "positions", "payroll", "location"})


class SetupIncompleteError(Exception):
    def __init__(self, missing_items: list[str]) -> None:
        self.missing_items = missing_items
        super().__init__("Setup incomplete")


def _step_complete(db: Session, business_id, key: str, business: Business) -> bool:
    if key == "shifts":
        return (
            db.query(Shift)
            .filter(Shift.business_id == business_id, Shift.is_active.is_(True))
            .count()
            >= 1
        )
    if key == "positions":
        return (
            db.query(Position)
            .filter(Position.business_id == business_id, Position.is_active.is_(True))
            .count()
            >= 1
        )
    if key == "payroll":
        cfg = db.get(BusinessPayrollConfig, business_id)
        rest_day = db.get(BusinessRestDayPolicy, business_id)
        return (
            cfg is not None
            and cfg.next_payday_date is not None
            and rest_day is not None
        )
    if key == "attendance_policy":
        return db.get(BusinessAttendancePolicy, business_id) is not None
    if key == "holidays":
        return (
            db.query(Holiday)
            .filter(Holiday.business_id == business_id, Holiday.is_active.is_(True))
            .count()
            >= 1
        )
    if key == "location":
        loc = (
            db.query(BusinessLocation)
            .filter(
                BusinessLocation.business_id == business_id,
                BusinessLocation.is_primary.is_(True),
            )
            .first()
        )
        return (
            loc is not None
            and loc.latitude is not None
            and loc.longitude is not None
            and loc.geofence_radius_m is not None
        )
    if key == "review":
        return business.setup_completed_at is not None
    return False


def get_setup_status(db: Session, business: Business) -> SetupStatusResponse:
    business_id = business.id
    steps: list[SetupStepStatus] = []
    missing_items: list[str] = []

    for key, label in SETUP_STEPS:
        complete = _step_complete(db, business_id, key, business)
        steps.append(SetupStepStatus(key=key, label=label, complete=complete))
        if not complete and key != "review":
            missing_items.append(f"{label} not configured")

    completed_steps = sum(1 for s in steps if s.complete)
    total_steps = len(steps)
    completion_percent = int((completed_steps / total_steps) * 100) if total_steps else 0

    return SetupStatusResponse(
        setup_completed_at=business.setup_completed_at,
        completion_percent=completion_percent,
        completed_steps=completed_steps,
        total_steps=total_steps,
        steps=steps,
        missing_items=missing_items,
    )


def complete_setup(db: Session, business: Business) -> None:
    status = get_setup_status(db, business)
    missing_required = [
        f"{step.label} not configured"
        for step in status.steps
        if step.key in REQUIRED_SETUP_KEYS and not step.complete
    ]
    if missing_required:
        raise SetupIncompleteError(missing_required)

    business.setup_completed_at = datetime.now(timezone.utc)
    business.status = BusinessStatus.active
    db.commit()
