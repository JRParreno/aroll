# Aroll+

**Face Recognition-Based Attendance and Payroll System**

Capstone / thesis project for small food-and-service businesses in Bicol, Philippines.

---

## Project setup (first time)

**Prerequisites:** Python 3.11+, Node.js 18+, Flutter 3.2+, Docker Desktop (recommended).

```powershell
cd c:\Users\jrparreno\Development\aroll
.\scripts\setup.ps1
```

This installs dependencies, creates `.env` files, and (if Docker is available) migrates and seeds the database.

Full guide: [**docs/PROJECT-SETUP.md**](docs/PROJECT-SETUP.md)

---

## Quick start (daily dev)

```powershell
.\scripts\aroll.ps1
```

Menu options:

| # | Action |
|---|--------|
| 0 | **Project setup** (first time — same as `setup.ps1`) |
| 1 | Start PostgreSQL (Docker) |
| 2 | Migrate + seed database |
| 3 | Start FastAPI backend → http://localhost:8000/docs |
| 4 | Start admin web → http://localhost:5173 |
| 5 | Start Flutter mobile |
| 6 | Start all (DB + migrate + backend + admin-web) |
| 7 | Build all |
| 8 | Clean all |

**Default platform admin:** `admin@example.com` / `changeme123`

---

## Project layout

```
aroll/
  backend/         # FastAPI + Alembic
  admin-web/       # React + Vite + shadcn-style UI
  mobile/          # Flutter + BLoC + go_router + shadcn_ui
  docs/            # System design + W1 data requirements
  scripts/         # setup.ps1, aroll.ps1 menu, build, clean
  docker-compose.yml
```

---

## Public server

The server branch is `release/deployment-ready`. It does not include a database dump. Alembic rebuilds the schema, including the `vector` extension, on an empty PostgreSQL 16 database.

On a fresh Ubuntu VM:

```bash
sudo bash deploy/bootstrap-ubuntu.sh your-name.duckdns.org
```

That script installs Docker, Caddy, and the API service, generates `backend/.env` on the server, starts Postgres on `127.0.0.1:5432`, runs `alembic upgrade head`, and creates only the platform admin. It does not load Demo Café or Dev Lab.

After it finishes, sign in at `https://your-name.duckdns.org` as `admin@example.com` / `changeme123` and change that password. Approval email and owner Help need the SMTP values in the server's `backend/.env`. Face recognition downloads its two ONNX models during setup. The Android app is built separately; set `API_BASE_URL` in `mobile/.env` to `https://your-name.duckdns.org/api/v1` before `flutter build apk`.

To upgrade an existing server database, pull this branch and run `alembic upgrade head` from `backend/` with that server's `.env`. Do not run `python -m app.seed` on the server.

Local development still uses `docker compose up -d`, then `alembic upgrade head`, then `python -m app.seed` from `backend/`.

---

## Pilot businesses

Mr. Bean Cafe, Ugom Cafe, Pande Doc, Benzon Burger House

---

## Tech stack

| Layer | Technology |
|-------|------------|
| Mobile | Flutter, BLoC, go_router, GetIt, shadcn_ui, dio |
| Admin web | React, Vite, Tailwind, shadcn-style components, TanStack Query |
| API | FastAPI, JWT, SQLAlchemy, Alembic |
| Database | PostgreSQL + pgvector (Docker) |

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/SOLUTION.md](docs/SOLUTION.md) | System design |
| [docs/W1-DATA-REQUIREMENTS.md](docs/W1-DATA-REQUIREMENTS.md) | Locked data rules |
| [docs/PROJECT-SETUP.md](docs/PROJECT-SETUP.md) | First-time setup guide |
| [docs/IMPLEMENTATION-W1-W4.md](docs/IMPLEMENTATION-W1-W4.md) | Build notes |
| [docs/legal/](docs/legal/) | Terms / Privacy / Biometric **templates** only |
| [clean_code_bloc.md](clean_code_bloc.md) | Flutter BLoC guide |

**Runtime legal source of truth:** Platform Admin publishes default Terms, Privacy, and Biometric Consent. Businesses use those defaults unless an owner enables `use_custom_consents`. Employees review `/legal/b/{business_code}` and the server stores typed `consent_record` rows. Markdown files under `docs/legal/` are templates/reference — they are not the production consent documents.

---

## Manual commands

```powershell
# Database
docker compose up -d

# Backend
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\alembic upgrade head
.\.venv\Scripts\python -m app.seed
.\.venv\Scripts\uvicorn app.main:app --reload --port 8000

# Admin web
cd admin-web
npm install
npm run dev

# Mobile
cd mobile
flutter pub get
flutter run
```

---

## License & authors

Thesis project — add author names, institution, and year before submission.
