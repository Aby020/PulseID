# Next Task — Task 3: Backend core + data model (Phase 2)

## Objective

Scaffold the PulseID **Django backend** (`backend/`) and implement the
**core infrastructure + MVP data model** for Phase 2 of the roadmap. Deliver a
clean, tested Django project with the base services (`core` app) and the
Part A MVP entities, with correct migrations, DB constraints, and enforced
tenant isolation at the data layer. No web/mobile work in this task.

## Inspect First

- Analyze the current PulseID project structure and the completion state of
  Task 2 (Foundation): `make help`, `Makefile`, `docs/PROJECT_STRUCTURE.md`
  ("Backend" section), `.github/workflows/ci.yml`, `.env.example`.
- Read the relevant planning documents before implementing:
  `docs/ARCHITECTURE.md` (esp. §3.1 app layout, §4 data model/indexes),
  `docs/DECISIONS.md`, `docs/ROADMAP.md` (Phase 2 exit criteria),
  `docs/PRODUCT_REQUIREMENTS.md`.
- Read the applicable AbiLabs standards first and follow them:
  `@../standards/python/README.md`, `@../standards/django/README.md`,
  `@../standards/django/drf.md`, `@../standards/database/README.md`,
  `@../standards/testing/README.md`.
- Identify which backend directories/files need to be created or adjusted
  (currently only `backend/.gitkeep` exists).

## Requirements

- **Django project** in `backend/` (Python 3.12, Django 5.x, DRF):
  - `manage.py`, `pyproject.toml` (ruff, pytest, mypy; deps pinned),
    settings split into `config/settings/base.py`, `dev.py`, `production.py`
    (dev never used in production; `USE_TZ=True`).
  - `config/urls.py`, `wsgi.py`, `asgi.py`.
  - Password hashing: Argon2id. JWT (drf-simplejwt) config read from env.
  - Env config via `.env` (copy `.env.example`; never commit real secrets).
- **Apps per `ARCHITECTURE.md` §3.1** — create initially as stub apps:
  `accounts`, `organizations`, `employees`, `workplaces`, `schedules`,
  `attendance`, `presence`, `biometrics`, `notifications`, `audit`,
  `analytics`, plus `core`. Only `core` and the MVP data-model apps are
  implemented in this task; the rest remain empty placeholders.
- **`core` app (shared base infrastructure):**
  - UUID base model + timestamp mixin + soft-delete semantics where specified.
  - `AbstractTenantModel` base (organization FK + tenant-scoped manager) so
    cross-tenant access is architecturally impossible at the query layer.
  - Timezone utilities (attendance day in org timezone), error envelope,
    pagination classes (limit/offset + cursor), RBAC permission classes.
- **MVP data model (Part A entities)** per `ARCHITECTURE.md` §4:
  `Organization`, `User` (custom), `Role`, `OrganizationMembership`,
  `Employee`, `Workplace` (schema-only for MVP), `WorkSchedule`,
  `AttendancePolicy`, `WorkSession`, `AttendanceEvent`, `AuditLog`.
  - Enforce the **one-active-session** constraint (DB-level), FK constraints,
    and indexes matching the query patterns in `ARCHITECTURE.md` §4.
- **Tests ship with the change** (pytest): model/constraint tests, tenant
  isolation tests, sane default behavior; ≥80% coverage on new code;
  deterministic. Update the `Makefile` `test`/`lint` targets so
  `make test` and `make lint` run the backend suite (pytest + ruff) and the CI
  workflow gains the backend checks (Python setup, ruff, pytest, migrations
  `--check`).
- All Pulses standards apply: typed code, snake_case, ORM only (no raw SQL),
  constraints at the DB, no secrets, Conventional Commits on a
  `feature/backend-core-data` branch off `main`.

## Acceptance Criteria

- [ ] `backend/` Django project scaffolds cleanly (`make backend` boots,
      `manage.py check` passes) with settings split, `USE_TZ=True`, Argon2id,
      and env-driven config.
- [ ] `core` app provides tenant base model + scoped manager, timezone utils,
      error envelope, pagination, and permission classes.
- [ ] All Part A MVP models exist with correct relationships, DB constraints
      (incl. one-active-session), and indexes; cross-tenant queries are blocked
      at the data layer.
- [ ] Migrations are clean and reproducible (`makemigrations --check --dry-run`
      exits clean); DB schema matches the models.
- [ ] `pytest backend/` passes with ≥80% coverage on new code (model,
      constraint, and tenant-isolation tests); `ruff check` clean.
- [ ] `Makefile` `test`/`lint` run the backend suite; CI workflow for the
      backend is green on the feature branch.
- [ ] No app code for web/mobile; no secrets committed; existing foundation
      functionality (root files, docs, structure checks) remains intact.

Do not begin unrelated work (no web, mobile, auth flows, or attendance engine
services in this task). After completing this task, analyze the project again
and provide the next task prompt.