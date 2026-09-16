# PulseID — Architecture Decisions

Every significant architectural decision with: the **Decision**, the **Options considered**, a **Recommendation**, **Why** (reason), and **Trade-offs**. IDs are cross-referenced in `ARCHITECTURE.md` and `ROADMAP.md`.

> Once a decision is finalized in Task 1, do not silently change it. Revisiting a decision requires a new ADR-style note with rationale.

---

## D-01 — Repository structure: Monorepo vs multi-repo

**Decision:** How should the backend, web, mobile, and infrastructure code be organized?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Monorepo (single git repo) | `PulseID/backend/`, `PulseID/web/`, `PulseID/mobile/`, `PulseID/infra/`, `PulseID/docs/` in one repo |
| Multi-repo (separate repos) | `PulseID-backend`, `PulseID-web`, `PulseID-mobile` each with their own git remote |
| Poly-repo + workspace (Bazel/Nx) | Monorepo-shaped but using a build-system workspace to simulate per-component repos |

**Recommendation:** **Monorepo.**

**Why:**

1. **API contract sync.** Backend and both clients share an OpenAPI contract; a monorepo makes it possible to change an API field and update clients in one atomic commit.
2. **Simpler security and CI for a small/medium team.** One CI pipeline, one code-review workflow, one set of secrets to rotate.
3. **History is unified.** Cross-cutting features (e.g., adding a presence-check field) are reviewed as one change; `git blame` tells the full story.
4. **No build-system overhead.** Poly-repo/Bazel adds tooling weight that doesn't pay off at this product's team size.
5. **Consistent with AbiLabs convention** (each project at the workspace root is one repo) while keeping internal boundaries by convention + CI enforcement, not by repo separation.

**Trade-offs:**

- Upside: atomic commits, easier cross-layer refactoring, single CI authn, easier local dev for cross-cutting work.
- Downside: in a larger org, one repo can create contention; mitigated here by clear internal directory ownership and fast CI times.
- Mitigation if the product scales: backend can be broken out later (the `backend/` directory boundary exists); clients' dependency graphs are lightweight (API contract only).

---

## D-02 — Backend shape: Modular monolith vs microservices

**Decision:** Should PulseID’s backend be a single deployable application or split into services at this stage?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Modular Django monolith | One Django project, several Django apps mapping to domain areas; one deployment |
| Microservices | Separate services per domain (attendance service, presence service, etc.) |
| Service-boundary-in-monolith | Monolith now; clear internal interfaces so services can be extracted later without rewrites |

**Recommendation:** **Modular Django monolith with explicit service boundaries in code.**

**Why:**

1. The team is small; the overhead of multi-service infra and distributed transactions is not justified.
2. The tenant-boundary is simpler to enforce with a single database and a single context-setting middleware.
3. The domain rules are tightly coupled (presence checks are scheduled against active work sessions); splitting early introduces unnecessary network hops and failure modes.
4. The module boundaries (`ARCHITECTURE.md` §3.1) are clean enough that extraction is possible later (e.g., presence engine, biometric provider).

**Trade-offs:**

- Upside: simple deployment, a single transaction boundary, easy cross-domain consistency, straightforward debugging.
- Downside: at extreme scale the monolith becomes the bottleneck; mitigated by clear module boundaries so extraction is incremental and later.
- Mitigation if needed: presence engine and biometric verification are explicit extraction candidates; interfaces already assume the split is possible.

---

## D-03 — Backend technology choices

**Decision:** What should the backend stack be and why?

**Options considered (and rejections):**

| Technology | Decision | Why |
| ---------- | -------- | ---- |
| Framework: Django + DRF | ✅ Selected | Strong ORM, mature auth/admin/CSRF/ORM-integrity-mechanisms, excellent multi-tenant query patterns; mature DRF for a well-defined REST API; Django's migration framework meets the integrity and auditability requirements; ecosystem covers off-the-shelf: JWT (simplejwt), throttle/permission/caching integrations. |
| Database: PostgreSQL | ✅ Selected | Strong constraints/indexes; JSON (JsonField) for flexible payloads; timezone-aware; mature Django; row-level locking (`select_for_update` for clock-in); ACID for integrity. |
| Cache/Broker: Redis | ✅ Selected | Sub-millisecond cache + Celery broker + throttle counters; cheap, multi-purpose for this scale; no dedicated MQ needed yet. |
| Async jobs: Celery + Beat | ✅ Selected | Mature; supports `eta` and periodic; worker pool segregation possible; has well-understood retry/failure semantics needed for the presence scan + notification reliability. |
| WSGI: gunicorn | ✅ Selected | Standard for Django in production; worker model; never use `runserver`. |
| Framework: Flask / FastAPI | ❌ Rejected | Less built-in structure for the kinds of models, migrations, and admin features PulseID benefits from. |
| Database: MySQL | ❌ Rejected | MySQL is viable but lacks the same strengths in advanced constraint/index types and JSON support; no compelling advantage here. |
| Message queue: Kafka | ❌ Rejected | Volume and complexity do not justify it; async job + Beat are sufficient. |
| Full-text/search: Elasticsearch | ❌ Rejected | Queries are structured; Postgres `LIKE`/`ILIKE` and indexes are adequate. A search engine is a post-MVP option if query patterns grow complex. |

**Trade-offs:**

- Upside: mature, well-understood stack; reliable integrity mechanisms; huge hiring/resource ecosystem; scales well for the initial years.
- Downside: Django is synchronous by default (async views are improving but not the default story); mitigated by moving expensive work into Celery and caching aggressively.
- Performance: p95 < 300 ms is met via query optimization and caching; async avoids blocking.

---

## D-04 — Authentication: session/JWT/refresh model

**Decision:** How do mobile + web authenticate and how are tokens managed?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Django sessions (cookies) | Standard Django auth |
| JWT access + rotating server-stored refresh tokens | Access = JWT (stateless, short TTL), refresh = opaque token on a `RefreshToken` model |
| Third-party auth provider (Firebase Auth, Clerk) | Offload auth entirely |

**Recommendation:** **JWT access + rotating server-stored refresh tokens (opaque, hashed at rest).**

**Why:**

1. The mobile app cannot use cookies/sessions the same way; JWTs provide a universal bearer scheme for web + mobile without writing a custom session adapter.
2. Access tokens are stateless and fast to validate (no DB lookup per request); refresh tokens being server-stored gives revocability and token-theft detection (reuse invalidates the family).
3. No third-party auth vendor: multi-tenant control and audit are easier in-repo; no vendor lock-in; biometric-related auth decisions in the future stay under our control.

**Trade-offs:**

- Upside: revocable refresh; stateless fast access; portable across mobile/web; theft detection via rotation.
- Downside: short-lived access tokens require refresh logic on clients; mitigated by React Query/expo client helpers; short TTL is a design benefit (less exposure on theft).
- Downside: refresh token is a DB lookup (for revocation); it is infrequent (only on refresh, not every request) and cachable per-user.

---

## D-05 — Presence-check scheduling: rolling scan vs per-check eta tasks

**Decision:** How do scheduled presence checks get due and resolved on time?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Per-check `apply_async(eta=due_at)` | One Celery task per check scheduled for its exact due time |
| Rolling scheduler (Beat task every Ns) | Periodic task queries for due checks |
| External scheduler (cron + DB) | OS cron or a dedicated scheduling service reading the DB |

**Recommendation:** **Rolling scheduler with per-check expiry `apply_async`.**

**Why:**

1. A rolling scan (Beat runs every ~30 s; the scan queries `status IN (scheduled, due) AND due_at <= now + buffer`) handles volume efficiently (index scan) and is simple.
2. Per-check expiry tasks (`apply_async(eta=response_window_deadline)`) provide precise deadline handling without constantly polling for expired responses.
3. **Self-healing:** if a worker misses a beat (worker crash), the next beat picks up all due checks — no checks are silently lost, which is a critical reliability property.
4. A Redis lock around the scan prevents double-dispatch on multiple workers.
5. An explicit reconciliation sweep resolves any stray checks that fell through the cracks (the "no silent loss" guarantee).

**Trade-offs:**

- Upside: reliable (self-healing), simple to reason about, cheap at realistic volume.
- Downside: there is a bounded latency (≤ the beat interval) before a check becomes due and is dispatched; this is acceptable and even desirable (a few seconds of jitter is normal for notification delivery).
- Alternative analysis: per-check `eta` is very precise but a missed worker loses the task; external scheduler adds another moving part with little benefit here.

---

## D-06 — Face verification: where processing happens

**Decision:** How should face enrollment, liveness detection, and face matching be implemented in the architecture?

*(Full analysis in `ARCHITECTURE.md` §12.)*

**Options considered:**

| Option | Description |
| ------ | ----------- |
| On-device only | Liveness + matching all on device; template stored locally |
| Backend (in Django) | Matching done in the backend application |
| Dedicated verification service | Isolated service boundary handling template storage + matching |
| Hybrid | Liveness on device, encrypted template sent to dedicated service |

**Recommendation:** **Hybrid (on-device capture/liveness, dedicated service for matching + template management).**

**Why:**

1. Liveness is most effective at the edge (harder to spoof at the source); matches run centrally where templates live and can be controlled, audited, and deleted.
2. The dedicated service isolates a fast-moving vendor/algorithm from the core app; swapping the matching engine becomes a service boundary change, not a domain rewrite.
3. The backend never sees raw images, minimizing blast radius and privacy exposure.
4. Encrypted templates, strict access control, explicit retention + deletion, and audit-without-payloads satisfy privacy requirements without overloading the main app.

**Trade-offs:**

- Upside: strong anti-spoofing, isolated audit, swappable algorithm, minimal data exposure.
- Downside: one more service to deploy; mitigated by containerization and a simple contract (`verify(template_id, challenge) → verdict`).
- Key risk: trust the device for template quality; mitigated by enrollment quality checks, attestation, and post-MVP anti-replay hardening.

---

## D-07 — Time & attendance day boundaries

**Decision:** When an employee clocks in on Monday night and clocks out on Tuesday morning (shift that spans midnight), which day does the session belong to?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Server date of clock-in | Attendance day = clock-in date (org tz) |
| Server date of clock-out | Attendance day = clock-out date (org tz) |
| Schedule start date | Attendance day = the date of the schedule window the clock-in aligns to |

**Recommendation:** **Server date of clock-in (in org timezone).**

**Why:**

1. Most real shifts start and end on the same calendar day; multi-day shifts are rare and the policy can override them if they arise.
2. For normal shifts, associating the session with clock-in day gives the expected report behavior (Monday's roster shows Monday's attendance).
3. It is the simplest rule to explain, audit, and compute; schedule-based assignment adds complexity (what if the employee is unscheduled, or early/late?).

**Trade-offs:**

- Upside: simple, predictable, auditable; works for the common case.
- Downside: a session whose clock-in is 11:59 PM belongs to the next day's shift, which is slightly non-intuitive for the employee; mitigated by showing both the org-timezone clock-in time and the "attendance day" in the UI.
- When very rare true multi-day shifts matter, policy can assign attendance-day rules per schedule.

---

## D-08 — Pagination: offset vs cursor for event/audit streams

**Decision:** What pagination style should be used for time-ordered, append-heavy event streams?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| LimitOffsetPagination | Standard `?limit=N&offset=M` |
| CursorPagination | Opaque cursor pointing to the next row; stable under new inserts |

**Recommendation:** **Cursor pagination for event/audit streams; LimitOffset for standard lists.**

**Why:**

1. Append-heavy streams (attendance events, audit logs) grow at the end; offset pagination is unstable under concurrent inserts (rows shift, duplicates/skips appear on page navigation).
2. Cursor pagination is stable and usually more efficient (avoids a large OFFSET scan).
3. DRF’s `CursorPagination` is built-in and well-suited.

**Trade-offs:**

- Upside: stable pages under concurrent writes; performant; built-in.
- Downside: cannot jump to an arbitrary page number (acceptable for streams where users scroll forward in time); total count is omitted from the cursor response.
- Standard lists (employee list, workplace list) stay LimitOffset since they are not append-heavy and users may want to jump pages.

---

## D-09 — Notification and biometric providers: abstraction boundary

**Decision:** How tightly should the backend couple to the push provider or face-verification SDK?

**Recommendation:** **Adapter pattern — an explicit interface per provider, implementations in separate modules.**

**Why:**

1. The product needs to evolve (Expo Push → FCM/APNs directly; face provider from A → B); coupling makes this a domain rewrite.
2. A simple adapter interface (e.g., `NotificationChannel.send(to, payload) → result`) allows swapping implementations behind tests without touching attendance/presence domain logic.
3. Biometrics have stricter isolation requirements; the adapter boundary naturally becomes a process boundary later (per D-06).

**Trade-offs:**

- Upside: clean upgrade path, testability (mock at the interface), clear responsibility.
- Downside: slight indirection; mitigated by keeping adapters thin and well-tested.
- No over-engineering: the interfaces are not elaborate; they reflect a single core method.

---

## D-10 — Server-authoritative time

**Decision:** Who "owns" the clock for attendance: the mobile device or the server?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Server-only | Server records `datetime.now(tz=UTC)` on every clock action; client sends optional `device_reported_at` for debugging only |
| Client-reported time trusted | Client sends the attendance timestamp; server stores it |

**Recommendation:** **Server-only authoritative time. Device time is captured as `device_reported_at` metadata only and never influences attendance calculations.**

**Why:**

1. Device clocks are unreliable (manual manipulation, timezone drift, NTP drift); trusting them creates opportunities for time-based attendance fraud.
2. The server is a known, secured, auditable environment; its time is under your control (NTP-managed in production).
3. Capturing `device_reported_at` separately still allows detecting and auditing suspicious anomalies (huge server-device time gap).

**Trade-offs:**

- Upside: auditability, integrity, no device-time fraud; simple computation.
- Downside: if network latency is huge, the server timestamp differs from the moment the user taps "clock in"; for attendance purposes, network order-of-seconds is acceptable and arguably more honest (what the server can prove). For ultra-precise response timing, client-reported time could inform a tolerance band post-MVP.
- Mitigation: all latency-sensitive explanations (the UI can say "recorded at HH:MM:SS server time") are transparent to the user.

---

## D-11 — Refresh token theft detection (rotation family)

**Decision:** When a refresh token is reused after being replaced, what happens?

**Options considered:**

| Option | Description |
| ------ | ----------- |
| Ignore (no theft detection) | Allow reuse of old tokens until they expire |
| Detect and revoke family | Reuse triggers revocation of all tokens in that rotation lineage |
| Detect and alert only | Reuse is logged but tokens are not revoked |

**Recommendation:** **Detect and revoke family (per D-04).**

**Why:**

1. Token rotation creates a lineage: refresh token T1 → T2 (replaced T1); if T1 is used again, an attacker likely has T1.
2. Revoking the whole family protects the legitimate user immediately; alerting is a secondary action.
3. This is a well-established security pattern with minimal implementation cost in the `RefreshToken` model.

**Trade-offs:**

- Upside: strong theft detection; limits damage window.
- Downside: legitimate use of a stale token (e.g., two devices logged in without shared storage) results in logout; acceptable for an attendance system where one active session is the design anyway.