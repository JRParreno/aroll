"""Face detection + recognition using OpenCV zoo ONNX models.

Detection: YuNet (face_detection_yunet_2023mar.onnx)
Recognition: SFace (face_recognition_sface_2021dec.onnx) — 128-d embeddings,
which matches the vector(128) column in employee_face_embedding.

Both models run natively through OpenCV (cv2.FaceDetectorYN /
cv2.FaceRecognizerSF); no extra Python dependencies are required.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

import cv2
import numpy as np
from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 128
MODEL_VERSION = "sface_v3"

_MODELS_DIR = Path(__file__).resolve().parent.parent.parent / "models"
_DETECTOR_PATH = _MODELS_DIR / "face_detection_yunet_2023mar.onnx"
_RECOGNIZER_PATH = _MODELS_DIR / "face_recognition_sface_2021dec.onnx"

# YuNet score threshold; detections below this are ignored.
_DETECT_SCORE_THRESHOLD = 0.7
# Cap the longer image side before detection to keep inference fast.
_MAX_DETECT_SIDE = 1280

_lock = threading.Lock()
_detector: cv2.FaceDetectorYN | None = None
_recognizer: cv2.FaceRecognizerSF | None = None


class FacePipelineError(HTTPException):
    def __init__(self, code: str, message: str, status_code: int = 400) -> None:
        super().__init__(
            status_code=status_code,
            detail={"code": code, "message": message},
        )


def _load_models() -> tuple[cv2.FaceDetectorYN, cv2.FaceRecognizerSF]:
    global _detector, _recognizer
    with _lock:
        if _detector is None or _recognizer is None:
            if not _DETECTOR_PATH.is_file() or not _RECOGNIZER_PATH.is_file():
                raise FacePipelineError(
                    "face_models_missing",
                    "Face models are missing on the server. Download YuNet and "
                    f"SFace ONNX files into {_MODELS_DIR}.",
                    status_code=500,
                )
            _detector = cv2.FaceDetectorYN.create(
                str(_DETECTOR_PATH),
                "",
                (320, 320),
                score_threshold=_DETECT_SCORE_THRESHOLD,
            )
            _recognizer = cv2.FaceRecognizerSF.create(str(_RECOGNIZER_PATH), "")
        return _detector, _recognizer


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


def _detect_faces(image: np.ndarray) -> np.ndarray:
    """Return YuNet detections (N x 15 array) for the image."""
    detector, _ = _load_models()

    scale = 1.0
    h, w = image.shape[:2]
    longest = max(h, w)
    if longest > _MAX_DETECT_SIDE:
        scale = _MAX_DETECT_SIDE / longest
        image = cv2.resize(image, (int(w * scale), int(h * scale)))
        h, w = image.shape[:2]

    with _lock:
        detector.setInputSize((w, h))
        _, faces = detector.detect(image)

    if faces is None or len(faces) == 0:
        return np.empty((0, 15), dtype=np.float32)
    if scale != 1.0:
        faces = faces.copy()
        # First 14 columns are coordinates (box + landmarks); rescale to original.
        faces[:, :14] /= scale
    return faces


def _largest_face(faces: np.ndarray) -> np.ndarray:
    areas = faces[:, 2] * faces[:, 3]
    return faces[int(np.argmax(areas))]


def detect_and_embed(image_bytes: bytes) -> list[float]:
    """Detect the most prominent face and return a 128-d SFace embedding."""
    image = _decode_image(image_bytes)
    faces = _detect_faces(image)

    if faces.shape[0] == 0:
        raise FacePipelineError(
            "no_face",
            "No face detected. Face the camera with good lighting and try again.",
        )
    if faces.shape[0] > 1:
        logger.info("Multiple faces detected (%s); using largest.", faces.shape[0])

    face = _largest_face(faces)
    _, recognizer = _load_models()
    with _lock:
        aligned = recognizer.alignCrop(image, face)
        feature = recognizer.feature(aligned)

    vec = np.asarray(feature, dtype=np.float64).ravel()
    if vec.shape[0] != EMBEDDING_DIM:
        raise FacePipelineError(
            "embedding_error",
            f"Unexpected embedding size {vec.shape[0]} (expected {EMBEDDING_DIM}).",
            status_code=500,
        )

    norm = np.linalg.norm(vec)
    if norm < 1e-8:
        raise FacePipelineError(
            "weak_face",
            "Could not build a face embedding from this image. Try better lighting.",
        )
    return (vec / norm).tolist()


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
