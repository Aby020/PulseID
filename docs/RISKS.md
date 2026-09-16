# PulseID — Risks

Each risk: **what**, **why it matters**, **likelihood**, **impact**, and **mitigation**. Cross-references to decisions in `DECISIONS.md` and architecture sections in `ARCHITECTURE.md`.

Impact scale: **H** = could compromise integrity, privacy, or auditability; **M** = degrades reliability, performance, or usability; **L** = minor inconvenience or technical debt.

---

## 1. Technical risks

### T-01 — Concurrent clock-in race conditions

**What:** Two simultaneous clock-in requests from the same device (network retry) or two devices create two active `WorkSession` rows, breaking the one-active-session invariant.

**Why it matters:** Duplicate sessions corrupt the attendance ledger and undermine audit trust.

**Likelihood:** M (network retries and app lifecycle events make this plausible).

**Impact:** H.

**Mitigation:**

- Unique partial DB constraint: only one active session per employee at the DB level (`ARCHITECTURE.md` §4.3).
- `select_for_update` inside the clock-in transaction to serialize concurrent requests.
- Idempotency key at the API: repeat requests within the retention window return the same session.
- Tests explicitly exercise concurrent clock-in under race conditions.

---

### T-02 — Presence scheduler silently loses checks

**What:** A Celery worker dies between picking up due checks and dispatching notifications; checks that were transitioned from `due` → `awaiting_response` may not get dispatched or resolved.

**Why it matters:** The presence-check guarantee is "no silent loss"; a missed notification damages audit trust and manager confidence.

**Likelihood:** L (workers dying mid-task is uncommon but possible in production).

**Impact:** H.

**Mitigation:**

- Rolling scheduler scans for stale `awaiting_response` checks past their expected dispatch time and re-dispatches (`ARCHITECTURE.md` §10).
- Reconciliation sweep catches any orphaned state and forces resolution.
- Redis lock prevents double-dispatch; if the lock dies with the worker, the next beat acquires it.
- Every check outcome is always computed; the system converges to a terminal state even after failures.

---

### T-03 — Clock skew between server and Celery workers

**What:** If the Celery worker's system time is wrong (NTP failure), `due_at` comparisons in the presence scan produce checks that fire too early or too late.

**Why it matters:** Presence checks either fire late (user sees no prompt) or early (premature alerts), degrading both reliability and UX.

**Likelihood:** L (NTP failure is rare; container/VM clocks are usually reliable).

**Impact:** M.

**Mitigation:**

- All attendance time comparisons use the server's own UTC clock (`ARCHITECTURE.md` §5); workers and scheduler must share accurate time (NTP in production, documented infra requirement).
- Post-MVP: add a health check that alerts if the worker's perceived time drifts more than a configurable threshold from a known time source.

---

### T-04 — Timezone handling errors in attendance day computation

**What:** Attendance "day" is determined in the organization's timezone (`DECISIONS.md` D-07); a bug in tz conversion or a missing tz on the org causes sessions to be attributed to the wrong day, breaking reports and history.

**Why it matters:** Wrong day attribution affects every attendance summary, report, and payroll-related view.

**Likelihood:** M (timezone bugs are notoriously easy to introduce; edge cases around DST changes are common).

**Impact:** H.

**Mitigation:**

- `Organization.timezone` is required (not nullable); validated as a valid IANA tz at creation.
- All attendance-day functions use `zoneinfo.ZoneInfo` (Python 3.9+) and are unit-tested with DST edge cases.
- Unit tests explicitly exercise sessions that span midnight and DST transitions.
- Backend timezone utilities live in `core/timezone.py` — no ad-hoc conversions elsewhere.

---

### T-05 — Rollback or failure of a state transition in a transaction

**What:** A clock-in creates a `WorkSession` and `AttendanceEvent` in one transaction; if the transaction fails after the session is written, the state is inconsistent.

**Why it matters:** Partial writes create a session without an event (or vice versa), breaking the invariant that the ledger is the source of truth.

**Likelihood:** L (Django transactions are well-understood; failures are rare).

**Impact:** H.

**Mitigation:**

- Every clock-in/out is a single atomic transaction; `WorkSession` and `AttendanceEvent` are written in the same commit.
- DB constraints (one-active-session) act as the final safety net.
- If the transaction fails, the API returns an error; the user retries; no partial state leaks.
- Migration and periodic health checks detect orphaned sessions without events and flag them for manual resolution.

---

## 2. Security risks

### S-01 — Refresh token theft and session hijacking

**What:** An attacker obtains a refresh token (via device theft, client-side injection, or log exposure) and uses it to mint new access tokens.

**Why it matters:** The attacker can impersonate the employee, performing attendance actions under their identity.

**Likelihood:** M (device theft is realistic; token exfiltration via logs or insecure storage is preventable but possible).

**Impact:** H.

**Mitigation:**

- Token rotation with family-based revocation (`DECISIONS.md` D-11): reuse of a revoked token invalidates the entire family.
- Refresh tokens stored hashed at rest; never in plaintext logs.
- Short-lived access tokens (15–20 min) limit damage window even if stolen.
- Logout revokes the refresh token family server-side.
- Post-MVP: device fingerprinting to detect suspicious new-device token usage; MFA option.

---

### S-02 — Cross-tenant data leakage

**What:** A bug in the query layer or middleware allows an employee of Org A to see Org B's attendance data.

**Why it matters:** This is the most damaging possible data breach for a multi-tenant system; regulatory and trust implications are severe.

**Likelihood:** L (if enforced at three layers as designed), but individual bugs are always possible.

**Impact:** H (catastrophic).

**Mitigation:**

- Three-layer enforcement: (1) tenant middleware/context from JWT, (2) base model manager forces org filter, (3) API permission class denies cross-tenant (returns 404, not 403, to avoid existence leaking).
- `org_id` never taken from the request body; always from the authenticated context.
- Comprehensive multi-tenant test suite: every tenant-scoped endpoint is tested with a wrong-tenant token; the test asserts 404.
- No raw SQL; Django ORM only (prevents accidental cross-tenant queries).
- Periodic security review (Phase 13) includes targeted cross-tenant access tests.

---

### S-03 — Rate limiting bypass on attendance endpoints

**What:** An attacker floods clock-in/out or presence-response endpoints, disrupting service or brute-forcing idempotency keys.

**Why it matters:** Disruption of attendance recording affects all employees; brute-forcing could cause denial-of-service or unexpected side effects.

**Likelihood:** M (automated abuse is a standard threat; rate limits are a known mitigation).

**Impact:** M.

**Mitigation:**

- Redis-backed DRF throttles with tighter limits on `auth/*` and `attendance/*` (`ARCHITECTURE.md` §6.3).
- Idempotency keys are UUIDs (unpredictable); duplicates within a window return the existing result without side effects.
- App-level rate limiting (not just IP) to prevent authenticated abuse; unauthenticated endpoints also rate-limited.
- Post-MVP: WAF or bot-mitigation layer in front of the API gateway.

---

### S-04 — Weak or compromised password hashing

**What:** Using an outdated or misconfigured password hashing algorithm makes offline brute-force feasible if the DB is leaked.

**Why it matters:** Attendance systems contain sensitive employment data; credential compromise is a prerequisite for many attack chains.

**Likelihood:** L (if Argon2id is used correctly; the risk is in misconfiguration, not the algorithm).

**Impact:** H.

**Mitigation:**

- Argon2id as the primary hasher (`ARCHITECTURE.md` §3.3); Django's `Argon2PasswordHasher` with default (strong) parameters.
- `password_reset` invalidates active sessions and is rate-limited; password-reset tokens are short-lived and single-use.
- No plaintext password ever logged or transmitted (enforced by Django's auth and DRF serializer).
- Periodic review of hasher parameters as computational power increases.

---

### S-05 — Biometric template theft or misuse (post-MVP)

**What:** An attacker exfiltrates biometric templates; unlike passwords, biometric data cannot be reissued.

**Why it matters:** Biometric data is irrevocable; misuse has lifelong privacy implications for employees.

**Likelihood:** L (if the dedicated verification service isolation and encryption are correctly implemented; the risk is in implementation errors).

**Impact:** H (irrevocable privacy harm).

**Mitigation:**

- Dedicated verification service boundary (D-06): Django never sees or stores raw biometric data; templates are encrypted at rest with envelope encryption.
- No raw face images stored ever; immediate deletion after template extraction.
- Templates are separated from ordinary employee data (separate storage, separate access control).
- Consent-based enrollment with explicit policy; consent withdrawal deletes templates end-to-end.
- Audit logs record enrollment/verification events without payload content.
- Per-attempt rate limiting and liveness challenges (D-09) reduce the value of stolen templates (they cannot be replayed).
- Retention policy enforcement job deletes expired templates automatically.

---

### S-06 — Admin privilege abuse within an organization

**What:** A malicious organization administrator reassigns roles, tampers with attendance data, or accesses data beyond what their administrative role requires.

**Why it matters:** An admin has elevated privileges; abuse can alter attendance records or spy on employees.

**Likelihood:** L (internal threat is lower-probability than external).

**Impact:** H.

**Mitigation:**

- `AttendanceEvent` is append-only; admin cannot edit or delete events; only creation and soft-annotation are allowed via explicit admin APIs (not generic CRUD).
- Audit log is append-only; admin actions are themselves audited and cannot be tampered with by the admin who performed them.
- Role permissions are explicit and granular; the org admin role is defined by what it can do, not a blanket `is_superuser`.
- Superuser (platform operator) is separate from org admin; cross-org admin escalation is impossible.
- Post-MVP: sensitive admin actions (role changes, policy changes) require re-authentication (step-up auth).

---

## 3. Privacy risks

### P-01 — Biometric data not meeting regulatory requirements

**What:** GDPR, BIPA (Illinois), CCPA, and similar regulations impose strict rules on biometric data collection, consent, retention, and deletion; non-compliance carries significant legal penalties.

**Why it matters:** Legal exposure, loss of trust, potential fines.

**Likelihood:** M (regulatory landscape is actively evolving; different jurisdictions have different rules).

**Impact:** H (legal and financial).

**Mitigation:**

- Biometric consent is explicit, recorded (who, when, which policy), and withdrawable.
- Templates are encrypted at rest and in transit; no raw images stored.
- Retention and deletion are policy-configurable and enforced by automated jobs; deletion is end-to-end.
- Audit records the lifecycle without capturing the biometric payload.
- Before enabling biometric features in any jurisdiction, a legal review of applicable regulations (BIPA, GDPR Art. 9, local rules) is mandatory — documented as a gate in the roadmap (Phase 8).
- No biometric features ship without completed legal review.

---

### P-02 — Location data misuse or over-collection

**What:** The app collects location data more frequently than intended, or location data is retained beyond policy.

**Why it matters:** Continuous location tracking violates the product's privacy-by-design commitment and applicable law.

**Likelihood:** L (the architecture explicitly prohibits continuous tracking; the risk is in implementation bugs).

**Impact:** H (privacy harm, legal exposure).

**Mitigation:**

- Location is captured only at attendance events (clock-in/clock-out/presence-check) when policy requires it (`ARCHITECTURE.md` §13).
- No background location permission is requested; `expo-location` is called only in response to explicit user action.
- Location rows share the retention policy of event data; automatic cleanup.
- Tests verify that no location capture occurs outside of event handlers.

---

### P-03 — PII exposure in logs

**What:** Sensitive data (employee names, attendance patterns, tokens, device identifiers) appears in application logs, log aggregators, or error reports, accessible to operations staff or third-party monitoring tools.

**Why it matters:** Unauthorized exposure of employment and presence data violates privacy commitments.

**Likelihood:** M (logging sensitive data is a common mistake; requires discipline).

**Impact:** M.

**Mitigation:**

- Structured logging with explicit allow-list of what is logged per event type (`ARCHITECTURE.md` §18).
- No passwords, tokens, refresh secrets, push tokens, biometric payloads, or raw location in logs.
- PII fields are explicitly excluded from the logging middleware; a logging standard doc enforced in code review.
- Sentry error reports are configured to scrub PII fields before transmission.
- `request_id` correlation allows debugging without exposing personal data.

---

## 4. Biometric-specific risks

### B-01 — Presentation attacks (spoofing) defeat face verification

**What:** A photo, video, or mask of the enrolled employee is used to pass face verification, enabling a "buddy punching" attack via someone other than the real employee.

**Why it matters:** This undermines the core value proposition of face verification (identity assurance at attendance).

**Likelihood:** M (presentation attacks are well-documented; anti-spoofing technology is not perfect).

**Impact:** H (attendance integrity compromised for a specific incident; trust impact).

**Mitigation:**

- Liveness detection (D-06) is mandatory before face matching; a challenge-response protocol with fresh nonce, time-bounding, and single-use.
- Liveness captures include 3D depth check (if supported by device) or motion analysis (video sequence, blink, head turn) — chosen based on the selected provider's capabilities.
- Post-MVP: device attestation (Android SafetyNet/Apple DeviceCheck) to detect emulators and rooted/jailbroken devices.
- Provider swap-in: the verification service boundary allows upgrading the anti-spoofing algorithm without domain changes.
- Rate limiting on verification attempts (one per N seconds) to slow brute-force.

---

### B-02 — Biometric template is compromised and cannot be reissued

**What:** Unlike a password, a biometric (face fingerprint) cannot be changed; if the template database is compromised, the employee's biometric identity is permanently compromised.

**Why it matters:** Irrevocable privacy harm; the employee cannot "reset" their face.

**Likelihood:** L (if encryption and access controls are correctly implemented).

**Impact:** H (irrevocable).

**Mitigation:**

- Templates are encrypted with envelope encryption (data key per org or per enrollment; master key in a KMS, not in the DB).
- Dedicated verification service boundary isolates template storage from the main application DB.
- Consent withdrawal triggers immediate end-to-end template deletion; retention policy enforcement job cleans up expired templates.
- The breach scenario is explicitly part of the security hardening phase (Phase 13) red-team testing.
- Post-MVP: consider cancelable biometric schemes (template perturbation with a secret salt) if the provider supports it, so a breach of a salted template is non-invertible.

---

## 5. Attendance manipulation risks

### A-01 — Fake clock-in via stolen credentials

**What:** An attacker obtains an employee's password and clocks in/out remotely, creating attendance records without the employee being present.

**Why it matters:** Attendance manipulation; payroll implications; audit failure.

**Likelihood:** M (phishing and credential stuffing are common attack vectors).

**Impact:** H.

**Mitigation (MVP):**

- Strong password requirements + Argon2id.
- Account lockout after repeated failures (throttle + exponential backoff on login).
- Device/device metadata logged with each attendance event (for anomaly review, not for trust decision yet).
- Post-MVP (Phase 8–9): face verification at clock-in/out turns stolen credentials into insufficient attack vector (the attacker cannot spoof the face + liveness).

---

### A-02 — Clock-in on behalf of another employee (buddy punching)

**What:** Employee A uses Employee B's phone/credentials to clock in on their behalf.

**Why it matters:** Undermines attendance integrity and payroll accuracy.

**Likelihood:** M (a known, common attendance fraud).

**Impact:** M.

**Mitigation (MVP):**

- Device-level anomaly detection (post-MVP): flag if a single device logs attendance for multiple employees; manager-visible alert.
- Phase 8–9: face verification is the definitive mitigation; each clock-in/out is matched against the enrolled employee.
- Phase 10: location verification corroborates that the employee is at the expected workplace.

---

### A-03 — Time manipulation via client device clock

**What:** An employee manipulates their phone's system clock before clocking in/out, hoping the device time influences the recorded attendance time.

**Why it matters:** If device time is trusted, attendance records are unreliable.

**Likelihood:** L (the risk is mitigated by design; a user might try it once and discover it doesn't work).

**Impact:** H (if device time were trusted — but it is not).

**Mitigation:**

- Server-authoritative time (`DECISIONS.md` D-10); device time is captured as metadata only and never used in attendance calculations.
- Large discrepancies between device time and server time are logged as anomalies (audit signal) for manager review.
- Post-MVP: device attestation further reduces the feasibility of clock manipulation.

---

### A-04 — Presence-check response by a non-employee

**What:** Someone other than the enrolled employee responds to a presence check (if verification is not yet enabled).

**Why it matters:** Presence confirmation is meaningless if the responder is not the actual employee.

**Likelihood:** M (until face verification is enabled in Phase 8–9).

**Impact:** M (reduced attendance integrity; but presence checks alone are not the only verification layer).

**Mitigation:**

- Phase 8–9: liveness + face verification at presence-check time makes impersonation impractical.
- Phase 7: even before face verification, the presence-check response includes device metadata and is logged for anomaly review.
- Escalation policy: multiple missed checks flag the session for manager review, which catches patterns.

---

## 6. Scalability risks

### SC-01 — Presence-check scan becomes a bottleneck at high employee volume

**What:** The rolling scheduler scans `PresenceCheck` every 30 s; with tens of thousands of active sessions each generating periodic checks, the scan query becomes slow.

**Why it matters:** Slow scans lead to late check dispatch, degrading the user experience and reliability.

**Likelihood:** L (realistic employee volume for this product tier is hundreds to low thousands per organization; tens of thousands is a stretch scenario).

**Impact:** M.

**Mitigation:**

- Index on `PresenceCheck(status, due_at)` keeps the scan efficient; query is scoped to checks due now, not the full table.
- Worker concurrency can be increased; scan is idempotent and parallelizable with locks.
- If volume grows beyond tens of thousands concurrent sessions, the scan can be partitioned by org or sharded — the interface (`ARCHITECTURE.md` §10) allows this without domain changes.
- Monitor scan latency; alert if it exceeds a threshold; this is a scaling decision point, not an emergency.

---

### SC-02 — Attendance event volume causes slow history queries

**What:** Over years, a single employee accumulates tens of thousands of attendance events; org-wide queries (all employees in a date range) become slow.

**Why it matters:** HR/manager reporting and analytics degrade; API response times increase.

**Likelihood:** L (takes years of accumulated data per org to hit meaningful scale).

**Impact:** M.

**Mitigation:**

- Index on `(employee_id, timestamp)` and `(session_id, timestamp)` handles the primary query patterns efficiently.
- Cursor pagination (D-08) keeps page-load queries fast regardless of total row count.
- Post-MVP: periodic summary snapshots (materialized views or summary tables) for report-heavy queries.
- Table partitioning by time is a documented escalation option if row counts exceed tens of millions per org (not MVP).

---

## 7. Mobile-specific risks

### M-01 — Expo push token registration failure (token not registered or stale)

**What:** The mobile app fails to register its Expo push token with the backend, or the token becomes stale (app reinstalled, device change); notifications are silently dropped.

**Why it matters:** Presence-check prompts are not delivered; the employee doesn't see the check; the check eventually times out and is flagged as missed.

**Likelihood:** M (app reinstalls, token expiry, network hiccups are common).

**Impact:** M (one check may be missed; patterns of missed checks are visible to managers).

**Mitigation:**

- Token registration is retried on every app foreground event; the backend updates the token if it changed.
- Notification delivery failure is recorded (`Notification.status = failed`); a push failure does not affect the attendance record — the employee can still respond via the in-app inbox.
- Push is a delivery channel, not a trust boundary; the presence-check resolution logic is independent of push success.
- Post-MVP: APNs/FCM feedback integration to detect and clean stale tokens proactively.

---

### M-02 — Offline state causes confusion about clock-in success

**What:** A user taps "Clock In" while on a flaky connection; the request fails silently; the user believes they are clocked in but the server has no record.

**Why it matters:** The employee thinks they are clocked in; the manager sees no attendance; payroll is affected.

**Likelihood:** M (network conditions are variable).

**Impact:** H (attendance integrity impacted for an individual).

**Mitigation:**

- Attendance actions (clock in/out, presence response) **require connectivity** (`PRODUCT_REQUIREMENTS.md` §6.5); the app explicitly shows "Offline — clock in unavailable" rather than queuing offline.
- A failed request surfaces a clear, actionable error with `request_id`; the user retries when connectivity returns.
- The "current session" view (home screen) queries the server on every app foreground, so stale local state is quickly corrected.
- Post-MVP: offline viewing of cached history (read-only) is a nice-to-have but does not affect attendance integrity.

---

## 8. Deployment risks

### D-01 — Database migration causes downtime or data loss

**What:** A Django migration modifies a large table in production, locking it and blocking writes; or a migration contains a bug that corrupts data.

**Why it matters:** Attendance recording is unavailable during downtime; data loss is catastrophic for audit and payroll.

**Likelihood:** L (Django migrations are generally safe; risk increases with table size and migration complexity).

**Impact:** H.

**Mitigation:**

- Migrations are run as a **separate step before new code deploys** (`ARCHITECTURE.md` §16); if a migration fails, the old code continues to serve.
- Migrations that touch large tables must use `AddIndexConcurrently` and `RunPython` with data migrations that are batched and resumable — documented in the Django standard.
- No migration is ever applied directly on production without a tested backup.
- Schema changes that break the old code version are forbidden; backward-compatible migrations are enforced via a review checklist.
- Automated backups (with point-in-time recovery) are tested before first production migration.

---

### D-02 — Secrets exposed in repo or logs

**What:** A secret (database password, API key, signing key) is committed to git or appears in log output.

**Why it matters:** Compromised secrets enable full system takeover.

**Likelihood:** L (preventable with tooling; the risk is in human error or misconfiguration).

**Impact:** H (full compromise).

**Mitigation:**

- `.env` files and secret values are `.gitignore`d; `.env.example` documents required variables without values.
- GitHub Actions secrets; no secrets in workflow YAML files.
- `bandit` and secret-scanning in CI (Phase 13); pre-commit hooks prevent accidental secret commits.
- No secrets in logs; logging middleware scrubs sensitive values.
- Production secrets come from a secret manager, not from the git repo or env files checked into the repo.

---

### D-03 — Incomplete rollback after a failed deployment

**What:** A new code version is deployed, fails partially (e.g., new field referenced in old code path), and rollback leaves the system in an inconsistent state.

**Why it matters:** Attendance recording may be unavailable or partially broken during recovery.

**Likelihood:** L (if deployment follows the pre-migration + backward-compatibility rule).

**Impact:** M (service disruption until rollback completes; no data loss if pre-migration was clean).

**Mitigation:**

- Backward-compatible migrations + separate migration step mean rollback is safe: revert the code, leave the DB (forward-compatible).
- Health checks (`/healthz`, `/readz`) in the deployment pipeline gate promotion; a failed health check prevents rollout from completing.
- Feature flags for new features: a broken new feature can be toggled off without code rollback (post-MVP enhancement to the deployment story).
- Documented rollback runbook for each deployment phase.