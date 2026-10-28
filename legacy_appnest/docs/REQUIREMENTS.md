# Requirements and acceptance evidence

[Documentation index](README.md) · [Architecture](../ARCHITECTURE.md) ·
[Verification records](VERIFICATION.md)

Status meanings: **tested** = locally executed evidence at a recorded checkpoint;
**implemented** = source present but a listed external/environment layer is
unverified; **deferred** = intentionally unavailable. A historical passing check
does not establish current acceptance or cover the open defects below. Use
[the development guide](DEVELOPMENT.md#verification) to reproduce the current
verification entrypoint.

| Acceptance requirement | Status | Evidence / qualification |
| --- | --- | --- |
| 1. Same engine, separate definitions, reload persistence | Tested | Three templates plus relabeled fourth definition in PostgreSQL tests; browser-created shift survived web/server reload |
| 2. App/record/invitation/notification/media tenant isolation | Tested locally | Real-DB authorization, bound invitations, private-media authorization and cross-app reference rejection |
| 3. Member cannot grant rights, edit counters/protected workflow | Tested | Policy tests and typed action handlers; generic patch rejects protected input |
| 4. 20 concurrent final-place attempts → one allocation | Tested | Independent committed sessions/transactions, not a single rollback wrapper |
| 5. Identical command retry returns stored outcome; changed input fails | Tested at service and widget boundaries | Same-key receipt regression including retry after publication. Both renderers retain the original key, payload and revision after an unconfirmed response; explicit recovery does not replay on reconnect. Pending UI commands do not survive browser reload |
| 6. Capacity release and transaction rollback preserve invariants | Tested | Repeated release, failed capacity/create transaction, business/outbox checks; stream cancellation is a separate open defect |
| 7. Preview cannot reach live writes/schedules | Tested | Network-free adapter package contract; independent preview mutation test; synthetic UI labels |
| 8. Optional additions preserve records/claims/IDs | Tested | Spec compatibility + PostgreSQL publication test + actual endpoint demo + browser manual publish |
| 9. Stale drafts/jobs and safe publication retries | Tested | Expected-version/hash/receipt and obsolete generation/manual mutation regressions |
| 10. Interruption between committed run and scheduling recovers | Tested | Separate persistent PostgreSQL database and two actual processes; repeat wakeup → one durable notification |
| 11. Rule/date/archive/grant changes suppress stale work | Tested locally | Execution-state and explicit re-enrollment regressions; retry eligibility is rechecked under the app lock, failure backoff is shared by direct/reconciler callers, and unchanged revoked assignees no longer block unrelated edits. New PostgreSQL regressions cover these boundaries |
| 12. Reconnect/repeated invalidations recover state | Tested locally, bounded | Reconnect/resume/duplicate-event tests and historical live server restart. Legacy access failures dismiss editors and fence late reads; cancellation/session closure stops idle heartbeat polling. Widget/controller regressions cover these fixes; current WebSocket transport and multi-instance/load acceptance remain unverified |
| 13. AI failure does not break apps; template mode explicit | Tested; dated live evidence | Bounded attempts, preserved prior apps, explicit template mode. Historical browser creation, publication, CRUD and semantic label editing are recorded in [AI_CREATION_CHECK.md](AI_CREATION_CHECK.md); broader creation/edit outcomes in [CUSTOMIZATION_AI_CHECK.md](CUSTOMIZATION_AI_CHECK.md) |
| 14. Mobile/desktop, keyboard and large text | Tested, bounded | Renderer 390×844/1440×1000 at 150%; browser 1280×720 and 390×844; Tab focus and mobile builder publication. Full accessibility audit deferred |
| 15. Discover and resume unfinished new apps after reopening | Tested locally | Committed PostgreSQL sessions cover author-private discovery, concurrent resume and revoked access; Flutter route tests cover `/drafts/<appId>`, refresh, authentication and publication using synthetic transport. Connected browser acceptance remains unverified |

## Architecture review and current acceptance gaps

The 2026-10-07 [review](ARCHITECTURE_REVIEW.md#confirmed-findings) reproduced six
defects and remains a historical record. Retained-command recovery now uses the
original key/input/revision for **Retry save**, verified with lost-response widget
adapters. Reminder retry deadlines and shared failure backoff are covered by
PostgreSQL checks, including a contended app lock and terminal retry exhaustion.
Unchanged revoked assignees remain historical references without blocking note
or workflow edits; inactive creates and assignment actions remain rejected.

The CI workflows now pin Flutter 3.47.0/Dart 3.13.0. Published commit
`7ba9d63586b90213d24b731058dfabe86487a2f3` passed
[Analyze](https://github.com/Xuefeng-Zhu/AppNest/actions/runs/38178300937),
[Format](https://github.com/Xuefeng-Zhu/AppNest/actions/runs/38178300907) and
[Tests](https://github.com/Xuefeng-Zhu/AppNest/actions/runs/38178300924) on
2026-10-11. Subsequent working-tree changes need their own verification.

Legacy authorization UI lifecycle now has stream/query failure and late-read
widget regressions. Cancellation-aware event streams have idle/pending
cancellation, pause/resume, session-closure and access-failure controller tests.
Actual WebSocket transport cleanup and browser-reload recovery of pending record
commands remain unverified or unimplemented respectively. The table does not
establish multi-instance, live-provider, physical-device, deployment or full
accessibility acceptance.

That review ran static analysis, 81 spec tests, 259 server tests and 92 focused
renderer tests. Eight additional invariant checks reproduced defects rather
than passing. It did not run the full verification script, a new release build,
restart smoke, live provider/browser flow or device acceptance. Those results
are distinct from the earlier full-suite checkpoints below.

## Vertical slices

These describe delivered scope and its recorded evidence, subject to the open
gaps above.

- **A tested:** official Serverpod 4 scaffold; real auth; PostgreSQL dynamic serialization spike; pure-Dart AppSpec/schema; shared renderer; persistent CRUD.
- **B tested:** workspace + explicit app grants; hashed invitations; capacity claims; idempotency/revisions; typed streams; concurrency.
- **C tested:** atomic outbox; recurring reconciler; Future Calls; actual in-app reminder, run history and process restart proof.
- **D implemented/tested, with dated live evidence:** recoverable jobs, bounded server-only provider adapter, isolated preview, manual/semantic edits, exact review/publication and safe evolution. Browser creation/publication and semantic label editing were verified on 2026-09-22; the later targeted evaluation records broader outcomes without establishing a general reliability rate.
- **E tested with limitations:** calm launcher, bounded tile request, workspace switcher, templates/inbox, shell/sharing/activity, manual field/label/choice/view order, remix/unpin/archive, responsive layouts and repeatable seed/demo.

## Additional scope

### Rich personal mini-apps (2026-09-22)

Implemented: Daily Planner Today/Tasks/Progress, dedicated detail/editor pages, app identity and themed tabs/desktop navigation, authenticated page/record URLs, guarded unsaved edits, retained filters/search/pagination/scroll, grouped database-wide summaries, independent personal reminder times, owner delivery and typed reminder state. Manual and AI definition editing share capability gates, strict references, publication diffs and canonical compatibility checks.

Automated acceptance covers legacy hashes and records; invalid navigation/action references; semantic page edits; preview/live query parity; rapid navigation, unavailable records, stale responses, revoked access and read-only roles; local midnight/DST boundaries and undated tasks; reminder status transitions, rescheduling/clearing, explicit enrollment, deduplication, archive suppression and restart recovery. Exact executed results and remaining live browser checks are recorded in [VERIFICATION.md](VERIFICATION.md). Isolated rendered screenshots do not prove connected end-to-end delivery. See [MINI_APPS.md](MINI_APPS.md) for the implemented contract.

Typed endpoints cover manifests/list/templates/instantiate/remix/archive/pin; builder begin/get/patch/generate/publish; record query/get/aggregate and create/patch through the uniform action endpoint; private image upload/read; invitations/grants; event streams; inbox/read and run history. Notification effects have no arbitrary client-callable endpoint. The semantic component library uses approved view tokens and validated bindings rather than arbitrary widgets.

Generated source and migrations are delivered. The JSONB adapter and custom database guards are documented and tested. Operational request/job/run logs and local guardrails are present. External production auth/email/Redis/storage, cloud deployment, arbitrary file/video attachments, comprehensive performance/retention operations and full accessibility certification remain deferred as documented in SECURITY.md.

### Rich component library (2026-09-23)

Implemented: tables, local-date calendars/agendas and timelines, database-wide
numeric and time-series charts, metric/target cards, private images and galleries,
static banners/formatted text, typed controls, multi-step forms, checklists and
workflow drag/move controls. AI, manual editing, visual editing, preview and live
adapters use the same capability-gated definitions. Three new templates provide
examples without changing existing published definitions.

Automated coverage includes canonical compatibility, component bindings, more
than 100-record aggregation, DST buckets, form submission and conflict behavior,
private-media quotas/references/revocation/cleanup, actual HTTP upload transport,
and concurrent media requests against ephemeral PostgreSQL. Renderer captures
are isolated synthetic evidence. At that checkpoint, the development database had the media
migrations, and the updated server and release web app were activated locally.
Connected checks passed for authenticated creation/publication, browser image
upload, final-only multi-step submission, image/record reload persistence,
keyboard workflow movement, checklists, calendar agendas and charts. A separate
authenticated client smoke verified 106 persisted records, authorization,
revision/receipt behavior, private-image revocation and fresh-login persistence.
See [component behavior](RICH_COMPONENTS.md) and the
[dated connected verification record](RICH_COMPONENTS_LIVE_CHECK.md). These
checks do not establish native-device, rich-component live-AI, or production
acceptance.

At that checkpoint, the central **template/manual** demo was verified end to end. Real natural-language generation through Nebius Nemotron also created and published Plant Corner and Trip Kit, with authenticated live record editing, workflow transitions and summary counts. A credentialed semantic label edit preserved the rest of the definition exactly. See [the AI creation check](AI_CREATION_CHECK.md). The later [customization evaluation](CUSTOMIZATION_AI_CHECK.md) records additional edits; neither record establishes the complete AI sharing/reminder sequence or current provider availability.

### App appearance and page composition (2026-09-23)

Implemented: coordinated Clean, Editorial and Playful styles; accent colors,
heading typography, spacing and corner overrides; style previews and reset
controls; stacked, two-column and featured-first page layouts; responsive banner
image placement. AI creation/editing and click-to-edit use the same bounded
definition and semantic-patch contract. Absent properties preserve canonical
legacy definitions; presentation changes retain business data and require
publication before reaching the live app.

Automated verification passed: 346 tests across spec, renderer, Flutter authoring
and server packages; real PostgreSQL publication/authorization checks; isolated
two-process reminder recovery; analysis/format checks; and the release web build.
Eight isolated desktop/mobile captures were visually inspected. Connected runtime
activation, preview-to-published visual parity and appearance-specific live-AI
behavior remain unverified; prior connected evidence above does not establish
those layers. See [the appearance contract and verification record](APPEARANCE.md)
for defaults, capability semantics and exact boundaries.

### Everyday customization (2026-09-23)

Implemented: describe-first creation with optional guidance; Notes, Reminders,
Calendar and Clock & Focus examples; appearance/content/layout/behavior controls;
one explicit publication review; reminder timing edits with renewed approval;
and a device-local focus countdown that survives normal reopening. Immediate
durable generation dispatch, visible recovery metadata and safe failed-edit
discard support the same creation loop. Existing app identities and data remain
protected by the shared compatibility and authenticated publication contracts.

Verification passed: 505 tests, analysis/formatting, PostgreSQL integration and
two-process reminder recovery, plus web and Android release compilation. iOS
compilation was blocked by an uninstalled Xcode platform component. Live AI checks
passed 5/8 creation scenarios and all 8 edit scenarios on their latest checks;
three edits used explicit templates because creation failed. AI creation still
needs reliability work. At that checkpoint, connected acceptance for these
customization changes and physical-device interaction remained unverified.
Phone capabilities were added in the subsequent mobile milestone below;
background alerts remain deferred. See [the live AI evaluation](CUSTOMIZATION_AI_CHECK.md).
See [the customization contract and execution record](CUSTOMIZATION.md).

### Mobile capabilities (2026-09-24)

Implemented: Android/iOS device-information cards, flashlight, foreground
brightness, keep-awake and haptic controls, manual/AI authoring, Phone Toolkit,
and per-mini-app local consent. Preview controls are synthetic; browser/desktop
show unsupported-platform guidance. Device values never reach the backend or AI.

Initial verification: 539 tests, analysis/formatting and reminder restart recovery
passed. Android release compilation and direct iOS Swift type-checking passed;
the full iOS build was initially blocked by the missing Xcode iOS 26.5 platform.
Later that day, the signed iOS build and signature verification passed, and Phone
Toolkit reached a connected browser AI preview after fixes. Installation of the
later frontend update could not proceed because the phone was unavailable.
Physical-device generation and controls remain unverified. See
[mobile features](MOBILE_FEATURES.md) and the [iPhone investigation](IPHONE_AI_CHECK.md).

### Concurrent AI generation (2026-10-07)

Removed the app-wide single-generation lease gate. Independent users' builds can
overlap, with eight shared Future Call slots per server process. Each user's
one-active-job and 30-jobs-per-rolling-day quotas remain. Reconciliation wakes a
bounded batch of due or expired jobs; duplicate deliveries, old leases and manual
edits cannot overwrite the current draft.

Verification: `scripts/verify.sh` passed workspace static analysis, formatting,
all 551 tests (81 spec, 171 renderer, 174 Flutter app, 125 server), and the
separate-process reminder restart smoke against embedded PostgreSQL. Regressions hold two users' provider
calls open simultaneously, race same-user enqueue requests, reject duplicate and
late worker results, and recover multiple missed wakeups. Provider responses in
these tests are synthetic; no live-provider concurrency or load test was run.
The server needed a restart to load the updated worker-pool configuration;
this record does not confirm the configuration of a currently running process.
