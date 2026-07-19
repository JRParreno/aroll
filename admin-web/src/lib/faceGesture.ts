import { FaceLandmarker, FilesetResolver } from "@mediapipe/tasks-vision";

// Client-side liveness helper: detects a blink or smile from the webcam using
// MediaPipe FaceLandmarker blendshapes. This only guides *when* to capture a
// frame. The FastAPI server remains authoritative for identity (ArcFace match).

const WASM_CDN =
  "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm";
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

// Blink is a temporal event: both eyes go from open -> closed -> open.
const BLINK_CLOSED = 0.5; // blendshape score treated as "eye closed"
const BLINK_OPEN = 0.2; // score treated as "eye open" again
// Smile must be held for a few frames to avoid neutral-face false positives.
const SMILE_THRESHOLD = 0.55;
const SMILE_HOLD_FRAMES = 3;

export type GestureKind = "blink" | "smile";

export type GestureReading = {
  faceDetected: boolean;
  blinkScore: number;
  smileScore: number;
  eyesClosed: boolean;
  /** Emitted once on the frame a gesture completes, otherwise null. */
  gesture: GestureKind | null;
};

function scoreOf(
  categories: { categoryName?: string; score: number }[],
  name: string
): number {
  const found = categories.find((c) => c.categoryName === name);
  return found ? found.score : 0;
}

export class GestureLivenessDetector {
  private landmarker: FaceLandmarker;
  private lastVideoTime = -1;
  // Blink finite-state machine.
  private eyesWereClosed = false;
  private smileFrames = 0;
  private smileLatched = false;

  private constructor(landmarker: FaceLandmarker) {
    this.landmarker = landmarker;
  }

  static async create(): Promise<GestureLivenessDetector> {
    const fileset = await FilesetResolver.forVisionTasks(WASM_CDN);
    let landmarker: FaceLandmarker;
    try {
      landmarker = await FaceLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
        runningMode: "VIDEO",
        numFaces: 1,
        outputFaceBlendshapes: true,
      });
    } catch {
      // Some machines lack a usable WebGL delegate — fall back to CPU.
      landmarker = await FaceLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: MODEL_URL, delegate: "CPU" },
        runningMode: "VIDEO",
        numFaces: 1,
        outputFaceBlendshapes: true,
      });
    }
    return new GestureLivenessDetector(landmarker);
  }

  /** Reset the gesture state (e.g. when a new attempt starts). */
  reset() {
    this.eyesWereClosed = false;
    this.smileFrames = 0;
    this.smileLatched = false;
  }

  /**
   * Process one video frame. Pass a monotonically increasing timestamp (ms).
   * Returns the current scores and a one-shot gesture event when detected.
   */
  detect(video: HTMLVideoElement, timestampMs: number): GestureReading {
    // Skip if the frame has not advanced to avoid MediaPipe timestamp errors.
    if (video.currentTime === this.lastVideoTime) {
      return {
        faceDetected: false,
        blinkScore: 0,
        smileScore: 0,
        eyesClosed: this.eyesWereClosed,
        gesture: null,
      };
    }
    this.lastVideoTime = video.currentTime;

    const result = this.landmarker.detectForVideo(video, timestampMs);
    const blendshapes = result.faceBlendshapes?.[0]?.categories;
    if (!blendshapes || blendshapes.length === 0) {
      // Lost the face — reset blink FSM so a stale half-blink can't complete.
      this.eyesWereClosed = false;
      this.smileFrames = 0;
      return {
        faceDetected: false,
        blinkScore: 0,
        smileScore: 0,
        eyesClosed: false,
        gesture: null,
      };
    }

    const blinkScore = Math.max(
      scoreOf(blendshapes, "eyeBlinkLeft"),
      scoreOf(blendshapes, "eyeBlinkRight")
    );
    const smileScore =
      (scoreOf(blendshapes, "mouthSmileLeft") +
        scoreOf(blendshapes, "mouthSmileRight")) /
      2;

    let gesture: GestureKind | null = null;

    // Blink: require closed then open again.
    if (blinkScore >= BLINK_CLOSED) {
      this.eyesWereClosed = true;
    } else if (blinkScore <= BLINK_OPEN && this.eyesWereClosed) {
      this.eyesWereClosed = false;
      gesture = "blink";
    }

    // Smile: require it to be held, then latch until it drops (avoid repeats).
    if (smileScore >= SMILE_THRESHOLD) {
      this.smileFrames += 1;
      if (this.smileFrames >= SMILE_HOLD_FRAMES && !this.smileLatched) {
        this.smileLatched = true;
        if (!gesture) gesture = "smile";
      }
    } else {
      this.smileFrames = 0;
      this.smileLatched = false;
    }

    return {
      faceDetected: true,
      blinkScore,
      smileScore,
      eyesClosed: this.eyesWereClosed,
      gesture,
    };
  }

  close() {
    try {
      this.landmarker.close();
    } catch {
      // ignore
    }
  }
}
