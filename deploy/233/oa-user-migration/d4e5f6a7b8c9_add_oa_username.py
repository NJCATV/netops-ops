"""为统一用户增加 OA 登录账号

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-07-19
"""

from alembic import op
import sqlalchemy as sa


revision = "d4e5f6a7b8c9"
down_revision = "c3d4e5f6a7b8"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("oa_username", sa.String(length=64), nullable=True))
    op.create_unique_constraint("uq_users_oa_username", "users", ["oa_username"])


def downgrade():
    op.drop_constraint("uq_users_oa_username", "users", type_="unique")
    op.drop_column("users", "oa_username")
