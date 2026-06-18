from pydantic import BaseModel, EmailStr, Field

from app.models.enums import EmploymentType


class EmployeeCreate(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=2, max_length=200)
    position_title: str = Field(min_length=1, max_length=100)
    employment_type: EmploymentType = EmploymentType.full_time
    phone: str | None = None
    position_id: str | None = None


class EmployeeUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=200)
    position_title: str | None = Field(default=None, min_length=1, max_length=100)
    employment_type: EmploymentType | None = None
    phone: str | None = None
    position_id: str | None = None


class EmployeeResponse(BaseModel):
    id: str
    email: str
    full_name: str
    position_title: str | None
    phone: str | None = None
    employment_type: str
    status: str
    must_change_password: bool
    temporary_password: str | None = None

    class Config:
        from_attributes = True


class EmployeeCreateResponse(EmployeeResponse):
    pass
