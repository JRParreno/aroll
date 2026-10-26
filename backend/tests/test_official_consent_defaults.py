"""Official consent defaults stay identical to the saved platform documents."""

from __future__ import annotations

import hashlib

from sqlalchemy import func

from app.db.session import SessionLocal
from app.models.consent_document import SCOPE_PLATFORM, ConsentDocument
from app.models.consent_record import ConsentRecord
from app.models.platform_legal_document import PlatformLegalDocument
from app.models.user import User
from app.services.consent_catalog import (
    document_published,
    ensure_platform_consent_documents,
    is_legacy_short_consent,
    list_catalog_documents,
    replace_legacy_short_consents,
)
from app.services.legal_consent import (
    ALL_TYPES,
    DEFAULT_VERSIONS,
    content_hash,
    default_legal_content,
    ensure_platform_legal_defaults,
    section_published,
)

# SHA-256 of the platform documents saved in this development database
# before they were copied into app/legal_defaults.
OFFICIAL_SHA256 = {
    "terms": "762a947e931c32ccb14d62d3e6e44a1e2cebeca655e3285a6fc1435c40a96ba5",
    "privacy": "0f236832be59bd48059f4686689fa180176840505b63abbc4fa7b2b54437348c",
    "biometric": "db278ed1fb932d2edefbefcc4f4e02d1788907b7267d5a03548fc41a9c015cd5",
}


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def test_official_files_match_saved_platform_documents():
    for consent_type, expected in OFFICIAL_SHA256.items():
        official = default_legal_content("Aroll+", consent_type)
        named = default_legal_content("North Cafe", consent_type)
        assert _sha(official) == expected
        assert content_hash(official) == expected
        assert named == "North Cafe" + official[len("Aroll+") :]
        assert official.startswith(f"Aroll+ ")
        assert "## " in official


def test_sync_updates_unedited_defaults_without_duplicates_or_lost_acceptances():
    db = SessionLocal()
    originals = []
    catalog_originals = []
    try:
        for consent_type in ALL_TYPES:
            row = db.get(PlatformLegalDocument, consent_type)
            assert row is not None
            originals.append(
                (
                    consent_type,
                    row.content,
                    row.version,
                    row.published,
                    row.updated_by,
                    row.updated_at,
                )
            )
        catalog_rows = [
            row
            for row in list_catalog_documents(
                db, scope=SCOPE_PLATFORM, business_id=None
            )
            if row.consent_type in ALL_TYPES
        ]
        assert len(catalog_rows) == 3
        for row in catalog_rows:
            catalog_originals.append(
                (
                    row.id,
                    row.body_text,
                    row.version,
                    row.is_active,
                    row.is_required,
                    row.title,
                    row.position,
                    row.updated_by,
                    row.updated_at,
                )
            )
        acceptance_count = db.query(func.count(ConsentRecord.id)).scalar()
        sample = db.query(ConsentRecord).order_by(ConsentRecord.created_at.asc()).first()
        sample_snapshot = None if sample is None else (sample.id, sample.content_snapshot, sample.policy_version)

        stale = "Stale seeded consent that must be replaced."
        for consent_type, *_rest in originals:
            row = db.get(PlatformLegalDocument, consent_type)
            row.content = stale
            row.version = DEFAULT_VERSIONS[consent_type]
            row.published = True
            row.updated_by = None
        for row in catalog_rows:
            row.body_text = stale
            row.version = DEFAULT_VERSIONS[row.consent_type]
            row.is_active = True
            row.updated_by = None
            row.file_stored_name = None
        db.commit()

        ensure_platform_legal_defaults(db)
        db.commit()
        ensure_platform_legal_defaults(db)
        db.commit()

        for consent_type in ALL_TYPES:
            official = default_legal_content("Aroll+", consent_type)
            row = db.get(PlatformLegalDocument, consent_type)
            assert row.content == official
            assert row.version == DEFAULT_VERSIONS[consent_type]
            assert section_published(row.content, row.version)
        refreshed = [
            row
            for row in list_catalog_documents(
                db, scope=SCOPE_PLATFORM, business_id=None
            )
            if row.consent_type in ALL_TYPES
        ]
        assert len(refreshed) == 3
        for row in refreshed:
            assert row.body_text == default_legal_content("Aroll+", row.consent_type)
            assert document_published(row)

        assert db.query(func.count(ConsentRecord.id)).scalar() == acceptance_count
        if sample_snapshot is not None:
            kept = db.get(ConsentRecord, sample_snapshot[0])
            assert kept is not None
            assert kept.content_snapshot == sample_snapshot[1]
            assert kept.policy_version == sample_snapshot[2]

        admin = db.query(User).first()
        assert admin is not None
        edited = "Administrator managed consent text."
        terms = db.get(PlatformLegalDocument, "terms")
        terms.content = edited
        terms.version = "terms-admin-kept"
        terms.published = True
        terms.updated_by = admin.id
        catalog_terms = next(row for row in refreshed if row.consent_type == "terms")
        catalog_terms.body_text = edited
        catalog_terms.version = "terms-admin-kept"
        catalog_terms.updated_by = admin.id
        db.commit()

        ensure_platform_legal_defaults(db)
        db.commit()
        assert db.get(PlatformLegalDocument, "terms").content == edited
        kept_catalog = db.get(ConsentDocument, catalog_terms.id)
        assert kept_catalog.body_text == edited
        assert kept_catalog.version == "terms-admin-kept"
    finally:
        for consent_type, content, version, published, updated_by, updated_at in originals:
            row = db.get(PlatformLegalDocument, consent_type)
            if row is None:
                continue
            row.content = content
            row.version = version
            row.published = published
            row.updated_by = updated_by
            row.updated_at = updated_at
        for (
            row_id,
            body_text,
            version,
            is_active,
            is_required,
            title,
            position,
            updated_by,
            updated_at,
        ) in catalog_originals:
            row = db.get(ConsentDocument, row_id)
            if row is None:
                continue
            row.body_text = body_text
            row.version = version
            row.is_active = is_active
            row.is_required = is_required
            row.title = title
            row.position = position
            row.updated_by = updated_by
            row.updated_at = updated_at
        db.commit()
        db.close()


def test_legacy_short_consent_is_replaced_and_rewritten_text_is_kept():
    legacy_privacy = (
        "North Cafe Privacy Policy\n\n"
        "Aroll+ processes account, attendance, location (for geofence checks), "
        "and face embedding data to provide workplace timekeeping.\n\n"
        "Face images are processed to create numeric templates and are not "
        "kept as a long-term photo album. Data is isolated to this business "
        "and is not used for marketing.\n\n"
        "You may request access, correction, or deletion of biometric templates "
        "through your employer. Aroll+ is intended for adult employees (18+)."
    )
    rewritten = "Administrator managed privacy text."
    assert is_legacy_short_consent(legacy_privacy, "privacy")
    assert not is_legacy_short_consent(rewritten, "privacy")
    assert not is_legacy_short_consent(
        default_legal_content("Aroll+", "privacy"), "privacy"
    )

    db = SessionLocal()
    row = (
        db.query(ConsentDocument)
        .filter(
            ConsentDocument.scope == SCOPE_PLATFORM,
            ConsentDocument.consent_type == "privacy",
        )
        .one()
    )
    original = (
        row.body_text,
        row.version,
        row.updated_by,
        row.updated_at,
        row.file_stored_name,
    )
    try:
        row.body_text = legacy_privacy
        row.updated_by = db.query(User).first().id
        db.commit()
        replace_legacy_short_consents(db)
        db.commit()
        db.refresh(row)
        assert row.body_text == default_legal_content("Aroll+", "privacy")
        assert row.version == original[1]
        assert "## Information Aroll+ uses" in row.body_text

        row.body_text = rewritten
        db.commit()
        replace_legacy_short_consents(db)
        db.commit()
        db.refresh(row)
        assert row.body_text == rewritten
    finally:
        row.body_text, row.version, row.updated_by, row.updated_at, row.file_stored_name = original
        db.commit()
        db.close()


def test_catalog_ensure_does_not_insert_a_second_core_document():
    db = SessionLocal()
    try:
        before = (
            db.query(func.count(ConsentDocument.id))
            .filter(
                ConsentDocument.scope == SCOPE_PLATFORM,
                ConsentDocument.consent_type.in_(ALL_TYPES),
            )
            .scalar()
        )
        ensure_platform_consent_documents(db)
        db.commit()
        ensure_platform_consent_documents(db)
        db.commit()
        after = (
            db.query(func.count(ConsentDocument.id))
            .filter(
                ConsentDocument.scope == SCOPE_PLATFORM,
                ConsentDocument.consent_type.in_(ALL_TYPES),
            )
            .scalar()
        )
        assert before == after == 3
    finally:
        db.close()
