"""Owner setup wizard schema

Revision ID: 004
Revises: 003
Create Date: 2026-06-06

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TYPE payperiodtype ADD VALUE IF NOT EXISTS 'bi_weekly'")

    for enum_sql in (
        "CREATE TYPE shifttype AS ENUM ('morning', 'afternoon', 'evening', 'night')",
        "CREATE TYPE holidaytype AS ENUM ('regular', 'special_non_working', 'company')",
        "CREATE TYPE missingclockoutpolicy AS ENUM ('auto_clock_out', 'require_manager_approval')",
        "CREATE TYPE weekday AS ENUM ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')",
    ):
        op.execute(
            f"""
            DO $$ BEGIN
                {enum_sql};
            EXCEPTION
                WHEN duplicate_object THEN null;
            END $$;
            """
        )

    shifttype = postgresql.ENUM(
        "morning", "afternoon", "evening", "night", name="shifttype", create_type=False
    )
    holidaytype = postgresql.ENUM(
        "regular",
        "special_non_working",
        "company",
        name="holidaytype",
        create_type=False,
    )
    missingclockoutpolicy = postgresql.ENUM(
        "auto_clock_out",
        "require_manager_approval",
        name="missingclockoutpolicy",
        create_type=False,
    )
    weekday = postgresql.ENUM(
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
        name="weekday",
        create_type=False,
    )

    op.add_column(
        "business",
        sa.Column("setup_completed_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.add_column(
        "shift",
        sa.Column(
            "shift_type",
            shifttype,
            nullable=False,
            server_default="morning",
        ),
    )
    op.add_column(
        "shift",
        sa.Column("employee_capacity", sa.Integer(), server_default="1", nullable=False),
    )

    op.add_column("position", sa.Column("description", sa.Text(), nullable=True))

    op.add_column(
        "business_payroll_config",
        sa.Column(
            "auto_reset_payroll_cycle",
            sa.Boolean(),
            server_default="true",
            nullable=False,
        ),
    )

    op.create_table(
        "business_attendance_policy",
        sa.Column("business_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("early_clock_in_minutes", sa.Integer(), server_default="15"),
        sa.Column("on_time_grace_minutes", sa.Integer(), server_default="10"),
        sa.Column("half_day_threshold_minutes", sa.Integer(), server_default="120"),
        sa.Column("absent_threshold_minutes", sa.Integer(), server_default="240"),
        sa.Column("early_out_deduction_enabled", sa.Boolean(), server_default="false"),
        sa.Column(
            "early_out_deduction_per_minute",
            sa.Numeric(10, 2),
            server_default="2.0",
        ),
        sa.Column("overtime_enabled", sa.Boolean(), server_default="true"),
        sa.Column("overtime_minimum_minutes", sa.Integer(), server_default="30"),
        sa.Column(
            "overtime_rate_per_minute",
            sa.Numeric(10, 2),
            server_default="5.0",
        ),
        sa.Column(
            "missing_clock_out_policy",
            missingclockoutpolicy,
            server_default="auto_clock_out",
        ),
        sa.Column(
            "attendance_based_salary_enabled",
            sa.Boolean(),
            server_default="true",
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )

    op.create_table(
        "business_rest_day_policy",
        sa.Column("business_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("weekly_rest_day", weekday, server_default="sunday"),
        sa.Column("work_on_rest_day_allowed", sa.Boolean(), server_default="false"),
        sa.Column(
            "rest_day_premium_percent",
            sa.Numeric(5, 2),
            server_default="30.0",
        ),
        sa.Column("use_custom_premium", sa.Boolean(), server_default="false"),
        sa.Column("custom_premium_percent", sa.Numeric(5, 2), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )

    op.create_table(
        "holiday",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("holiday_date", sa.Date(), nullable=False),
        sa.Column("is_paid", sa.Boolean(), server_default="true"),
        sa.Column("holiday_type", holidaytype, nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default="true"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )


def downgrade() -> None:
    op.drop_table("holiday")
    op.drop_table("business_rest_day_policy")
    op.drop_table("business_attendance_policy")
    op.drop_column("business_payroll_config", "auto_reset_payroll_cycle")
    op.drop_column("position", "description")
    op.drop_column("shift", "employee_capacity")
    op.drop_column("shift", "shift_type")
    op.drop_column("business", "setup_completed_at")
    op.execute("DROP TYPE IF EXISTS weekday")
    op.execute("DROP TYPE IF EXISTS missingclockoutpolicy")
    op.execute("DROP TYPE IF EXISTS holidaytype")
    op.execute("DROP TYPE IF EXISTS shifttype")
