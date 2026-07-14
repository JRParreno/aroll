"""OpenCV face detection + 128-d histogram embedding (opencv_hist_v1).

Detects a single face in an image, crops it, and builds an L2-normalized
128-dimensional descriptor from block mean/std features. Swappable later for
ONNX / face_recognition without changing API clients.
"""

from __future__ import annotations

import logging

import cv2
import numpy as np
from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 128
MODEL_VERSION = "opencv_hist_v1"

# Relaxed cascade thresholds so webcam / phone photos work under average lighting.
_SCALE_FACTOR = 1.1
_MIN_NEIGHBORS = 4
_MIN_FACE_SIZE = (48, 48)


class FacePipelineError(HTTPException):
    def __init__(self, code: str, message: str, status_code: int = 400) -> None:
        super().__init__(
            status_code=status_code,
            detail={"code": code, "message": message},
        )


def _cascade() -> cv2.CascadeClassifier:
    path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    classifier = cv2.CascadeClassifier(path)
    if classifier.empty():
        raise FacePipelineError(
            "face_detector_unavailable",
            "Face detector failed to load on the server.",
            status_code=500,
        )
    return classifier


def _decode_image(image_bytes: bytes) -> np.ndarray:
    if not image_bytes:
        raise FacePipelineError("invalid_image", "Empty image upload.")
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image is None:
        raise FacePipelineError(
            "invalid_image",
            "Could not decode image. Use JPEG or PNG.",
        )
    return image


def _detect_faces(gray: np.ndarray) -> list[tuple[int, int, int, int]]:
    classifier = _cascade()
    faces = classifier.detectMultiScale(
        gray,
        scaleFactor=_SCALE_FACTOR,
        minNeighbors=_MIN_NEIGHBORS,
        minSize=_MIN_FACE_SIZE,
        flags=cv2.CASCADE_SCALE_IMAGE,
    )
    return [(int(x), int(y), int(w), int(h)) for x, y, w, h in faces]


def _largest_face(
    faces: list[tuple[int, int, int, int]],
) -> tuple[int, int, int, int]:
    return max(faces, key=lambda f: f[2] * f[3])


def _crop_face(gray: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    x, y, w, h = box
    # Expand crop slightly for context; clamp to image bounds.
    pad_x = int(w * 0.1)
    pad_y = int(h * 0.1)
    x0 = max(0, x - pad_x)
    y0 = max(0, y - pad_y)
    x1 = min(gray.shape[1], x + w + pad_x)
    y1 = min(gray.shape[0], y + h + pad_y)
    crop = gray[y0:y1, x0:x1]
    if crop.size == 0:
        raise FacePipelineError("no_face", "Face crop was empty.")
    return crop


def _embedding_from_crop(crop: np.ndarray) -> list[float]:
    """Build a 128-d L2-normalized descriptor from an 8x8 grid of mean/std."""
    resized = cv2.resize(crop, (64, 64), interpolation=cv2.INTER_AREA)
    resized = cv2.equalizeHist(resized).astype(np.float32) / 255.0

    features: list[float] = []
    block = 8
    for row in range(0, 64, block):
        for col in range(0, 64, block):
            cell = resized[row : row + block, col : col + block]
            features.append(float(cell.mean()))
            features.append(float(cell.std()))

    # 8x8 blocks * 2 = 128 features exactly.
    vec = np.asarray(features[:EMBEDDING_DIM], dtype=np.float64)
    if vec.shape[0] < EMBEDDING_DIM:
        vec = np.pad(vec, (0, EMBEDDING_DIM - vec.shape[0]))

    norm = np.linalg.norm(vec)
    if norm < 1e-8:
        raise FacePipelineError(
            "weak_face",
            "Face image is too uniform to build an embedding. Try better lighting.",
        )
    vec = vec / norm
    return vec.tolist()


def detect_and_embed(image_bytes: bytes) -> list[float]:
    """Detect exactly one face and return a 128-d embedding."""
    image = _decode_image(image_bytes)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = _detect_faces(gray)

    if not faces:
        raise FacePipelineError(
            "no_face",
            "No face detected. Face the camera with good lighting and try again.",
        )
    if len(faces) > 1:
        # Prefer the largest face rather than failing hard on distant people.
        logger.info("Multiple faces detected (%s); using largest.", len(faces))

    crop = _crop_face(gray, _largest_face(faces))
    return _embedding_from_crop(crop)


def cosine_similarity(a: list[float] | np.ndarray, b: list[float] | np.ndarray) -> float:
    va = np.asarray(a, dtype=np.float64)
    vb = np.asarray(b, dtype=np.float64)
    denom = float(np.linalg.norm(va) * np.linalg.norm(vb))
    if denom < 1e-12:
        return 0.0
    return float(np.dot(va, vb) / denom)


def best_match_score(
    probe: list[float],
    gallery: list[list[float]],
) -> float:
    if not gallery:
        return 0.0
    return max(cosine_similarity(probe, sample) for sample in gallery)


def match_passed(score: float, threshold: float | None = None) -> bool:
    limit = settings.face_match_threshold if threshold is None else threshold
    return score >= limit
