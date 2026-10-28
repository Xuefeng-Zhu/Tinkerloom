# Security boundaries and operational limitations

This describes the checked-out implementation. Dated acceptance records remain
historical evidence; they do not establish production readiness or a clean current
runtime. See the [architecture review](ARCHITECTURE_REVIEW.md) for historical
findings and the [development guide](DEVELOPMENT.md) for local operation.

## Implemented boundary

Live endpoints require Serverpod authentication. No client-supplied actor or tenant ID is trusted. Workspace and app grant checks precede data access. Mini-app definitions cannot grant rights, contain credentials or choose network destinations. Model output is parsed and validated, never executed. Capacity/claims, workflow transitions, assignment, notifications and automations are trusted handlers, not editable payload authority.

Cross-app/tenant IDs, wrong invitation recipients, protected workflow/capacity edits, viewer mutations, notification access, stale definitions, revision conflicts, changed idempotency requests and invalid database relationships have regression coverage. Owners alone archive. Archive disables writes and stale effects. Invitation tokens are random, hashed, scoped, role-selected, expiring, single-use and revocable. Notification listing/read state rechecks current app access.

Preview has no transport or scheduler dependency. AI prompts omit private records; operators alone control provider configuration. HTTP diagnostics do not expose provider response bodies or secrets. Framework server-side exception stacks can appear in development logs; typed client errors do not expose stacks.

## Known correctness limitations

The 2026-10-07 [architecture review](ARCHITECTURE_REVIEW.md#confirmed-findings)
retains its original reproductions. Current fixes and remaining limits are:

- **Client command retries:** both renderer variants retain the command key,
  exact input and original revision after an unconfirmed response. Explicit
  **Retry save** replays that request, with lost-response widget regressions.
  Pending commands remain scoped to the mounted runtime and do not survive
  browser reload. Server receipts deduplicate the same key and exact input.
- **Authorization UI lifecycle:** legacy access errors now dismiss open editors
  and fence late query results. Widget regressions cover stream/query failures
  and stale reads; current backend grants remain authoritative.
- **Concurrent editors:** pristine editors refresh fields and their revision
  together. Dirty forms and unconfirmed commands retain the original snapshot
  and revision, preserving conflict detection and exact receipt retries.
- **Stream cleanup:** a cancellation-aware controller stops heartbeat timers on
  subscription cancellation or session closure and discards pending reads.
  Heartbeats still recheck current grants. Unit regressions cover idle/pending
  cancellation, pause/resume, closure and access failure; actual WebSocket/load
  acceptance remains a separate check.
- **Reminder retry timing:** direct wakeups and reconciliation enforce both
  `dueAt` and `nextAttemptAt` after locking and reloading the app/run. Failed
  effects roll back before a generation-fenced transaction persists backoff;
  both callers share the five-attempt budget. PostgreSQL regressions cover early
  wakeups, lock contention, failures and terminal exhaustion.
- **Revoked assignments:** unchanged references are retained as historical data
  during unrelated edits and workflow transitions. They grant no access. Creates,
  changed references and explicit assignment actions still require active app
  membership. PostgreSQL regressions cover owner/member edits, revoked reads,
  inactive assignment rejection and clearing/reassignment.

The CI SDK mismatch in that historical review was repaired. Analyze, Format and
Tests use Flutter 3.47.0/Dart 3.13.0; all three passed on published commit
`7ba9d63586b90213d24b731058dfabe86487a2f3` on 2026-10-11. This records that
commit's automated verification, not CI acceptance of subsequent working-tree
changes or production readiness.

## Release gates / not proven

- **Local-only seeded environment.** Public synthetic credentials must never be enabled on an exposed deployment. Seeding refuses non-development run modes; no production user-switcher endpoint exists.
- **No production auth/email verification.** Real local password login is tested. Production email transport, abuse protections, account recovery and operator configuration require deployment-specific verification. The default Serverpod Cloud email configuration is not evidence that a cloud service is connected.
- **Web tokens:** the current official scaffold client stores auth tokens using its SDK storage. Before public deployment, configure HTTPS, strict allowed origins, secure httpOnly cookie auth where supported, CSP and a reviewed host origin policy. Local development listeners must not be exposed to untrusted networks.
- **Startup:** companion integrity guards are installed just after Serverpod starts listeners. Future production orchestration must gate readiness/traffic until setup completes and separate schema-maintenance privileges from runtime privileges.
- **Scale:** app-level serialization, field projections and server-side revision polling are intentional MVP tradeoffs. No throughput/load benchmark or multi-instance Redis/shared-event deployment has been verified. Independent AI jobs share eight Future Call slots per process with reminders and reconciliation; when the pool is full, other work waits for a slot. Due times are persisted, and scheduling lag is logged. The pool does not enforce provider RPM/TPM limits across server processes.
- **Retention/quotas:** chosen query/spec/job/fan-out limits are implemented, but total record storage, audit/outbox retention, database backups/restoration, orphan draft cleanup and per-organization billing/abuse controls need operator policies. Old drafts count toward the workspace app limit. Do not delete database directories as routine cleanup.
- **AI:** provider credentials are read server-side from the ignored environment-specific `config/passwords.yaml`; `.env` files alone do not configure this adapter. Availability depends on the operator's current configuration. Historical [connected AI creation/editing](AI_CREATION_CHECK.md) and [provider-only customization evaluation](CUSTOMIZATION_AI_CHECK.md) establish different layers and retain their failures and limitations. They do not verify provider privacy contracts, current credentials, production expense controls or universal generation quality. Response-format hints are provider-dependent; strict application validation remains authoritative. Saved job usage describes the latest attempt, not cumulative billed usage across retries; use provider billing for totals.
- **Accessibility:** semantic controls, keyboard traversal, responsive screens and renderer tests at 150% text are checked. This is not an exhaustive screen-reader/WCAG audit or a native-device accessibility certification.
- **UI scope:** invitation binding and member pickers use account IDs, not a contacts directory. The member directory returns at most 100 grants without pagination, so larger memberships are incomplete in management and assignment pickers. Page-local grouped record lists are labeled when pagination applies; `runtime.summary` and `runtime.aggregate` compute database-wide results. Existing-record activation selection displays up to 50 rows per relevant collection, with the server enforcing a 500-record explicit maximum.
- **Private images:** authenticated app-scoped uploads/reads use private storage,
  same-app references and retained-version protection. JPEG frame/component
  budgets are checked before decoder allocation; original EXIF is replaced by
  bounded scalar orientation. PNG inflation is counted against exact scanline
  geometry before decoding. Animated PNG/WebP and inconsistent WebP headers are
  rejected; unnecessary metadata is stripped before parsing. Processing allows
  two completions per process and one per account, rejects excess work before
  retrieving originals, and terminates workers after 30 seconds. These are
  application budgets, not an OS-enforced heap limit or measured load guarantee.
  Revocation denies subsequent reads; already-delivered bytes cannot be recalled.
  See [media limits and authorization](RICH_COMPONENTS.md#private-images).
- **Optional Compose databases:** published ports bind to loopback and require
  external per-service passwords. Credentials of previously initialized volumes
  require owner-managed rotation; no running volume was inspected or changed.
- **Future capability limits:** no arbitrary file/video attachments, payments, general external integrations, public marketplace, executable plug-ins, recurring user-local schedules, offline writes or destructive data migrations. Definition versions do not restore deleted data or undo delivered effects.

No production deployment, penetration test, external delivery, signed mobile installation or hackathon eligibility is claimed.
