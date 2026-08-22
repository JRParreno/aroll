"""Leave requests module and attendance on_leave status

Revision ID: 022
Revises: 021
Create Date: 2026-08-03
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "022"
down_revision: Union[str, None] = "021"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_LEAVE_TYPE = sa.Enum(
    "sick",
    "vacation",
    "emergency",
    "maternity",
    "paternity",
    "unpaid",
    "other",
    name="leavetype",
)

_LEAVE_STATUS = sa.Enum(
    "pending",
    "approved",
    "rejected",
    name="leaverequeststatus",
)


def upgrade() -> None:
    bind = op.get_bind()
    op.execute("ALTER TYPE attendancestatus ADD VALUE IF NOT EXISTS 'on_leave'")
    _LEAVE_TYPE.create(bind, checkfirst=True)
    _LEAVE_STATUS.create(bind, checkfirst=True)

    op.create_table(
        "leave_request",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("business_id", sa.UUID(), nullable=False),
        sa.Column("employee_id", sa.UUID(), nullable=False),
        sa.Column(
            "leave_type",
            postgresql.ENUM(
                "sick",
                "vacation",
                "emergency",
                "maternity",
                "paternity",
                "unpaid",
                "other",
                name="leavetype",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("leave_days", sa.Integer(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("supporting_document", sa.Text(), nullable=True),
        sa.Column(
            "status",
            postgresql.ENUM(
                "pending",
                "approved",
                "rejected",
                name="leaverequeststatus",
                create_type=False,
            ),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("owner_remarks", sa.String(length=500), nullable=True),
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
        sa.ForeignKeyConstraint(["business_id"], ["business.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reviewed_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_leave_request_business_id", "leave_request", ["business_id"])
    op.create_index("ix_leave_request_employee_id", "leave_request", ["employee_id"])
    op.create_index("ix_leave_request_status", "leave_request", ["status"])
    op.create_index(
        "ix_leave_request_dates",
        "leave_request",
        ["start_date", "end_date"],
    )


def downgrade() -> None:
    op.drop_index("ix_leave_request_dates", table_name="leave_request")
    op.drop_index("ix_leave_request_status", table_name="leave_request")
    op.drop_index("ix_leave_request_employee_id", table_name="leave_request")
    op.drop_index("ix_leave_request_business_id", table_name="leave_request")
    op.drop_table("leave_request")
    bind = op.get_bind()
    _LEAVE_STATUS.drop(bind, checkfirst=True)
    _LEAVE_TYPE.drop(bind, checkfirst=True)
