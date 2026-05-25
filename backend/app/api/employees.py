import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_roles
from app.core.security import generate_temporary_password, hash_password
from app.db.session import get_db
from app.models.employee import Employee
from app.models.enums import UserRole
from app.models.user import User
from app.schemas.employee import (
    EmployeeCreate,
    EmployeeCreateResponse,
    EmployeeResponse,
)

router = APIRouter(prefix="/employees", tags=["employees"])


@router.get("", response_model=list[EmployeeResponse])
def list_employees(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    rows = (
        db.query(Employee, User)
        .join(User, Employee.user_id == User.id)
        .filter(Employee.business_id == user.business_id, Employee.is_active.is_(True))
        .all()
    )
    return [
        EmployeeResponse(
            id=str(emp.id),
            email=u.email,
            full_name=emp.full_name,
            position_title=emp.position_title,
            employment_type=emp.employment_type.value,
            is_active=emp.is_active,
        )
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

    email = body.email.lower().strip()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(400, "Email already registered")

    temp_password = generate_temporary_password()
    new_user = User(
        business_id=user.business_id,
        email=email,
        password_hash=hash_password(temp_password),
        role=UserRole.employee,
        must_change_password=True,
    )
    db.add(new_user)
    db.flush()

    position_id = uuid.UUID(body.position_id) if body.position_id else None
    employee = Employee(
        business_id=user.business_id,
        user_id=new_user.id,
        position_id=position_id,
        full_name=body.full_name,
        position_title=body.position_title,
        employment_type=body.employment_type,
        phone=body.phone,
    )
    db.add(employee)
    db.commit()
    db.refresh(employee)

    return EmployeeCreateResponse(
        id=str(employee.id),
        email=new_user.email,
        full_name=employee.full_name,
        position_title=employee.position_title,
        employment_type=employee.employment_type.value,
        is_active=employee.is_active,
        temporary_password=temp_password,
    )
