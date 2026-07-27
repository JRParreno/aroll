import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, ScanFace, Trash2, Upload } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Label } from "@/components/ui/label";
import {
  createFaceLivenessChallenge,
  deleteEmployeeFaceSamples,
  enrollEmployeeFaceSamples,
  getEmployeeFaceStatus,
  listEmployees,
  observeFaceLivenessPose,
  verifyEmployeeFace,
  verifyEmployeeFaceLiveness,
  type FaceLivenessVerifyResult,
  type FaceVerifyResult,
  type LivenessChallenge,
  type LivenessPoseObserveResult,
} from "@/lib/api";
import {
  GestureLivenessDetector,
  type GestureKind,
  type GestureReading,
} from "@/lib/faceGesture";

const TARGET_SAMPLES = 3;
const OBSERVE_INTERVAL_MS = 500;
const STABILITY_REQUIRED = 2;
const OBSERVE_JPEG_QUALITY = 0.72;

type LivenessMode = "quick" | "strong";

function gestureLabel(kind: GestureKind): string {
  return kind === "blink" ? "Blink" : "Smile";
}

type LivenessStep =
  | "idle"
  | "center"
  | "turn"
  | "return"
  | "blink"
  | "ready"
  | "verifying";

function blobFromCanvas(
  canvas: HTMLCanvasElement,
  quality = 0.92
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (blob) resolve(blob);
        else reject(new Error("Could not capture frame"));
      },
      "image/jpeg",
      quality
    );
  });
}

function apiErrorMessage(error: unknown, fallback: string): string {
  if (
    error &&
    typeof error === "object" &&
    "response" in error &&
    error.response &&
    typeof error.response === "object" &&
    "data" in error.response
  ) {
    const data = (error.response as { data?: unknown }).data;
    if (typeof data === "string") return data;
    if (data && typeof data === "object") {
      const detail = (data as { detail?: unknown }).detail;
      if (typeof detail === "string") return detail;
      if (detail && typeof detail === "object" && "message" in detail) {
        return String((detail as { message: unknown }).message);
      }
    }
  }
  if (error instanceof Error) return error.message;
  return fallback;
}

function directionLabel(direction: string) {
  return direction === "turn_left" ? "LEFT" : "RIGHT";
}

export function OwnerFaceDemoPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const observeAbortRef = useRef<AbortController | null>(null);
  const stabilityRef = useRef(0);
  const autoVerifyLockRef = useRef(false);
  const gestureDetectorRef = useRef<GestureLivenessDetector | null>(null);
  const gestureRafRef = useRef<number | null>(null);
  const gestureLockRef = useRef(false);

  const [employeeId, setEmployeeId] = useState(
    searchParams.get("employeeId") ?? ""
  );
  const [cameraOn, setCameraOn] = useState(false);
  const [samples, setSamples] = useState<string[]>([]);
  const [enrollBlinkDone, setEnrollBlinkDone] = useState(false);
  const [enrollBlinkWatching, setEnrollBlinkWatching] = useState(false);
  const [autoMode, setAutoMode] = useState(true);
  const [livenessMode, setLivenessMode] = useState<LivenessMode>("quick");
  const enrollBlinkLockRef = useRef(false);
  const strongBlinkLockRef = useRef(false);
  const enrollBlinkRafRef = useRef<number | null>(null);
  const strongBlinkRafRef = useRef<number | null>(null);

  const [gestureRunning, setGestureRunning] = useState(false);
  const [gestureLoading, setGestureLoading] = useState(false);
  const [gestureReading, setGestureReading] = useState<GestureReading | null>(
    null
  );
  const [quickResult, setQuickResult] = useState<FaceVerifyResult | null>(null);
  const [quickGesture, setQuickGesture] = useState<GestureKind | null>(null);

  const [challenge, setChallenge] = useState<LivenessChallenge | null>(null);
  const [livenessStep, setLivenessStep] = useState<LivenessStep>("idle");
  const [centerPreview, setCenterPreview] = useState<string | null>(null);
  const [turnPreview, setTurnPreview] = useState<string | null>(null);
  const [returnPreview, setReturnPreview] = useState<string | null>(null);
  const [centerBlob, setCenterBlob] = useState<Blob | null>(null);
  const [turnBlob, setTurnBlob] = useState<Blob | null>(null);
  const [returnBlob, setReturnBlob] = useState<Blob | null>(null);
  const [verifyResult, setVerifyResult] =
    useState<FaceLivenessVerifyResult | null>(null);
  const [secondsLeft, setSecondsLeft] = useState<number | null>(null);
  const [liveObserve, setLiveObserve] =
    useState<LivenessPoseObserveResult | null>(null);
  const [stabilityCount, setStabilityCount] = useState(0);
  const [observing, setObserving] = useState(false);

  const employeesQuery = useQuery({
    queryKey: ["employees"],
    queryFn: () => listEmployees(),
  });

  const faceStatusQuery = useQuery({
    queryKey: ["face-status", employeeId],
    queryFn: () => getEmployeeFaceStatus(employeeId),
    enabled: Boolean(employeeId),
  });

  const selectedEmployee = useMemo(
    () => employeesQuery.data?.find((e) => e.id === employeeId) ?? null,
    [employeesQuery.data, employeeId]
  );

  useEffect(() => {
    const fromUrl = searchParams.get("employeeId");
    if (fromUrl && fromUrl !== employeeId) {
      setEmployeeId(fromUrl);
    }
  }, [searchParams, employeeId]);

  useEffect(() => {
    return () => {
      observeAbortRef.current?.abort();
      if (gestureRafRef.current !== null) {
        cancelAnimationFrame(gestureRafRef.current);
      }
      if (enrollBlinkRafRef.current !== null) {
        cancelAnimationFrame(enrollBlinkRafRef.current);
      }
      if (strongBlinkRafRef.current !== null) {
        cancelAnimationFrame(strongBlinkRafRef.current);
      }
      gestureDetectorRef.current?.close();
      gestureDetectorRef.current = null;
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  useEffect(() => {
    if (!challenge) {
      setSecondsLeft(null);
      return;
    }
    const tick = () => {
      const ms = new Date(challenge.expires_at).getTime() - Date.now();
      setSecondsLeft(Math.max(0, Math.ceil(ms / 1000)));
    };
    tick();
    const id = window.setInterval(tick, 500);
    return () => window.clearInterval(id);
  }, [challenge]);

  const stopObserving = useCallback(() => {
    observeAbortRef.current?.abort();
    observeAbortRef.current = null;
    setObserving(false);
    stabilityRef.current = 0;
    setStabilityCount(0);
  }, []);

  const stopGestureLiveness = useCallback(() => {
    if (gestureRafRef.current !== null) {
      cancelAnimationFrame(gestureRafRef.current);
      gestureRafRef.current = null;
    }
    gestureLockRef.current = false;
    setGestureRunning(false);
  }, []);

  function clearLivenessCaptures() {
    if (centerPreview) URL.revokeObjectURL(centerPreview);
    if (turnPreview) URL.revokeObjectURL(turnPreview);
    if (returnPreview) URL.revokeObjectURL(returnPreview);
    setCenterPreview(null);
    setTurnPreview(null);
    setReturnPreview(null);
    setCenterBlob(null);
    setTurnBlob(null);
    setReturnBlob(null);
    setVerifyResult(null);
    setLiveObserve(null);
    autoVerifyLockRef.current = false;
  }

  function resetLiveness() {
    stopObserving();
    clearLivenessCaptures();
    setChallenge(null);
    setLivenessStep("idle");
  }

  function resetQuickLiveness() {
    stopGestureLiveness();
    setGestureReading(null);
    setQuickResult(null);
    setQuickGesture(null);
  }

  async function startCamera() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "user",
          width: { ideal: 640 },
          height: { ideal: 480 },
        },
        audio: false,
      });
      streamRef.current?.getTracks().forEach((t) => t.stop());
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      setCameraOn(true);
    } catch {
      toast.error(
        "Could not access webcam. Allow camera permission to run liveness."
      );
    }
  }

  function stopCamera() {
    stopObserving();
    stopGestureLiveness();
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setCameraOn(false);
  }

  async function captureFrame(quality = 0.92): Promise<Blob> {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas) throw new Error("Camera is not ready");
    canvas.width = video.videoWidth || 640;
    canvas.height = video.videoHeight || 480;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas unavailable");
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    return blobFromCanvas(canvas, quality);
  }

  async function addEnrollmentSample() {
    if (samples.length >= TARGET_SAMPLES) {
      toast.message(`Already have ${TARGET_SAMPLES} samples`);
      return;
    }
    try {
      const blob = await captureFrame();
      const url = URL.createObjectURL(blob);
      setSamples((prev) => {
        const next = [...prev, url];
        if (next.length >= TARGET_SAMPLES) {
          setEnrollBlinkDone(false);
          enrollBlinkLockRef.current = false;
        }
        return next;
      });
    } catch (error) {
      toast.error(apiErrorMessage(error, "Capture failed"));
    }
  }

  function onFileEnroll(files: FileList | null) {
    if (!files?.length) return;
    const next = Array.from(files)
      .slice(0, TARGET_SAMPLES - samples.length)
      .map((f) => URL.createObjectURL(f));
    setSamples((prev) => {
      const merged = [...prev, ...next].slice(0, TARGET_SAMPLES);
      if (merged.length >= TARGET_SAMPLES) {
        setEnrollBlinkDone(false);
        enrollBlinkLockRef.current = false;
      }
      return merged;
    });
  }

  async function ensureGestureDetector(): Promise<GestureLivenessDetector> {
    if (!gestureDetectorRef.current) {
      gestureDetectorRef.current = await GestureLivenessDetector.create();
    }
    return gestureDetectorRef.current;
  }

  // Enroll last step: require a blink before samples can be submitted.
  useEffect(() => {
    const shouldWatch =
      cameraOn &&
      samples.length >= TARGET_SAMPLES &&
      !enrollBlinkDone &&
      livenessStep === "idle" &&
      !gestureRunning;

    if (!shouldWatch) {
      setEnrollBlinkWatching(false);
      if (enrollBlinkRafRef.current !== null) {
        cancelAnimationFrame(enrollBlinkRafRef.current);
        enrollBlinkRafRef.current = null;
      }
      return;
    }

    let cancelled = false;
    setEnrollBlinkWatching(true);

    const run = async () => {
      try {
        const detector = await ensureGestureDetector();
        if (cancelled) return;
        detector.reset();
        const loop = () => {
          if (cancelled || enrollBlinkLockRef.current) return;
          const video = videoRef.current;
          if (video && video.readyState >= 2) {
            const reading = detector.detect(video, performance.now());
            if (reading.gesture === "blink") {
              enrollBlinkLockRef.current = true;
              setEnrollBlinkDone(true);
              setEnrollBlinkWatching(false);
              toast.success("Blink confirmed — you can enroll face samples");
              return;
            }
          }
          enrollBlinkRafRef.current = requestAnimationFrame(loop);
        };
        enrollBlinkRafRef.current = requestAnimationFrame(loop);
      } catch {
        setEnrollBlinkWatching(false);
      }
    };
    void run();

    return () => {
      cancelled = true;
      if (enrollBlinkRafRef.current !== null) {
        cancelAnimationFrame(enrollBlinkRafRef.current);
        enrollBlinkRafRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    cameraOn,
    samples.length,
    enrollBlinkDone,
    livenessStep,
    livenessMode,
    gestureRunning,
  ]);

  // Strong mode last step: blink after center/turn/return before verify.
  useEffect(() => {
    if (livenessStep !== "blink" || !cameraOn || livenessMode !== "strong") {
      if (strongBlinkRafRef.current !== null) {
        cancelAnimationFrame(strongBlinkRafRef.current);
        strongBlinkRafRef.current = null;
      }
      return;
    }

    let cancelled = false;
    strongBlinkLockRef.current = false;

    const run = async () => {
      try {
        const detector = await ensureGestureDetector();
        if (cancelled) return;
        detector.reset();
        const loop = () => {
          if (cancelled || strongBlinkLockRef.current) return;
          const video = videoRef.current;
          if (video && video.readyState >= 2) {
            const reading = detector.detect(video, performance.now());
            if (reading.gesture === "blink") {
              strongBlinkLockRef.current = true;
              setLivenessStep("ready");
              toast.success("Blink confirmed — verifying…");
              return;
            }
          }
          strongBlinkRafRef.current = requestAnimationFrame(loop);
        };
        strongBlinkRafRef.current = requestAnimationFrame(loop);
      } catch {
        toast.error("Could not start blink detection");
        setLivenessStep("idle");
      }
    };
    void run();

    return () => {
      cancelled = true;
      if (strongBlinkRafRef.current !== null) {
        cancelAnimationFrame(strongBlinkRafRef.current);
        strongBlinkRafRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [livenessStep, cameraOn, livenessMode]);

  async function blobsFromObjectUrls(urls: string[]): Promise<Blob[]> {
    const blobs: Blob[] = [];
    for (const url of urls) {
      const res = await fetch(url);
      blobs.push(await res.blob());
    }
    return blobs;
  }

  const enroll = useMutation({
    mutationFn: async () => {
      if (!employeeId) throw new Error("Select an employee first");
      if (samples.length < TARGET_SAMPLES) {
        throw new Error(
          `Capture ${TARGET_SAMPLES} face samples before enrolling`
        );
      }
      if (!enrollBlinkDone) {
        throw new Error("Blink once to confirm liveness before enrolling");
      }
      const files = await blobsFromObjectUrls(samples);
      return enrollEmployeeFaceSamples(employeeId, files);
    },
    onSuccess: (data) => {
      toast.success(data.message);
      queryClient.invalidateQueries({ queryKey: ["face-status", employeeId] });
      samples.forEach((url) => URL.revokeObjectURL(url));
      setSamples([]);
      setEnrollBlinkDone(false);
      setEnrollBlinkWatching(false);
      enrollBlinkLockRef.current = false;
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Enrollment failed"));
    },
  });

  const verifyLiveness = useMutation({
    mutationFn: async (frames: {
      challengeId: string;
      center: Blob;
      turn: Blob;
      returnFrame: Blob;
    }) => {
      if (!employeeId) throw new Error("Select an employee first");
      return verifyEmployeeFaceLiveness({
        employeeId,
        challengeId: frames.challengeId,
        centerFrame: frames.center,
        turnFrame: frames.turn,
        returnFrame: frames.returnFrame,
      });
    },
    onSuccess: (data) => {
      stopObserving();
      setVerifyResult(data);
      setChallenge(null);
      setLivenessStep("idle");
      toast.success(data.message);
    },
    onError: (error) => {
      stopObserving();
      setLivenessStep("idle");
      toast.error(apiErrorMessage(error, "Liveness verify failed"));
      const msg = apiErrorMessage(error, "");
      if (msg.includes("expired") || msg.includes("already used")) {
        resetLiveness();
      }
    },
  });

  const verifyQuickIdentity = useMutation({
    mutationFn: async (frame: Blob) => {
      if (!employeeId) throw new Error("Select an employee first");
      return verifyEmployeeFace(employeeId, frame);
    },
    onSuccess: (data) => {
      setQuickResult(data);
      if (data.passed) {
        toast.success(
          "Identity match passed (blink/smile detected on-device)"
        );
      } else {
        toast.error("Face did not match — try again");
      }
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Identity verify failed"));
    },
    onSettled: () => {
      // Allow another attempt after this capture resolves.
      gestureLockRef.current = false;
    },
  });

  const stopGestureRef = useRef(stopGestureLiveness);
  stopGestureRef.current = stopGestureLiveness;
  const verifyQuickRef = useRef(verifyQuickIdentity);
  verifyQuickRef.current = verifyQuickIdentity;

  const startGestureLiveness = useCallback(async () => {
    if (!cameraOn) {
      toast.error("Start the webcam first");
      return;
    }
    if (!employeeId) {
      toast.error("Select an employee first");
      return;
    }
    setQuickResult(null);
    setQuickGesture(null);
    gestureLockRef.current = false;

    if (!gestureDetectorRef.current) {
      try {
        setGestureLoading(true);
        gestureDetectorRef.current = await GestureLivenessDetector.create();
      } catch {
        setGestureLoading(false);
        toast.error(
          "Could not load the on-device face model. Check your connection and retry."
        );
        return;
      }
      setGestureLoading(false);
    }

    gestureDetectorRef.current.reset();
    setGestureRunning(true);

    const loop = () => {
      const detector = gestureDetectorRef.current;
      const video = videoRef.current;
      if (!detector || !video) {
        stopGestureRef.current();
        return;
      }
      try {
        const reading = detector.detect(video, performance.now());
        setGestureReading(reading);
        if (reading.gesture && !gestureLockRef.current) {
          gestureLockRef.current = true;
          setQuickGesture(reading.gesture);
          // Capture a high-quality frame and verify identity server-side.
          void captureFrame(0.92)
            .then((blob) => verifyQuickRef.current.mutate(blob))
            .catch(() => {
              gestureLockRef.current = false;
            });
        }
      } catch {
        // transient detector error — keep looping
      }
      gestureRafRef.current = requestAnimationFrame(loop);
    };
    gestureRafRef.current = requestAnimationFrame(loop);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cameraOn, employeeId]);

  const saveStepFrame = useCallback(
    async (step: "center" | "turn" | "return", blob: Blob) => {
      const url = URL.createObjectURL(blob);
      if (step === "center") {
        setCenterPreview((prev) => {
          if (prev) URL.revokeObjectURL(prev);
          return url;
        });
        setCenterBlob(blob);
        setLivenessStep("turn");
        toast.message("Center captured — now turn as instructed");
      } else if (step === "turn") {
        setTurnPreview((prev) => {
          if (prev) URL.revokeObjectURL(prev);
          return url;
        });
        setTurnBlob(blob);
        setLivenessStep("return");
        toast.message("Turn captured — look straight again");
      } else {
        setReturnPreview((prev) => {
          if (prev) URL.revokeObjectURL(prev);
          return url;
        });
        setReturnBlob(blob);
        setLivenessStep("blink");
        strongBlinkLockRef.current = false;
        toast.message("Last step — blink once to confirm");
      }
      stabilityRef.current = 0;
      setStabilityCount(0);
      setLiveObserve(null);
    },
    []
  );

  const startObserving = useCallback(
    (activeChallenge: LivenessChallenge, step: "center" | "turn" | "return") => {
      stopObserving();
      if (!cameraOn || !employeeId) return;

      const controller = new AbortController();
      observeAbortRef.current = controller;
      setObserving(true);
      stabilityRef.current = 0;
      setStabilityCount(0);

      const loop = async () => {
        while (!controller.signal.aborted) {
          if (new Date(activeChallenge.expires_at).getTime() <= Date.now()) {
            toast.error("Challenge expired — start a new one");
            controller.abort();
            setObserving(false);
            setChallenge(null);
            setLivenessStep("idle");
            setLiveObserve(null);
            return;
          }
          try {
            const frame = await captureFrame(OBSERVE_JPEG_QUALITY);
            if (controller.signal.aborted) return;
            const result = await observeFaceLivenessPose({
              employeeId,
              challengeId: activeChallenge.challenge_id,
              step,
              frame,
            });
            if (controller.signal.aborted) return;
            setLiveObserve(result);
            if (result.ready) {
              stabilityRef.current += 1;
              setStabilityCount(stabilityRef.current);
              if (stabilityRef.current >= STABILITY_REQUIRED) {
                // Use a higher-quality capture for the saved frame.
                const saved = await captureFrame(0.92);
                if (controller.signal.aborted) return;
                await saveStepFrame(step, saved);
                return;
              }
            } else {
              stabilityRef.current = 0;
              setStabilityCount(0);
            }
          } catch (error) {
            if (controller.signal.aborted) return;
            const msg = apiErrorMessage(error, "Pose check failed");
            if (
              msg.includes("expired") ||
              msg.includes("already used") ||
              msg.includes("not found")
            ) {
              toast.error(msg);
              controller.abort();
              setObserving(false);
              setChallenge(null);
              setLivenessStep("idle");
              setLiveObserve(null);
              return;
            }
            // Soft transient errors (e.g. no_face): show guidance and keep polling.
            setLiveObserve({
              challenge_id: activeChallenge.challenge_id,
              employee_id: employeeId,
              step,
              direction: activeChallenge.direction,
              ready: false,
              face_detected: false,
              face_count: 0,
              yaw: null,
              detection_score: null,
              guidance: msg.includes("No face")
                ? "No face detected — face the camera."
                : msg,
              reason_code: msg.includes("No face") ? "no_face" : "observe_error",
              expires_at: activeChallenge.expires_at,
            });
            stabilityRef.current = 0;
            setStabilityCount(0);
          }
          await new Promise((r) => setTimeout(r, OBSERVE_INTERVAL_MS));
        }
      };

      void loop();
    },
    [cameraOn, employeeId, saveStepFrame, stopObserving]
  );

  // Drive auto observation when step changes.
  useEffect(() => {
    if (!autoMode || !challenge || !cameraOn) return;
    if (
      livenessStep === "center" ||
      livenessStep === "turn" ||
      livenessStep === "return"
    ) {
      startObserving(challenge, livenessStep);
      return () => stopObserving();
    }
    stopObserving();
  }, [
    autoMode,
    challenge,
    cameraOn,
    livenessStep,
    startObserving,
    stopObserving,
  ]);

  // Auto-submit when all three frames are ready.
  useEffect(() => {
    if (
      livenessStep !== "ready" ||
      !challenge ||
      !centerBlob ||
      !turnBlob ||
      !returnBlob ||
      autoVerifyLockRef.current ||
      verifyLiveness.isPending
    ) {
      return;
    }
    autoVerifyLockRef.current = true;
    setLivenessStep("verifying");
    verifyLiveness.mutate({
      challengeId: challenge.challenge_id,
      center: centerBlob,
      turn: turnBlob,
      returnFrame: returnBlob,
    });
  }, [
    livenessStep,
    challenge,
    centerBlob,
    turnBlob,
    returnBlob,
    verifyLiveness,
  ]);

  // Switching modes tears down whichever flow is not active.
  useEffect(() => {
    if (livenessMode === "quick") {
      stopObserving();
      resetLiveness();
    } else {
      stopGestureLiveness();
      setGestureReading(null);
      setQuickResult(null);
      setQuickGesture(null);
    }
    // resetLiveness is stable enough for this teardown; deps kept minimal.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [livenessMode, stopObserving, stopGestureLiveness]);

  const startChallenge = useMutation({
    mutationFn: async () => {
      if (!employeeId) throw new Error("Select an employee first");
      if (!cameraOn) throw new Error("Start the webcam before liveness");
      return createFaceLivenessChallenge(employeeId);
    },
    onSuccess: (data) => {
      stopObserving();
      clearLivenessCaptures();
      setChallenge(data);
      setLivenessStep("center");
      toast.message(
        autoMode
          ? `Auto mode: ${data.instruction}`
          : data.instruction
      );
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Could not start challenge"));
    },
  });

  async function captureLivenessStep() {
    if (!challenge) {
      toast.error("Start a liveness challenge first");
      return;
    }
    if (!cameraOn) {
      toast.error("Webcam is required for liveness");
      return;
    }
    if (secondsLeft === 0) {
      toast.error("Challenge expired — start a new one");
      resetLiveness();
      return;
    }
    if (livenessStep === "blink") {
      setLivenessStep("ready");
      toast.success("Blink confirmed — verifying…");
      return;
    }
    if (
      livenessStep !== "center" &&
      livenessStep !== "turn" &&
      livenessStep !== "return" &&
      livenessStep !== "ready"
    ) {
      return;
    }
    try {
      const blob = await captureFrame();
      const step =
        livenessStep === "ready" ? "return" : (livenessStep as "center" | "turn" | "return");
      await saveStepFrame(step, blob);
    } catch (error) {
      toast.error(apiErrorMessage(error, "Capture failed"));
    }
  }

  const clearSamples = useMutation({
    mutationFn: async () => {
      if (!employeeId) throw new Error("Select an employee first");
      return deleteEmployeeFaceSamples(employeeId);
    },
    onSuccess: () => {
      toast.success("Face samples cleared");
      queryClient.invalidateQueries({ queryKey: ["face-status", employeeId] });
      resetLiveness();
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Could not clear samples"));
    },
  });

  function selectEmployee(id: string) {
    setEmployeeId(id);
    resetLiveness();
    resetQuickLiveness();
    if (id) setSearchParams({ employeeId: id });
    else setSearchParams({});
  }

  const status = faceStatusQuery.data;
  const captureHint =
    livenessStep === "center"
      ? "1/4 Look straight"
      : livenessStep === "turn" && challenge
        ? `2/4 Turn ${directionLabel(challenge.direction)}`
        : livenessStep === "return"
          ? "3/4 Look straight again"
          : livenessStep === "blink"
            ? "4/4 Blink once to confirm"
            : livenessStep === "ready"
              ? "Frames ready — verifying…"
              : livenessStep === "verifying"
                ? "Submitting liveness verify…"
                : "Start challenge to begin";

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Face recognition demo"
        description="Enroll face samples (ending with a blink), then prove liveness. Strong mode: head-turn sequence + final blink; Quick mode: blink/smile then identity check."
      />
      <OwnerPageContent>
        <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
          <section className="space-y-4 rounded-xl border border-slate-200 bg-white p-5">
            <div className="space-y-2">
              <Label htmlFor="employee">Employee</Label>
              <select
                id="employee"
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                value={employeeId}
                onChange={(e) => selectEmployee(e.target.value)}
              >
                <option value="">Select employee…</option>
                {(employeesQuery.data ?? []).map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.full_name}
                    {emp.position_title ? ` — ${emp.position_title}` : ""}
                  </option>
                ))}
              </select>
              <p className="text-xs text-muted-foreground">
                Or open from{" "}
                <Link className="underline" to="/owner/employees">
                  Employees
                </Link>{" "}
                → Enroll face.
              </p>
            </div>

            {selectedEmployee && (
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <span className="font-medium">{selectedEmployee.full_name}</span>
                {status ? (
                  <>
                    <Badge variant="secondary">
                      {status.face_registration_status}
                    </Badge>
                    <span className="text-muted-foreground">
                      {status.sample_count} sample
                      {status.sample_count === 1 ? "" : "s"}
                      {status.model_version
                        ? ` · ${status.model_version}`
                        : ""}
                    </span>
                    <span className="text-muted-foreground">
                      threshold {status.threshold.toFixed(2)}
                    </span>
                  </>
                ) : faceStatusQuery.isLoading ? (
                  <span className="text-muted-foreground">Loading status…</span>
                ) : null}
              </div>
            )}

            <div className="overflow-hidden rounded-lg bg-slate-950">
              <video
                ref={videoRef}
                className="aspect-video w-full object-cover"
                playsInline
                muted
              />
              <canvas ref={canvasRef} className="hidden" />
            </div>

            <div className="flex flex-wrap gap-2">
              {!cameraOn ? (
                <Button type="button" onClick={startCamera}>
                  <Camera className="mr-2 h-4 w-4" />
                  Start camera
                </Button>
              ) : (
                <Button type="button" variant="outline" onClick={stopCamera}>
                  Stop camera
                </Button>
              )}
              <Button
                type="button"
                variant="outline"
                disabled={!cameraOn}
                onClick={addEnrollmentSample}
              >
                Capture enroll sample ({samples.length}/{TARGET_SAMPLES})
              </Button>
            </div>

            <div className="flex flex-wrap gap-3 text-sm">
              <label className="inline-flex cursor-pointer items-center gap-2 text-muted-foreground hover:text-foreground">
                <Upload className="h-4 w-4" />
                Upload enroll photos
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  className="hidden"
                  onChange={(e) => {
                    onFileEnroll(e.target.files);
                    e.target.value = "";
                  }}
                />
              </label>
              <span className="text-xs text-muted-foreground">
                File upload is for enrollment only — liveness requires live webcam.
              </span>
            </div>
          </section>

          <section className="space-y-6">
            <div className="rounded-xl border border-slate-200 bg-white p-5">
              <h2 className="text-base font-semibold">1. Enroll</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Capture {TARGET_SAMPLES} clear face photos, then blink once to
                confirm you are live. Raw images are not stored — only embeddings.
              </p>
              <div className="mt-4 grid grid-cols-3 gap-3">
                {Array.from({ length: TARGET_SAMPLES }).map((_, i) => (
                  <div
                    key={i}
                    className="aspect-square overflow-hidden rounded-lg border border-dashed border-slate-300 bg-slate-50"
                  >
                    {samples[i] ? (
                      <img
                        src={samples[i]}
                        alt={`Sample ${i + 1}`}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                        #{i + 1}
                      </div>
                    )}
                  </div>
                ))}
              </div>
              {samples.length >= TARGET_SAMPLES && (
                <p
                  className={`mt-3 text-sm font-medium ${
                    enrollBlinkDone ? "text-emerald-700" : "text-amber-700"
                  }`}
                >
                  {enrollBlinkDone
                    ? "Blink confirmed — ready to enroll."
                    : enrollBlinkWatching
                      ? "Last step: look at the camera and blink once."
                      : "Start the camera, then blink once to finish enrollment."}
                </p>
              )}
              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  type="button"
                  disabled={
                    !employeeId ||
                    enroll.isPending ||
                    samples.length < TARGET_SAMPLES ||
                    !enrollBlinkDone
                  }
                  onClick={() => enroll.mutate()}
                >
                  {enroll.isPending ? "Enrolling…" : "Enroll face samples"}
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  disabled={samples.length === 0}
                  onClick={() => {
                    samples.forEach((url) => URL.revokeObjectURL(url));
                    setSamples([]);
                    setEnrollBlinkDone(false);
                    setEnrollBlinkWatching(false);
                    enrollBlinkLockRef.current = false;
                  }}
                >
                  Clear captures
                </Button>
                <Button
                  type="button"
                  variant="destructive"
                  disabled={
                    !employeeId ||
                    !status?.sample_count ||
                    clearSamples.isPending
                  }
                  onClick={() => clearSamples.mutate()}
                >
                  <Trash2 className="mr-2 h-4 w-4" />
                  Reset enrolled face
                </Button>
              </div>
            </div>

            <div className="rounded-xl border border-slate-200 bg-white p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="text-base font-semibold">2. Liveness verify</h2>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {livenessMode === "quick"
                      ? "Quick mode: just look at the camera and blink (or smile). The face model captures automatically, then the server checks identity."
                      : "Strong mode: center → turn → return, then blink once. Auto mode polls YuNet pose guidance and captures when stable."}
                  </p>
                </div>
                {livenessMode === "strong" && (
                  <label className="inline-flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={autoMode}
                      onChange={(e) => {
                        setAutoMode(e.target.checked);
                        if (!e.target.checked) stopObserving();
                      }}
                    />
                    Auto capture
                  </label>
                )}
              </div>

              <div className="mt-3 inline-flex rounded-lg border border-slate-200 p-0.5 text-sm">
                <button
                  type="button"
                  className={`rounded-md px-3 py-1.5 font-medium transition ${
                    livenessMode === "quick"
                      ? "bg-slate-900 text-white"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                  onClick={() => setLivenessMode("quick")}
                >
                  Quick · blink/smile
                </button>
                <button
                  type="button"
                  className={`rounded-md px-3 py-1.5 font-medium transition ${
                    livenessMode === "strong"
                      ? "bg-slate-900 text-white"
                      : "text-slate-600 hover:text-slate-900"
                  }`}
                  onClick={() => setLivenessMode("strong")}
                >
                  Strong · head turn
                </button>
              </div>

              {livenessMode === "quick" && (
                <div className="mt-4 space-y-4">
                  <div className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
                    Blink/smile detection runs on-device (MediaPipe) and only
                    decides <em>when</em> to capture. The server still verifies
                    identity, but it cannot independently prove the blink — use
                    Strong mode when you need spoof-resistant liveness.
                  </div>

                  <div className="flex flex-wrap gap-2">
                    {!gestureRunning ? (
                      <Button
                        type="button"
                        disabled={
                          !employeeId || !cameraOn || gestureLoading
                        }
                        onClick={() => void startGestureLiveness()}
                      >
                        <ScanFace className="mr-2 h-4 w-4" />
                        {gestureLoading
                          ? "Loading face model…"
                          : "Start blink/smile liveness"}
                      </Button>
                    ) : (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={stopGestureLiveness}
                      >
                        Stop
                      </Button>
                    )}
                    <Button
                      type="button"
                      variant="ghost"
                      disabled={!gestureReading && !quickResult}
                      onClick={resetQuickLiveness}
                    >
                      Reset
                    </Button>
                  </div>

                  {gestureRunning && (
                    <div className="rounded-lg border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-950">
                      <p className="font-medium">
                        Watching… blink or smile to capture
                        {verifyQuickIdentity.isPending ? " · verifying…" : ""}
                      </p>
                      {gestureReading && (
                        <p className="mt-1 text-xs">
                          {gestureReading.faceDetected
                            ? `Face detected · blink ${gestureReading.blinkScore.toFixed(
                                2
                              )} · smile ${gestureReading.smileScore.toFixed(2)}`
                            : "No face — center your face in the frame"}
                        </p>
                      )}
                    </div>
                  )}

                  {quickResult && (
                    <div
                      className={`rounded-lg border px-3 py-2 text-sm ${
                        quickResult.passed
                          ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                          : "border-red-200 bg-red-50 text-red-900"
                      }`}
                    >
                      <p className="font-medium">
                        {quickResult.passed
                          ? `Identity match passed${
                              quickGesture
                                ? ` · ${gestureLabel(quickGesture).toLowerCase()} detected on-device`
                                : ""
                            }`
                          : "Identity did not match"}
                      </p>
                      <p className="mt-1">
                        Mean score {quickResult.match_score.toFixed(3)} / threshold{" "}
                        {quickResult.threshold.toFixed(3)}
                      </p>
                      <p className="mt-1 text-xs opacity-80">
                        {quickResult.message}
                      </p>
                      {quickResult.passed && (
                        <p className="mt-2 text-xs opacity-80">
                          Blink/smile is checked in the browser only. Use Strong
                          (head-turn) mode for server-verified liveness.
                        </p>
                      )}
                    </div>
                  )}
                </div>
              )}

              {livenessMode === "strong" && (
              <>
              

              {challenge && (
                <div className="mt-3 rounded-lg border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-950">
                  <p className="font-medium">
                    Challenge: turn {directionLabel(challenge.direction)}
                    {secondsLeft !== null ? ` · ${secondsLeft}s left` : ""}
                    {observing ? " · watching…" : ""}
                  </p>
                  <p className="mt-1 text-xs opacity-90">{challenge.instruction}</p>
                  <p className="mt-1 text-xs font-medium">{captureHint}</p>
                  {liveObserve && (
                    <p className="mt-2 text-xs">
                      {liveObserve.face_detected
                        ? `Face detected · yaw ${(liveObserve.yaw ?? 0).toFixed(3)}`
                        : "No face"}
                      {" · "}
                      {liveObserve.guidance}
                      {liveObserve.ready
                        ? ` · stability ${stabilityCount}/${STABILITY_REQUIRED}`
                        : ""}
                    </p>
                  )}
                </div>
              )}

              <div className="mt-4 grid grid-cols-3 gap-3">
                {(
                  [
                    ["Center", centerPreview],
                    ["Turn", turnPreview],
                    ["Return", returnPreview],
                  ] as const
                ).map(([label, preview]) => (
                  <div key={label} className="space-y-1">
                    <p className="text-xs font-medium text-muted-foreground">
                      {label}
                    </p>
                    <div className="aspect-square overflow-hidden rounded-lg border border-slate-200 bg-slate-50">
                      {preview ? (
                        <img
                          src={preview}
                          alt={label}
                          className="h-full w-full object-cover"
                        />
                      ) : (
                        <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                          —
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  type="button"
                  variant="outline"
                  disabled={
                    !employeeId || !cameraOn || startChallenge.isPending
                  }
                  onClick={() => startChallenge.mutate()}
                >
                  <ScanFace className="mr-2 h-4 w-4" />
                  {startChallenge.isPending
                    ? "Starting…"
                    : challenge
                      ? "New challenge"
                      : "Start liveness challenge"}
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  disabled={
                    autoMode ||
                    !challenge ||
                    !cameraOn ||
                    livenessStep === "idle" ||
                    livenessStep === "verifying" ||
                    secondsLeft === 0
                  }
                  onClick={captureLivenessStep}
                >
                  Manual capture
                </Button>
                <Button
                  type="button"
                  disabled={
                    autoMode ||
                    !challenge ||
                    livenessStep !== "ready" ||
                    verifyLiveness.isPending
                  }
                  onClick={() => {
                    if (!challenge || !centerBlob || !turnBlob || !returnBlob)
                      return;
                    setLivenessStep("verifying");
                    verifyLiveness.mutate({
                      challengeId: challenge.challenge_id,
                      center: centerBlob,
                      turn: turnBlob,
                      returnFrame: returnBlob,
                    });
                  }}
                >
                  {verifyLiveness.isPending
                    ? "Verifying…"
                    : "Run liveness verify"}
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  disabled={!challenge && !centerBlob}
                  onClick={resetLiveness}
                >
                  Reset
                </Button>
              </div>

              {verifyResult && (
                <div
                  className={`mt-4 rounded-lg border px-3 py-2 text-sm ${
                    verifyResult.passed && verifyResult.liveness_passed
                      ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                      : "border-red-200 bg-red-50 text-red-900"
                  }`}
                >
                  <p className="font-medium">
                    {verifyResult.liveness_passed
                      ? "Liveness + match passed"
                      : "Failed"}
                  </p>
                  <p className="mt-1">
                    Score {verifyResult.match_score.toFixed(3)} / threshold{" "}
                    {verifyResult.threshold.toFixed(3)} ·{" "}
                    {verifyResult.direction.replace("_", " ")}
                  </p>
                  <p className="mt-1 text-xs opacity-80">
                    yaw center {verifyResult.pose.center_yaw.toFixed(3)}, turn{" "}
                    {verifyResult.pose.turn_yaw.toFixed(3)}, return{" "}
                    {verifyResult.pose.return_yaw.toFixed(3)}
                  </p>
                  <p className="mt-1 text-xs opacity-80">{verifyResult.message}</p>
                </div>
              )}
              </>
              )}
            </div>
          </section>
        </div>
      </OwnerPageContent>
    </OwnerPage>
  );
}
