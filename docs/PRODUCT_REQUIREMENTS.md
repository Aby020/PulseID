# PulseID — Product Requirements

> **PulseID — Intelligent Workforce Presence**
> *Verify. Work. Track.*

**Status:** Phase 0 — Planning (Task 1). No application code exists yet.
**Owning document:** `PRODUCT_REQUIREMENTS.md` is the single source of truth for *what* PulseID must do. The *how* lives in `ARCHITECTURE.md`. Decisions and rationale live in `DECISIONS.md`.

---

## 1. Product vision

PulseID is a modern employee-attendance and workforce-presence platform built around **verified work sessions**.

An employee starts a work session, PulseID records it, periodically requests presence confirmation, the employee verifies presence (eventually with face + liveness verification), and the session ends with clock-out. Attendance records are computed from immutable events, not from a single mutable "attendance" row, so the system is auditable and can evolve to support face verification, liveness detection, location verification, notifications, attendance rules, and analytics **without a major architectural rewrite**.

## 2. Product goals

1. **Verified presence** — attendance actions are attributable to the actual employee, protectable against spoofing (face, liveness, location) as those capabilities mature.
2. **Auditable by design** — every meaningful action is an immutable event with an audit trail, enabling HR and administrators to reconstruct exactly what happened.
3. **Privacy-first biometric and location handling** — no continuous location tracking; biometric data stored minimally, encrypted, consent-gated, and deletable.
4. **Multi-tenant from day one** — organizations are isolated at the data layer; cross-tenant access is architecturally impossible, not merely discouraged.
5. **Clock integrity** — server time is authoritative for attendance timestamps; device clocks are never trusted for attendance decisions.
6. **Incrementally buildable** — a clear roadmap from MVP (no face/liveness/location) to a fully verified workforce platform.
7. **Portfolio-quality and production-ready** — clean architecture, tests, security baseline, observability, and a realistic deployment story.

## 3. Target users

| User | Primary surface | Needs |
| ---- | --------------- | ----- |
| Employee | Mobile app (Expo / React Native) | Clock in/out, view active session + duration, respond to presence checks, face verification, attendance history & summaries, notifications |
| HR / Manager | Web app (React + Vite + Tailwind) | View employees, monitor attendance, live work status, review history / missed checks / late arrivals / early departures, analytics, reports, schedules, attendance rules |
| Organization Administrator | Web app | Everything above, plus organization, users, roles, workplaces, schedules, policies (attendance + presence-check), system settings, audit logs |

Roles are extensible. The RBAC model (see `ARCHITECTURE.md` § AuthZ) allows new roles to be added without code changes in the core domain.

## 4. Core workflows

### 4.1 Primary workflow (conceptual target)

```
Employee → Authenticate → Employee Dashboard → Start Work Session
→ Optional/required verification → Clock In → Working
→ PulseID schedules presence verification → Push/in-app prompt
→ Employee opens verification → Liveness → Face verify → Optional location verify
→ Presence confirmed → Continue working → Additional checks when required
→ Clock Out → Final verification if policy requires → Session completed
→ Attendance record finalized
```

**Not implemented in Task 1.** This is the north star the architecture must support.

### 4.2 MVP workflow (what the architecture must support first)

```
Employee authenticates (mobile)
→ Views dashboard (web admin sees live status)
→ Clock in  → server-authoritative timestamp → WorkSession ACTIVE + AttendanceEvent(CLOCK_IN)
→ Clock out → WorkSession ENDED + AttendanceEvent(CLOCK_OUT)
→ Employee views history/summaries; manager monitors and reports
```

## 5. Roles

- **Employee** — mobile app user; owns their sessions/presence responses; cannot administrate.
- **Manager** — web user; monitors employees in their org; reviews/reports; cannot manage org-wide config.
- **HR** — web user; manages employees, schedules, policies, and attendance data.
- **Organization Administrator** — web user; full configuration within the org, including audit-log review.
- **System/Superuser** (internal) — platform operator; cross-org concerns only where explicitly required; restricted.

Role-to-capability mapping will be enforced in `OrganizationMembership` + policy layer (see `ARCHITECTURE.md` § AuthZ). Additional roles (e.g., Auditor, Site Lead, Payroll) can be added later.

## 6. Functional requirements

Priorities: **M** = MVP, **P** = Post-MVP, **A** = Advanced.

### 6.1 Authentication & accounts
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| AUTH-01 | Employee logs in to the mobile app with email + password. | M |
| AUTH-02 | Admin/HR/Manager logs in to the web app. | M |
| AUTH-03 | Access tokens are short-lived; refresh tokens rotate and are revocable server-side. | M |
| AUTH-04 | Password reset via email with a short-lived, single-use link. | M |
| AUTH-05 | Account status (active/disabled) gates all access. | M |
| AUTH-06 | Logout revokes the refresh token on the server. | M |
| AUTH-07 | A user can belong to exactly one organization at a time for MVP (multi-membership is P). | M |
| AUTH-08 | Roles and permissions are checked per request (RBAC). | M |
| AUTH-09 | Password hashing uses a strong algorithm (Argon2id). | M |
| AUTH-10 | Session/device management: list and revoke active sessions. | P |

### 6.2 Employees & organization
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| ORG-01 | Organization administrator creates an organization. | M |
| ORG-02 | Administrator invites users (manager/HR/employee) with role assignment. | M |
| ORG-03 | Administrator creates/updates employee profiles (employment details, default workplace, schedule, policy). | M |
| ORG-04 | Deactivated employees cannot authenticate; historical data is retained. | M |
| ORG-05 | Every tenant-scoped query is isolated to the caller's organization. | M |

### 6.3 Workplaces
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| WPL-01 | Define workplaces with name, address, optional lat/lng + allowed radius (geofence). | P |
| WPL-02 | Assign an employee to a default workplace. | P |
| WPL-03 | Location verification is **event-based only**; no continuous tracking. | P |

### 6.4 Schedules & attendance rules
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| SCH-01 | Define recurring schedule templates (days, start/end, timezone). | M |
| SCH-02 | Assign employees to schedules; handle time zones per organization. | M |
| SCH-03 | AttendancePolicy configures late threshold, grace period, early-departure threshold, overtime rules, presence-check policy. | M |
| SCH-04 | Policies are org-level with optional per-employee override. | P |

### 6.5 Work sessions & clock in/out
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| WK-01 | Employee clocks in → creates an active WorkSession + a CLOCK_IN AttendanceEvent with server-authoritative timestamp. | M |
| WK-02 | Concurrent/double clock-in requests cannot create two active sessions (idempotent + constraint-enforced). | M |
| WK-03 | Employee views the active session and live working duration. | M |
| WK-04 | Employee clocks out → WorkSession ends + CLOCK_OUT event. | M |
| WK-05 | Duplicate clock-out is rejected idempotently. | M |
| WK-06 | Employee can view attendance history and summaries. | M |
| WK-07 | Breaks are tracked as explicit break events (duration excluded from paid work time). | P |
| WK-08 | Late arrival / early departure / overtime are computed from policy + events. | P |
| WK-09 | Optional/required verification can be attached to clock-in/clock-out per policy. | P |

### 6.6 Presence checks
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| PRC-01 | Active sessions are periodically sent a presence check (fixed interval or randomized within a window — policy-configured). | P |
| PRC-02 | Check has a response window and grace period; employee responds in-app (or via push). | P |
| PRC-03 | Presence check supports optional verification (liveness/face/location) when those capabilities exist. | P |
| PRC-04 | Outcomes: verified / failed / timed out / missed; missed checks are escalated and manager-visible. | P |
| PRC-05 | Every check attempt and outcome is audit-logged. | P |
| PRC-06 | A manager can view all presence-check activity for their team. | P |

### 6.7 Reports & analytics
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| REP-01 | HR/Manager exports attendance reports (per employee/team/date range). | P |
| REP-02 | Working-hour analytics: planned vs actual, late arrivals, early departures, missed checks, overtime. | P |
| REP-03 | Reports are generated asynchronously (Celery) and delivered via the web app. | P |

### 6.8 Face verification (future)
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| FACE-01 | Authorized enrollment process registers an employee's biometric identity with explicit consent. | A |
| FACE-02 | Attendance actions can require 1:1 face verification against the enrolled identity. | A |
| FACE-03 | Liveness detection guards against photo/video/replay spoofing. | A |
| FACE-04 | No raw face images are stored; only encrypted templates, with retention & deletion policies. | A |
| FACE-05 | Biometric data is stored separately from employee data with strict access control and audit. | A |
| FACE-06 | Biometric consent can be withdrawn; templates are deletable end-to-end. | A |

### 6.9 Notifications
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| NOT-01 | Push notification for a due presence check. | P |
| NOT-02 | In-app notification inbox with read/unread state. | P |
| NOT-03 | Attendance notifications: clock-in reminder, clock-out reminder, late arrival warning, missed-check alert. | P |
| NOT-04 | Administrative notifications (policy change, schedule published). | P |

### 6.10 Audit
| ID | Requirement | Priority |
| -- | ----------- | -------- |
| AUD-01 | AuditLog records who did what, when, and the before/after of sensitive changes (append-only). | M |
| AUD-02 | Authentication, authorization denials, attendance actions, policy/role changes, and admin actions are audited. | M |
| AUD-03 | Biometric lifecycle (enrollment/verification/revocation) is audited without logging biometric payloads. | A |
| AUD-04 | Organization admin can review audit logs scoped to their organization. | P |

## 7. Non-functional requirements

| ID | Requirement | Target |
| -- | ----------- | ------ |
| NFR-01 | **Security** — OWASP baseline; deny-by-default authorization; secrets never in code. | M |
| NFR-02 | **Privacy** — data minimization; biometric/location treated as sensitive; documented retention & deletion. | M |
| NFR-03 | **Multi-tenancy** — hard isolation; no cross-tenant data access (enforced at the data layer). | M |
| NFR-04 | **Reliability** — audit/attendance events are never silently lost; idempotent state changes. | M |
| NFR-05 | **Performance** — p95 API response < 300 ms for CRUD; clock-in < 1 s end-to-end. | M |
| NFR-06 | **Scalability** — read-scaling via caching; async job queue for deferred work. | P |
| NFR-07 | **Observability** — structured logs, correlation IDs, health endpoints, error tracking; no PII/biometric content in logs. | M |
| NFR-08 | **Testability** — unit + API + authz + security tests; ≥ 80% coverage on new code. | M |
| NFR-09 | **Time correctness** — UTC storage, per-org timezones, server-authoritative timestamps. | M |
| NFR-10 | **Accessibility** — web admin meets WCAG 2.1 AA; mobile uses accessible controls. | P |
| NFR-11 | **Mobile offline** — graceful degradation: explicit "offline/online" state; clock-in requires connectivity (server timestamp is authoritative); offline *viewing* of history is P. | M |
| NFR-12 | **Compliance-ready** — consent records, retention policies, and audit that satisfy a GDPR-like audit. | P |

## 8. Attendance requirements (detailed)

- **Server-authoritative timestamps.** Device clocks are never trusted. The server records `clock_in_at` / `clock_out_at`; the client may send `device_reported_at` as metadata only (diagnostics), never as the recorded time.
- **UTC at rest.** All `DateTimeField`s are stored in UTC. Attendance days and shifts are interpreted in the organization's configured timezone.
- **Concurrent safety.** Clock-in is guarded by a unique database constraint (one active `WorkSession` per employee) *and* an idempotency key; races resolve to a single active session.
- **Event integrity.** `AttendanceEvent` is an append-only ledger. Work duration, lateness, early departure, overtime are *derived* from events + policy, never stored as a single mutable value (an explicit computed snapshot may be cached).
- **Day boundaries.** Attendance "day" is defined by the org timezone, and schedule windows are interpreted in that timezone.
- **Breaks.** Break start/end are events; break duration is excluded from billable/paid work duration per policy (P).
- **Overtime.** Computed against scheduled end + policy threshold (P).

## 9. Presence-check requirements (detailed)

- **Policy-driven.** Org-level AttendancePolicy defines: enabled/disabled, fixed interval **or** random-in-window schedule, expected response window, grace period, escalation rules.
- **Lifecycle.** Check is scheduled → due → employee is prompted → response + optional verification → resolved as verified / failed / timed out / missed.
- **Reliability.** A check that cannot be delivered must still resolve as missed (no silent loss); outcomes are computed even if the client never responded.
- **Visibility.** Managers can see all checks for their team: pending, verified, missed, escalated.
- **Audit.** Every schedule, prompt, response, and resolution is recorded in `AuditLog`/`VerificationAttempt`.

## 10. Face-verification requirements (detailed)

- **Enrollment.** Admin/HR initiates; employee consents explicitly (stored consent record with policy reference and date); a quality-checked capture produces a biometric template. Enrollment is approved/activated before it can be used.
- **Verification.** 1:1 match of a fresh capture against the enrolled template at attendance actions when the policy requires it.
- **Liveness.** Anti-spoofing (photo/video/replay/mask) is mandatory before matching is trusted.
- **Privacy & storage.** Raw images are deleted immediately after template extraction. Templates are encrypted at rest, separated from ordinary employee data, access-controlled, versioned, retention-policied, and end-to-end deletable on consent withdrawal.
- **Not implemented in MVP.** The architecture isolates the biometric provider behind a service boundary so the implementation can land without core rewrites (see `ARCHITECTURE.md` § Face verification and `DECISIONS.md`).

## 11. Location requirements (detailed)

- **Event-based only.** A latitude/longitude + accuracy reading is captured **only at an attendance event** (clock-in, clock-out, presence check) when the policy requires location. **No continuous background tracking.**
- **Verified server-side.** The geofence decision (inside/outside allowed radius) is computed on the server from the reported coordinate; the client never self-asserts "in range."
- **Permissions.** Location permission is requested at event time, with a privacy explanation; the user can decline and the event may still record without location (per policy: warn-only vs mandatory).
- **Integrity.** Coordinates are treated as attestations, not proof; corroborated by replay/idempotency protections and, where appropriate, device attestation (P).

## 12. Notification requirements (detailed)

- **Push** for urgent, time-sensitive events (presence-check prompt, missed check, late-arrival warning).
- **In-app inbox** for everything, with read/unread and deep-link targets.
- **Delivery model.** Outbound notification is a first-class, persisted object with status (queued → sent → delivered/failed), so delivery can be retried and audited.
- **Preference.** Per-user notification preferences (channels on/off) with mandatory categories non-suppressible per policy.

## 13. Security requirements (summary — full model in `ARCHITECTURE.md` § Security)

- Strong password hashing (Argon2id), MFA as an option (P).
- Short-lived access tokens, rotating server-side refresh tokens, device/session revocation.
- Deny-by-default RBAC; every API request checks organization + role.
- Rate limiting on authentication and attendance endpoints.
- Idempotency keys prevent duplicate clock-in/out replay.
- Secrets via environment/infrastructure, never in code.
- Minimal attack surface on public endpoints; strict CORS/CSRF posture for web; secure storage on mobile (Keychain/Keystore).

## 14. Privacy requirements (summary — full model in `ARCHITECTURE.md` § Privacy)

- Data minimization throughout (biometric, location, and device telemetry).
- Biometric data: consent, encrypted templates only, separate storage, strict access, retention + deletion.
- Location: event-based, never continuous.
- Audit logs record actions, not secrets/biometric payloads.
- Users can request data export and deletion in line with policy.

## 15. Future features (out of current scope, architecture must not block)

- Face verification & liveness (see § 10).
- Location / geofence verification (see § 11).
- Push notifications (see § 12).
- Payroll export, third-party HRIS integration.
- Manager approvals, shift swaps, time-off.
- Attendance analytics dashboards and ML-based anomaly detection ("buddy punching" pattern detection).
- Multi-organization membership for a single user.
- Multiple workplaces per employee; location-based workplace auto-suggestion.
- Break tracking, overtime, and flexible schedules.

## 16. Out of scope (explicitly not in the product)

- Continuous employee location tracking (never).
- Raw face-image storage (never).
- Attendance decisions based on device-reported time (never).
- Biometric template extraction on shared/unmanaged devices without policy approval.