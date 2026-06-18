import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.core.security import generate_temporary_password, hash_password
from app.db.session import get_db
from app.models.employee import Employee
from app.models.enums import EmployeeStatus, UserRole
from app.models.payroll import Position
from app.models.user import User
from app.schemas.employee import (
    EmployeeCreate,
    EmployeeCreateResponse,
    EmployeeResponse,
    EmployeeUpdate,
)

router = APIRouter(prefix="/employees", tags=["employees"])


def _employee_response(emp: Employee, user: User) -> EmployeeResponse:
    return EmployeeResponse(
        id=str(emp.id),
        email=user.email,
        full_name=emp.full_name,
        position_title=emp.position_title,
        phone=emp.phone,
        employment_type=emp.employment_type.value,
        status=emp.status.value,
        must_change_password=user.must_change_password,
        temporary_password=(
            user.pending_temporary_password if user.must_change_password else None
        ),
    )


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


@router.get("", response_model=list[EmployeeResponse])
def list_employees(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    include_inactive: bool = False,
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    query = (
        db.query(Employee, User)
        .join(User, Employee.user_id == User.id)
        .filter(Employee.business_id == user.business_id)
    )
    if not include_inactive:
        query = query.filter(Employee.status != EmployeeStatus.inactive)
    rows = query.order_by(Employee.full_name).all()
    return [_employee_response(emp, u) for emp, u in rows]


@router.post("", response_model=EmployeeCreateResponse, status_code=201)
def create_employee(
    body: EmployeeCreate,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    email = body.email.lower().strip()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(400, "Email already registered")

    position_id = uuid.UUID(body.position_id) if body.position_id else None
    position_title = body.position_title.strip()
    if position_id:
        pos = db.get(Position, position_id)
        if pos is None or pos.business_id != user.business_id:
            raise HTTPException(400, "Invalid position")
        if not position_title:
            position_title = pos.title

    temp_password = generate_temporary_password()
    new_user = User(
        business_id=user.business_id,
        email=email,
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
        phone=body.phone.strip() if body.phone else None,
        status=EmployeeStatus.invited,
    )
    db.add(employee)
    db.commit()
    db.refresh(employee)

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

    if "position_id" in updates:
        raw_position_id = updates.pop("position_id")
        if raw_position_id:
            pos = db.get(Position, uuid.UUID(raw_position_id))
            if pos is None or pos.business_id != user.business_id:
                raise HTTPException(400, "Invalid position")
            emp.position_id = pos.id
            if "position_title" not in updates:
                emp.position_title = pos.title
        else:
            emp.position_id = None

    for field, value in updates.items():
        if field == "full_name" and value is not None:
            setattr(emp, field, value.strip())
        elif field == "position_title" and value is not None:
            setattr(emp, field, value.strip())
        elif field == "phone":
            setattr(emp, field, value.strip() if value else None)
        else:
            setattr(emp, field, value)

    db.commit()
    db.refresh(emp)
    return _employee_response(emp, linked_user)


@router.post("/{employee_id}/deactivate", response_model=EmployeeResponse)
def deactivate_employee(
    employee_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")

    emp, linked_user = _get_business_employee(db, employee_id, user.business_id)
    if emp.status == EmployeeStatus.inactive:
        raise HTTPException(400, "Employee is already inactive")

    emp.status = EmployeeStatus.inactive
    emp.is_active = False
    linked_user.is_active = False
    db.commit()
    db.refresh(emp)
    return _employee_response(emp, linked_user)


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

    emp.is_active = True
    linked_user.is_active = True
    emp.status = (
        EmployeeStatus.invited
        if linked_user.must_change_password
        else EmployeeStatus.active
    )
    db.commit()
    db.refresh(emp)
    return _employee_response(emp, linked_user)
