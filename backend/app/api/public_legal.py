"""Unauthenticated owner-configured legal webpage."""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.legal_consent import PublicLegalPageResponse
from app.services.legal_consent import (
    lookup_business_by_code,
    public_legal_payload,
    render_legal_html_page,
)

router = APIRouter(prefix="/public/legal", tags=["public-legal"])


@router.get("/{business_code}", response_model=PublicLegalPageResponse)
def get_public_legal_page(
    business_code: str,
    db: Annotated[Session, Depends(get_db)],
):
    business = lookup_business_by_code(db, business_code)
    return PublicLegalPageResponse(**public_legal_payload(business))


@router.get("/{business_code}/page")
def get_public_legal_html(
    business_code: str,
    db: Annotated[Session, Depends(get_db)],
):
    business = lookup_business_by_code(db, business_code)
    return render_legal_html_page(business)
