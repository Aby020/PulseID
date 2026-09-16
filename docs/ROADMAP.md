# PulseID — Roadmap

Companion documents: `PRODUCT_REQUIREMENTS.md` (what), `ARCHITECTURE.md` (how), `DECISIONS.md` (why), `PROJECT_STRUCTURE.md` (layout), `RISKS.md` (threats + mitigations).

Phases 0–14. Each phase ends with a reviewable checkpoint; **one task at a time, never auto-advancing**.

---

## Tiers

| Tier | Meaning | Phases |
| ---- | ------- | ------ |
| **MVP** | A usable, secure attendance platform: employees clock in/out on mobile, HR manages them and views attendance on web, backend + auth + data + observability are solid. **No face/liveness/location/push/presence-check yet.** | 0–6 (and the MVP slice of 12–14) |
| **Post-MVP** | Verified presence becomes real: presence checks, push notifications, event-based location, reports/analytics. | 7, 11, 12 |
| **Advanced** | Biometric identity: face verification + liveness. | 8, 9, 10, 13 |

One phase may deliver a *subset* (e.g., Phase 5 delivers a working shell with the energy of login + clock in/out; the rest of the mobile screens follow within the same phase).

---

## Phase 0 — Planning ✅ (this task)
- Write `PRODUCT_REQUIREMENTS.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `DECISIONS.md`, `PROJECT_STRUCTURE.md`, `RISKS.md`.
- Agree on MVP scope and the decision records (D-01…D-10).
- **Exit criteria:** documents consistent, no contradictions, decisions recorded, architecture supports the full roadmap without rewrite.

## Phase 1 — Foundation
- Initialize **PulseID as its own independent git repository** (out of the AbiLabs meta-repo), branch policy `feature/<name>` off `main`, Conventional Commits.
- Create the monorepo skeleton per `PROJECT_STRUCTURE.md`: `backend/`, `web/`, `mobile/`, `docs/`, `infra/`, `scripts/`, root `README.md`, `.github/workflows/ci.yml` (lint + test green on PR), `.gitignore`, `Makefile`/task runner.
- Root `README.md` (project summary + how to run).
- **Exit criteria:** repo is independent; CI runs lint+tests on a trivial scaffold; contributors can bootstrap.

## Phase 2 — Backend (core + data)
- Django project `backend/`, apps per `ARCHITECTURE.md` §3.1 (`accounts`, `organizations`, `employees`, `workplaces`, `schedules`, `attendance`, `presence`, `biometrics`, `notifications`, `audit`, `analytics`, `core`).
- Base infra: `core` tenant mixins, timezone utils, error envelope, pagination, permission classes; `USE_TZ=True`.
- **Data model (Part A — MVP entities):** `Organization`, `User` (custom), `Role`, `OrganizationMembership`, `Employee`, `Workplace` (schema-only for MVP), `WorkSchedule`, `AttendancePolicy`, `WorkSession`, `AttendanceEvent`, `AuditLog`.
- Migrations with correctness-reviewed constraints (one-active-session constraint, indexes per `ARCHITECTURE.md` §4).
- **Exit criteria:** migrations clean; models + constraints tested; tenant isolation forced in the data layer.

## Phase 3 — Backend: authentication & authorization
- Argon2id password hashing; login/refresh/logout; rotating server-stored refresh tokens (D-04); account status; password reset flow.
- `/api/v1/auth/*`, `/api/v1/me`; RBAC permission classes; tenant middleware; existence hiding cross-tenant.
- Auth + authz + multi-tenant test suites (see `standards/testing`).
- **Exit criteria:** auth tests green; cross-tenant access proven impossible in tests; rate limiting on auth endpoints.

## Phase 4 — Backend: attendance engine (server-authoritative clock)
- `ClockInService` / `ClockOutService`: one-active-session guarantee + idempotency, immutable `AttendanceEvent` ledger, derived duration/late/early computed from policy.
- Work-session API: start/end/current; events cursor-paginated.
- Attendance policy application, org-timezone day boundaries.
- Unit + API + concurrency tests (two concurrent clock-ins → one session).
- **Exit criteria:** clock in/out verified; idempotency and concurrency tested; server timestamp authority proven.

## Phase 5 — Admin web app (MVP)
- Vite + React + TS + Tailwind scaffold with design tokens; OpenAPI-generated client; route guards by role.
- Sections: **Dashboard, Employees, Attendance (history + status), Schedules, Policies, Workplaces (schema), Settings**; live work status view.
- Component + critical workflow tests; WCAG baseline.
- **Exit criteria:** HR can manage employees, view attendance, run basic reports; role-gated navigation.

## Phase 6 — Mobile app (MVP)
- Expo + React Native + TS; navigation skeleton (auth switch + tabs); secure token storage (Keychain/Keystore); React Query + typed API client.
- Screens: Splash, Login, Home (with active session + live duration), Clock-in, Active work session, Clock out, Attendance history/details, Profile.
- Clock in/out requires connectivity (server timestamp authoritative); offline messaging for attendance actions.
- Component + auth + clock-in/out workflow tests.
- **Exit criteria:** a tester can sign in, clock in, watch duration, respond, clock out, view history — all against the real backend.

## Phase 7 — Presence-check engine (Post-MVP)
- `PresenceCheck` state machine + rolling scheduler (Beat scan every 30 s) + per-check expiry tasks (D-05); Redis scan lock; reconciliation sweep.
- Policies: fixed interval / random-in-window, response window, grace, escalation.
- Employee respond flow (mobile) + manager visibility (web); missed/escalated flows; audit trail.
- Presence-check + scheduler + reliability tests (no silent loss).
- **Exit criteria:** checks schedule, prompt, verify, expire, and escalate correctly under load/dead-worker simulation.

## Phase 8 — Face verification (Advanced)
- `FaceEnrollment` + consent records; enrollment workflow (admin-initiated, employee-approved, quality capture → template); provider behind the contract (D-06).
- Verification at policy-gated actions; `VerificationAttempt` integration; enrollment approval status.
- Encrypted template storage, retention/expiry job; end-to-end deletion path; audit without payloads.
- **Exit criteria:** enroll → verify → reject-non-match → withdraw-consent-deletes → audit intact, all tested.

## Phase 9 — Liveness (Advanced)
- Per-attempt liveness challenge (fresh nonce, time-bounded, single-use) at the device; spoofing tests (photo/video/mask) in the evaluation harness.
- Tighten verification attempt rate limits and anti-replay posture.
- **Exit criteria:** repeat-playback/replay attacks fail verification; false-accept test set tracked.

## Phase 10 — Location verification (Advanced/Post-MVP boundary)
- Event-based coordinate capture + server-side geofence check against `Workplace` radius; policy modes (not_required / warn_only / required).
- Location on clock-in/out/presence-check when policy requires; no continuous tracking.
- **Exit criteria:** inside/outside decisions are server-computed; privacy guarantees hold; spoof signals audited.

## Phase 11 — Notifications & push (Post-MVP)
- `Notification` record + channel abstraction + Celery delivery with retries; in-app inbox; device token registry via Expo Push Service.
- Presence-prompt, clock-in/out reminders, late-arrival warning, missed-check alert, admin notices.
- **Exit criteria:** end-to-end push delivered, inbox updates, retries/backoff and failure states verified.

## Phase 12 — Reports, analytics & testing hardening
- Async report generation (Celery) for attendance; analytics: planned vs actual, late arrivals, early departures, missed checks, overtime.
- Deepen suites: end-to-end workflow tests (mobile+web+backend) for the important employee journeys; coverage ≥ 80% on new code; determinism.
- **Exit criteria:** report jobs correct and checked; E2E suite covers clock-in/out, presence, and admin review.

## Phase 13 — Security hardening
- Full security review per `standards/security`: OWASP pass, dependency audit (pip-audit, npm audit), secrets scanning, rate-limit tuning, brute-force/reset-abuse testing, RBAC penetration tests, session/token-theft scenarios.
- **Exit criteria:** security gate passes; findings resolved or accepted with an ADR.

## Phase 14 — Deployment
- Production architecture per `ARCHITECTURE.md` §16: gunicorn + TLS, Postgres + backups (restore-tested), Redis, Celery worker/beat, web static hosting, EAS-distributed mobile.
- Env/secrets via secret manager; GitHub Actions deploy pipeline with gated migrations; monitoring (health checks, Sentry, metrics, worker monitoring) live.
- **Exit criteria:** deployed to a real environment; health checks green; backup restore drill passed; runbooks written.

---

## MVP boundary (explicit)

**In MVP:** Phase 0–6, plus the MVP-critical slice of 12–14 (essential tests/CI in 1 and 12, baseline security in 13 where cheap, dev-only run in 14).
**Not MVP:** presence checks (7), push (11), location (10), face (8), liveness (9), advanced reports/analytics.
The architecture (D-01…D-10) is chosen so 7–11 lay on without restructuring.

## Sequencing constraints
- Phase 7 (presence) needs the attendance engine (4) and async infra (1–2) ready.
- Phase 8–9 (face/liveness) need the `biometrics` provider boundary in place from Phase 2 and need 4 (verification attachments at attendance actions).
- Phase 11 needs the `Notification` record (2) and mobile push plumbing (6).
- Phase 13 is a gate before 14.