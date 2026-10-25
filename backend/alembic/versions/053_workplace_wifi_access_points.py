"""Optional workplace Wi-Fi access points

Revision ID: 053
Revises: 052
Create Date: 2026-10-24

Adds an owner-managed allow-list per worksite and nullable attendance
evidence columns. Existing locations and attendance rows are unchanged.
Wi-Fi stays opt-in until an owner registers an access point.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "053"
down_revision: Union[str, None] = "052"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "workplace_wifi_access_point",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column(
            "business_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("business.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "location_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("business_location.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("label", sa.String(length=80), nullable=False),
        sa.Column("ssid", sa.String(length=64), nullable=True),
        sa.Column("bssid", sa.String(length=17), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "location_id",
            "bssid",
            name="uq_workplace_wifi_location_bssid",
        ),
    )
    op.create_index(
        "ix_workplace_wifi_location_id",
        "workplace_wifi_access_point",
        ["location_id"],
    )
    op.add_column(
        "attendance_record",
        sa.Column("wifi_verification_in", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "attendance_record",
        sa.Column("wifi_verification_out", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "attendance_record",
        sa.Column(
            "matched_wifi_access_point_id_in",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.add_column(
        "attendance_record",
        sa.Column(
            "matched_wifi_access_point_id_out",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.create_foreign_key(
        "fk_attendance_wifi_ap_in",
        "attendance_record",
        "workplace_wifi_access_point",
        ["matched_wifi_access_point_id_in"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_attendance_wifi_ap_out",
        "attendance_record",
        "workplace_wifi_access_point",
        ["matched_wifi_access_point_id_out"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_attendance_wifi_ap_out", "attendance_record", type_="foreignkey")
    op.drop_constraint("fk_attendance_wifi_ap_in", "attendance_record", type_="foreignkey")
    op.drop_column("attendance_record", "matched_wifi_access_point_id_out")
    op.drop_column("attendance_record", "matched_wifi_access_point_id_in")
    op.drop_column("attendance_record", "wifi_verification_out")
    op.drop_column("attendance_record", "wifi_verification_in")
    op.drop_index("ix_workplace_wifi_location_id", table_name="workplace_wifi_access_point")
    op.drop_table("workplace_wifi_access_point")
