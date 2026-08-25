# Attendance Check-In System — GPS Geofence + Face Liveness

[![Backend](https://img.shields.io/badge/backend-FastAPI-009688)](https://fastapi.tiangolo.com/)
[![Frontend](https://img.shields.io/badge/frontend-React%2018%20%2B%20Vite-61dafb)](https://react.dev/)
[![Mobile](https://img.shields.io/badge/mobile-Flutter%20%2F%20PWA-02569B)](https://flutter.dev/)
[![Database](https://img.shields.io/badge/database-PostgreSQL-336791)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A production employee attendance system that replaces the paper sign-in sheet with a
check-in that can actually be trusted: the employee must be **physically inside a
geofenced radius around a real office** and must **pass a face-liveness check** before
the clock-in is written to the database. Managers review everything as a monthly
calendar and get a daily summary pushed to LINE.

**Live deployment:** https://thanakronpart-time.com
**Full technical documentation:** [`checkin-system/README.md`](checkin-system/README.md) (Thai)

---

## Why I built this

I work part-time at MARDODI (บริษัท มาดูดิ จำกัด). Attendance there was recorded the way
it is recorded at a lot of small Thai companies — a shared sheet and a group chat message.
That created three concrete problems, and each one shaped a design decision in this repo:

**1. Attendance data was unverifiable.**
"I arrived at 08:45" was a claim, not a record. Anyone could write anything, and there was
no way to reconstruct the truth afterwards. I actually tried to reconstruct it — I exported
Google Takeout location history to see whether past attendance could be recovered from
phone GPS. It could not: Location History had been disabled on every device, so there was
no historical track to analyse (the full write-up is in
[`checkin-system/TRAVEL_ANALYSIS.md`](checkin-system/TRAVEL_ANALYSIS.md)). That negative
result is *why* the system logs its own ground truth from day one instead of trying to
derive attendance from data someone else owns.

**2. Location alone can be faked, and face alone can be faked.**
A GPS coordinate can be spoofed by a mock-location app. A face photo can be held up to a
camera. Requiring **both** — you are inside the radius **and** a live face is detected — makes
casual buddy-punching meaningfully harder without buying biometric hardware. The geofence
check is deliberately performed **server-side** (`backend/app/geofence.py`); the mobile app
computes distance too, but only to show the user feedback before they submit. The client is
never the authority.

**3. The manager needed a view, not a log.**
Raw check-in rows are useless to a non-technical manager. The React dashboard renders a
monthly calendar per employee, and a scheduled job pushes a daily summary to LINE — the
channel the team already uses — so nobody has to remember to open a web app.

Beyond the business problem, this repo is where I taught myself to ship a system end to
end rather than a demo: multi-branch geofencing, JWT auth with role separation, an
idempotent startup migration path, HTTPS via Cloudflare Tunnel without opening a router
port, and a PWA install path so employees on both Android and iOS get the same build.

---

## What it does

| Capability | Detail |
|---|---|
| **Multi-site geofencing** | Haversine distance against a configurable list of offices; if the user is inside more than one radius, the **nearest** one wins and its name is stored on the record |
| **Face liveness gate** | Google ML Kit face detection on device; a check-in is rejected if no live face is present |
| **Continuous location pings** | Flutter background service reports coordinates every 60s to `POST /locations/ping`, so presence is a time series, not a single point |
| **Tracking from login to logout** | Tracking starts the moment a session opens — before any clock-in, inside the geofence or at home — and stops only on logout or the 22:00 session cut-off. The app escalates to Android's *Allow all the time* location grant and keeps re-asking every 10 minutes until it gets it |
| **Today's timesheet on the phone** | The employee's own home screen lists every clock-in/out of the current Thai day with place and distance, plus first-in, last-out, and a live running total of hours worked |
| **Role-separated auth** | JWT (bcrypt-hashed passwords); manager-only endpoints for employee lists, calendar reports, and other employees' face records |
| **Manager calendar** | React + Ant Design monthly grid of in/out times and in-geofence status per employee |
| **Face enrollment gallery** | Webcam capture stored as a per-employee reference history, streamed back only to the owner or a manager |
| **LINE daily summary** | Scheduled task posts an end-of-day attendance summary to the team's LINE channel |
| **Installable PWA** | `vite-plugin-pwa`, with API requests deliberately excluded from the cache so attendance data is never stale |

## Architecture

```
┌──────────────────────┐   GPS every 60s + face scan   ┌──────────────────────┐
│  Flutter app / PWA   │ ────────────────────────────► │  FastAPI (uvicorn)   │
│  ML Kit · Geolocator │ ◄──────────────────────────── │  JWT · SQLAlchemy    │
└──────────────────────┘        accept / reject        └──────────┬───────────┘
                                                                  │
┌──────────────────────┐        manager reports        ┌──────────▼───────────┐
│  React + Vite + AntD │ ◄───────────────────────────► │     PostgreSQL       │
│  monthly calendar    │                               │  employees·checkins  │
└──────────────────────┘                               │  faces·location_pings│
                                                       └──────────┬───────────┘
                                                                  │ daily 
                                                       ┌──────────▼───────────┐
                                                       │  LINE Messaging API  │
                                                       └──────────────────────┘

Edge:  Cloudflare Tunnel → IIS :80 ─┬─ React static build
                                    └─ /auth /checkins /faces /reports … → uvicorn :8001
```

**Why this edge design:** the server is a Windows machine on an office network with no
static public IP and no router access. Cloudflare Tunnel gives a stable domain and free
TLS with an outbound-only connection — and TLS was not optional, because browsers refuse
`getUserMedia` (camera access for face capture) on plain HTTP. IIS with URL Rewrite + ARR
serves the static React build and proxies API paths to uvicorn, so the SPA and the API
share one origin and CORS stops being a problem in production.

## Tech stack

| Layer | Stack |
|---|---|
| Backend | Python · FastAPI · SQLAlchemy 2.0 (typed `Mapped[...]`) · Pydantic · python-jose · passlib/bcrypt |
| Database | PostgreSQL (SQLite for local dev) |
| Web | React 18 · Vite 5 · Ant Design 5 · React Router 6 · vite-plugin-pwa |
| Mobile | Flutter 3 · geolocator · camera · google_mlkit_face_detection · flutter_background_service |
| Infra | Docker Compose · IIS (URL Rewrite + ARR) · Cloudflare Tunnel · Windows Scheduled Tasks · PowerShell automation |

## Repository layout

```
checkin-system/
├── backend/          FastAPI service
│   ├── app/
│   │   ├── routers/  auth · checkins · faces · locations · reports · line
│   │   ├── geofence.py   Haversine + nearest-office selection
│   │   ├── security.py   JWT issue/verify, password hashing
│   │   ├── database.py   engine, session, additive startup migrations
│   │   └── models.py     Employee · CheckIn · FaceProfile · LocationPing
│   ├── tests_e2e.py      end-to-end API tests
│   └── Dockerfile
├── frontend/         React manager dashboard (PWA)
├── flutter_app/      Employee mobile client
├── deploy/           Cloudflare Tunnel · IIS · ngrok · LINE setup scripts
├── TRAVEL_ANALYSIS.md   Google Takeout feasibility study
└── README.md            Full setup guide (Thai)
```

## Quick start

```bash
git clone https://github.com/thanakon-film60/project_job_part-time.git
cd project_job_part-time/checkin-system
docker compose up --build          # API docs at http://localhost:8000/docs
```

```bash
cd frontend
npm install
cp .env.example .env               # VITE_API_BASE=http://localhost:8000
npm run dev                        # http://localhost:5173
```

Seed accounts created by `backend/seed.py` — employee `EMP001 / password123`,
manager `BOSS001 / boss12345`. Configure office geofences via the `OFFICES` JSON
variable in `backend/.env`. Step-by-step instructions, including Windows deployment,
are in [`checkin-system/README.md`](checkin-system/README.md).

## Core API

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/auth/register` · `/auth/login` | Registration and JWT issue |
| `POST` | `/checkins` | Clock in/out — validates geofence + face, stores photo |
| `GET` | `/checkins/me` | Own attendance history — optional `days` / `limit` (the app asks for `days=1` to render today's list) |
| `POST` | `/faces/enroll` | Enroll a reference face photo |
| `GET` | `/faces/employee/{id}` · `/faces/{id}/photo` | Face history (owner or manager only) |
| `POST` | `/locations/ping` | Continuous GPS reporting |
| `GET` | `/reports/calendar` · `/reports/employees` | Manager-only reporting |
| `GET` | `/reports/geofence` | Configured offices and radii |

## Engineering notes and known limits

I would rather state these than let a reviewer discover them:

- **Face check is liveness, not identity.** ML Kit confirms a real face is present; it does
  not verify *whose* face. True 1:1 matching needs embeddings (e.g. FaceNet) compared
  against enrolled references — the `face_profiles` table already stores those references,
  so the data model is ready for it. This is the next thing I intend to build.
- **Schema migrations are additive at startup.** `database.py` runs `ALTER TABLE` for
  late-added columns such as `office_name`. It is honest and idempotent, but Alembic is the
  correct answer once the schema changes shape rather than just growing.
- **Production hardening checklist:** rotate `SECRET_KEY` out of `.env` into a secret store,
  narrow `ALLOWED_ORIGINS`, and move check-in photos from local disk to object storage.
- **Offices live in an env var, not a table.** Fine for two sites; a real `offices` table
  with an admin UI is the right move past a handful.

## Roadmap

- [ ] Face embeddings for 1:1 identity verification against enrolled photos
- [ ] Alembic migrations replacing the additive startup path
- [ ] Leave/overtime tracking and CSV/Excel payroll export
- [ ] Admin UI for managing offices and radii
- [ ] Automated tests in CI (GitHub Actions)

## License

MIT — see [LICENSE](LICENSE).

## Author

**Thanakon** · [GitHub](https://github.com/thanakon-film60) · thanakon.film60@gmail.com
