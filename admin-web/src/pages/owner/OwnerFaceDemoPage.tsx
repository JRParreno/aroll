import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, ScanFace, Trash2, Upload } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
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
  deleteEmployeeFaceSamples,
  enrollEmployeeFaceSamples,
  getEmployeeFaceStatus,
  listEmployees,
  verifyEmployeeFace,
  type FaceVerifyResult,
} from "@/lib/api";

const TARGET_SAMPLES = 3;

function blobFromCanvas(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (blob) resolve(blob);
        else reject(new Error("Could not capture frame"));
      },
      "image/jpeg",
      0.92
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

export function OwnerFaceDemoPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const [employeeId, setEmployeeId] = useState(
    searchParams.get("employeeId") ?? ""
  );
  const [cameraOn, setCameraOn] = useState(false);
  const [samples, setSamples] = useState<string[]>([]);
  const [verifyPreview, setVerifyPreview] = useState<string | null>(null);
  const [verifyResult, setVerifyResult] = useState<FaceVerifyResult | null>(
    null
  );

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
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  async function startCamera() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
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
      toast.error("Could not access webcam. Allow camera permission or use file upload.");
    }
  }

  function stopCamera() {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setCameraOn(false);
  }

  async function captureFrame(): Promise<Blob> {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas) throw new Error("Camera is not ready");
    canvas.width = video.videoWidth || 640;
    canvas.height = video.videoHeight || 480;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas unavailable");
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    return blobFromCanvas(canvas);
  }

  async function addEnrollmentSample() {
    if (samples.length >= TARGET_SAMPLES) {
      toast.message(`Already have ${TARGET_SAMPLES} samples`);
      return;
    }
    try {
      const blob = await captureFrame();
      const url = URL.createObjectURL(blob);
      setSamples((prev) => [...prev, url]);
    } catch (error) {
      toast.error(apiErrorMessage(error, "Capture failed"));
    }
  }

  async function captureVerifyFrame() {
    try {
      const blob = await captureFrame();
      if (verifyPreview) URL.revokeObjectURL(verifyPreview);
      setVerifyPreview(URL.createObjectURL(blob));
      setVerifyResult(null);
    } catch (error) {
      toast.error(apiErrorMessage(error, "Capture failed"));
    }
  }

  function onFileEnroll(files: FileList | null) {
    if (!files?.length) return;
    const next = Array.from(files)
      .slice(0, TARGET_SAMPLES - samples.length)
      .map((f) => URL.createObjectURL(f));
    setSamples((prev) => [...prev, ...next].slice(0, TARGET_SAMPLES));
  }

  function onFileVerify(files: FileList | null) {
    const file = files?.[0];
    if (!file) return;
    if (verifyPreview) URL.revokeObjectURL(verifyPreview);
    setVerifyPreview(URL.createObjectURL(file));
    setVerifyResult(null);
  }

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
        throw new Error(`Capture ${TARGET_SAMPLES} face samples before enrolling`);
      }
      const files = await blobsFromObjectUrls(samples);
      return enrollEmployeeFaceSamples(employeeId, files);
    },
    onSuccess: (data) => {
      toast.success(data.message);
      queryClient.invalidateQueries({ queryKey: ["face-status", employeeId] });
      samples.forEach((url) => URL.revokeObjectURL(url));
      setSamples([]);
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Enrollment failed"));
    },
  });

  const verify = useMutation({
    mutationFn: async () => {
      if (!employeeId) throw new Error("Select an employee first");
      if (!verifyPreview) throw new Error("Capture or upload a verify photo");
      const blob = await (await fetch(verifyPreview)).blob();
      return verifyEmployeeFace(employeeId, blob);
    },
    onSuccess: (data) => {
      setVerifyResult(data);
      if (data.passed) toast.success(data.message);
      else toast.error(data.message);
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Verify failed"));
    },
  });

  const clearSamples = useMutation({
    mutationFn: async () => {
      if (!employeeId) throw new Error("Select an employee first");
      return deleteEmployeeFaceSamples(employeeId);
    },
    onSuccess: () => {
      toast.success("Face samples cleared");
      queryClient.invalidateQueries({ queryKey: ["face-status", employeeId] });
      setVerifyResult(null);
    },
    onError: (error) => {
      toast.error(apiErrorMessage(error, "Could not clear samples"));
    },
  });

  function selectEmployee(id: string) {
    setEmployeeId(id);
    setVerifyResult(null);
    if (id) setSearchParams({ employeeId: id });
    else setSearchParams({});
  }

  const status = faceStatusQuery.data;

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Face recognition demo"
        description="Sample owner flow: enroll 3 face photos for an employee, then verify a live capture against those embeddings."
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
              <Button
                type="button"
                variant="outline"
                disabled={!cameraOn}
                onClick={captureVerifyFrame}
              >
                <ScanFace className="mr-2 h-4 w-4" />
                Capture verify photo
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
              <label className="inline-flex cursor-pointer items-center gap-2 text-muted-foreground hover:text-foreground">
                <Upload className="h-4 w-4" />
                Upload verify photo
                <input
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    onFileVerify(e.target.files);
                    e.target.value = "";
                  }}
                />
              </label>
            </div>
          </section>

          <section className="space-y-6">
            <div className="rounded-xl border border-slate-200 bg-white p-5">
              <h2 className="text-base font-semibold">1. Enroll</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Capture {TARGET_SAMPLES} clear face photos (different angles help).
                Raw images are not stored — only 128-d embeddings.
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
              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  type="button"
                  disabled={!employeeId || enroll.isPending}
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
              <h2 className="text-base font-semibold">2. Verify</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Capture one live photo and compare it to enrolled embeddings
                (same API Flutter will use for attendance).
              </p>
              <div className="mt-4 flex flex-wrap items-start gap-4">
                <div className="h-40 w-40 overflow-hidden rounded-lg border border-slate-200 bg-slate-50">
                  {verifyPreview ? (
                    <img
                      src={verifyPreview}
                      alt="Verify"
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                      No photo
                    </div>
                  )}
                </div>
                <div className="min-w-[12rem] flex-1 space-y-3">
                  <Button
                    type="button"
                    disabled={!employeeId || verify.isPending}
                    onClick={() => verify.mutate()}
                  >
                    {verify.isPending ? "Verifying…" : "Run face verify"}
                  </Button>
                  {verifyResult && (
                    <div
                      className={`rounded-lg border px-3 py-2 text-sm ${
                        verifyResult.passed
                          ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                          : "border-red-200 bg-red-50 text-red-900"
                      }`}
                    >
                      <p className="font-medium">
                        {verifyResult.passed ? "Match passed" : "Match failed"}
                      </p>
                      <p className="mt-1">
                        Score {verifyResult.match_score.toFixed(3)} / threshold{" "}
                        {verifyResult.threshold.toFixed(3)}
                      </p>
                      <p className="mt-1 text-xs opacity-80">
                        {verifyResult.message}
                      </p>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </section>
        </div>
      </OwnerPageContent>
    </OwnerPage>
  );
}
