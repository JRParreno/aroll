from pydantic import BaseModel, EmailStr, Field

from app.models.enums import EmploymentType


class EmployeeCreate(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=2, max_length=200)
    position_title: str | None = None
    employment_type: EmploymentType = EmploymentType.full_time
    phone: str | None = None
    position_id: str | None = None


class EmployeeResponse(BaseModel):
    id: str
    email: str
    full_name: str
    position_title: str | None
    employment_type: str
    is_active: bool

    class Config:
        from_attributes = True


class EmployeeCreateResponse(EmployeeResponse):
    temporary_password: str
