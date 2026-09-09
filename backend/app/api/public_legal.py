from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.business import Business
from app.schemas.legal_consent import PublicLegalPageResponse
from app.services.legal_consent import (
    ensure_legal_consent_url,
    render_legal_html_page,
    resolve_legal_content,
)

router = APIRouter(prefix="/public/legal", tags=["public-legal"])


def _normalize_business_code(value: str) -> str:
    return value.strip().upper().replace(" ", "")


def _business_by_code(db: Session, business_code: str) -> Business:
    code = _normalize_business_code(business_code)
    if not code:
        raise HTTPException(404, "Business not found")
    business = (
        db.query(Business)
        .filter(func.upper(Business.business_code) == code)
        .first()
    )
    if business is None:
        raise HTTPException(404, "Business not found")
    ensure_legal_consent_url(business)
    return business


@router.get("/{business_code}", response_model=PublicLegalPageResponse)
def get_public_legal_page(
    business_code: str,
    db: Annotated[Session, Depends(get_db)],
):
    business = _business_by_code(db, business_code)
    return PublicLegalPageResponse(
        business_name=business.name,
        business_code=business.business_code,
        legal_consent_url=ensure_legal_consent_url(business),
        content=resolve_legal_content(business),
        updated_at=business.legal_consent_updated_at,
        is_demo=bool(business.is_demo),
    )


@router.get("/{business_code}/page")
def get_public_legal_html_page(
    business_code: str,
    db: Annotated[Session, Depends(get_db)],
):
    business = _business_by_code(db, business_code)
    return render_legal_html_page(business)
