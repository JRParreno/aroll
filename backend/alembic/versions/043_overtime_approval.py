"""OT approval required + attendance OT approval status.

Revision ID: 043
Revises: 042
Create Date: 2026-09-22

When overtime_approval_required is false (default), payroll OT pay is unchanged.
When true, qualifying OT is recorded on the attendance punch and becomes
payable only after Owner/manager approval. Rejected OT stays worked, not paid.
Does not change attendance Time In/Time Out.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "043"
down_revision: Union[str, None] = "042"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

ot_approval_status = postgresql.ENUM(
    "pending",
    "approved",
    "rejected",
    name="overtimeapprovalstatus",
    create_type=False,
)


def upgrade() -> None:
    ot_approval_status.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "business_payroll_config",
        sa.Column(
            "overtime_approval_required",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column(
        "attendance_record",
        sa.Column(
            "ot_approval_status",
            ot_approval_status,
            nullable=True,
        ),
    )
    op.add_column(
        "attendance_record",
        sa.Column(
            "ot_reviewed_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user.id"),
            nullable=True,
        ),
    )
    op.add_column(
        "attendance_record",
        sa.Column(
            "ot_reviewed_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.create_index(
        "ix_attendance_record_ot_approval_status",
        "attendance_record",
        ["business_id", "ot_approval_status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_attendance_record_ot_approval_status",
        table_name="attendance_record",
    )
    op.drop_column("attendance_record", "ot_reviewed_at")
    op.drop_column("attendance_record", "ot_reviewed_by")
    op.drop_column("attendance_record", "ot_approval_status")
    op.drop_column("business_payroll_config", "overtime_approval_required")
    ot_approval_status.drop(op.get_bind(), checkfirst=True)
