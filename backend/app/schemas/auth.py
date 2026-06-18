from pydantic import BaseModel, EmailStr, Field
from datetime import datetime


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class BusinessOwnerLoginRequest(BaseModel):
    business_code: str
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    must_change_password: bool = False
    employee_id: str | None = None
    business_id: str | None = None
    full_name: str | None = None
    position: str | None = None
    role: str | None = None
    business_name: str | None = None


class UserMeResponse(BaseModel):
    id: str
    email: str
    role: str
    business_id: str | None
    must_change_password: bool
    employee_id: str | None = None
    full_name: str | None = None
    position: str | None = None
    business_name: str | None = None
    business_code: str | None = None
    setup_completed_at: datetime | None = None
