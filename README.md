# PulseID

> **Intelligent Workforce Presence Platform**
> *Verify. Work. Track.*

---

## Overview

PulseID is a modern employee-attendance and workforce-presence platform built around **verified work sessions**. Employees clock in/out via a mobile app, PulseID records immutable attendance events, and HR/managers monitor attendance through a web dashboard.

The platform is designed to evolve from a solid MVP (clock in/out, attendance history, admin management) into a fully verified workforce system with face verification, liveness detection, event-based location verification, and presence checks — **without architectural rewrites**.

## Current Status

**Phase 1 — Foundation**

The repository structure, planning documentation, and development tooling are being established. No application code has been implemented yet.

## Architecture

```
┌────────────────┐      ┌─────────────────┐
│  Mobile app    │      │  Admin web app  │
│  React Native  │      │  React + Vite   │
│  (Expo, TS)    │      │  (HR/Manager)   │
└───────┬────────┘      └────────┬────────┘
        │ HTTPS / JSON               │ HTTPS / JSON
        ▼                           ▼
┌──────────────────────────────────────────────┐
│                API Gateway tier              │
│  Django REST Framework — modular monolith    │
│  Auth (JWT) · RBAC · Tenant context ·        │
│  Attendance domain · Presence engine API     │
└──────┬───────────────────┬───────────────────┘
       │ synchronous        │ asynchronous
       ▼                    ▼
┌─────────────┐      ┌──────────────────────┐
│ PostgreSQL  │      │ Redis + Celery       │
│ (source of  │      │ (broker, cache,      │
│  truth)     │      │  scheduler)          │
└─────────────┘      └──────────────────────┘
```

**Shape:** A modular Django monolith in front of PostgreSQL, with Redis + Celery for async work. The backend is organized into domain-specific Django apps (accounts, organizations, attendance, presence, biometrics, etc.) behind clear service boundaries.

## Repository Structure

```
PulseID/
├── backend/          # Python + Django + DRF (modular monolith)
├── web/              # React + TypeScript + Vite + Tailwind (admin)
├── mobile/           # React Native + Expo + TypeScript (employee)
├── infra/            # Docker, deployment config
├── scripts/          # Developer utilities
├── docs/             # Planning & architecture documentation
├── .github/          # CI/CD workflows
├── Makefile          # Development commands
├── README.md
└── LICENSE
```

## Technology Stack

| Layer | Technology |
| ----- | ---------- |
| **Mobile** | React Native + Expo + TypeScript |
| **Admin Web** | React + TypeScript + Vite + Tailwind CSS |
| **Backend** | Python 3.12 + Django 5.x + Django REST Framework |
| **Database** | PostgreSQL |
| **Cache / Broker** | Redis |
| **Async Jobs** | Celery + Celery Beat |
| **Auth** | JWT (drf-simplejwt) + rotating server-stored refresh tokens |
| **Password Hashing** | Argon2id |
| **WSGI** | gunicorn (production) |

## Development Phases

| Phase | Description | Status |
| ----- | ----------- | ------ |
| 0 | Planning & architecture | Complete |
| 1 | Foundation (repo, skeleton, CI) | **In progress** |
| 2 | Backend core + data model | Pending |
| 3 | Authentication & authorization | Pending |
| 4 | Attendance engine | Pending |
| 5 | Admin web app (MVP) | Pending |
| 6 | Mobile app (MVP) | Pending |
| 7 | Presence-check engine | Pending |
| 8–10 | Face verification, liveness, location | Pending |
| 11 | Notifications & push | Pending |
| 12 | Reports, analytics, test hardening | Pending |
| 13 | Security hardening | Pending |
| 14 | Deployment | Pending |

See [ROADMAP.md](docs/ROADMAP.md) for detailed phase descriptions and exit criteria.

## Planning Documentation

All architecture and planning documents live in [`docs/`](docs/):

| Document | Purpose |
| -------- | ------- |
| [PRODUCT_REQUIREMENTS.md](docs/PRODUCT_REQUIREMENTS.md) | What PulseID must do — features, workflows, non-functional requirements |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | How PulseID is built — system design, data model, API, security |
| [ROADMAP.md](docs/ROADMAP.md) | Phased delivery plan with exit criteria |
| [DECISIONS.md](docs/DECISIONS.md) | Architecture decision records (D-01 through D-11) |
| [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) | Repository layout and file responsibilities |
| [RISKS.md](docs/RISKS.md) | Technical, security, privacy, and deployment risks with mitigations |

## Getting Started

> **Note:** Application code has not been implemented yet. These commands will be functional once the backend, web, and mobile apps are scaffolded in later phases.

```bash
# Clone the repository
git clone <repository-url>
cd PulseID

# Set up environment
cp .env.example .env
# Edit .env with your local configuration

# Bootstrap development environment
make setup

# Run the backend (once implemented)
make backend

# Run the web admin (once implemented)
make web

# Run the mobile app (once implemented)
make mobile
```

## Development Principles

- **Server-authoritative time** — device clocks are never trusted for attendance decisions
- **Immutable event ledger** — every attendance action is an append-only event; derived results are computed, not stored as mutable state
- **Multi-tenant by design** — hard data isolation at the database layer; cross-tenant access is architecturally impossible
- **Privacy-first** — biometric and location data are handled with explicit consent, encryption, retention policies, and deletion paths
- **Incrementally buildable** — each phase delivers value without requiring future phases to be complete
- **Audit-ready** — every meaningful action is logged with actor, timestamp, and context

## Security & Privacy

- OWASP baseline security practices
- Deny-by-default authorization (RBAC on every endpoint)
- Secrets managed via environment variables, never in code
- Strong password hashing (Argon2id) with rotating refresh tokens
- **Biometric data** (face verification, liveness) will be implemented only in later phases (8–9), with encrypted template storage, consent management, and end-to-end deletion
- **Location data** will be event-based only (no continuous tracking), verified server-side, in later phases (10)
- All timestamps stored in UTC; attendance days interpreted in organization timezone

## License

License decision pending. See [LICENSE](LICENSE).

---

*PulseID — Verify. Work. Track.*
