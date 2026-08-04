"""Business leave policy + leave request paid snapshots

Revision ID: 024
Revises: 023
Create Date: 2026-08-03
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "024"
down_revision: Union[str, None] = "023"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

DEFAULT_TREATMENTS = {
    "sick": True,
    "vacation": True,
    "emergency": False,
    "maternity": True,
    "paternity": True,
    "unpaid": False,
    "other": False,
}


def upgrade() -> None:
    op.create_table(
        "business_leave_policy",
        sa.Column("business_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("treatments", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "config_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
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
        sa.PrimaryKeyConstraint("business_id"),
    )

    op.add_column(
        "leave_request",
        sa.Column("policy_is_paid", sa.Boolean(), nullable=True),
    )
    op.add_column(
        "leave_request",
        sa.Column("is_paid", sa.Boolean(), nullable=True),
    )
    op.add_column(
        "leave_request",
        sa.Column(
            "is_paid_overridden",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )

    # Backfill existing leave rows using previous hardcoded rule.
    op.execute(
        """
        UPDATE leave_request
        SET
            policy_is_paid = (leave_type::text <> 'unpaid'),
            is_paid = (leave_type::text <> 'unpaid'),
            is_paid_overridden = false
        WHERE policy_is_paid IS NULL OR is_paid IS NULL
        """
    )

    op.alter_column("leave_request", "policy_is_paid", nullable=False)
    op.alter_column("leave_request", "is_paid", nullable=False)

    # Seed default leave policy for every existing business.
    conn = op.get_bind()
    business_ids = conn.execute(sa.text("SELECT id FROM business")).fetchall()
    import json

    treatments_json = json.dumps(DEFAULT_TREATMENTS)
    for (business_id,) in business_ids:
        conn.execute(
            sa.text(
                """
                INSERT INTO business_leave_policy (business_id, treatments, config_json)
                VALUES (:business_id, CAST(:treatments AS jsonb), '{}'::jsonb)
                ON CONFLICT (business_id) DO NOTHING
                """
            ),
            {"business_id": str(business_id), "treatments": treatments_json},
        )


def downgrade() -> None:
    op.drop_column("leave_request", "is_paid_overridden")
    op.drop_column("leave_request", "is_paid")
    op.drop_column("leave_request", "policy_is_paid")
    op.drop_table("business_leave_policy")
