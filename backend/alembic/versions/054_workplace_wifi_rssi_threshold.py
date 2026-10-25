"""Optional workplace Wi-Fi RSSI threshold

Revision ID: 054
Revises: 053
Create Date: 2026-10-25

Adds a nullable minimum signal floor on the workplace location. Existing
rows stay null, so Wi-Fi fallback remains BSSID-only until an owner sets it.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "054"
down_revision: Union[str, None] = "053"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "business_location",
        sa.Column("minimum_rssi_dbm", sa.Integer(), nullable=True),
    )
    op.create_check_constraint(
        "ck_business_location_minimum_rssi_dbm",
        "business_location",
        "minimum_rssi_dbm IS NULL OR "
        "(minimum_rssi_dbm >= -120 AND minimum_rssi_dbm <= -20)",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_business_location_minimum_rssi_dbm",
        "business_location",
        type_="check",
    )
    op.drop_column("business_location", "minimum_rssi_dbm")
