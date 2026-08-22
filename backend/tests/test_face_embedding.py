"""Unit tests for OpenCV face embedding helpers."""

from __future__ import annotations

import numpy as np
import pytest

from app.services.face_embedding import (
    EMBEDDING_DIM,
    FacePipelineError,
    best_match_score,
    cosine_similarity,
    detect_and_embed,
    match_passed,
    mean_match_score,
    min_match_score,
    robust_match_score,
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
    assert match_passed(0.55, threshold=0.50) is True
    assert match_passed(0.40, threshold=0.50) is False


def test_yunet_to_arcface_landmarks_keeps_image_left_eye_first():
    """Frontal face: anatomical right eye is image-left and must map to ArcFace[0]."""
    import numpy as np

    from app.services.face_embedding import _yunet_to_arcface_landmarks

    # Synthetic YuNet row: right_eye at x=40, left_eye at x=80 (frontal).
    face = np.zeros(15, dtype=np.float32)
    face[4], face[5] = 40.0, 50.0  # right eye (image-left)
    face[6], face[7] = 80.0, 50.0  # left eye (image-right)
    face[8], face[9] = 60.0, 70.0
    face[10], face[11] = 45.0, 90.0  # right mouth
    face[12], face[13] = 75.0, 90.0  # left mouth
    src = _yunet_to_arcface_landmarks(face)
    assert src[0, 0] < src[1, 0]
    assert src[3, 0] < src[4, 0]


def test_identity_match_dual_gate_balances_far_frr():
    """Mean+min dual gate on ArcFace cosine scale (post landmark fix)."""
    from app.services.face_embedding import identity_match_passed

    # Impostor band for correct ArcFace is typically well below 0.40.
    assert (
        identity_match_passed(
            mean_score=0.35,
            min_score=0.30,
            centroid_score=0.34,
            threshold=0.50,
            min_threshold=0.42,
        )
        is False
    )
    # Genuine live probe on correctly aligned ArcFace.
    assert (
        identity_match_passed(
            mean_score=0.62,
            min_score=0.55,
            centroid_score=0.60,
            threshold=0.50,
            min_threshold=0.42,
        )
        is True
    )
    # High mean without a strong min must fail.
    assert (
        identity_match_passed(
            mean_score=0.60,
            min_score=0.30,
            centroid_score=0.58,
            threshold=0.50,
            min_threshold=0.42,
        )
        is False
    )


def test_mean_match_stricter_than_best():
    """A lookalike that luckily hits one enrolled sample still fails on mean."""
    probe = [1.0, 0.0, 0.0]
    gallery = [
        [1.0, 0.0, 0.0],  # identical → 1.0
        [0.0, 1.0, 0.0],  # orthogonal → 0.0
        [0.0, 0.0, 1.0],  # orthogonal → 0.0
    ]
    assert best_match_score(probe, gallery) == pytest.approx(1.0)
    assert mean_match_score(probe, gallery) == pytest.approx(1.0 / 3.0)
    assert match_passed(best_match_score(probe, gallery), threshold=0.50) is True
    assert match_passed(mean_match_score(probe, gallery), threshold=0.50) is False


def test_attendance_identity_uses_mean_not_single_hit():
    """Attendance must not accept a stranger who luckily matches one sample."""
    probe = [1.0, 0.0, 0.0]
    gallery = [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
    ]
    score = mean_match_score(probe, gallery)
    assert score == pytest.approx(1.0 / 3.0)
    assert match_passed(score, threshold=0.50) is False


def test_robust_match_ignores_weak_outlier_but_blocks_single_hit():
    """Top-2/3 mean tolerates one weak enrollment sample, not a one-hit lookalike."""
    probe = [1.0, 0.0, 0.0]
    # Unit-ish vectors for predictable cosine scores.
    genuine_gallery = [
        [1.0, 0.0, 0.0],  # cos = 1.0
        [0.9, 0.4358898943540673, 0.0],  # cos ≈ 0.9
        [0.0, 1.0, 0.0],  # cos = 0.0 outlier
    ]
    # top 2 of 3 → (1.0 + 0.9) / 2 = 0.95
    assert robust_match_score(probe, genuine_gallery) == pytest.approx(0.95)

    lookalike_gallery = [
        [1.0, 0.0, 0.0],  # lucky hit 1.0
        [0.0, 1.0, 0.0],  # 0.0
        [0.0, 0.0, 1.0],  # 0.0
    ]
    # top 2 of 3 → (1.0 + 0.0) / 2 = 0.5 — below a strict ArcFace mean gate.
    assert robust_match_score(probe, lookalike_gallery) == pytest.approx(0.5)
    assert match_passed(robust_match_score(probe, lookalike_gallery), threshold=0.51) is False
    assert match_passed(robust_match_score(probe, genuine_gallery), threshold=0.50) is True
    # Attendance path uses mean — lookalike gallery mean is ~0.33.
    assert match_passed(mean_match_score(probe, lookalike_gallery), threshold=0.50) is False
    # Genuine gallery with one orthogonal outlier: mean ≈ 0.633 still clears 0.50,
    # which is why attendance also requires min_match against every sample.
    assert mean_match_score(probe, genuine_gallery) == pytest.approx(0.6333333333, rel=1e-3)
    assert min_match_score(probe, genuine_gallery) == pytest.approx(0.0)
    # A clean genuine gallery should pass mean at 0.50:
    clean_gallery = [
        [1.0, 0.0, 0.0],
        [0.95, 0.3122498999, 0.0],
        [0.92, 0.3919183588, 0.0],
    ]
    assert match_passed(mean_match_score(probe, clean_gallery), threshold=0.50) is True

def test_invalid_image_raises():
    with pytest.raises(FacePipelineError) as exc:
        detect_and_embed(b"not-an-image")
    assert exc.value.detail["code"] == "invalid_image"


def test_empty_image_raises():
    with pytest.raises(FacePipelineError) as exc:
        detect_and_embed(b"")
    assert exc.value.detail["code"] == "invalid_image"


def test_detect_and_embed_returns_embedding_when_face_found():
    """Detector may miss synthetic faces; skip if environment cannot detect."""
    data = _synthetic_face_jpeg()
    try:
        vec = detect_and_embed(data)
    except FacePipelineError as exc:
        if exc.detail.get("code") in ("no_face", "weak_face"):
            pytest.skip("Detector did not find the synthetic face in this env")
        raise
    assert len(vec) == EMBEDDING_DIM
    norm = float(np.linalg.norm(vec))
    assert norm == pytest.approx(1.0, abs=1e-5)
