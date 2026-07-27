"""Attendance correction requests for missed clock-in/out

Revision ID: 019
Revises: 018
Create Date: 2026-07-19

Employees can request forgotten punch corrections; owner/manager approves
before attendance and payroll are updated.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "019"
down_revision: Union[str, None] = "018"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_STATUS = sa.Enum(
    "pending",
    "approved",
    "rejected",
    name="attendancecorrectionstatus",
)


def upgrade() -> None:
    bind = op.get_bind()
    _STATUS.create(bind, checkfirst=True)

    op.create_table(
        "attendance_correction_request",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("business_id", sa.UUID(), nullable=False),
        sa.Column("employee_id", sa.UUID(), nullable=False),
        sa.Column("shift_assignment_id", sa.UUID(), nullable=False),
        sa.Column("attendance_record_id", sa.UUID(), nullable=True),
        sa.Column("requested_time_in", sa.DateTime(timezone=True), nullable=True),
        sa.Column("requested_time_out", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column(
            "status",
            postgresql.ENUM(
                "pending",
                "approved",
                "rejected",
                name="attendancecorrectionstatus",
                create_type=False,
            ),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("review_note", sa.String(length=500), nullable=True),
        sa.Column("reviewed_by", sa.UUID(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["attendance_record_id"], ["attendance_record.id"]),
        sa.ForeignKeyConstraint(["business_id"], ["business.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["shift_assignment_id"], ["shift_assignment.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["reviewed_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_acr_business_status",
        "attendance_correction_request",
        ["business_id", "status"],
    )
    op.create_index(
        "idx_acr_employee_created",
        "attendance_correction_request",
        ["employee_id", "created_at"],
    )
    op.create_index(
        "idx_acr_assignment",
        "attendance_correction_request",
        ["shift_assignment_id"],
    )


def downgrade() -> None:
    op.drop_index("idx_acr_assignment", table_name="attendance_correction_request")
    op.drop_index("idx_acr_employee_created", table_name="attendance_correction_request")
    op.drop_index("idx_acr_business_status", table_name="attendance_correction_request")
    op.drop_table("attendance_correction_request")
    _STATUS.drop(op.get_bind(), checkfirst=True)
