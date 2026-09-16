# PulseID — Architecture

> Companion to `PRODUCT_REQUIREMENTS.md` (what) and `DECISIONS.md` (why). This document is the *how*.

**Status:** Phase 0 — Planning (Task 1). No code exists. Every section below that references a runnable component is the agreed target design; implementation proceeds phase by phase per `ROADMAP.md`.

---

## 1. High-level architecture

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
│  Reverse proxy (TLS termination)             │
│  Django REST Framework — monolithic core     │
│  Auth (JWT) · RBAC · Tenant context ·        │
│  Attendance domain · Presence engine API     │
└──────┬───────────────────┬───────────────────┘
       │ synchronous        │ asynchronous
       ▼                    ▼
┌─────────────┐      ┌───────────────┐
│ PostgreSQL  │      │ Redis (broker │
│ (source of  │      │ + cache +     │
│  truth)     │      │  throttle)    │
└─────────────┘      └──────┬────────┘
                            ▼
                   ┌──────────────────────┐
                   │ Celery worker + Beat │
                   │  · presence scheduler│
                   │  · notifications     │
                   │  · reports           │
                   └──────────────────────┘
```

**Shape.** A modular **Django monolith** (one codebase, several Django apps) in front of PostgreSQL, with Redis + Celery for async work. The core attendance/domain apps are written so that face verification, location verification, push notification providers, and the presence-check engine plug in **behind service boundaries** — they are capabilities of the backend, not forks in the data model.

**Why a monolith (module) rather than microservices.** For this product's current scale and team, a well-modularized monolith is simpler to secure (one tenant-boundary enforcement point), simpler to deploy (fewer moving parts), and cheaper to run — while the presence-check engine is isolated behind its own async pipeline so it can be extracted into a dedicated service later with no rewrites. Rationale and trade-offs: `DECISIONS.md` D-02.

## 2. Repository structure

Single **monorepo**, one independent git repo at `D:\AbiLabs\PulseID` (consistent with the AbiLabs rule that each product is its own repo). Layout: `PROJECT_STRUCTURE.md`. Rationale: `DECISIONS.md` D-01.

## 3. Backend architecture

Stack: **Python 3.12 · Django 5.x · Django REST Framework · PostgreSQL 16 · Redis · Celery + Celery Beat**. Reasoned selections and rejections: `DECISIONS.md` D-03.

### 3.1 Django app boundaries (modular monolith)

One Django **project**, several apps that map 1:1 to domain areas (single responsibility per app; no app is an "models dump"):

| App | Responsibility | Owns |
| --- | -------------- | ---- |
| `accounts` | Authentication, sessions, tokens, password reset, invites | `User`, refresh tokens, `Account` status |
| `organizations` | Tenant, membership, roles | `Organization`, `OrganizationMembership`, `Role` |
| `employees` | Employee identity & employment data (tied to a User) | `Employee` |
| `workplaces` | Physical locations + geofences | `Workplace` |
| `schedules` | Shift templates, rosters, day windows | `WorkSchedule` |
| `attendance` | Policies, work sessions, immutable event ledger, computed results | `AttendancePolicy`, `WorkSession`, `AttendanceEvent`, attendance results |
| `presence` | Presence-check engine (schedule, prompt, resolution) | `PresenceCheck`, `VerificationAttempt` |
| `biometrics` | Enrollment & verification (face) behind a provider interface | `FaceEnrollment`, consent records |
| `notifications` | Outbound notification records, channels (push/in-app) | `Notification` |
| `audit` | Append-only audit trail | `AuditLog` |
| `analytics` | Reports & working-hour analytics (reads event ledger) | report jobs, aggregates |
| `core` (shared) | Base models, tenant mixins, timezone utils, error envelope, pagination, permissions | shared plumbing |

### 3.2 Layering inside the backend

- **Api layer** (serializers + viewsets): DTOs, validation, pagination, authz entry.
- **Service/domain layer** (plain Python in each app): business rules — e.g., `ClockInService`, `PresenceResolutionService` — testable without HTTP. Services hold the invariants (state machines, idempotency, policy application).
- **Data layer** (models, managers, constraints): storage + integrity enforced at the DB.
- **Infrastructure adapters** (Redis, Celery, email, push provider, future face provider): behind thin interfaces so the domain never imports a vendor SDK.

### 3.3 Technology additions & justification

| Technology | Role | Justification (see D-03) |
| ---------- | ---- | ------------------------ |
| PostgreSQL | Primary relational DB | JSON-capable, strong constraints, UTF8/collation, mature Django support |
| Redis | Cache, rate-limit store, Celery broker/result backend, presence-check coordination locks | Sub-millisecond, multi-purpose; justified no further |
| Celery + Beat | Async jobs, scheduled presence scans, notifications, reports | Durable queue with retries for reliability requirements |
| gunicorn | WSGI server in production | Standard, worker-process model, never `runserver` in prod |
| drf-simplejwt | Access/refresh token issuance | Mature, audited, supports rotation |
| argon2-cffi | Password hashing | Argon2id is the current OWASP-recommended KDF; Django has a first-party hasher |

**Rejected (no justified need yet):** a separate message queue beyond Redis/Celery (Kafka) — event volume is not at that scale; a dedicated search engine (Elasticsearch) — queries are structured and indexable in Postgres; a separate API gateway product — a reverse proxy + DRF serves.

## 4. Database architecture

Full detail in the phase that implements it. Agreed shape:

### 4.1 Entities and why each exists

| Entity | Purpose | Why separate |
| ------ | ------- | ------------ |
| `Organization` | Tenant root. Holds name and **timezone** (domain config). | Everything is scoped under a tenant; timezone is tenant config. |
| `User` | Authentication principal (login identity). | Identity is distinct from employment; a principal may (later) belong to multiple organizations. |
| `Employee` | Employment record: org, profile, default workplace, schedule, policy overrides, employment status. 1:1 with `User` (MVP). | Employment facts are not auth facts; keeps `User` clean and separates ordinary data from sensitive data. |
| `Role` | Named RBAC role with permissions. | Clean role-permission matrix; extensible roles without code churn. |
| `OrganizationMembership` | Links `User` → `Organization` with a `Role` (+ status). | This is the tenant-membership boundary that authorization is built on. |
| `Workplace` | A location: name, address, optional lat/lng + allowed radius. | Location verification targets a workplace, not a free-form coordinate. |
| `WorkSchedule` | Recurring shift template: days, start/end, timezone; assigned to employees. | "What is expected" must be separated from "what happened" (events) so lateness/overtime are derivable. |
| `AttendancePolicy` | Org-level (with optional per-employee override) rules: grace, late threshold, early-departure, overtime, required verification, presence-check policy. | Rules are configuration, versioned, and applied at read time — not baked into stored rows. |
| `WorkSession` | **Mutable aggregate**: state machine (created → active → ended/cancelled); the current session for an employee. | One live session per employee; owning state transitions and idempotency. |
| `AttendanceEvent` | **Immutable, append-only ledger**: clock-in/clock-out (later: break start/end, overtime event). Records server-timestamp, source, optional location, device metadata. | Auditability and reconstruction. Nothing is ever edited or deleted — derived results (duration, lateness) are computed from this ledger. |
| `PresenceCheck` | A scheduled presence-verification instance with its own state machine (scheduled → due → awaiting response → verified / failed / timed out / missed). | A distinct lifecycle with its own policy handling; separate from the session it belongs to. |
| `VerificationAttempt` | One attempt to verify presence, location, or (future) identity. Records outcome + non-sensitive metadata. | Every verification is provable; face/liveness providers attach here later without touching WorkSession. |
| `FaceEnrollment` | (Future) biometric enrollment reference: consent record, encrypted template (or template reference), version, status. No raw image. | Biometric data is kept separate from employee data and access-controlled independently. |
| `Notification` | Outbound notification: type, recipient, channel, status (queued/sent/delivered/failed), payload reference. | Delivery is retriable and auditable; in-app inbox built on the same table. |
| `AuditLog` | Append-only trail: actor, org, action, category, target, snapshot delta. | Meets auditability and governance requirements without polluting domain tables. |

### 4.2 Critical relationships

```
Organization 1─n OrganizationMembership n─1 User         (membership boundary)
Organization 1─n Employee 1─1 User
Organization 1─n Workplace
Organization 1─n Roles
Organization 1─n WorkSchedule        (assignable to Employees)
Organization 1─n AttendancePolicy    (per-employee overrides allowed)
Employee  1─n WorkSession
WorkSession 1─n AttendanceEvent     (immutable)
WorkSession 1─n PresenceCheck       1─n VerificationAttempt (+ WorkSession→VerificationAttempt optional)
Employee  1─n Notification
User      1─n AuditLog (actor)
```

### 4.3 Important integrity & constraints

- **Concurrent clock-in:** a partial unique index / constraint ensuring at most one **active** `WorkSession` per employee (e.g., `UniqueConstraint(fields=["employee"], condition=Q(status=ACTIVE), name="uniq_active_session_per_employee")`), *plus* an idempotency key at the API.
- **Duplicate events:** no two `AttendanceEvent`s of the same `kind` from the same session can both be "terminal" (clock-in twice / clock-out twice) — enforced in the service layer and mirrored by a DB constraint where expressible.
- **One employee ↔ one active session** (above). Presence checks can only attach to an active session.
- **Tenant isolation:** every tenant-scoped table carries an explicit `organization` FK. See § 8.3.
- **Timestamps:** all `DateTimeField`s are `USE_TZ=True`, stored UTC. See § 5.
- **Audit insert-only:** tables `audit_*` are write-only from the app (no update/delete APIs; DB-level trigger/privilege guard in prod).
- **Biometric rows (future):** never store raw images; template blob encrypted (envelope encryption); `organization` FK present for isolation; retention/expiry enforced by scheduled job.

### 4.4 Indexing & partitioning notes

- Index `AttendanceEvent(session_id, "timestamp")` and `AttendanceEvent(employee_id, "timestamp")` (typical queries: today's events for one employee/session).
- Index `WorkSession(employee, status)` for "find active session".
- Index `PresenceCheck(status, due_at)` for the presence scheduler scan.
- Index `AuditLog(organization, "timestamp")` and `AuditLog(actor)`.
- Partitioning by time is **not** needed for MVP; revisit if event volume per tenant grows beyond ~tens of millions of rows (note in `RISKS.md`).

## 5. Time & attendance logic

- **Storage:** all datetimes UTC (Django `USE_TZ = True`). Clients receive/display in their org timezone; the API returns ISO-8601 with `Z`.
- **Tenant timezone:** `Organization.timezone` (IANA identifier). Attendance "day" boundaries, schedule interpretation, and report windows are computed in the **org timezone**, not the server or device timezone.
- **Authority:** server time. Device-reported time is captured as `device_reported_at` metadata only, never used in computed attendance values.
- **Scheduled start vs actual:** `WorkSchedule` gives expected start/end; events give actual; `ClockInService` marks late vs on-time by comparing server clock-in against scheduled start (`+ grace` and `+ late threshold` from policy). All of this is **derived** at read time (with caching of computed summaries), never written as a single mutable `is_late` flag.
- **Day boundaries:** a work session that spans midnight belongs to the attendance day of its **start**, interpreted in org timezone (documented decision in `DECISIONS.md` D-07; kept configurable per policy).
- **Duration:** `clock_out - clock_in`, minus breaks if policy excludes them → `DecimalField(seconds)` value computed by a service and cached on a derived `AttendanceResult` row (derived-but-persisted snapshot is safe; the ledger remains the source of truth).

## 6. API architecture

### 6.1 Organization & versioning
- REST, JSON. Base path: **`/api/v1/`**. Version in the URL path (explicit, cache/CDN-friendly); when a breaking change is required, `/api/v2/` lives alongside v1 until clients are migrated. Content-type is `application/json` (or `application/problem+json` for errors).
- Resource areas map to apps: `auth`, `users`, `organizations`, `employees`, `workplaces`, `schedules`, `attendance/work-sessions`, `attendance/events`, `presence/checks`, `notifications`, `reports`, `analytics`, `audit`.

### 6.2 Authentication & authorization
- **Access:** HTTP `Authorization: Bearer <jwt>` access token (short-lived, ~15–20 min).
- **Refresh:** `POST /api/v1/auth/refresh` with a rotating, server-stored refresh token (revocable; single-use-per-rotation; reuse detection invalidates the whole family).
- **AuthZ:** every request resolves the caller's `OrganizationMembership` → org + role; DRF permission classes + a base viewset inject the tenant scope. See § 8.

### 6.3 Format contracts
- **Success:** RESTful resources with stable field naming (snake_case), ISO-8601 timestamps, and `id` as string/UUID.
- **Errors:** consistent envelope:

```json
{
  "error": {
    "code": "work_session_already_active",
    "message": "You already have an active work session.",
    "details": { "field": "…", "extra": "…" },
    "request_id": "req_…"
  }
}
```

  HTTP status codes always correct (400 validation, 401 unauthenticated, 403 forbidden, 404 not found, 409 conflict, 422 for semantic/state conflicts where applicable, 429 throttled, 5xx server). `request_id` correlates with logs.

- **Pagination:** `LimitOffsetPagination` for generic lists; **cursor pagination** for time-ordered, append-heavy streams (attendance events, audit logs, notifications) so pages stay stable under writes.
- **Filtering:** query parameters (`?from=…&to=…&employee=…&status=…`); filtering is allow-listed per endpoint and validated (rejects unknown parameters).
- **Rate limiting:** DRF throttles backed by Redis — stricter scopes for `auth/*` (login, refresh, password reset) and `attendance/*` (clock in/out); per-user, per-IP fallback.
- **Idempotency:** state-changing attendance endpoints accept `Idempotency-Key` header; the server returns the same result for a repeated key within a retention window and never double-applies a clock-in. Non-idempotent side effects (reports) use job ids.
- **Validation:** serializer-level validation for requests; domain/service-level invariants for state machines; DB constraints as the final backstop.

### 6.4 API surface preview (not implemented)

| Method | Path | Purpose |
| ------ | ---- | ------- |
| POST | `/api/v1/auth/login` | Issue access + refresh |
| POST | `/api/v1/auth/refresh` | Rotate refresh token |
| POST | `/api/v1/auth/logout` | Revoke refresh token |
| GET | `/api/v1/me` | Current user + memberships + roles |
| POST | `/api/v1/attendance/work-sessions/start` | Clock in (idempotent) |
| POST | `/api/v1/attendance/work-sessions/{id}/end` | Clock out (idempotent) |
| GET | `/api/v1/attendance/work-sessions/current` | Active session + live duration |
| GET | `/api/v1/attendance/events` | Cursor-paginated event ledger |
| GET/POST | `/api/v1/presence/checks` | List / respond to presence checks |
| GET | `/api/v1/employees` · `/workplaces` · `/schedules` · `/policies` | HR/Admin resources |
| GET | `/api/v1/reports/attendance` | Report generation (async) |
| GET | `/api/v1/audit` | Audit log (Admin) |

## 7. Mobile architecture (Expo / React Native / TypeScript)

Employees only. Not implemented in Task 1 — this is the target design.

### 7.1 Skeleton
- **Tooling:** Expo (managed workflow for MVP, can prebuild when native modules require) + TypeScript + React Navigation + a typed API client generated from the OpenAPI spec shared with the web app (single source of truth for the contract).
- **Navigation:** root switch by **auth state** (`Authenticated` vs `SignedOut` vs `Loading`); within-app bottom tabs (`Home` / `History` / `Notifications` / `Profile`) and a stack for flows (clock-in, presence verification, face verification later).
- **State:** server state via React Query (cache, retries, dedupe); auth/session state in a small typed store (Zustand) mirrored into secure storage; navigation state handled by React Navigation. UI state stays local to screens.
- **API layer:** one `http` client wrapper — injects auth header, refresh-on-401 with retry-once, wraps the error envelope into typed errors, and surfaces `request_id`. Base URL via app config per environment.
- **Secure token storage:** `expo-secure-store` (Keychain/Keystore). Access token in memory only; refresh token in secure storage.
- **Offline:** app is `fresh-first`; attendance actions (clock in/out) **require connectivity** because the server timestamp is authoritative. Presence responses likewise require connectivity. Offline *viewing* of cached history is a post-MVP nicety.
- **Push notifications:** Expo token registered with the backend (which stores it on the `Notification` device record); foreground handling makes presence prompts route to the verification screen.
- **Camera/Location (future):** `expo-camera` / `expo-location` permissions requested **at feature time** with an explanatory prompt; captures flow through the verification service; location only at attendance events.
- **Error & loading states:** every screen defines empty/loading/error/retry states; a global error banner surfaces `request_id` so support can correlate.
- **Sensitive data:** no attendance decisions trusted from device time; device metadata sent is minimal and non-sensitive (DIY device fingerprint for abuse detection is post-MVP and kept out of event payloads that get logged).

### 7.2 Future screens (post-MVP)
Splash · Onboarding · Login · Forgot password · Home · Clock-in · Active work session · Presence verification · Face verification · Attendance history · Attendance details · Notifications · Profile · Settings. Each maps to a route in the navigation skeleton above; none are built in Task 1.

## 8. Web architecture (React + TypeScript + Vite + Tailwind)

HR / Manager / Administrator only.

### 8.1 Skeleton
- **Build:** Vite + React + TypeScript, Tailwind CSS for styling with design tokens (no magic values), Motion for purposeful micro-interaction where it aids clarity.
- **Routing:** React Router; route guards keyed to the caller's role (from `/me`).
- **State:** server state via TanStack Query (stale-while-revalidate, optimistic updates for toggles); auth/session in a minimal store; everything derived from the backend.
- **API client:** same generated OpenAPI client as mobile (or a thin web variant), same envelope/error handling, refresh-on-401.
- **Layout:** authenticated shell with sections — Dashboard, Employees, Attendance, Live Work Status, Presence Checks, Schedules, Workplaces, Reports, Analytics, Settings, Audit Logs (projected; built phase by phase).
- **Tables & queries:** cursor/limit-offset-aware table components; async report actions surface job state.
- **Accessibility:** semantic HTML, WCAG 2.1 AA target, keyboard navigable, focus management on modals.

## 9. Authentication & authorization architecture

### 9.1 Credentials & tokens
- **Passwords:** Argon2id (Django `Argon2PasswordHasher`).
- **Access token:** short-lived JWT (15–20 min) carrying `user_id`, `org_id`, `role`, `scope`. Stateless, so it is **not** revocable individually — hence short TTL.
- **Refresh token:** opaque random string, hashed at rest, stored server-side on a `RefreshToken(device, user, org, expires_at, revoked_at, replaced_by)` model. Rotation: each refresh mints a new access token **and** replaces the refresh token; reuse of a revoked token invalidates the whole family (theft detection).
- **Logout:** revokes refresh tokens for that device/family. **Session management:** list & revoke active devices (post-MVP).
- **Password reset:** email link, single-use, short expiry, invalidates active sessions; audit-logged.
- **Account status:** `User/Employee.status` gates login; disabled users are rejected at authentication and their tokens stop validating at refresh.

### 9.2 RBAC & tenant isolation
- **Model:** `OrganizationMembership(user, organization, role)` is the authorization root. Permissions are checked against `role.permissions`.
- **Enforcement — three layers:**
  1. **Tenant middleware/context:** each request resolves the caller's org from the token and sets a request-scoped tenant context.
  2. **Data layer:** all tenant-scoped models use a base manager that applies `filter(organization=<current org>)` automatically; direct queries must opt out deliberately (forbidden in normal app code). Cross-org reads are structurally impossible in normal flows.
  3. **Permission classes at the API:** endpoint-level role checks by default **deny**; only explicitly granted permissions are allowed.
- **Never trust client assertions:** `org_id` comes from the token/context, never from the request body. An employee of Org A accessing Org B's resource gets 404 (not 403) — existence is hidden cross-tenant.
- **Multi-membership (future):** a user may hold a token per org; tokens carry exactly one `org_id`; org switching mints a new token. MVP keeps one org per user to reduce attack surface.

## 10. Presence-check architecture

### 10.1 Scheduling model
- **Mechanism (recommended):** a **rolling scheduler**, not one Celery task per check. Celery **Beat** runs a periodic task (default every 30 s) that:
  1. Queries `PresenceCheck(status IN (scheduled, due), due_at <= now)` for active sessions governed by presence-check policies;
  2. Moves due checks to `awaiting_response`, dispatches the notification (push + in-app), and schedules an **expiry task** (`apply_async(eta=response_window_deadline)`) per check;
  3. An **audit sweep** task reconciles anything left in an inconsistent state (no silent loss — outcomes always converge).
- **Why rolling scan over per-check `eta` scheduling:** one periodic task is self-healing (a missed beat cannot permanently strand checks), simpler to reason about, and cheap (targeted index scan). A `Redis` lock around the scan prevents double-dispatch on multiple workers. Per-check expiry tasks provide precise deadlines without polling churn. This is decision `D-05`.
- **Randomization:** policy supports **fixed interval** or **random within a window**; randomization is decided server-side at schedule time (a draw from the configured window), never client-side.

### 10.2 Check lifecycle (state machine)

```
scheduled ──due──▶ due
                   │ scan
                   ▼
        awaiting_response  ──response + verify──▶ verified
                   │                                (or failed)
                   │ timeout (deadline)
                   ▼
                missed ──▶ escalated (if policy)
```

- **Grace period** = extra time allowed before a check counts as missed.
- **Expiration** = hard deadline for the response window.
- **Resolution:** `verified` requires a successful `VerificationAttempt` (presence, and — when enabled — liveness/face/location). `failed` = attempted but verification failed. `timeout`/`missed` = no valid response in time.
- **Escalation:** missed checks (or N consecutive misses) flag the session state for manager visibility and notify managers (policy-driven).
- **Attachments:** each check may record `VerificationAttempt`s; the audit trail stores scheduling, prompt, response, and outcome.
- **Concurrency safety:** per-check transitions are guarded by `select_for_update` + status precondition checks, so two workers cannot double-resolve a check.

## 11. Notification architecture

- **Kinds:** presence-check prompt, attendance reminders (clock-in/out), late-arrival warning, missed-check alert, admin notifications.
- **Records:** `Notification` model is the contract of record (recipient, type, channel, payload, status); every outbound notification is persisted first.
- **Channels:**
  - **Push:** Expo Push Service (routes to APNs/FCM) for MVP — one provider integration; wrapped behind a `NotificationChannel` abstraction so a direct FCM/APNs implementation can replace it. Token registered per device (`DeviceToken`).
  - **In-app inbox:** rows in `Notification` surfaced by `GET /notifications` with read/unread; deep-link targets (e.g., open the presence screen).
- **Delivery pipeline:** Celery task enqueued per notification → attempts push → records `sent/failed` → retries with backoff (configurable); in-app rows are always available even if push fails.
- **Preferences:** per-user category toggles; time-critical categories (presence prompt) default-on.
- **Never logged:** push tokens are treated as sensitive identifiers; they are not emitted to logs.

## 12. Face-verification architecture (future — design now)

### 12.1 Where processing happens — the comparison

| Option | Pros | Cons | Verdict |
| ------ | ---- | ---- | ------- |
| On-device only | No biometric data leaves the device; low latency | Match against a stored template must still live somewhere (template on device = unmanaged & duplicated); device compromise exposes enrollment; version-skew of SDKs; hard to audit centrally | Rejected as the *sole* mechanism |
| Backend (in Django core) | Simple; central audit | Couples a security-sensitive, evolving vendor SDK into the core app; heavy image compute competes with API traffic | Rejected as the *implementation* location |
| Dedicated verification service | Isolation, independent scaling, strict access control, provider-swappable, clean audit boundary | One more service to run | **Core of the recommendation** |
| Hybrid (capture/liveness on-device → encrypted template → dedicated service for matching) | Liveness at the edge (harder to spoof at source), minimal raw data leaves the device, matching isolated & auditable centrally | Requires careful key/transport design | **Recommended** |

**Recommendation (D-06):** **hybrid**. The camera capture and **liveness challenge** run on-device (anti-spoofing closest to the source). Only a **signed, encrypted, format-specified template** (not the raw image) is sent to a **dedicated Face Verification Service** — a separate, tightly access-controlled service (own network segment, own ingress) that performs 1:1 matching against enrolled templates and returns only a verdict (match/no-match + confidence band) to the attendance domain. The Django backend never handles raw biometric images and never stores them.

- **Enrollment:** Admin initiates → employee consents (consent record with policy + timestamp) → device captures under quality checks → service extracts template → template encrypted at rest, versioned, linked to `FaceEnrollment` (status `pending_approval → active` after admin approval) → raw capture deleted immediately.
- **Storage & privacy:** templates encrypted (envelope encryption, key separate from tenant DB), isolated table/DB, strict IAM, retention + expiry enforcement, end-to-end deletion on consent withdrawal (delete template + verification history references; audit event retained without payload).
- **Provider boundary:** the service wraps a selected provider/SDK (e.g., an on-prem library or cloud API) behind a contract (`Verify(template_id, challenge) → verdict`); the choice is swap-in/out without domain changes.
- **Replay/liveness:** liveness challenge is per-attempt (fresh nonce), time-bounded, single-use; verification attempts are rate-limited and carry an audit + `VerificationAttempt` row. Device attestation countermeasures are strengthened post-MVP.

## 13. Location architecture (future — design now)

- **Event-based only.** `expo-location` permission requested at the moment of the attendance event (with explanation). One reading (lat + lng + accuracy + timestamp) is attached to the event.
- **Server-side decision:** the `geofence` check (distance to `Workplace` centroid ≤ allowed radius) runs in the attendance service against **server time** — the client cannot assert "inside." Result stored on the event/attempt.
- **Policy modes:** `not_required` / `warn_only` / `required`. In `required` mode a failed or missing location reading blocks the action and is flagged for review; in `warn_only` it records a warning.
- **Privacy:** no background/continuous tracking, no history of locations outside attendance events; location rows are subject to retention policy like other event data.
- **Integrity:** a spoofed coordinate is treated as an attack signal (audit, anomaly flag) — device attestation hardening is a post-MVP anti-fraud layer.

## 14. Redis / Celery architecture

- **Redis uses:** (1) Celery broker + result backend, (2) cache (organizations, policies, permission trees — with explicit invalidation), (3) DRF throttling counters, (4) distributed locks for the presence-scheduler scan and clock-in idempotency short-circuit.
- **Celery queues:** `default` (notifications, emails, reports) and `presence` (scheduler scan, expiry tasks) — configured concurrency so presence deadlines aren't starved by report runs.
- **Tasks** (projected): presence scan (Beat), presence expiry, notification send/retry, attendance result recompute, report generation, biometric cleanup/retention sweep (future), session/family revocation sweep.
- **Failure semantics:** tasks are idempotent and retried with backoff; presence outcomes converge via reconciliation sweep (see § 10) even if a worker dies.

## 15. Security boundaries

| Boundary | Control |
| -------- | ------- |
| **Network/transport** | TLS everywhere; public surface is HTTPS only. |
| **API access** | Bearer JWT; short TTL; RBAC on every endpoint; deny-by-default. |
| **Tenant** | Tenant context + forced-org data layer + existence hiding (404) cross-tenant — the *how* of "Org A can never see Org B." |
| **Attendance integrity** | Server-time authority; idempotency; one-active-session constraint; immutable event ledger; verification attached to attempts. |
| **Authentication** | Argon2id; rotating revocable refresh tokens; reuse detection; rate limited auth endpoints; account status gating. |
| **Biometrics (future)** | Isolated service; encrypted templates only; no raw image storage; consent + retention + deletion; per-attempt liveness nonces; separate access control. |
| **Location (future)** | Event-based only; server-side geofence; no continuous collection. |
| **Admin privilege** | RBAC max-permission scoping; sensitive admin actions audited; no cross-org admin escalation. |
| **Logs** | Never log passwords, tokens, refresh secrets, push tokens, biometric payloads, or raw location beyond what's required; PII minimized. |
| **Dependencies/infra** | Secrets from env/secret manager only; dependency audit in CI; least-privilege service accounts. |

## 16. Deployment architecture

Full detail lands with the deployment phase. Agreed target:

- **Backend:** Django + gunicorn behind a TLS-terminating reverse proxy; PostgreSQL (managed or container); Redis (managed or container); Celery worker + Beat run as separate processes. Lightweight containers; migrations run as a separate step before new code rolls out.
- **Web:** Vite production build → static hosting/CDN (or served by the same reverse proxy for MVP); immutable asset cache.
- **Mobile:** Expo application builds via **EAS**; distribution via stores (and TestFlight/internal track for the portfolio); API base URL injected per environment; app signing via EAS/Keystore, never in the repo.
- **Configuration & secrets:** `.env`-driven, secrets from the host's secret manager in prod; **nothing secret in the repo**.
- **CI/CD (GitHub Actions):** lint (ruff, eslint/tsc) → tests (pytest, vitest/jest) → security scan (bandit, `pip-audit`, `npm audit`) → build artifacts → deploy on tag/merge per branch policy. Migrations gated and reviewed.
- **Backups:** PostgreSQL automated backups with point-in-time recovery; Redis is a cache (loss acceptable except broker durability mitigations); backup restore tested on a schedule.
- **Monitoring:** health endpoints (`/healthz`, `/readyz`) checked by the platform; structured logs to a central sink; Sentry for errors; Django-Prometheus metrics (request latency, DB pool, Celery queue depth); Flower (or a log/counter-based) view of workers; audit log as its own append-only sink.

## 17. Data flow (attendance example)

```
Mobile: user taps "Clock in"
  → POST /api/v1/attendance/work-sessions/start  (Idempotency-Key)
  → API layer: authenticate → tenant context → RBAC (employee) → throttle
  → ClockInService (domain):
       - find active session for employee (constraint guarantees ≤1)
       - if exists → return existing (idempotent), 200/409 semantics
       - else create WorkSession(status=active)  SAVEPOINT/transaction
              + AttendanceEvent(CLOCK_IN, server_ts, source=mobile)
       - apply policy: required verification? schedule presence checks?
       - write AuditLog(clock_in)
  → commit → return session + events
  → Celery (if policy): enqueue first presence check scheduling
  → Redis: short-circuit cache cleared for this employee's "current" view
Web admin: pull Live Work Status → GET /api/v1/employees/status
  → tenant filter → cached briefly → event ledger summarized
```

## 18. Observability — what is logged vs never

**Logged (structured JSON, with `request_id` and tenant):** API access (method, path, status, latency), auth events (login attempt result, token refresh, revocation), attendance actions (clock-in/out with source), presence outcomes, policy/role/admin changes, job lifecycle (enqueued/succeeded/retried/failed), security events (throttle hits, authz denials, suspicious patterns), audit log entries with **snapshot deltas** (not raw payloads).
**Never logged:** passwords or password hashes, access tokens, refresh tokens, reset links, push/notification tokens, biometric templates or face data of any kind, deliberate raw biometric or liveness payloads, raw location beyond the minimal event attributes, personal data not required for the log's purpose.

## 19. Consistency of decisions across documents

| Topic | Decided here / in DECISIONS.md |
| ----- | ------------------------------ |
| Monorepo | D-01 |
| Modular monolith backend | D-02 |
| Django+DRF+Postgres+Redis+Celery | D-03 |
| JWT + rotating server-stored refresh tokens | D-04 |
| Rolling-scheduler presence engine | D-05 |
| Hybrid face verification with dedicated service | D-06 |
| UTC storage + org timezone; session-day from start in org tz | D-07 |
| Cursor pagination for event streams | D-08 |
| Provider abstractions (notifications, biometrics) | D-09 |
| Server-authoritative time; device time only metadata | D-10 |