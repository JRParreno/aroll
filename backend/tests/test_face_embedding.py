"""Unit tests for OpenCV face embedding helpers."""

from __future__ import annotations

import numpy as np
import pytest

from app.services.face_embedding import (
    FacePipelineError,
    cosine_similarity,
    detect_and_embed,
    match_passed,
)


def _synthetic_face_jpeg(*, seed: int = 0, size: int = 240) -> bytes:
    """Draw a blob that Haar cascade often accepts as a face-like region.

    For unit tests of decode/embed path we inject a real crop via detect path
    only when cascade finds something. Prefer testing cosine helpers and
    embedding-from-bytes error cases; full cascade coverage is integration.
    """
    import cv2

    rng = np.random.default_rng(seed)
    img = np.full((size, size, 3), 220, dtype=np.uint8)
    # Oval "head" with darker eyes/mouth — improves cascade hit rate.
    cv2.ellipse(img, (size // 2, size // 2), (70, 90), 0, 0, 360, (180, 160, 140), -1)
    cv2.circle(img, (size // 2 - 25, size // 2 - 20), 8, (40, 40, 40), -1)
    cv2.circle(img, (size // 2 + 25, size // 2 - 20), 8, (40, 40, 40), -1)
    cv2.ellipse(img, (size // 2, size // 2 + 30), (25, 12), 0, 0, 180, (60, 40, 40), 2)
    noise = rng.integers(0, 15, img.shape, dtype=np.uint8)
    img = cv2.add(img, noise)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def test_cosine_similarity_identical():
    a = [1.0, 0.0, 0.0]
    assert cosine_similarity(a, a) == pytest.approx(1.0)


def test_cosine_similarity_orthogonal():
    a = [1.0, 0.0]
    b = [0.0, 1.0]
    assert cosine_similarity(a, b) == pytest.approx(0.0)


def test_match_passed_threshold():
    assert match_passed(0.8, threshold=0.72) is True
    assert match_passed(0.5, threshold=0.72) is False


def test_invalid_image_raises():
    with pytest.raises(FacePipelineError) as exc:
        detect_and_embed(b"not-an-image")
    assert exc.value.detail["code"] == "invalid_image"


def test_empty_image_raises():
    with pytest.raises(FacePipelineError) as exc:
        detect_and_embed(b"")
    assert exc.value.detail["code"] == "invalid_image"


def test_detect_and_embed_returns_128_when_face_found():
    """Cascade may miss synthetic faces; skip if environment cannot detect."""
    data = _synthetic_face_jpeg()
    try:
        vec = detect_and_embed(data)
    except FacePipelineError as exc:
        if exc.detail.get("code") == "no_face":
            pytest.skip("Haar cascade did not detect synthetic face in this env")
        raise
    assert len(vec) == 128
    norm = float(np.linalg.norm(vec))
    assert norm == pytest.approx(1.0, abs=1e-5)
