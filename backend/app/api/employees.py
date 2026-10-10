import uuid
import re
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.core.deps import require_roles
from app.core.security import generate_temporary_password, hash_password
from app.core.timezone import business_today
from app.db.session import get_db
from app.models.business import Business, BusinessRegistration
from app.models.employee import Employee
from app.models.enums import EmployeeStatus, PayBasis, UserRole
from app.models.attendance import AttendanceRecord
from app.models.attendance_correction import AttendanceCorrectionRequest
from app.models.activity_log import ActivityLog
from app.models.face_embedding import EmployeeFaceEmbedding
from app.models.face_liveness import FaceLivenessChallenge
from app.models.leave_request import LeaveRequest
from app.models.payroll import PayrollRun, Position
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.schedule_template import ScheduleTemplate, ScheduleTemplateEntry
from app.models.scheduling import ShiftAssignment
from app.models.user import User
from app.schemas.employee import (
    EmployeeCreate,
    EmployeeCreateResponse,
    EmployeeResponse,
    EmployeeUpdate,
    _validate_pay_fields,
)
from app.schemas.legal_consent import (
    EmployeeConsentSummary,
    LegalConsentWithdrawRequest,
)
from app.services.legal_consent import (
    clear_employee_face_data,
    consent_summary_for_employee,
    withdraw_biometric_consent,
)
from app.services.position_pay_config import (
    apply_config_to_employee_fields,
    resolve_pay_config,
)
from app.services.shift_versioning import assignment_ids_to_remove_on_deactivate

router = APIRouter(prefix="/employees", tags=["employees"])


def _integrity_constraint_hint(exc: IntegrityError) -> str | None:
    """Best-effort FK / constraint name from a DB IntegrityError."""
    orig = getattr(exc, "orig", None)
    diag = getattr(orig, "diag", None)
    name = getattr(diag, "constraint_name", None) if diag is not None else None
    if name:
        return str(name)
    text = str(orig or exc)
    marker = 'constraint "'
    if marker in text:
        start = text.index(marker) + len(marker)
        end = text.find('"', start)
        if end > start:
            return text[start:end]
    return None


def _clear_user_actor_fks(
    db: Session,
    *,
    linked_user_id: uuid.UUID,
    reassign_to_user_id: uuid.UUID,
) -> None:
    """Release NO ACTION user FKs that block hard-delete of the linked account.

    Nullable actor columns are cleared (history rows kept).
    NOT NULL actor columns on other rows are reassigned to the deleting owner/manager.
    """
    uid = linked_user_id

    db.query(LeaveRequest).filter(LeaveRequest.reviewed_by == uid).update(
        {LeaveRequest.reviewed_by: None},
        synchronize_session=False,
    )
    db.query(AttendanceCorrectionRequest).filter(
        AttendanceCorrectionRequest.reviewed_by == uid
    ).update(
        {AttendanceCorrectionRequest.reviewed_by: None},
        synchronize_session=False,
    )
    db.query(PayrollAdjustment).filter(PayrollAdjustment.created_by == uid).update(
        {PayrollAdjustment.created_by: None},
        synchronize_session=False,
    )
    db.query(PayrollAdjustment).filter(PayrollAdjustment.updated_by == uid).update(
        {PayrollAdjustment.updated_by: None},
        synchronize_session=False,
    )
    db.query(PayrollAdjustment).filter(PayrollAdjustment.deleted_by == uid).update(
        {PayrollAdjustment.deleted_by: None},
        synchronize_session=False,
    )
    db.query(PayrollRun).filter(PayrollRun.run_by == uid).update(
        {PayrollRun.run_by: None},
        synchronize_session=False,
    )
    db.query(ScheduleTemplate).filter(ScheduleTemplate.created_by == uid).update(
        {ScheduleTemplate.created_by: None},
        synchronize_session=False,
    )
    db.query(BusinessRegistration).filter(
        BusinessRegistration.reviewed_by == uid
    ).update(
        {BusinessRegistration.reviewed_by: None},
        synchronize_session=False,
    )

    # enrolled_by / requested_by are NOT NULL — reassign leftover rows (other employees).
    if reassign_to_user_id != uid:
        db.query(EmployeeFaceEmbedding).filter(
            EmployeeFaceEmbedding.enrolled_by == uid
        ).update(
            {EmployeeFaceEmbedding.enrolled_by: reassign_to_user_id},
            synchronize_session=False,
        )
        db.query(FaceLivenessChallenge).filter(
            FaceLivenessChallenge.requested_by == uid
        ).update(
            {FaceLivenessChallenge.requested_by: reassign_to_user_id},
            synchronize_session=False,
        )


def _float_or_none(value) -> float | None:
    if value is None:
        return None
    return float(value)


def _employee_response(
    emp: Employee,
    user: User,
    *,
    consent: EmployeeConsentSummary | None = None,
) -> EmployeeResponse:
    pay_basis = getattr(emp, "pay_basis", None) or PayBasis.daily
    return EmployeeResponse(
        id=str(emp.id),
        email=user.email,
        username=user.email,
        generated_username=user.email if user.must_change_password else None,
        full_name=emp.full_name,
        position_title=emp.position_title,
        position_id=str(emp.position_id) if emp.position_id else None,
        phone=emp.phone,
        profile_image_url=emp.profile_image_url,
        employment_type=emp.employment_type.value,
        pay_basis=pay_basis.value if hasattr(pay_basis, "value") else str(pay_basis),
        daily_rate=_float_or_none(getattr(emp, "daily_rate", None)),
        hourly_rate=_float_or_none(getattr(emp, "hourly_rate", None)),
        monthly_salary=_float_or_none(getattr(emp, "monthly_salary", None)),
        status=emp.status.value,
        must_change_password=user.must_change_password,
        face_registration_status=(
            getattr(emp, "face_registration_status", None) or "not_registered"
        ),
        temporary_password=(
            user.pending_temporary_password if user.must_change_password else None
        ),
        consent=consent,
    )


def _consent_for(db: Session, emp: Employee, business: Business | None) -> EmployeeConsentSummary | None:
    if business is None:
        return None
    return EmployeeConsentSummary(**consent_summary_for_employee(db, emp, business))


def _generate_employee_username(db: Session, full_name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", ".", full_name.lower().strip()).strip(".")
    if not base:
        base = "employee"
    base = base[:32]
    candidate = base
    counter = 1
    while db.query(User).filter(User.email == candidate).first() is not None:
        counter += 1
        candidate = f"{base}{counter}"
    return candidate


def _get_business_employee(
    db: Session, employee_id: uuid.UUID, business_id: uuid.UUID
) -> tuple[Employee, User]:
    row = (
        db.query(Employee, User)
        .join(User, Employee.user_id == User.id)
        .filter(Employee.id == employee_id, Employee.business_id == business_id)
        .first()
    )
    if row is None:
        raise HTTPException(404, "Employee not found")
    return row


def _require_business_position(
    db: Session, position_id: uuid.UUID, business_id: uuid.UUID
) -> Position:
    pos = (
        db.query(Position)
        .options(joinedload(Position.pay_configs))
        .filter(Position.id == position_id, Position.business_id == business_id)
        .first()
    )
    if pos is None:
        # Preserve MagicMock / unit-test stubs that patch db.get.
        pos = db.get(Position, position_id)
        if pos is None or getattr(pos, "business_id", None) != business_id:
            raise HTTPException(400, "Invalid position")
    # In-memory/test objects may leave is_active unset (None); treat that as active.
    if getattr(pos, "is_active", True) is False:
        raise HTTPException(400, "Invalid position")
    return pos


def _assert_employment_matches_position(
    pos: Position, employment_type
) -> None:
    pos_employment = getattr(pos, "employment_type", None)
    if pos_employment is not None and pos_employment != employment_type:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "employment_type_mismatch",
                "message": (
                    "Selected role belongs to a different employment type. "
                    "Choose a role configured for this employment type."
                ),
            },
        )


def _raise_pay_validation(exc: ValueError) -> None:
    raise HTTPException(400, str(exc)) from exc


@router.get("", response_model=list[EmployeeResponse])
def list_employees(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    include_inactive: bool = False,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    query = (
        db.query(Employee, User)
        .join(User, Employee.user_id == User.id)
        .filter(Employee.business_id == user.business_id)
    )
    if not include_inactive:
        query = query.filter(Employee.status != EmployeeStatus.inactive)
    rows = query.order_by(Employee.full_name).all()
    return [
        _employee_response(emp, u, consent=_consent_for(db, emp, business))
        for emp, u in rows
    ]


@router.post("", response_model=EmployeeCreateResponse, status_code=201)
def create_employee(
    body: EmployeeCreate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    username = _generate_employee_username(db, body.full_name)

    position_id = uuid.UUID(body.position_id) if body.position_id else None
    position_title = body.position_title.strip()
    pos: Position | None = None
    if position_id:
        pos = _require_business_position(db, position_id, user.business_id)
        if not position_title:
            position_title = pos.title
        _assert_employment_matches_position(pos, body.employment_type)

    pay_basis = body.pay_basis or PayBasis.daily
    daily_rate = body.daily_rate
    hourly_rate = body.hourly_rate
    monthly_salary = body.monthly_salary

    if pos is not None:
        # Design B: Setup Wizard config is authoritative when a Role is selected.
        if pay_basis == PayBasis.monthly:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "pay_config_not_found",
                    "message": (
                        "Monthly pay is not configured in Setup Wizard. "
                        "Choose a Daily or Hourly rate configured for this role."
                    ),
                },
            )
        cfg = resolve_pay_config(pos, pay_basis)
        resolved = apply_config_to_employee_fields(cfg)
        pay_basis = resolved["pay_basis"]
        daily_rate = resolved["daily_rate"]
        hourly_rate = resolved["hourly_rate"]
        monthly_salary = resolved["monthly_salary"]

    try:
        _validate_pay_fields(
            pay_basis=pay_basis,
            daily_rate=daily_rate,
            hourly_rate=hourly_rate,
            monthly_salary=monthly_salary,
        )
    except ValueError as exc:
        _raise_pay_validation(exc)

    temp_password = generate_temporary_password()
    new_user = User(
        business_id=user.business_id,
        email=username,
        password_hash=hash_password(temp_password),
        role=UserRole.employee,
        must_change_password=True,
        pending_temporary_password=temp_password,
    )
    db.add(new_user)
    db.flush()

    employee = Employee(
        business_id=user.business_id,
        user_id=new_user.id,
        position_id=position_id,
        full_name=body.full_name.strip(),
        position_title=position_title,
        employment_type=body.employment_type,
        pay_basis=pay_basis,
        daily_rate=daily_rate,
        hourly_rate=hourly_rate,
        monthly_salary=monthly_salary,
        phone=body.phone.strip() if body.phone else None,
        status=EmployeeStatus.invited,
    )
    db.add(employee)
    db.commit()
    db.refresh(employee)
    db.refresh(new_user)

    return _employee_response(employee, new_user)


@router.put("/{employee_id}", response_model=EmployeeResponse)
def update_employee(
    employee_id: uuid.UUID,
    body: EmployeeUpdate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    emp, linked_user = _get_business_employee(db, employee_id, user.business_id)
    updates = body.model_dump(exclude_unset=True)

    pos: Position | None = None
    if "position_id" in updates:
        raw_position_id = updates.pop("position_id")
        if raw_position_id:
            pos = _require_business_position(
                db, uuid.UUID(raw_position_id), user.business_id
            )
            emp.position_id = pos.id
            if "position_title" not in updates:
                emp.position_title = pos.title
        else:
            emp.position_id = None
            pos = None
    elif emp.position_id is not None:
        pos = _require_business_position(db, emp.position_id, user.business_id)

    for field, value in updates.items():
        if field in ("daily_rate", "hourly_rate", "monthly_salary", "pay_basis"):
            # Applied after authoritative resolution when a Role is selected.
            continue
        if field == "full_name" and value is not None:
            setattr(emp, field, value.strip())
        elif field == "position_title" and value is not None:
            setattr(emp, field, value.strip())
        elif field == "phone":
            setattr(emp, field, value.strip() if value else None)
        else:
            setattr(emp, field, value)

    employment_type = emp.employment_type
    if pos is not None:
        _assert_employment_matches_position(pos, employment_type)
        requested_basis = updates.get("pay_basis", emp.pay_basis) or PayBasis.daily
        if isinstance(requested_basis, str):
            requested_basis = PayBasis(requested_basis)
        if requested_basis == PayBasis.monthly:
            # Preserve existing monthly-only employees until they switch basis.
            if emp.pay_basis != PayBasis.monthly:
                raise HTTPException(
                    status_code=400,
                    detail={
                        "code": "pay_config_not_found",
                        "message": (
                            "Monthly pay is not configured in Setup Wizard. "
                            "Choose a Daily or Hourly rate configured for this role."
                        ),
                    },
                )
            # Keep stored monthly values; ignore client rate overrides for other fields.
        else:
            cfg = resolve_pay_config(pos, requested_basis)
            resolved = apply_config_to_employee_fields(cfg)
            emp.pay_basis = resolved["pay_basis"]
            emp.daily_rate = resolved["daily_rate"]
            emp.hourly_rate = resolved["hourly_rate"]
            emp.monthly_salary = resolved["monthly_salary"]
    else:
        # No Role: allow legacy field updates (including monthly).
        if "pay_basis" in updates and updates["pay_basis"] is not None:
            emp.pay_basis = updates["pay_basis"]
        if "daily_rate" in updates:
            emp.daily_rate = updates["daily_rate"]
        if "hourly_rate" in updates:
            emp.hourly_rate = updates["hourly_rate"]
        if "monthly_salary" in updates:
            emp.monthly_salary = updates["monthly_salary"]

    pay_basis = emp.pay_basis or PayBasis.daily
    try:
        _validate_pay_fields(
            pay_basis=pay_basis,
            daily_rate=_float_or_none(emp.daily_rate),
            hourly_rate=_float_or_none(emp.hourly_rate),
            monthly_salary=_float_or_none(emp.monthly_salary),
        )
    except ValueError as exc:
        _raise_pay_validation(exc)

    db.commit()
    db.refresh(emp)
    return _employee_response(emp, linked_user)


@router.post("/{employee_id}/deactivate", response_model=EmployeeResponse)
def deactivate_employee(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    request: Request,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    emp, linked_user = _get_business_employee(db, employee_id, user.business_id)
    if emp.status == EmployeeStatus.inactive:
        raise HTTPException(400, "Employee is already inactive")

    business = db.get(Business, user.business_id)
    today = business_today(business.timezone if business else None)

    try:
        remove_ids = assignment_ids_to_remove_on_deactivate(
            db, employee_id=emp.id, today=today
        )
        if remove_ids:
            db.query(ShiftAssignment).filter(
                ShiftAssignment.id.in_(remove_ids)
            ).delete(synchronize_session=False)

        emp.status = EmployeeStatus.inactive
        emp.is_active = False
        linked_user.is_active = False
        deleted = clear_employee_face_data(db, emp)
        from app.core.request_meta import audit_meta_from_request
        from app.services.activity_logger import add_log

        meta = audit_meta_from_request(request)
        add_log(
            db,
            user.id,
            "face_cleared",
            f"Cleared face embeddings for {emp.full_name} during deactivation "
            f"({deleted} sample(s))",
            platform=meta.get("platform"),
            device=meta.get("device"),
            ip_address=meta.get("ip_address"),
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail=(
                "Unable to deactivate this employee because related schedule "
                "records could not be updated."
            ),
        ) from None
    db.refresh(emp)
    return _employee_response(emp, linked_user, consent=_consent_for(db, emp, business))


@router.post(
    "/{employee_id}/biometric-consent/withdraw",
    response_model=EmployeeResponse,
)
def withdraw_employee_biometric_consent(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    request: Request,
    body: LegalConsentWithdrawRequest | None = None,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    business = db.get(Business, user.business_id)
    if business is None:
        raise HTTPException(404, "Business not found")
    emp, linked_user = _get_business_employee(db, employee_id, user.business_id)
    withdraw_biometric_consent(
        db,
        employee=emp,
        business=business,
        actor_user_id=user.id,
        client=(body.client if body else "web"),
        request=request,
    )
    db.commit()
    db.refresh(emp)
    return _employee_response(emp, linked_user, consent=_consent_for(db, emp, business))


@router.delete("/{employee_id}")
def delete_employee(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    emp, linked_user = _get_business_employee(db, employee_id, user.business_id)

    try:
        # Corrections first: attendance_record_id is NO ACTION.
        db.query(AttendanceCorrectionRequest).filter(
            AttendanceCorrectionRequest.employee_id == emp.id
        ).delete(synchronize_session=False)

        # Exceptional hard-delete: remove live adjustment rows (incl. soft-deleted).
        db.query(PayrollAdjustment).filter(
            PayrollAdjustment.employee_id == emp.id
        ).delete(synchronize_session=False)

        db.query(ScheduleTemplateEntry).filter(
            ScheduleTemplateEntry.employee_id == emp.id
        ).delete(synchronize_session=False)

        db.query(AttendanceRecord).filter(
            AttendanceRecord.business_id == user.business_id,
            AttendanceRecord.employee_id == emp.id,
        ).delete(synchronize_session=False)
        db.query(ShiftAssignment).filter(ShiftAssignment.employee_id == emp.id).delete(
            synchronize_session=False
        )
        # Keep finalized Payslip snapshots. employee_id SET NULL via FK.
        db.query(EmployeeFaceEmbedding).filter(
            EmployeeFaceEmbedding.employee_id == emp.id
        ).delete(synchronize_session=False)
        db.query(FaceLivenessChallenge).filter(
            FaceLivenessChallenge.employee_id == emp.id
        ).delete(synchronize_session=False)

        # Clear/reassign remaining user-side actor FKs that block User delete.
        _clear_user_actor_fks(
            db,
            linked_user_id=linked_user.id,
            reassign_to_user_id=user.id,
        )

        # Preserve audit history; keep business scope, then clear User FK.
        db.query(ActivityLog).filter(ActivityLog.user_id == linked_user.id).update(
            {
                ActivityLog.business_id: linked_user.business_id or emp.business_id,
                ActivityLog.user_id: None,
            },
            synchronize_session=False,
        )

        db.delete(emp)
        db.delete(linked_user)
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        hint = _integrity_constraint_hint(exc)
        detail = (
            "Unable to delete this employee because related records "
            "still depend on the account."
        )
        if hint:
            detail = f"{detail} ({hint})"
        raise HTTPException(status_code=409, detail=detail) from None
    return {"status": "ok"}


@router.post("/{employee_id}/reactivate", response_model=EmployeeResponse)
def reactivate_employee(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    emp, linked_user = _get_business_employee(db, employee_id, user.business_id)
    if emp.status != EmployeeStatus.inactive:
        raise HTTPException(400, "Employee is not inactive")

    emp.status = (
        EmployeeStatus.invited
        if linked_user.must_change_password
        else EmployeeStatus.active
    )
    emp.is_active = True
    linked_user.is_active = True
    db.commit()
    db.refresh(emp)
    return _employee_response(emp, linked_user)
