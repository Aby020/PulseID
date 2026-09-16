# PulseID — Project Structure

Single **monorepo** (one independent git repo at `D:\AbiLabs\PulseID`). Rationale: `DECISIONS.md` D-01; full layout description below.

---

## Repository root

```
PulseID/
├── .github/                    # CI/CD workflows, issue templates
│   └── workflows/
│       └── ci.yml              # lint + test + security scan on PR
├── backend/                    # Django project (root; Python 3.12, Django 5.x, DRF)
│   ├── manage.py
│   ├── pyproject.toml          # ruff, pytest, mypy config; pinned deps
│   ├── config/                 # Django project settings package
│   │   ├── settings/
│   │   │   ├── base.py         # shared settings, installed apps, middleware
│   │   │   ├── dev.py          # local dev (DEBUG, DEBUG-toolbar, SQLite fallback optional)
│   │   │   └── production.py   # gunicorn, security headers, static, real DB
│   │   ├── urls.py
│   │   └── wsgi.py / asgi.py
│   ├── accounts/               # auth: login, refresh, logout, password reset, invite
│   ├── organizations/          # tenants, membership, roles, RBAC
│   ├── employees/              # employee identity & employment data
│   ├── workplaces/             # workplace locations + geofences
│   ├── schedules/              # shift templates, rosters, timezone windows
│   ├── attendance/             # policies, WorkSession, AttendanceEvent, results
│   ├── presence/               # PresenceCheck, VerificationAttempt, scheduler
│   ├── biometrics/             # FaceEnrollment, consent, provider boundary
│   ├── notifications/          # Notification records, push + in-app channels
│   ├── audit/                  # AuditLog (append-only trail)
│   ├── analytics/              # report jobs, aggregates (reads event ledger)
│   ├── core/                   # shared: base models, tenant mixins, tz utils, pagination, error envelope, permissions
│   └── tests/                  # top-level test packages mirroring apps (pytest)
│       ├── conftest.py         # shared fixtures
│       ├── test_accounts/
│       ├── test_attendance/
│       └── ...
├── web/                        # Admin web app (React + TS + Vite + Tailwind)
│   ├── package.json            # deps: react, react-router-dom, @tanstack/react-query, tailwindcss, vite, motion
│   ├── tsconfig.json
│   ├── vite.config.ts
│   ├── index.html
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx             # route guards by role
│   │   ├── api/                # generated API client from OpenAPI + http wrapper
│   │   ├── auth/               # auth state store, hooks
│   │   ├── layout/             # shell, sidebar, headers
│   │   ├── pages/              # Dashboard, Employees, Attendance, ...
│   │   ├── components/         # reusable UI components + design tokens
│   │   └── lib/                # shared helpers, types
│   ├── public/
│   └── tests/
├── mobile/                     # Employee mobile app (Expo + React Native + TS)
│   ├── package.json            # deps: expo, react-navigation, zustand, react-query, secure-store
│   ├── app.json                # Expo config, splash, permissions declarations
│   ├── tsconfig.json
│   ├── App.tsx                 # root switch by auth state
│   ├── src/
│   │   ├── api/                # generated API client + http wrapper (keychain, refresh)
│   │   ├── auth/               # auth store, secure storage, token refresh
│   │   ├── navigation/         # root navigator, tab bar, stacks
│   │   ├── screens/            # Splash, Login, Home, ClockIn, ActiveSession, History, ...
│   │   ├── components/         # reusable RN components
│   │   └── lib/                # shared helpers, types, push registration
│   └── tests/
├── infra/                      # Infrastructure-as-code
│   ├── docker/
│   │   ├── Dockerfile.django   # backend image
│   │   └── nginx.conf          # reverse proxy / static serving
│   ├── docker-compose.yml      # local dev stack: django, postgres, redis, celery worker, celery beat
│   └── env.example             # documented env vars (no secrets)
├── scripts/                    # Developer utilities
│   ├── setup.sh                # bootstrap local dev
│   └── lint-skills.ps1         # (if skill-related docs ever live here)
├── docs/                       # Project + planning documentation
│   ├── PRODUCT_REQUIREMENTS.md # moved here in Phase 1 from root
│   ├── ARCHITECTURE.md
│   ├── ROADMAP.md
│   ├── DECISIONS.md
│   ├── PROJECT_STRUCTURE.md    # this file
│   ├── RISKS.md
│   └── decisions/              # future ADRs beyond Task 1 decisions
├── Makefile                    # shortcuts: make setup, make test, make lint, make migrate
├── README.md                   # project summary, quickstart, where to find docs
├── LICENSE
├── .gitignore
├── .env.example                # root-level env example (duplicated for clarity)
└── Task.md                     # (ephemeral task brief; may be removed after Task 1)
```

> **Note:** `PRODUCT_REQUIREMENTS.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `DECISIONS.md`, `PROJECT_STRUCTURE.md`, and `RISKS.md` live at the repo root in Task 1 for discoverability. Phase 1 (`ROADMAP.md`) migrates them into `docs/` and updates all cross-references.

---

## Key files & responsibilities

### Backend (`backend/`)

| Path | Purpose |
| ---- | ---- |
| `config/settings/base.py` | Shared Django config: `INSTALLED_APPS`, middleware stack, REST framework settings, timezone (`USE_TZ=True`), password hashers (Argon2id), JWT config, Redis/Celery bindings |
| `config/settings/production.py` | Security headers (`HTTPS`, `HSTS`), gunicorn settings, sentry init, no `DEBUG` |
| `core/models.py` | `AbstractTenantModel` base (adds `organization` FK + tenant-scoped manager), UUID base model, timestamp mixin |
| `core/permissions.py` | RBAC permission classes (role-based, tenant-bound); cross-tenant deny-by-default |
| `core/pagination.py` | `LimitOffsetPagination`; `CursorPagination` subclass for event/audit streams |
| `core/errors.py` | Consistent error envelope helper; maps domain exceptions to HTTP status |
| `core/timezone.py` | Org-timezone date helpers (attendance day, schedule window interpretation in org tz) |
| `accounts/services.py` | `AuthService.login`, `.refresh`, `.logout`, `.password_reset`; token lifecycle |
| `attendance/services.py` | `ClockInService`, `ClockOutService`, `.current_session`, attendance result derivation |
| `attendance/queries.py` | Read-side queries: attendance history, summaries, "today" view — with org tz |
| `presence/scheduler.py` | Rolling scheduler scan task + per-check expiry dispatch + reconciliation sweep |
| `presence/resolver.py` | `PresenceResolutionService`: handles response, applies verification, transitions state |
| `biometrics/provider.py` | Provider interface (abstract): `enroll(template) → enrollment_id`, `.verify(template_id, challenge) → Verdict` |
| `notifications/channels.py` | Abstract `NotificationChannel.send(...)`, concrete Expo/FCM adapters |
| `audit/logger.py` | `AuditLogger.log(actor, action, category, target, delta)` — append-only write |

### Web (`web/`)

| Path | Purpose |
| ---- | ---- |
| `src/api/client.ts` | Base HTTP wrapper: auth header injection, refresh-on-401 retry-once, typed error envelope |
| `src/api/generated/` | Auto-generated OpenAPI client (one shared contract with mobile) |
| `src/auth/store.ts` | Auth state: user + org + role from `/me`; logout action |
| `src/layout/AppShell.tsx` | Authenticated shell with section nav; role-gated sections |
| `src/pages/` | One page per major section; thin — delegates to components and React Query hooks |
| `src/components/` | Design-system-aware UI primitives (data tables, stat cards, modals, forms) |
| `src/lib/hooks.ts` | React Query hooks wrapping API calls (list employees, get events, start report) |

### Mobile (`mobile/`)

| Path | Purpose |
| ---- | ---- |
| `src/api/client.ts` | HTTP client: Expo SecureStore for refresh token, in-memory access token, refresh-on-401, typed envelope |
| `src/auth/store.ts` | Zustand store: user/org, login action, logout action, secure token persistence |
| `src/navigation/RootNavigator.tsx` | Auth-state switch (Authenticated / SignedOut / Loading) |
| `src/navigation/AuthenticatedTabs.tsx` | Bottom tab bar: Home, History, Notifications, Profile |
| `src/navigation/AttendanceStack.tsx` | Stack: ClockIn → ActiveSession → (future: PresenceVerify, FaceVerify) |
| `src/screens/` | Thin screens; React Query hooks for data; no domain logic in components |
| `src/lib/push.ts` | Expo push token registration with the backend |

### Infra (`infra/`)

| Path | Purpose |
| ---- | ---- |
| `docker/Dockerfile.django` | Multi-stage build: dependencies → app; gunicorn entrypoint |
| `docker/nginx.conf` | TLS termination (prod) or local reverse proxy; static file caching |
| `docker-compose.yml` | Local dev: `django` (gunicorn/`runserver`), `postgres`, `redis`, `celery-worker`, `celery-beat`, volumes, env |
| `env.example` | All env vars documented (no values); `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY` (placeholder), `ALLOWED_HOSTS`, `CORS` |

---

## Commit conventions

Follow the workspace standard (Conventional Commits):

```
<type>(<scope>): short description

<body>
```

Scopes mirror the top-level directories: `backend`, `web`, `mobile`, `infra`, `docs`. Common prefixes: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`. One logical change per commit. Never push to `main`; use `feature/<name>` or `fix/<name>`.

---

## Migration path from Task 1 root docs → `docs/`

During Phase 1 the six planning documents will be moved into `docs/` and internal links updated. The monorepo layout above reflects the final intended state.