import uuid

from sqlalchemy import Boolean, Enum, ForeignKey, Numeric
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.enums import Weekday


class BusinessRestDayPolicy(Base):
    __tablename__ = "business_rest_day_policy"

    business_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("business.id"), primary_key=True
    )
    weekly_rest_day: Mapped[Weekday] = mapped_column(
        Enum(Weekday), default=Weekday.sunday
    )
    work_on_rest_day_allowed: Mapped[bool] = mapped_column(Boolean, default=False)
    rest_day_premium_percent: Mapped[float] = mapped_column(Numeric(5, 2), default=30.0)
    use_custom_premium: Mapped[bool] = mapped_column(Boolean, default=False)
    custom_premium_percent: Mapped[float | None] = mapped_column(
        Numeric(5, 2), nullable=True
    )
