import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import require_roles
from app.db.session import get_db
from app.models.enums import UserRole
from app.models.user import User
from app.schemas.schedule_reuse import (
    ScheduleReuseApplyRequest,
    ScheduleReuseApplyResponse,
    ScheduleReusePreviewRequest,
    ScheduleReusePreviewResponse,
    ScheduleReuseSuggestionsResponse,
    ScheduleTemplateCreateRequest,
    ScheduleTemplateDetailResponse,
    ScheduleTemplateRenameRequest,
    ScheduleTemplateSummary,
)
from app.services import schedule_reuse as reuse_service

router = APIRouter(prefix="/schedules/reuse", tags=["schedule-reuse"])
templates_router = APIRouter(prefix="/schedules/templates", tags=["schedule-templates"])


def _business_id(user: User) -> uuid.UUID:
    if user.business_id is None:
        raise HTTPException(400, "No business context")
    return user.business_id


@router.get("/suggestions", response_model=ScheduleReuseSuggestionsResponse)
def get_reuse_suggestions(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
    target_week_start: Annotated[date, Query(description="Monday of the target week")],
):
    return reuse_service.reuse_suggestions(
        db, _business_id(user), target_week_start
    )


@router.post("/preview", response_model=ScheduleReusePreviewResponse)
def preview_schedule_reuse(
    body: ScheduleReusePreviewRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return reuse_service.build_preview(
        db,
        _business_id(user),
        body.source,
        body.target_week_start,
        body.source_week_start,
        body.template_id,
    )


@router.post("/apply", response_model=ScheduleReuseApplyResponse)
def apply_schedule_reuse(
    body: ScheduleReuseApplyRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return reuse_service.apply_reuse(
        db,
        _business_id(user),
        body.source,
        body.target_week_start,
        body.conflict_mode,
        body.source_week_start,
        body.template_id,
    )


@templates_router.get("", response_model=list[ScheduleTemplateSummary])
def list_schedule_templates(
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return reuse_service.list_templates(db, _business_id(user))


@templates_router.post("", response_model=ScheduleTemplateSummary, status_code=201)
def create_schedule_template(
    body: ScheduleTemplateCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return reuse_service.create_template_from_week(
        db,
        _business_id(user),
        body.name,
        body.week_start,
        user.id,
    )


@templates_router.get("/{template_id}", response_model=ScheduleTemplateDetailResponse)
def get_schedule_template(
    template_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return reuse_service.get_template_detail(db, _business_id(user), template_id)


@templates_router.patch("/{template_id}", response_model=ScheduleTemplateSummary)
def rename_schedule_template(
    template_id: uuid.UUID,
    body: ScheduleTemplateRenameRequest,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    return reuse_service.rename_template(
        db, _business_id(user), template_id, body.name
    )


@templates_router.delete("/{template_id}")
def delete_schedule_template(
    template_id: uuid.UUID,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User, Depends(require_roles(UserRole.owner, UserRole.manager))],
):
    reuse_service.delete_template(db, _business_id(user), template_id)
    return {"status": "ok"}
