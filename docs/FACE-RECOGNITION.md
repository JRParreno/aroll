# Face recognition — implementation guide

**Status:** Sample pipeline shipped (backend + owner admin-web demo). Flutter camera wiring is documented here for the next mobile pass.

**Related:** [SOLUTION.md](./SOLUTION.md) §9.1 · [DATABASE-ERD.md](./DATABASE-ERD.md) `employee_face_embedding`

---

## Architecture

```
Client (admin-web / Flutter)
  → FastAPI multipart upload
  → OpenCV Haar detect + 128-d L2 embedding (opencv_hist_v1)
  → PostgreSQL pgvector (employee_face_embedding)
  → Cosine similarity vs enrolled samples
```

| Setting | Env / config | Default |
|---------|--------------|---------|
| Match threshold | `FACE_MATCH_THRESHOLD` | `0.72` |
| Model version | `FACE_MODEL_VERSION` | `opencv_hist_v1` |
| Enrollment samples | min / max | `3` / `5` |

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
  "model_version": "opencv_hist_v1",
  "face_registered_at": "2026-07-14T…",
  "threshold": 0.72
}
```

#### `POST /employees/{employee_id}/face-samples`

Multipart form field: `files` (repeat 3–5 times). Replaces any previous samples and sets `face_registration_status=completed`.

#### `DELETE /employees/{employee_id}/face-samples`

Clears embeddings and resets status to `not_registered`.

#### `POST /face/verify` (sample / demo)

Multipart:

| Field | Type |
|-------|------|
| `employee_id` | UUID string |
| `file` | image (JPEG/PNG) |

Response:

```json
{
  "employee_id": "…",
  "match_score": 0.8512,
  "passed": true,
  "threshold": 0.72,
  "model_version": "opencv_hist_v1",
  "message": "Face match passed."
}
```

### Employee mobile — clock-in

| Endpoint | Body | Face |
|----------|------|------|
| `POST /employee/attendance/clock-in` | JSON `{ latitude, longitude, shift_assignment_id? }` | No (GPS only; existing) |
| `POST /employee/attendance/clock-in-face` | Multipart | Yes |

#### `POST /employee/attendance/clock-in-face`

| Field | Type |
|-------|------|
| `latitude` | float |
| `longitude` | float |
| `face_image` | file |
| `shift_assignment_id` | UUID (optional) |
| `liveness_passed` | bool (default `true` until real liveness ships) |

On success, `attendance_record.face_match_score` and `liveness_passed` are set. Geofence still required.

### Error codes (structured `detail`)

| `code` | When |
|--------|------|
| `no_face` | Detector found no face |
| `invalid_image` | Not JPEG/PNG / empty |
| `not_enrolled` | No samples for employee |
| `face_mismatch` | Score below threshold (403 on clock-in) |
| `outside_geofence` | Existing geofence rejection |

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
4. **Start camera** (or upload files).
5. Capture **3** enroll samples → **Enroll face samples**.
6. Capture one verify photo → **Run face verify** → check score vs threshold.

Client helpers live in [`admin-web/src/lib/api.ts`](../admin-web/src/lib/api.ts):

- `getEmployeeFaceStatus`
- `enrollEmployeeFaceSamples`
- `verifyEmployeeFace`
- `deleteEmployeeFaceSamples`

UI: [`admin-web/src/pages/owner/OwnerFaceDemoPage.tsx`](../admin-web/src/pages/owner/OwnerFaceDemoPage.tsx)

### Productionizing the web UI

Reuse the same APIs from Employees (inline dialog) instead of a separate demo page. Keep webcam + file-upload fallback. Do not store preview blobs server-side.

---

## Flutter mobile — how to wire

GPS clock-in already works. Face is additive.

### Packages

```yaml
dependencies:
  camera: ^0.11.0          # or image_picker for stills
  permission_handler: ^11.0.0
```

### Enrollment (`face_registration_screen.dart`)

1. Request camera permission.
2. Capture 3–5 stills (front camera).
3. `multipart` POST to `/employees/{id}/face-samples` **as the owner/manager**, **or** add an employee self-enroll endpoint that reuses the same service (recommended follow-up: `POST /employee/face-samples` with the logged-in employee’s id).
4. Until self-enroll exists, owners enroll via admin-web; employee screen can poll `face_registration_status` from profile / `GET` me.
5. On success, call existing `POST /employee/face-registration` with `{ "status": "completed" }` only if you still need that metadata path — prefer trusting embeddings (`face-status` / `face_registered_at` set by enroll).

### Clock-in with face (`scan_attendance_screen.dart`)

1. Keep GPS geofence preview as today.
2. Capture one face frame when user taps Clock in.
3. POST multipart to `/employee/attendance/clock-in-face`:

```dart
final form = FormData.fromMap({
  'latitude': lat,
  'longitude': lng,
  if (shiftId != null) 'shift_assignment_id': shiftId,
  'liveness_passed': true, // replace with real challenge later
  'face_image': await MultipartFile.fromFile(path, filename: 'face.jpg'),
});
await dio.post('/employee/attendance/clock-in-face', data: form);
```

4. Map errors:

| Server | UI |
|--------|-----|
| `outside_geofence` | Existing geofence message |
| `no_face` | “No face detected — retake” |
| `not_enrolled` | “Ask your manager to enroll your face” |
| `face_mismatch` | “Face did not match — try again” |

5. Keep JSON `/attendance/clock-in` as fallback until enrollment coverage is complete (or gate clock-in on `face_registration_status == completed`).

### Liveness (later)

On-device blink / head-turn challenge before upload; send `liveness_passed: true` only after pass. Server already stores the flag.

---

## Backend layout

| Path | Role |
|------|------|
| `backend/app/services/face_embedding.py` | Detect + embed + cosine |
| `backend/app/api/face.py` | Owner enroll / status / verify |
| `backend/app/models/face_embedding.py` | SQLAlchemy model |
| `backend/alembic/versions/013_employee_face_embedding.py` | Table + HNSW index |
| `backend/app/services/attendance_clock.py` | Optional face on clock-in |

Install / migrate:

```powershell
cd backend
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\alembic upgrade head
```

Pin: `opencv-python-headless>=4.10.0,<5` (OpenCV 5 wheels currently lack `CascadeClassifier`).

---

## Swapping to a stronger model later

Keep:

- Table `employee_face_embedding` with `vector(128)` (or migrate dim if the new model differs)
- Same multipart APIs and response shapes
- Client unchanged

Change only:

1. `detect_and_embed()` implementation (e.g. ONNX FaceNet / InsightFace)
2. `MODEL_VERSION` / `face_model_version` setting
3. Re-enroll all employees (embeddings are not compatible across models)

---

## Manual test checklist

- [ ] Migrate to 013
- [ ] Owner Face demo: enroll 3 photos for a test employee
- [ ] Verify same person → `passed: true`
- [ ] Verify different person / no face → clear error
- [ ] Reset enrolled face → status `not_registered`
- [ ] Employee GPS clock-in (no face) still works
- [ ] `clock-in-face` with enrolled face sets `face_match_score`
