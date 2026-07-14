"""Employee face embedding table for pgvector matching

Revision ID: 013
Revises: 012
Create Date: 2026-07-14

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector

revision: str = "013"
down_revision: Union[str, None] = "012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    op.create_table(
        "employee_face_embedding",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("employee_id", sa.UUID(), nullable=False),
        sa.Column("embedding", Vector(128), nullable=False),
        sa.Column("model_version", sa.String(length=50), nullable=False),
        sa.Column("sample_index", sa.SmallInteger(), nullable=False),
        sa.Column("enrolled_by", sa.UUID(), nullable=False),
        sa.Column(
            "enrolled_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["employee_id"], ["employee.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["enrolled_by"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_efe_employee_id",
        "employee_face_embedding",
        ["employee_id"],
    )
    op.execute(
        "CREATE INDEX idx_efe_embedding ON employee_face_embedding "
        "USING hnsw (embedding vector_cosine_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_efe_embedding")
    op.drop_index("idx_efe_employee_id", table_name="employee_face_embedding")
    op.drop_table("employee_face_embedding")
