# Face recognition — implementation guide

**Status:** Sample pipeline shipped (backend + owner admin-web demo). Flutter camera wiring is documented here for the next mobile pass.

**Related:** [SOLUTION.md](./SOLUTION.md) §9.1 · [DATABASE-ERD.md](./DATABASE-ERD.md) `employee_face_embedding`

---

## Architecture

```
Client (admin-web / Flutter)
  → Request one-time head-turn challenge
  → Capture center → turn → return frames
  → FastAPI multipart upload
  → YuNet landmarks (pose) + SFace 128-d embedding (sface_v3)
  → PostgreSQL pgvector (employee_face_embedding)
  → Cosine similarity vs enrolled samples + liveness checks
```

| Setting | Env / config | Default |
|---------|--------------|---------|
| Match threshold | `FACE_MATCH_THRESHOLD` | `0.45` |
| Model version | `FACE_MODEL_VERSION` | `sface_v3` |
| Enrollment samples | min / max | `3` / `5` |
| Challenge TTL | `FACE_LIVENESS_CHALLENGE_TTL_SECONDS` | `90` |
| Center yaw max | `FACE_LIVENESS_CENTER_YAW_MAX` | `0.18` |
| Turn yaw min | `FACE_LIVENESS_TURN_YAW_MIN` | `0.28` |
| Continuity threshold | `FACE_LIVENESS_CONTINUITY_THRESHOLD` | `0.40` |

`sface_v3` uses real face-recognition models from the OpenCV zoo, run natively
by OpenCV (no extra Python deps):

- **YuNet** (`face_detection_yunet_2023mar.onnx`) — face detection + landmarks (also used for head-turn pose)
- **SFace** (`face_recognition_sface_2021dec.onnx`) — aligned crop → 128-d embedding

The ONNX files live in `backend/models/`. If missing, download them:

```powershell
cd backend; mkdir models -Force
curl.exe -L -o models\face_detection_yunet_2023mar.onnx https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
curl.exe -L -o models\face_recognition_sface_2021dec.onnx https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx
```

SFace's published benchmark threshold is `0.363`, but real webcam testing
showed impostor photos scoring up to ~0.37, so the default is a stricter
`0.45` (genuine matches typically score 0.5+; verify uses the best score
across all enrolled samples). Tune per deployment by testing a few genuine
and impostor captures. Embeddings are model-specific — re-enroll everyone
after any model change.

**Liveness:** randomized one-time head-turn (`turn_left` / `turn_right`) blocks
static printed photos and photo-on-phone attacks. It does **not** claim protection
against replayed videos or deepfakes.

Raw enrollment images are **not** stored long-term — only embeddings.

---

## APIs

Base path: `/api/v1` (Bearer JWT).

### Owner / manager — enrollment

#### `GET /employees/{employee_id}/face-status`

```json
{
  "employee_id": "…",
  "face_registration_status": "completed",
  "sample_count": 3,
  "model_version": "sface_v3",
  "face_registered_at": "2026-07-14T…",
  "threshold": 0.45
}
```

#### `POST /employees/{employee_id}/face-samples`

Multipart form field: `files` (repeat 3–5 times). Replaces any previous samples and sets `face_registration_status=completed`.

#### `DELETE /employees/{employee_id}/face-samples`

Clears embeddings and resets status to `not_registered`.

#### `POST /face/verify` (identity-only diagnostic)

Multipart identity compare **without** liveness. Useful for debugging embeddings.
Do **not** use this for attendance pass/fail.

| Field | Type |
|-------|------|
| `employee_id` | UUID string |
| `file` | image (JPEG/PNG) |

Response includes `liveness_checked: false`.

### Liveness challenge (web + Flutter)

#### `POST /face/liveness/challenges`

JSON body (owner/manager): `{ "employee_id": "…" }`  
Employees may omit `employee_id` (challenge is always for themselves).

```json
{
  "challenge_id": "…",
  "employee_id": "…",
  "direction": "turn_left",
  "instruction": "Look straight, then turn your head LEFT, then look straight again.",
  "expires_at": "2026-07-18T14:01:00+00:00",
  "ttl_seconds": 90
}
```

#### `POST /face/liveness/observe` (auto-capture guidance)

Non-consuming pose check for UI guidance. Clients may poll (~2 Hz) while a
challenge is active. **Does not** consume the challenge and **does not**
replace final verification — `/face/verify-liveness` still reprocesses all
three frames independently.

Multipart:

| Field | Type |
|-------|------|
| `challenge_id` | UUID |
| `step` | `center` \| `turn` \| `return` |
| `frame` | JPEG/PNG snapshot |
| `employee_id` | UUID (required for owner/manager) |

```json
{
  "challenge_id": "…",
  "employee_id": "…",
  "step": "center",
  "direction": "turn_left",
  "ready": true,
  "face_detected": true,
  "face_count": 1,
  "yaw": 0.05,
  "detection_score": 0.92,
  "guidance": "Hold still — looking straight.",
  "reason_code": null,
  "expires_at": "2026-07-18T14:01:00+00:00"
}
```

Use `ready` + consecutive stable frames in the client to auto-save each step.
Treat observe as soft guidance only.

#### `POST /face/verify-liveness`

Multipart:

| Field | Type |
|-------|------|
| `challenge_id` | UUID |
| `center_frame` | JPEG/PNG — looking straight |
| `turn_frame` | JPEG/PNG — instructed left/right turn |
| `return_frame` | JPEG/PNG — looking straight again |
| `employee_id` | UUID (required for owner/manager) |

Server validates: unused/unexpired challenge, front poses for center/return,
correct turn direction + magnitude, same identity across frames, enrolled match.
Challenge is consumed on success (and typically already consumed after any
accepted attempt — start a new challenge to retry).

### Employee mobile — clock-in

| Endpoint | Body | Face |
|----------|------|------|
| `POST /employee/attendance/clock-in` | JSON `{ latitude, longitude, shift_assignment_id? }` | No (GPS only; existing) |
| `POST /employee/attendance/clock-in-face` | Multipart + challenge | Yes + liveness |

#### `POST /employee/attendance/clock-in-face`

| Field | Type |
|-------|------|
| `latitude` | float |
| `longitude` | float |
| `challenge_id` | UUID |
| `center_frame` | file |
| `turn_frame` | file |
| `return_frame` | file |
| `shift_assignment_id` | UUID (optional) |

There is **no** client-trusted `liveness_passed` field. Server sets
`attendance_record.liveness_passed=true` and `face_match_score` only after
validation. Geofence still required.

### Error codes (structured `detail`)

| `code` | When |
|--------|------|
| `no_face` | Detector found no face |
| `invalid_image` | Not JPEG/PNG / empty |
| `not_enrolled` | No samples for employee |
| `face_mismatch` | Score below threshold (403) |
| `outside_geofence` | Existing geofence rejection |
| `challenge_not_found` | Unknown challenge id |
| `challenge_expired` | TTL elapsed |
| `challenge_used` | Already consumed |
| `pose_not_centered` | Center/return frame not looking straight |
| `turn_not_detected` | Turn too small |
| `turn_wrong_direction` | Turned opposite way |
| `identity_changed` | Different person between frames |

---

## Admin-web sample flow

**Sample URLs (local Vite, port 5173):**

| Page | URL |
|------|-----|
| Face demo | http://localhost:5173/owner/face-demo |
| Face demo (employee preselected) | http://localhost:5173/owner/face-demo?employeeId=`{uuid}` |
| Employees (Enroll face action) | http://localhost:5173/owner/employees |
| Owner login | http://localhost:5173/owner-login |

1. Log in as **owner**.
2. Open **Face demo** ([http://localhost:5173/owner/face-demo](http://localhost:5173/owner/face-demo)), or Employees → employee details → **Enroll face**.
3. Select an employee.
4. **Start camera** (required for liveness).
5. Capture **3** enroll samples → **Enroll face samples**.
6. Pick a **liveness mode**:
   - **Quick · blink/smile** (default) — the browser runs **MediaPipe FaceLandmarker** on-device, watches eye-blink / smile blendshapes, and auto-captures on a blink or smile. The captured frame is sent to `POST /face/verify` for server-side **identity** check.
   - **Strong · head turn** — server-verified randomized head-turn. With **Auto capture** on, the demo polls `POST /face/liveness/observe` ~every 500 ms, requires **two consecutive ready** observations per step, then auto-advances **center → turn → return** and auto-submits `POST /face/verify-liveness`. Manual capture/reset remain as fallback.

### Liveness modes — trade-off

| Mode | Liveness decided by | Spoof resistance | Convenience |
|------|--------------------|------------------|-------------|
| Quick (blink/smile) | **Client** (MediaPipe / ML Kit) | Lower — server can't independently prove the blink | Highest (no instructions to follow) |
| Strong (head turn) | **Server** (YuNet pose from 3 frames) | Higher — random direction can't be faked by a still photo | Slightly more friction |

In both modes the **server** still performs the SFace identity match. Quick mode is a convenience trade-off: use Strong mode where anti-spoofing matters (e.g. real attendance clock-in). `clock-in-face` currently uses the Strong (head-turn) path.

Live status shows face found, yaw/scores, guidance, and (Strong mode) stability + time remaining. Loops stop on expiry, employee change, camera stop, success/error, unmount, or mode switch.

Client helpers live in [`admin-web/src/lib/api.ts`](../admin-web/src/lib/api.ts):

- `getEmployeeFaceStatus`
- `enrollEmployeeFaceSamples`
- `createFaceLivenessChallenge`
- `observeFaceLivenessPose`
- `verifyEmployeeFaceLiveness`
- `deleteEmployeeFaceSamples`
- `verifyEmployeeFace` (identity check used by Quick blink/smile mode)

Browser gesture detection: [`admin-web/src/lib/faceGesture.ts`](../admin-web/src/lib/faceGesture.ts) (MediaPipe `@mediapipe/tasks-vision`). WASM + model load from CDN on first use.

UI: [`admin-web/src/pages/owner/OwnerFaceDemoPage.tsx`](../admin-web/src/pages/owner/OwnerFaceDemoPage.tsx)

### Productionizing the web UI

Reuse the same challenge + observe + three-frame APIs from Employees (inline dialog) instead of a separate demo page. Liveness must use live camera captures — do not accept still-file uploads for the pass/fail path.

---

## Flutter mobile — how to wire

GPS clock-in already works. Face is additive.

### Packages (recommended)

```yaml
dependencies:
  camera: ^0.11.0
  google_mlkit_face_detection: ^0.12.0   # free, on-device auto-capture
  permission_handler: ^11.0.0
```

`google_mlkit_face_detection` is **free** and runs on-device. Use it only to
decide *when* to capture frames. FastAPI YuNet/SFace remains authoritative for
liveness and identity — never trust ML Kit alone for pass/fail.

### Enrollment (`face_registration_screen.dart`)

1. Request camera permission.
2. Capture 3–5 stills (front camera).
3. `multipart` POST to `/employees/{id}/face-samples` **as the owner/manager**, **or** add an employee self-enroll endpoint that reuses the same service (recommended follow-up: `POST /employee/face-samples` with the logged-in employee’s id).
4. Until self-enroll exists, owners enroll via admin-web; employee screen can poll `face_registration_status` from profile / `GET` me.
5. On success, call existing `POST /employee/face-registration` with `{ "status": "completed" }` only if you still need that metadata path — prefer trusting embeddings (`face-status` / `face_registered_at` set by enroll).

### Clock-in with face + liveness (`scan_attendance_screen.dart`)

Two liveness modes mirror the web demo (see the trade-off table above). Pick
per your security needs — **Strong (head turn)** is server-verified and used by
`clock-in-face` today; **Quick (blink/smile)** is a lighter, client-side option.

#### Quick mode — ML Kit blink/smile auto-capture

Enable ML Kit classification/tracking so you get eye-open and smile probabilities:

```dart
final detector = FaceDetector(
  options: FaceDetectorOptions(
    enableClassification: true, // smilingProbability + eye-open probabilities
    enableTracking: true,
    performanceMode: FaceDetectorMode.fast,
  ),
);
```

1. Stream `camera` frames into `FaceDetector` and read the single tracked face.
2. Detect a gesture (mirror of `admin-web/src/lib/faceGesture.ts`):
   - **Blink:** `leftEyeOpenProbability` and `rightEyeOpenProbability` go **low** (eyes closed) then **high** again (open) — an open → closed → open sequence.
   - **Smile:** `smilingProbability` above ~0.6 held for a few frames.
3. On a gesture, capture one JPEG still and POST it to `POST /face/verify` for the **server identity** check (this endpoint does identity only, no liveness).
4. On `passed: true`, proceed with the normal GPS `POST /attendance/clock-in`.

ML Kit only decides *when* to capture — the server still verifies identity, but
it does **not** independently prove the blink. Use Strong mode where anti-spoofing
matters.

#### Strong mode — ML Kit head-turn auto-capture (server-verified)

1. Keep GPS geofence preview as today.
2. `POST /face/liveness/challenges` (employee JWT; no body needed).
3. Stream preview frames from `camera` into ML Kit `FaceDetector`.
4. Use `Face.headEulerAngleY`, face count (`faces.length == 1`), tracking id, and **2+ consecutive** frames that satisfy the current step:
   - **center / return:** `|yaw|` near 0 (e.g. &lt; ~12°)
   - **turn_left / turn_right:** yaw past a minimum magnitude in the instructed direction
5. **Front-camera mirroring:** preview may flip left/right visually. Map ML Kit yaw / UI arrows so “turn LEFT” matches the server’s `direction` (`turn_left` / `turn_right`), not the mirrored preview.
6. When a step is stable, save a JPEG still for that step and advance center → turn → return.
7. Upload **only** the final three images (plus GPS + `challenge_id`) to `/employee/attendance/clock-in-face`. Do **not** send ML Kit scores to the server.

```dart
// 1) Start challenge
final challenge = await dio.post('/face/liveness/challenges');
final challengeId = challenge.data['challenge_id'];
final direction = challenge.data['direction']; // turn_left | turn_right

// 2) Auto-capture center/turn/return with camera + ML Kit locally, then:
final form = FormData.fromMap({
  'latitude': lat,
  'longitude': lng,
  if (shiftId != null) 'shift_assignment_id': shiftId,
  'challenge_id': challengeId,
  'center_frame': await MultipartFile.fromFile(centerPath, filename: 'center.jpg'),
  'turn_frame': await MultipartFile.fromFile(turnPath, filename: 'turn.jpg'),
  'return_frame': await MultipartFile.fromFile(returnPath, filename: 'return.jpg'),
});
await dio.post('/employee/attendance/clock-in-face', data: form);
```

#### Alternative: backend-only observe polling

If ML Kit is unavailable on a device, poll `POST /face/liveness/observe` with
compressed snapshots (~500 ms), require two consecutive `ready: true` results
per step, then submit the same three frames to `clock-in-face` / `verify-liveness`.
This is heavier on the network/CPU than on-device ML Kit but reuses the same
authoritative final verify path.

#### Error mapping

| Server | UI |
|--------|-----|
| `outside_geofence` | Existing geofence message |
| `no_face` | “No face detected — retake” |
| `not_enrolled` | “Ask your manager to enroll your face” |
| `face_mismatch` | “Face did not match — try again” |
| `challenge_expired` / `challenge_used` | “Challenge expired — start again” |
| `pose_not_centered` | “Look straight at the camera” |
| `turn_not_detected` / `turn_wrong_direction` | “Turn your head farther / the other way” |
| `identity_changed` | “Keep the same face in frame” |

Keep JSON `/attendance/clock-in` as GPS-only fallback until enrollment coverage is complete (or gate clock-in on `face_registration_status == completed`).

### Security limits

- Head-turn liveness (**Strong mode**) **rejects static photos** (printed or on another phone screen) because a still image cannot produce a coherent center→turn→return pose sequence for a random direction.
- It does **not** fully stop a pre-recorded video of the employee performing both turns, or deepfake puppets. Stronger anti-spoof ML can be layered later without changing the multipart contract.
- ML Kit / `/face/liveness/observe` only guide capture timing. In Strong mode clients cannot fake a pass by claiming a pose was ready — final verify always reprocesses the three frames.
- **Quick mode (blink/smile)** decides liveness on the **client** (MediaPipe on web, ML Kit on mobile). The server still checks identity via `/face/verify`, but a determined attacker could bypass the client-side blink/smile check. Prefer Strong mode for attendance where spoofing is a concern.

---

## Backend layout

| Path | Role |
|------|------|
| `backend/app/services/face_embedding.py` | YuNet detect + SFace embed + landmarks |
| `backend/app/services/face_liveness.py` | One-time challenge + head-turn validation |
| `backend/app/api/face.py` | Enroll / status / verify / liveness APIs |
| `backend/app/models/face_embedding.py` | Embedding table |
| `backend/app/models/face_liveness.py` | Challenge table |
| `backend/alembic/versions/013_employee_face_embedding.py` | Embeddings + HNSW |
| `backend/alembic/versions/014_face_liveness_challenge.py` | Challenges |
| `backend/app/services/attendance_clock.py` | Clock-in after server liveness |

Install / migrate:

```powershell
cd backend
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\alembic upgrade head
```

Pin: `opencv-python-headless>=4.10.0,<5`.

---

## Swapping to a stronger model later

Keep:

- Table `employee_face_embedding` with `vector(128)` (or migrate dim if the new model differs)
- Same multipart APIs and response shapes
- Client unchanged

Change only:

1. `detect_and_observe()` / `detect_and_embed()` implementation
2. `MODEL_VERSION` / `face_model_version` setting
3. Re-enroll all employees (embeddings are not compatible across models)

---

## Manual test checklist

- [ ] Migrate to 014
- [ ] Owner Face demo: enroll 3 photos for a test employee
- [ ] Start liveness challenge → complete center/turn/return with live webcam → pass
- [ ] Still photo of a phone / printed face cannot complete a random head-turn → fail
- [ ] Wrong turn direction → `turn_wrong_direction`
- [ ] Expired/reused challenge → clear error; start a new challenge
- [ ] Different person → `face_mismatch` or fail
- [ ] Reset enrolled face → status `not_registered`
- [ ] Employee GPS clock-in (no face) still works
- [ ] `clock-in-face` with valid challenge sets `face_match_score` + `liveness_passed`
