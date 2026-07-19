"""Switch face embeddings to ArcFace R50 (512-d)

Revision ID: 015
Revises: 014
Create Date: 2026-07-19

The recognition model changed from SFace (128-d) to ArcFace R50 (512-d) for
much better separation of lookalikes (e.g. siblings). Old 128-d embeddings are
incompatible and are cleared; everyone must re-enroll their face.

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector

revision: str = "015"
down_revision: Union[str, None] = "014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _swap_embedding_dim(dim: int) -> None:
    # Table is emptied first, so dropping/re-adding the column avoids any
    # vector-dimension cast issues between the old and new models.
    op.execute("DROP INDEX IF EXISTS idx_efe_embedding")
    op.execute("DELETE FROM employee_face_embedding")
    op.drop_column("employee_face_embedding", "embedding")
    op.add_column(
        "employee_face_embedding",
        sa.Column("embedding", Vector(dim), nullable=False),
    )
    op.execute(
        "CREATE INDEX idx_efe_embedding ON employee_face_embedding "
        "USING hnsw (embedding vector_cosine_ops)"
    )
    # Force re-enrollment: old faces can no longer be matched.
    op.execute(
        "UPDATE employee SET face_registration_status = 'not_registered', "
        "face_registered_at = NULL"
    )


def upgrade() -> None:
    _swap_embedding_dim(512)


def downgrade() -> None:
    _swap_embedding_dim(128)
