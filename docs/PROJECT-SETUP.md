# Aroll+ — Project Setup (first time)

One-time setup on a new machine before daily development.

---

## 1. Prerequisites

Install these and confirm they work in PowerShell:

| Tool | Version | Check command | Purpose |
|------|---------|---------------|---------|
| **Python** | 3.11+ | `python --version` | FastAPI backend |
| **Node.js** | 18+ | `node --version` | Admin web |
| **npm** | 9+ | `npm --version` | Admin web |
| **Flutter** | 3.2+ | `flutter --version` | Mobile app |
| **Docker Desktop** | Latest (optional) | `docker --version` | PostgreSQL + pgvector |

**Recommended:** [VS Code](https://code.visualstudio.com/) or Cursor with extensions: **Python**, **Dart**, **Flutter**.

---

## 2. Automated setup (recommended)

From the repo root:

```powershell
cd c:\Users\jrparreno\Development\aroll
.\scripts\setup.ps1
```

This script will:

1. Check prerequisites
2. Create `backend/.env`, `admin-web/.env`, `mobile/.env` from examples (if missing)
3. Create Python venv and install backend dependencies
4. Run `npm install` in `admin-web/`
5. Run `flutter pub get` in `mobile/`
6. Optionally start Docker, run migrations, and seed the platform admin

---

## 3. Manual setup

### 3.1 Clone and enter the repo

```powershell
git clone <your-repo-url> aroll
cd aroll
```

### 3.2 Environment files

```powershell
Copy-Item backend\.env.example backend\.env
Copy-Item admin-web\.env.example admin-web\.env
Copy-Item mobile\.env.example mobile\.env
```

Edit if needed:

| File | Key | Default |
|------|-----|---------|
| `backend/.env` | `DATABASE_URL` | `postgresql://aroll:aroll@localhost:5432/aroll` |
| `admin-web/.env` | `VITE_API_URL` | `http://localhost:8000/api/v1` |
| `mobile/.env` | `API_BASE_URL` | `http://10.0.2.2:8000/api/v1` (Android emulator) |

For a **physical phone**, set `API_BASE_URL` to your PC’s LAN IP, e.g. `http://192.168.1.10:8000/api/v1`.

### 3.3 Database

**Option A — Docker (easiest)**

```powershell
docker compose up -d
```

**Option B — Local PostgreSQL**

Install PostgreSQL 16+, enable extension `vector`, create database `aroll`, and update `DATABASE_URL` in `backend/.env`.

### 3.4 Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\alembic upgrade head
.\.venv\Scripts\python -m app.seed
cd ..
```

Seed creates platform admin: **admin@example.com** / **changeme123**

### 3.5 Admin web

```powershell
cd admin-web
npm install
cd ..
```

### 3.6 Mobile

```powershell
cd mobile
flutter pub get
# First time only (if android/ missing):
# flutter create . --org ph.edu.bicol.aroll --project-name aroll_mobile
cd ..
```

---

## 4. Run the stack

Use the dev menu:

```powershell
.\scripts\aroll.ps1
```

| Option | When to use |
|--------|-------------|
| **0** | First-time setup (same as `setup.ps1`) |
| **2** | After DB is running — migrate + seed |
| **6** | Daily dev — DB + API + admin web |

---

## 5. Verify installation

| Check | URL / action |
|-------|----------------|
| API health | http://localhost:8000/health → `{"status":"ok"}` |
| API docs | http://localhost:8000/docs |
| Admin login | http://localhost:5173 → `admin@example.com` / `changeme123` |
| Mobile | `flutter run` — employee login after owner creates account |

### Sample API flow (Swagger)

1. `POST /api/v1/registrations` — submit a test business
2. Log in as admin → `POST /api/v1/admin/registrations/{id}/approve`
3. Log in as owner (owner email / `changeme123`) on admin web → add employee
4. Log in on mobile with employee email + temporary password → change password

---

## 6. Troubleshooting

| Problem | Fix |
|---------|-----|
| `docker` not found | Install Docker Desktop or use local Postgres + update `DATABASE_URL` |
| Alembic connection refused | Start database first (menu **1** or `docker compose up -d`) |
| Mobile cannot reach API | Use `10.0.2.2` on Android emulator; LAN IP on real device |
| `bcrypt` / login errors | Use backend venv Python; password max 72 bytes for bcrypt |
| Port 8000 / 5173 in use | Stop other apps or change ports in uvicorn / `vite.config.ts` |

---

## 7. Related docs

- [README.md](../README.md) — overview
- [IMPLEMENTATION-W1-W4.md](IMPLEMENTATION-W1-W4.md) — W2–W4 build notes
- [W1-DATA-REQUIREMENTS.md](W1-DATA-REQUIREMENTS.md) — business rules
