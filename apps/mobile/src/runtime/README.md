# Full AppSpec runtime foundation

This directory uses the canonical `src/spec` domain. It is separate from the existing bounded definition runtime. `FunctionRuntimeAdapter` accepts only `engine: "appspec.v1"`; the flat civil-date model is never inferred to be a full AppSpec.

`FunctionRuntimeAdapter.load(appId, transport)` reads `spec.getApp`. The transport must return the decoded Function `data` object and retain the existing authenticated Appwrite session/JWT checks. It must not accept a client actor ID or an administrative key. Known service errors should be thrown as `BackendError` or `RuntimeError`; lost/invalid transport responses remain uncertain for mutations. The adapter preserves current `BackendError` uncertainty. No SDK or authentication code is duplicated here.

The manifest matches `appwrite_backend/SPEC_ENGINE.md`: `allowedActions` is on the app DTO, the immutable version contains `{id, number, hash, spec}`, and the author's private draft includes nullable `publishedVersionId`. All new query/record calls carry the immutable version ID. Read DTOs reject mismatched versions, collections, duplicate rows, unsupported action IDs, invalid types, and impossible capacity counts. Shared `listMembers` uses complete paging without a version parameter. Media, reminder state and watch are explicitly unavailable in the current Function adapter; a parsed definition is never evidence of an installed effect.

## Host ownership and recovery

Create one `RuntimeController` per backend/project/account/app/version scope, outside route components. Supply a cryptographically random stable operation-ID factory from the host and a `RuntimeCommandStore` scoped to endpoint, project, account and app. The store contains record input and operation identity, **never** cookies, JWTs, API keys or passwords. A live controller refuses writes when its store reports memory-only durability. The only supplied store at this checkpoint is the isolated in-memory implementation; the host still needs a verified durable browser/native implementation.

The controller persists a frozen command before the first network call, reserves the write slot before awaiting persistence, and retains the original app/version/action/record revision/input together. A failed persistence call sends no network request. A lost response, transaction conflict, invalid success body, or failure to clear a successful command remains unresolved. Recovery reads the saved envelope without auto-sending it. Explicit retry sends that original envelope, including an older version ID, so the server can reauthorize and replay an exact historical receipt. A definite rejection must be acknowledged before a new command is allowed. Navigation, competing writes and inputs remain locked while a command is unresolved.

Dispose the controller on account/project/app changes and fence the host's transport to that scope. Disposing never deletes a saved command; the same account may need it later. The renderer remounts local UI state when the controller's unique scope changes. Dirty input fences late reads; a record read failure clears its prior details. A confirmed access failure during read/paging/write hides every cached record and local editor, blocks writes/retry, and calls the optional `onAccessFailure` host callback. Reopening requires a fresh authorized manifest/controller. The original command stays only in the account-scoped recovery store for safe later reconciliation. Per-page scroll position, query selection and loaded prefix survive route navigation within the controller's lifetime. Cross-process page/editor restoration remains a separate migration gate.

Definitions keep the original 128 KiB bound. Full runtime request snapshots instead have a 6 MiB bound consistent with the current Function contract, allowing forty full-length text fields. Both clone only validated own data descriptors and reject hidden functions/accessors, cycles, sparse arrays and excessive depth before serialization. Published definitions and retained commands are frozen after validation. Actual Appwrite gateway/body/timeout support remains a live-cloud gate.

## Queries and preview

`query.ts` builds validated filters and complete-collection sort requests. Timestamp comparisons preserve microseconds and signed years. Optional values sort last in either direction with code-unit record-ID tie breaking. Cursors bind collection/filters/sort; changed queries start at page one. Refresh refills the previously loaded prefix; paging rejects overlaps and nonadvancing cursors.

Summary and chart/metric results come from server aggregates, never from loaded row counts. Calendar badges use a complete month aggregate and a separate selected-day query. Each local midnight is constructed independently before conversion to UTC, including 23/25-hour DST days. Timeline groups explicitly describe loaded records, and the undated toggle sends a real null filter.

`createIsolatedPreview(spec)` creates independent records, receipts, cursor state, members, synthetic images/reminder examples and an in-memory timer store. It receives no transport, device bridge, host store or scheduler. Its seeded records follow the original Dart templates. All seven trusted action shapes are implemented: create/patch, workflow transition, assignment, capacity configure/claim/release. Initial workflow values, protected generic-patch fields, eligible preview members, declared transitions, capacity bounds and three policy presets are enforced. Capacity counters use pool semantics without incrementing the record revision, matching the Function handler. Exact receipts replay original outcomes after later edits; changed payloads reject operation-key reuse.

The timer controller uses saved UTC deadlines, serializes writes per view, and publishes changes only after the store commits. An unreadable timer is never silently replaced. Preview supplies memory storage. Live timer controls require an injected durable account/app-scoped `UtilityTimerStore`. Native notifications are not scheduled by this controller.

## Verification and remaining acceptance

Run from `apps/mobile`:

```sh
node --import tsx --test src/runtime/runtime.test.ts src/renderer/model.test.ts
npm run typecheck
node_modules/.bin/eslint src/runtime src/renderer --max-warnings=0
node_modules/.bin/prettier --check src/runtime src/renderer
```

The focused suite currently has 41 passing tests: all twelve canonical positive fixtures, complete aggregates beyond page limits, action/receipt/policy semantics, cursor and timestamp/DST boundaries, command retention/remount recovery, storage failures, late reads, private detail invalidation, manifest/transport guards, large full-engine records, JSON hook rejection, timers, editor values and appearance/layout helpers. These are local source/helper/controller tests. They do not prove mounted view interactions, native builds, a durable host store, deployed full-engine behavior, provider jobs, media delivery, reminder delivery or realtime. The whole migration remains governed by `docs/FULL_MIGRATION.md`.
