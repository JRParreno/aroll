"""Initial schema

Revision ID: 001
Revises:
Create Date: 2026-05-25

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "business_registration",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_name", sa.String(200), nullable=False),
        sa.Column("owner_name", sa.String(200), nullable=False),
        sa.Column("owner_email", sa.String(255), nullable=False),
        sa.Column("owner_phone", sa.String(50)),
        sa.Column("proposed_address", sa.Text()),
        sa.Column(
            "status",
            sa.Enum(
                "pending",
                "approved",
                "rejected",
                name="registrationstatus",
            ),
            nullable=False,
        ),
        sa.Column("reviewed_by", postgresql.UUID(as_uuid=True)),
        sa.Column("reviewed_at", sa.DateTime(timezone=True)),
        sa.Column("rejection_reason", sa.Text()),
        sa.Column(
            "submitted_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
    )

    op.create_table(
        "business",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("registration_id", postgresql.UUID(as_uuid=True), unique=True),
        sa.Column("business_code", sa.String(20), unique=True, nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column(
            "status",
            sa.Enum("active", "suspended", name="businessstatus"),
            nullable=False,
        ),
        sa.Column("timezone", sa.String(64), server_default="Asia/Manila"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["registration_id"], ["business_registration.id"]),
    )

    op.create_table(
        "user",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True)),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column(
            "role",
            sa.Enum(
                "platform_admin",
                "owner",
                "manager",
                "employee",
                name="userrole",
            ),
            nullable=False,
        ),
        sa.Column("is_active", sa.Boolean(), server_default="true"),
        sa.Column("must_change_password", sa.Boolean(), server_default="false"),
        sa.Column("last_login_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )
    op.create_foreign_key(
        "fk_registration_reviewed_by",
        "business_registration",
        "user",
        ["reviewed_by"],
        ["id"],
    )

    op.create_table(
        "business_location",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("label", sa.String(100)),
        sa.Column("address", sa.Text(), nullable=False),
        sa.Column("latitude", sa.Numeric(10, 7)),
        sa.Column("longitude", sa.Numeric(10, 7)),
        sa.Column("geofence_radius_m", sa.Integer(), server_default="75"),
        sa.Column("is_primary", sa.Boolean(), server_default="true"),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )

    op.create_table(
        "position",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("daily_rate", sa.Numeric(10, 2), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default="true"),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )

    op.create_table(
        "business_payroll_config",
        sa.Column("business_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "pay_period_type",
            sa.Enum("weekly", "semi_monthly", "monthly", name="payperiodtype"),
        ),
        sa.Column("late_deduction_enabled", sa.Boolean(), server_default="true"),
        sa.Column(
            "late_deduction_per_minute", sa.Numeric(10, 2), server_default="1.0"
        ),
        sa.Column("overtime_enabled", sa.Boolean(), server_default="true"),
        sa.Column("overtime_per_minute", sa.Numeric(10, 2), server_default="1.0"),
        sa.Column("next_payday_date", sa.Date()),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )

    op.create_table(
        "employee",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), unique=True, nullable=False),
        sa.Column("position_id", postgresql.UUID(as_uuid=True)),
        sa.Column("employee_code", sa.String(50)),
        sa.Column("full_name", sa.String(200), nullable=False),
        sa.Column("position_title", sa.String(100)),
        sa.Column(
            "employment_type",
            sa.Enum("full_time", "part_time", name="employmenttype"),
        ),
        sa.Column("phone", sa.String(50)),
        sa.Column("hire_date", sa.Date()),
        sa.Column("is_active", sa.Boolean(), server_default="true"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.ForeignKeyConstraint(["position_id"], ["position.id"]),
    )

    op.create_table(
        "shift",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("start_time", sa.Time(), nullable=False),
        sa.Column("end_time", sa.Time(), nullable=False),
        sa.Column("break_minutes", sa.Integer(), server_default="0"),
        sa.Column("is_active", sa.Boolean(), server_default="true"),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
    )

    op.create_table(
        "shift_assignment",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("shift_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("work_date", sa.Date(), nullable=False),
        sa.Column("notes", sa.Text()),
        sa.ForeignKeyConstraint(["shift_id"], ["shift.id"]),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"]),
    )

    op.create_table(
        "attendance_record",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("shift_assignment_id", postgresql.UUID(as_uuid=True)),
        sa.Column("time_in", sa.DateTime(timezone=True)),
        sa.Column("time_out", sa.DateTime(timezone=True)),
        sa.Column(
            "status",
            sa.Enum(
                "in_progress",
                "complete",
                "late",
                "absent",
                "incomplete",
                name="attendancestatus",
            ),
        ),
        sa.Column("latitude_in", sa.Numeric(10, 7)),
        sa.Column("longitude_in", sa.Numeric(10, 7)),
        sa.Column("latitude_out", sa.Numeric(10, 7)),
        sa.Column("longitude_out", sa.Numeric(10, 7)),
        sa.Column("face_match_score", sa.Numeric(5, 4)),
        sa.Column("liveness_passed", sa.Boolean()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"]),
        sa.ForeignKeyConstraint(["shift_assignment_id"], ["shift_assignment.id"]),
    )

    op.create_table(
        "payroll_run",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column(
            "status",
            sa.Enum("draft", "finalized", "cancelled", name="payrollrunstatus"),
        ),
        sa.Column("run_by", postgresql.UUID(as_uuid=True)),
        sa.Column("finalized_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"]),
        sa.ForeignKeyConstraint(["run_by"], ["user.id"]),
    )

    op.create_table(
        "payslip",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("payroll_run_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("regular_hours", sa.Numeric(8, 2), server_default="0"),
        sa.Column("overtime_hours", sa.Numeric(8, 2), server_default="0"),
        sa.Column("gross_pay", sa.Numeric(12, 2), server_default="0"),
        sa.Column("total_deductions", sa.Numeric(12, 2), server_default="0"),
        sa.Column("net_pay", sa.Numeric(12, 2), server_default="0"),
        sa.Column("breakdown_json", postgresql.JSONB()),
        sa.ForeignKeyConstraint(["payroll_run_id"], ["payroll_run.id"]),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"]),
    )


def downgrade() -> None:
    for t in [
        "payslip",
        "payroll_run",
        "attendance_record",
        "shift_assignment",
        "shift",
        "employee",
        "business_payroll_config",
        "position",
        "business_location",
        "user",
        "business",
        "business_registration",
    ]:
        op.drop_table(t)
    for e in [
        "payrollrunstatus",
        "attendancestatus",
        "employmenttype",
        "payperiodtype",
        "userrole",
        "businessstatus",
        "registrationstatus",
    ]:
        op.execute(f"DROP TYPE IF EXISTS {e}")
