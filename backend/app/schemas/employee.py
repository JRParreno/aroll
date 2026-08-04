from pydantic import BaseModel, Field, model_validator

from app.models.enums import EmploymentType, PayBasis


def _validate_pay_fields(
    *,
    pay_basis: PayBasis,
    daily_rate: float | None,
    hourly_rate: float | None,
    monthly_salary: float | None,
) -> None:
    if pay_basis == PayBasis.daily:
        if daily_rate is None or daily_rate <= 0:
            raise ValueError("daily_rate is required when pay_basis is daily.")
    elif pay_basis == PayBasis.hourly:
        if hourly_rate is None or hourly_rate <= 0:
            raise ValueError("hourly_rate is required when pay_basis is hourly.")
    elif pay_basis == PayBasis.monthly:
        if monthly_salary is None or monthly_salary <= 0:
            raise ValueError(
                "monthly_salary is required when pay_basis is monthly."
            )


class EmployeeCreate(BaseModel):
    full_name: str = Field(min_length=2, max_length=200)
    position_title: str = Field(min_length=1, max_length=100)
    employment_type: EmploymentType = EmploymentType.full_time
    phone: str | None = None
    position_id: str | None = None
    email: str | None = None
    pay_basis: PayBasis = PayBasis.daily
    daily_rate: float | None = Field(default=None, gt=0)
    hourly_rate: float | None = Field(default=None, gt=0)
    monthly_salary: float | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def _pay_required(self):
        # Create may omit daily_rate when position_id is set — API prefills
        # from Position before final validation. Skip here if daily + no rate
        # but position present; enforce in the API after prefill.
        if self.pay_basis == PayBasis.daily and self.daily_rate is None:
            if self.position_id:
                return self
            raise ValueError(
                "daily_rate is required when pay_basis is daily "
                "(or select a position to prefill it)."
            )
        if self.pay_basis == PayBasis.hourly:
            _validate_pay_fields(
                pay_basis=self.pay_basis,
                daily_rate=self.daily_rate,
                hourly_rate=self.hourly_rate,
                monthly_salary=self.monthly_salary,
            )
        elif self.pay_basis == PayBasis.monthly:
            _validate_pay_fields(
                pay_basis=self.pay_basis,
                daily_rate=self.daily_rate,
                hourly_rate=self.hourly_rate,
                monthly_salary=self.monthly_salary,
            )
        return self


class EmployeeUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=200)
    position_title: str | None = Field(default=None, min_length=1, max_length=100)
    employment_type: EmploymentType | None = None
    phone: str | None = None
    position_id: str | None = None
    pay_basis: PayBasis | None = None
    daily_rate: float | None = Field(default=None, gt=0)
    hourly_rate: float | None = Field(default=None, gt=0)
    monthly_salary: float | None = Field(default=None, gt=0)


class EmployeeResponse(BaseModel):
    id: str
    email: str
    username: str
    generated_username: str | None = None
    full_name: str
    position_title: str | None
    position_id: str | None = None
    phone: str | None = None
    profile_image_url: str | None = None
    employment_type: str
    pay_basis: str
    daily_rate: float | None = None
    hourly_rate: float | None = None
    monthly_salary: float | None = None
    status: str
    must_change_password: bool
    temporary_password: str | None = None

    class Config:
        from_attributes = True


class EmployeeCreateResponse(EmployeeResponse):
    pass
