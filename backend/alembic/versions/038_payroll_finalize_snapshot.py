"""Payroll finalize snapshots: version, audit config, unique payslip

Revision ID: 038
Revises: 037
Create Date: 2026-09-17

Phase 1 stores immutable Payslip.breakdown_json at finalization. Existing
typed summary columns are filled from the live payslip. employee_id becomes
nullable with ON DELETE SET NULL so deleting an employee cannot erase
historical snapshots. Uniqueness is (payroll_run_id, employee_id).
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "038"
down_revision: Union[str, None] = "037"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _foreign_key_name(table: str, column: str) -> str | None:
    inspector = sa.inspect(op.get_bind())
    for fk in inspector.get_foreign_keys(table):
        if fk.get("constrained_columns") == [column]:
            return fk.get("name")
    return None


def upgrade() -> None:
    op.add_column(
        "payroll_run",
        sa.Column("snapshot_version", sa.Integer(), nullable=True),
    )
    op.add_column(
        "payroll_run",
        sa.Column(
            "calculation_config_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )

    op.alter_column(
        "payslip",
        "employee_id",
        existing_type=postgresql.UUID(as_uuid=True),
        nullable=True,
    )
    fk_name = _foreign_key_name("payslip", "employee_id")
    if fk_name:
        op.drop_constraint(fk_name, "payslip", type_="foreignkey")
    op.create_foreign_key(
        "payslip_employee_id_fkey",
        "payslip",
        "employee",
        ["employee_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint(
        "uq_payslip_run_employee",
        "payslip",
        ["payroll_run_id", "employee_id"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_payslip_run_employee", "payslip", type_="unique")
    op.drop_constraint("payslip_employee_id_fkey", "payslip", type_="foreignkey")
    op.alter_column(
        "payslip",
        "employee_id",
        existing_type=postgresql.UUID(as_uuid=True),
        nullable=False,
    )
    op.create_foreign_key(
        "payslip_employee_id_fkey",
        "payslip",
        "employee",
        ["employee_id"],
        ["id"],
    )
    op.drop_column("payroll_run", "calculation_config_json")
    op.drop_column("payroll_run", "snapshot_version")
