# AppSpec runtime foundation: API version 1

This checkpoint implements the original AppSpec parser, private definition persistence, immutable publication, seven trusted action handlers, typed record projections, complete collection queries, and database-wide aggregates on the private Appwrite row store. It is isolated from the existing bounded Tinkerloom runtime. It does not complete the full migration matrix.

No Appwrite resources, credentials, deployments, or Git state were changed while building this checkpoint. Local results below use a simulated transaction store; actual Cloud transport, capacity contention, authorization, rollback, and latency acceptance remain required.

## Engines and compatibility

Ordinary app summaries now carry `engine: "bounded.v1"` or `engine: "appspec.v1"`. Missing engine on existing stored receipts remains a legacy acknowledgment, not authority to infer new permissions. Existing bounded definitions, civil dates, long text, app/record IDs, commands, and exact receipt responses remain unchanged. The bounded get/save/publish/record APIs reject AppSpec apps with `unsupported_runtime`; a full spec cannot accidentally be interpreted as a flat bounded definition.

AppSpec apps share the same workspace membership, explicit app grants, invitation, role revocation, and owner-only archive services. Workspace membership alone does not reveal an app. Their ordinary shared mutations also commit a control revision, audit entry, and durable outbox event through the same workspace/app guards. Published AppSpec apps are discoverable by currently authorized collaborators; private unpublished candidates stay author-private.

The Function still verifies JWTs through `/account`. All existing and new tables/rows use empty permissions. No direct client table grants or persistent API key are added.

## Definition APIs

Every operation is authenticated. JSON uses objects rather than JSON-in-JSON request strings. IDs are Appwrite strings, not the original PostgreSQL integer IDs. `operationId` is the retained command identity. The operations are deliberately versioned with the `spec.` prefix.

| Operation           | Input after `op`                                                                                                                                       | Response                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `spec.capabilities` | none                                                                                                                                                   | Parser declarations, available action/query handlers, unavailable effect/media status |
| `spec.templates`    | none                                                                                                                                                   | `{ templates: [{ key, name, spec }] }` for the original template catalog              |
| `spec.createApp`    | `id`, `workspaceId`, `name`, `operationId`                                                                                                             | `{ app }` with an empty private/published state                                       |
| `spec.getApp`       | `appId`                                                                                                                                                | `{ app }`                                                                             |
| `spec.saveDraft`    | `appId`, `operationId`, `expectedRevision`, nullable `expectedVersionId`, `spec`                                                                       | `{ app }`                                                                             |
| `spec.review`       | `appId`, `expectedRevision`, `enabledRuleIds`, `activateExistingRecordIds`                                                                             | `{ review }`                                                                          |
| `spec.publish`      | `appId`, `operationId`, `expectedRevision`, nullable `expectedVersionId`, `candidateHash`, `reviewHash`, `enabledRuleIds`, `activateExistingRecordIds` | `{ app }`                                                                             |

The AppSpec app DTO is:

```text
{
  id, workspaceId, name, engine: "appspec.v1", role, archived,
  capabilities: { editDefinition, share, writeRecords, archive, revokeAccess },
  allowedActions: [actionId, ...],
  controlRevision,
  version: null | { id, number, hash, spec },
  draft: null | {
    revision, baseVersionId, candidateHash, publishedVersionId: null | string, spec
  }
}
```

`version.id` is immutable; `version.number` increases per app. The private draft counter is independent. `allowedActions` contains action IDs under the current role/policy, not capability names; it supports create/toolbars even when a collection is empty. The `writeRecords` flag reflects whether any registered action is allowed. The server rechecks the actual action policy on every command regardless of UI flags.

Only the author sees their draft. A member/viewer receives `draft: null`; another builder or the app owner cannot read it. A new private save binds the current immutable publication ID and resets `publishedVersionId` to null. Publication verifies the exact private revision, canonical hash, unchanged publication base, compatibility, and review approval, creates an immutable version, and marks that private candidate consumed. A new command cannot republish a consumed candidate; its original receipt remains replayable. A new save is the explicit rebase/edit step.

Review returns `candidateHash`, `expectedRevision`, `baseVersionId`, `currentVersionId`, `reviewHash`, `changes`, `compatibilityErrors`, and the exact selected arrays. Its hash is the bundled AppSpec `hashJson` of `{ candidateHash, enabledRuleIds: sortedIds, activateExistingRecordIds: sortedIds }`. Unknown/duplicate selections fail. Activation IDs must identify records of the current app. Review is a server validation result; the client must still present it for explicit human publication approval.

## Records and trusted actions

| Operation        | Input after `op`                                                                                                       | Response                                                       |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `spec.execute`   | `appId`, `operationId`, `versionId`, `actionId`, optional `targetRecordId`, optional `expectedRecordRevision`, `input` | `{ outcome: { recordId, revision, message: "Saved" } }`        |
| `spec.getRecord` | `appId`, `versionId`, `recordId`                                                                                       | `{ record, versionId }`                                        |
| `spec.query`     | `appId`, `versionId`, `collectionId`, `query`                                                                          | `{ records, total, nextCursor, versionId }`                    |
| `spec.summary`   | same app/version/collection/query plus `groupFieldId`                                                                  | `{ total, groups: { choice: count }, versionId }`              |
| `spec.aggregate` | same app/version/collection/query plus `aggregate`                                                                     | `{ total, value, groups: [{ key, count, value }], versionId }` |

A runtime record is `{ id, collectionId, data, revision, writtenUnderVersionId, capacity, allocated, claimed, allowedActions }`. Capacity/allocation are nullable integers, claimed is a boolean, and allowed actions are action IDs. Creating allocates a server record ID inside the transaction; a retained operation ID resolves a lost response without creating a second record.

All seven original handlers are implemented:

| Capability               | Input and invariant                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `records.create.v1`      | `{ data, capacity? }`; typed normalization, current member references, initial workflow state, builder-only capacity-backed create |
| `records.patch.v1`       | `{ data: patch }`; exact record revision and full normalization; workflow/assignment fields cannot use generic patch input         |
| `workflow.transition.v1` | `{ value }`; only a declared transition from the stored current state                                                              |
| `assignment.assign.v1`   | `{ value }`; a current eligible same-app member, or null for an optional assignment                                                |
| `capacity.configure.v1`  | `{ capacity }`; owner/builder, integer 0–10,000, never below current allocation                                                    |
| `capacity.claim.v1`      | `{}`; one actor/pool identity, no allocation for repeated active claims, reject exhausted capacity                                 |
| `capacity.release.v1`    | `{}`; release only the caller's active claim, repeated releases do not decrement twice                                             |

Personal-tracker members are read-only. Group-workflow members may create, patch ordinary fields, assign, and perform approved transitions. Group-capacity members may claim/release only. Viewers never mutate. Builders/owners retain approved business actions. Unchanged revoked assignees remain historical references during unrelated edits; creates, changed references, and explicit assignment validate current membership and grants again.

Record changes, typed projections, pool/claim counters, receipt, audit, outbox, and app control revision commit atomically. Projection rows have stable record/field identities, reset every typed column, and use `present: false` for absence. This replaces SQL projection delete/reinsert without treating null as a present value. A forty-field create uses fewer than the Free plan's 100 staged-operation limit in this design; real Cloud operation/latency acceptance is still separate.

A current role is reauthorized before every receipt read and again after hydration, including conflict recovery. Historical action/version lookup authorizes the original action under the current role; new commands must use the active version. Matching receipts survive publication and archive. A revoked actor or a role that no longer permits that action cannot use an old receipt to regain access.

## Complete query and aggregate semantics

`query` uses the bundled `RecordQuery`: up to eight filters, two sorts, and 1–100 returned rows. Operators are `eq`, `in`, `contains`, `gte`, `lte`, and `lt`, with field/type validation. Contains is case-insensitive text; null is equality-only; membership lists cannot contain null. Null sort values stay last in both directions, followed by deterministic record-ID tie-breaking.

Cursors bind app, immutable version, collection, normalized filters and sort. They identify an anchor in the current authorized matching result. Query changes invalidate the cursor; an anchor that no longer matches gives a revision conflict instead of silently restarting. Page size does not change query identity.

The first Appwrite query adapter reads complete paginated record metadata and the typed projections needed for filters/sorts/metrics, then hydrates only the requested record page. Totals and aggregates include every matching record, even beyond the first Appwrite/backend/client page. Summary choices include zero counts; an unset choice contributes to total but not a named summary group. Aggregate choice groups include an unset group with key `""` when present. Missing numeric values do not enter averages; empty averages are null, and empty count/sum are zero.

Date buckets use explicitly supplied, ordered, nonoverlapping UTC intervals, up to 366. Each interval is inclusive at start and exclusive at end. The backend never substitutes the Cloud machine's local day. The client resolves each local midnight independently, including 23/25-hour DST days.

This implementation is complete but uses linear projection-page scans per queried field and sequential page hydration. Shared workspace/app read guards make a concurrent supported mutation conflict at commit rather than return a mixed snapshot. It is a correctness foundation, not indexed-query throughput proof. Actual synchronous Cloud timeout/latency measurements and further query planning are required before declaring the migration's performance/scale gates complete.

## Parser and transport boundaries

The bundled Dart parser/hash/compatibility engine is used directly. Existing valid canonical fixture hashes remain unchanged. Two intended invalid-input boundaries are hardened: timestamp civil rollover is rejected consistently with the RN validator, and integer/number magnitudes use explicit comparisons rather than an overflowing minimum-integer `abs()`.

Timestamps require complete date/time seconds, an explicit uppercase `Z` or `±HH:MM` offset, and optional 1–6 fraction digits. Gregorian fields, hours/minutes/seconds and offset ranges are validated before UTC normalization. Valid signed years, offsets and microseconds retain Dart canonical formatting. Aggregate bucket boundaries additionally require `Z` and use the same strict instant validation. Existing bounded civil dates remain a separate timezone-free type. The `spec_values.timestampValue` projection is a canonical `varchar(64)`, not an Appwrite datetime column: the upstream [datetime codec](https://github.com/utopia-php/database/blob/main/src/Database/DateTime.php) formats milliseconds and the [SQL adapter](https://github.com/utopia-php/database/blob/main/src/Database/Adapter/SQL.php) uses `DATETIME(3)`. Queries already compare parsed instants in Dart, so retaining lossless canonical strings preserves signed years and microsecond equality/ranges without relying on SQL datetime precision or year range.

The parser definition bound remains 128 KiB. Bounded operations retain their earlier 64 KiB request, 32 KiB canonical command, and 64 KiB receipt limits. New `spec.*` operations have explicit local ceilings of 6 MiB encoded request/record and 8 MiB response/receipt; the private REST adapter bounds row transport at 32 MiB. An oversized response fails explicitly, so callers can request a smaller page. These local ceilings do not establish Appwrite Free Cloud gateway/runtime support. Rejected inputs leave definitions/data unchanged, but actual gateway/body/timeout probes remain required.

## Additive schema

`schema.json` is the exact descriptive provisioning contract: seventeen private tables total. Existing apps gain optional `engine`, `specVersionId`, `specVersionNumber`, and `controlRevision`; bounded rows retain their defaults and IDs. Eight new tables are `spec_drafts`, `spec_versions`, `spec_records`, `spec_values`, `spec_pools`, `spec_claims`, `audit`, and `outbox`. JSON/text fields use off-page mediumtext; scalar projections are typed. Unique indexes protect author drafts, per-app version numbers, record/field projections, record/behavior pools, and pool/actor claims. Service checks validate repeated tenant/parent IDs on every path.

The outbox stores durable event planning/invalidation state; nothing marks an effect delivered. AI generation jobs/providers, reminder enrollment/reconciliation/delivery/inbox/run state, private-media validation/storage/cleanup, version-history UI/APIs, remix, and continued author-draft discovery remain unfinished migration work. They remain in scope. Parser acceptance is never advertised as an available worker, storage implementation, or renderer. Until those handlers are installed, nonempty reminder approval or non-null private-media references fail definitively with `capability_unavailable` before commit.

## Verification checkpoint

```sh
dart analyze lib test
dart format --output=none --set-exit-if-changed lib test
dart run test/service_check.dart
cd packages/appnest_spec
dart analyze lib test
dart test
```

Seventy-one backend groups pass: all previous fifty-one bounded/collaboration checks plus twenty full-engine groups. The new checks cover every original template, immutable/private publication and review, role/protected-field semantics, repeat-safe capacity operations, twenty contended final-place transactions, rollback and lost-response recovery, 115-row ranked queries, 105-row global summaries/aggregates, stale cursors, DST intervals, strict timestamp/number boundaries, cross-tenant/version rejection, failed effects, large definitions/records, and exact large archive receipts. The local HTTP transport probe also asserts Appwrite metadata-select encoding. The retained AppSpec package's 87 tests pass, including canonical golden hashes.

These are simulated-store and local HTTP/parser results. They do not establish a deployed engine, actual Cloud contention/rollback, Free gateway payload support, provider/media/reminder execution, renderer integration, native builds or device behavior, or completion of `docs/FULL_MIGRATION.md`.
