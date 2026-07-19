"""Face detection + recognition using OpenCV zoo / InsightFace ONNX models.

Detection: YuNet (face_detection_yunet_2023mar.onnx) — box + 5 landmarks.
Recognition: ArcFace ResNet-50 (arcface_w600k_r50.onnx, InsightFace buffalo_l)
— 512-d embeddings, which matches the vector(512) column in
employee_face_embedding. ArcFace separates lookalikes (e.g. siblings) far
better than the previous lightweight SFace model.

Both models run natively through OpenCV (cv2.FaceDetectorYN + cv2.dnn); no
extra Python dependencies are required. The ArcFace model is licensed by
InsightFace for non-commercial / academic research use.
"""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 512
MODEL_VERSION = "arcface_r50_v1"

_MODELS_DIR = Path(__file__).resolve().parent.parent.parent / "models"
_DETECTOR_PATH = _MODELS_DIR / "face_detection_yunet_2023mar.onnx"
_RECOGNIZER_PATH = _MODELS_DIR / "arcface_w600k_r50.onnx"

# YuNet score threshold; detections below this are ignored.
_DETECT_SCORE_THRESHOLD = 0.7
# Cap the longer image side before detection to keep inference fast.
_MAX_DETECT_SIDE = 1280

# ArcFace canonical 5-point template (112x112), order:
# left_eye, right_eye, nose, left_mouth, right_mouth.
_ARCFACE_REF = np.array(
    [
        [38.2946, 51.6963],
        [73.5318, 51.5014],
        [56.0252, 71.7366],
        [41.5493, 92.3655],
        [70.7299, 92.2041],
    ],
    dtype=np.float32,
)

_lock = threading.Lock()
_detector: cv2.FaceDetectorYN | None = None
_recognizer: cv2.dnn.Net | None = None


class FacePipelineError(HTTPException):
    def __init__(self, code: str, message: str, status_code: int = 400) -> None:
        super().__init__(
            status_code=status_code,
            detail={"code": code, "message": message},
        )


@dataclass(frozen=True)
class FaceObservation:
    """Structured face observation for recognition and liveness checks."""

    embedding: list[float]
    score: float
    # Normalized yaw proxy: nose_x offset from eye midpoint / inter-eye distance.
    # Negative ≈ looking left (subject's left / camera-right), positive ≈ looking right.
    yaw: float
    left_eye: tuple[float, float]
    right_eye: tuple[float, float]
    nose: tuple[float, float]
    box: tuple[float, float, float, float]
    face_count: int = 1


def _load_models() -> tuple[cv2.FaceDetectorYN, cv2.dnn.Net]:
    global _detector, _recognizer
    with _lock:
        if _detector is None or _recognizer is None:
            if not _DETECTOR_PATH.is_file() or not _RECOGNIZER_PATH.is_file():
                raise FacePipelineError(
                    "face_models_missing",
                    "Face models are missing on the server. Download YuNet and "
                    f"ArcFace (arcface_w600k_r50.onnx) ONNX files into {_MODELS_DIR}.",
                    status_code=500,
                )
            _detector = cv2.FaceDetectorYN.create(
                str(_DETECTOR_PATH),
                "",
                (320, 320),
                score_threshold=_DETECT_SCORE_THRESHOLD,
            )
            _recognizer = cv2.dnn.readNetFromONNX(str(_RECOGNIZER_PATH))
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


def _yaw_from_landmarks(
    left_eye: tuple[float, float],
    right_eye: tuple[float, float],
    nose: tuple[float, float],
) -> float:
    """Approximate yaw from YuNet landmarks.

    Positive values mean the nose is shifted toward the subject's right
    (image-left for a mirrored webcam feed, but we use landmark coords as-is).
    """
    eye_mid_x = (left_eye[0] + right_eye[0]) / 2.0
    inter_eye = abs(right_eye[0] - left_eye[0])
    if inter_eye < 1e-3:
        return 0.0
    return float((nose[0] - eye_mid_x) / inter_eye)


def _arcface_embedding(image: np.ndarray, face: np.ndarray) -> np.ndarray:
    """Align the face to the ArcFace template and return a 512-d feature."""
    # YuNet landmark order: right_eye, left_eye, nose, right_mouth, left_mouth.
    # Reorder to the ArcFace template order.
    src = np.array(
        [
            [face[6], face[7]],  # left_eye
            [face[4], face[5]],  # right_eye
            [face[8], face[9]],  # nose
            [face[12], face[13]],  # left_mouth
            [face[10], face[11]],  # right_mouth
        ],
        dtype=np.float32,
    )
    matrix, _ = cv2.estimateAffinePartial2D(src, _ARCFACE_REF, method=cv2.LMEDS)
    if matrix is None:
        raise FacePipelineError(
            "weak_face",
            "Could not align the face. Try a clearer, front-facing photo.",
        )
    aligned = cv2.warpAffine(image, matrix, (112, 112), borderValue=0)
    blob = cv2.dnn.blobFromImage(
        aligned, 1.0 / 127.5, (112, 112), (127.5, 127.5, 127.5), swapRB=True
    )
    _, recognizer = _load_models()
    with _lock:
        recognizer.setInput(blob)
        feature = recognizer.forward()
    return np.asarray(feature, dtype=np.float64).ravel()


def detect_and_observe(image_bytes: bytes) -> FaceObservation:
    """Detect the most prominent face and return embedding + landmarks."""
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
    # YuNet face row: x, y, w, h, right_eye_x, right_eye_y, left_eye_x, left_eye_y,
    # nose_x, nose_y, right_mouth_x, right_mouth_y, left_mouth_x, left_mouth_y, score
    right_eye = (float(face[4]), float(face[5]))
    left_eye = (float(face[6]), float(face[7]))
    nose = (float(face[8]), float(face[9]))
    score = float(face[14])
    box = (float(face[0]), float(face[1]), float(face[2]), float(face[3]))

    vec = _arcface_embedding(image, face)
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

    return FaceObservation(
        embedding=(vec / norm).tolist(),
        score=score,
        yaw=_yaw_from_landmarks(left_eye, right_eye, nose),
        left_eye=left_eye,
        right_eye=right_eye,
        nose=nose,
        box=box,
        face_count=int(faces.shape[0]),
    )


def detect_and_embed(image_bytes: bytes) -> list[float]:
    """Detect the most prominent face and return a 512-d ArcFace embedding."""
    return detect_and_observe(image_bytes).embedding


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
    """Highest similarity to any enrolled sample (lenient — lookalikes can luck out)."""
    if not gallery:
        return 0.0
    return max(cosine_similarity(probe, sample) for sample in gallery)


def mean_match_score(
    probe: list[float],
    gallery: list[list[float]],
) -> float:
    """Average similarity across all enrolled samples.

    Stricter than best/max: a sibling who luckily matches one enrollment photo
    still has to look like the rest of the gallery.
    """
    if not gallery:
        return 0.0
    scores = [cosine_similarity(probe, sample) for sample in gallery]
    return float(sum(scores) / len(scores))


def match_passed(score: float, threshold: float | None = None) -> bool:
    limit = settings.face_match_threshold if threshold is None else threshold
    return score >= limit
