"""Unauthenticated per-document consent page and file."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.services.consent_catalog import (
    catalog_item_payload,
    document_published,
    file_response,
    get_document,
    render_document_html,
)

router = APIRouter(prefix="/public/consents", tags=["public-consents"])


def _published_document(db: Session, document_id: UUID):
    document = get_document(db, document_id)
    if not document_published(document):
        raise HTTPException(404, "Consent document not found")
    return document


@router.get("/{document_id}")
def get_public_consent_document(
    document_id: UUID,
    db: Annotated[Session, Depends(get_db)],
):
    document = _published_document(db, document_id)
    payload = catalog_item_payload(document)
    payload.pop("body_text", None)
    return payload


@router.get("/{document_id}/page")
def get_public_consent_page(
    document_id: UUID,
    db: Annotated[Session, Depends(get_db)],
):
    document = _published_document(db, document_id)
    return render_document_html(document)


@router.get("/{document_id}/file")
def get_public_consent_file(
    document_id: UUID,
    db: Annotated[Session, Depends(get_db)],
):
    document = _published_document(db, document_id)
    return file_response(document)
