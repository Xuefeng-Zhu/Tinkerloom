# Offline import preflight and simulation

This tool is a concrete preparation step for [G07/G08](FULL_MIGRATION.md), not a data migration or cutover receipt. It reads explicit local files, validates an operator-prepared normalized legacy export, requires account/workspace mappings, plans deterministic destination rows, and simulates resumable batches in memory. It never connects to AppNest, Appwrite, a database, storage, authentication, or an AI provider. It has no apply mode, admin-key option, environment credential loading, or production `RowStore` adapter. No original data was read or modified to test this implementation.

`validForSimulation: true` means the submitted envelope can enter this simulator. Every report still says `cutoverReady: false` and `liveWrites: 0`. The export's consistent-snapshot flag and source-archive fingerprint are operator attestations, not proof that a real database export is complete. Local hashes detect input/progress changes; they are not signatures or authentication.

## Run locally

Use Dart 3.11 or later from `appwrite_backend/`. Dependencies are the existing locked backend dependencies; the planner itself uses only the pure `appnest_spec` package and `crypto`.

```sh
dart --suppress-analytics run tool/import/main.dart \
  --source test/fixtures/import/source.synthetic.json \
  --mapping test/fixtures/import/mapping.synthetic.json \
  --report /private/tmp/tinkerloom-import-report-1.json
```

Generate a local identity worksheet before filling an actual mapping:

```sh
dart --suppress-analytics run tool/import/main.dart \
  --source /private/path/normalized-export.json \
  --worksheet /private/path/new-identity-worksheet.json
```

The worksheet includes all declared actor references, typed member values, member query predicates, and workspace IDs. Destination values are deliberately null. A worksheet is invalid as an identity map until the operator replaces every null with an explicit identity and target. The tool never creates an account, copies a password, or guesses that similarly named/email accounts are the same person. Existing-account ownership and recovery require a separate authorized procedure.

Simulate seven operations, then resume with the exact same input bytes:

```sh
dart --suppress-analytics run tool/import/main.dart \
  --source test/fixtures/import/source.synthetic.json \
  --mapping test/fixtures/import/mapping.synthetic.json \
  --simulate 7 --ledger-out /private/tmp/tinkerloom-import-ledger-1.json \
  --report /private/tmp/tinkerloom-import-report-2.json

dart --suppress-analytics run tool/import/main.dart \
  --source test/fixtures/import/source.synthetic.json \
  --mapping test/fixtures/import/mapping.synthetic.json \
  --resume /private/tmp/tinkerloom-import-ledger-1.json \
  --simulate 10000 --ledger-out /private/tmp/tinkerloom-import-ledger-2.json \
  --report /private/tmp/tinkerloom-import-report-3.json
```

All output paths must be new. Existing files, including failed reports and unknown ledgers, are never overwritten. Choose a private directory with restrictive permissions for real identity worksheets/reports. This is not a secure credential vault. Stdout contains bounded counts, SHA-256 fingerprints, fixed issue codes, and simulation totals. Reports include old/destination IDs, dependencies, source metadata annotations, and quarantine fingerprints; row payloads, app names, record values, prompts, receipt keys, and raw outcomes are omitted. Source files and in-memory row payloads can contain private application data and must remain private. The CLI does not print local input paths on file errors.

Exit codes: `0` valid local preflight/simulation, `2` required unresolved issues, `64` invalid arguments, `65` malformed/unsafe input or ledger, and `74` local file failure. An invalid document fails at the first structural/reference error with a fixed code and field path. A valid document can report multiple required reconciliation issues. A worksheet reports all unresolved identities before a mapping is supplied. `--simulate` fails closed when required issues remain; run a dry run without that flag to retain the full issue report.

## Versioned normalized export

`tool/import/engine.dart` and `format.dart` are the enforced contract. The normalized fields were compared with the retained AppNest `appnest_server/lib/src/models/*.spy.yaml` models and hand-authored runtime/apps/automation/media modules, alongside its README, ARCHITECTURE, and REQUIREMENTS. Raw SQL JSONB, generated transport classes, and old receipt hashes are not interchangeable with this contract. The checked-in `test/fixtures/import/*.synthetic.json` pair is a complete example containing three policies, four immutable versions, a private candidate, a revoked assignee, a capacity pool/claim, and quarantined receipt/effect history. `make_synthetic_fixture.dart` regenerates only those synthetic files; it has no database exporter.

The root envelope has exactly these fields:

| Field                            | Contract                                                                                                                                                                                         |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `format`                         | `appnest.offline-export.v1`                                                                                                                                                                      |
| `sourceInstanceId`, `snapshotId` | Explicit stable source/snapshot identifiers; never infer from a project name.                                                                                                                    |
| `exportedAt`                     | Canonical UTC metadata timestamp.                                                                                                                                                                |
| `consistentSnapshot`             | Must be `true`; an authorized external exporter must actually take a consistent snapshot.                                                                                                        |
| `dataEncoding`                   | `serverpod-unwrapped-json.v1`. Entity `data` is the ORM-unwrapped object, not Serverpod's raw JSONB wrapper or a SQL dump.                                                                       |
| `sourceArchive`                  | `{sha256, byteLength}` of a separately retained source archive. The offline planner preserves this attestation through the exact envelope hash; it does not read or verify that archive's bytes. |
| `counts`                         | Exact count for every table below, including zeroes.                                                                                                                                             |
| `tables`                         | Every supported table must be present as an array; unknown tables/fields are rejected.                                                                                                           |

Every legacy relational ID is a canonical **positive decimal string**, bounded by signed PostgreSQL int64. This avoids losing IDs above JavaScript's safe-integer limit. Actor IDs remain original opaque `Session.authenticated.userIdentifier` strings, not numeric user rows or email addresses. Revisions/counts are bounded JSON integers. Metadata timestamps currently require lossless canonical `YYYY-MM-DDTHH:mm:ss.sssZ` within years 0001–9999. Microsecond, offset, signed-year, or otherwise incompatible **metadata** is explicitly rejected; never round/truncate it to get a pass. A target metadata-preservation strategy is still required for those exports. AppSpec record **field timestamps** use the actual richer AppSpec codec and retain canonical signed years and microseconds as lossless projection strings.

All fields listed for a table are required, including explicit nulls:

| Table             | Fields                                                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `workspaces`      | `id name ownerId personal createdAt`                                                                                                 |
| `memberships`     | `id workspaceId actorId role`                                                                                                        |
| `apps`            | `id workspaceId ownerId name activeVersionId archived controlRevision createdAt`                                                     |
| `grants`          | `id appId workspaceId actorId role revoked`                                                                                          |
| `shortcuts`       | `id appId actorId`                                                                                                                   |
| `versions`        | `id appId workspaceId number specJson candidateHash publisherId createdAt`                                                           |
| `drafts`          | `id appId workspaceId actorId baseVersionId candidateJson candidateHash mutation activeJobId publishedVersionId updatedAt`           |
| `records`         | `id appId workspaceId collectionId data creatorId revision writtenUnderVersionId createdAt updatedAt deleted`                        |
| `pools`           | `id appId workspaceId recordId behaviorId capacity allocated`                                                                        |
| `claims`          | `id appId workspaceId poolId actorId active createdAt updatedAt`                                                                     |
| `receipts`        | `id appId actorId idempotencyKeySha256 requestHash outcomeSha256 recordId revision state`                                            |
| `pendingCommands` | `id appId actorId requestHash state`                                                                                                 |
| `media`           | `id assetId appId workspaceId uploaderId status contentType byteLength storedBytes width height originalRemoved createdAt updatedAt` |
| `mediaReferences` | `id appId assetRowId draftId versionId recordId`                                                                                     |
| `automations`     | `id appId workspaceId ruleId enabled executionActorId ruleSha256`                                                                    |
| `jobs`            | `id appId draftId actorId status mutation contentSha256`                                                                             |
| `history`         | `id appId kind state contentSha256`                                                                                                  |

Receipt rows are redacted normalized archive descriptors, not raw `ActionReceipt` rows. Fingerprint the old key and serialized outcome externally; confirmed outcomes require an existing same-app `recordId` and a revision no later than that record. Unknown outcomes must have null record/revision and remain blocking. Jobs exclude prompts, provider configuration and leases: use a separately retained archive plus a content hash. Actual old generation states are `queued`, `generating`, `validating`, `preview ready`, `stale`, and `failed`; the first three require reconciliation. Actual media `issuing` reservations are retained as unresolved alongside pending/processing/ready/failed/deleting/deleted states.

`history.kind` is `audit`, `notification`, `automationRun`, `outbox`, or `invitationRedacted`. Keep raw source history outside the import envelope and supply its content fingerprint. Nonterminal/unknown history requires reconciliation. Arbitrary history state text is fingerprinted and reported as `unknown`, not echoed. Invitation rows never include token hashes or bearer tokens; redacted metadata can only be archived. Do not export auth/password/session tables, invitation secrets, media upload descriptions/URLs, API keys, provider secrets, or raw service configuration. Unknown top-level/table/row keys are rejected. Business record fields are validated against their declared AppSpec, not scanned with an unreliable secret-name heuristic.

## Explicit destination mapping

The map has exactly `format`, `sourceInstanceId`, `sourceSha256`, `target`, `accounts`, and `workspaces`:

- `format`: `tinkerloom.identity-map.v1`.
- `sourceSha256`: SHA-256 of the **exact UTF-8 source file bytes**. Whitespace changes require a new map binding and invalidate the old resume ledger.
- `target`: `{endpoint, projectId, databaseId, operatorAccountId}`. Endpoint must be an explicit HTTPS `/v1` endpoint with no userinfo, query, or fragment. These values identify a destination; they do not authorize it.
- `accounts`: `{sourceActorId, targetAccountId}` for each referenced principal, including historical revoked assignees/claimants. Duplicate or merged source/target principals are rejected. Unused mappings block preflight to expose accidental map mixing.
- `workspaces`: `{sourceWorkspaceId, targetWorkspaceId, disposition}`. Disposition is `create` or `existing`. Workspace merging is rejected. Existing destinations require an owner assertion and must not be overwritten by the future runner.

The target hash binds endpoint, project, database, and operator account; the exact map hash additionally binds all account/workspace choices. Derived app/record identities use source instance + target scope + source table/ID. Version, draft, membership, grant, shortcut, projection, pool and claim identities use the same natural-ID formulas as the current Function (`v/s/m/g/k/f/p/c` respectively). The report includes an explicit source-to-destination ID map. Original relational IDs cannot be reused across an arbitrary existing target safely; source IDs remain in the report/archive. Existing target collision and authorization checks remain an operational gate.

## Validated plan semantics

The planner uses the real `appnest_spec` parser, canonicalization/hash, compatibility checks and collection normalizer. It verifies every immutable version hash, contiguous version history, same-app latest active version, typed record data under its written version and current compatible definition, and exact declared references. It rejects unknown capabilities, destructive version changes, unsafe integers, rollover timestamps, SQL wrappers, duplicate keys/IDs/natural keys, missing identities and cross-app/workspace substitutions.

Typed member values and static member query predicates are rewritten only through explicit account mappings; arbitrary strings are never replaced. Version hashes are recomputed after typed changes and the source hash remains annotated. A historical revoked assignee remains data, without creating a grant. Every app owner requires workspace membership; active grants require workspace membership and a valid app role. Workspace membership alone never becomes an app grant. Revoked grants and archived apps remain revoked/archived.

Record IDs/revisions/written-version relations and typed query projections are preserved. Current optional fields gain explicit absent projections. Derived old `FieldValue` rows are rebuilt from validated records instead of being trusted/copied. Capacity state is validated against the declared behavior with bounds 0–10000, exactly one pool per capacity record, unique actor claims, exact `allocated == activeClaims`, and same-parent references. Revoked/inactive actors do not silently free existing places. App activation is ordered after all planned app data. **The ordering is not a live transaction/maintenance fence.**

Appwrite has one current candidate per app/author. The most recent source candidate can be planned, but multiple historical author candidates remain archived and block replay until their retention strategy is resolved. Serverpod `mutation` is not Appwrite's candidate `revision`: new candidate revision starts at 1 and original mutation remains annotated. Consumed candidates retain their exact corresponding published version. App creation timestamps/personal-workspace metadata remain report annotations; the future runner must resolve actual launcher ordering and personal-workspace semantics rather than pretending it can restore Appwrite `$createdAt` with a row payload.

Legacy receipts are **never** reinterpreted as Appwrite idempotency receipts: their actor/app scope, request hash and serialized outcome differ, and destination IDs have changed. Confirmed receipts are quarantined fingerprints; unknown/outstanding commands block replay. No command is executed. Old audit/inbox/outbox/job history is fingerprinted for preservation, not fabricated as delivered/new-platform history.

Automation requests remain in immutable definitions, but **no enabled approval, enrollment, automation run, notification, outbox wakeup or worker dispatch row is planned**, even if the source automation was enabled. Review and approve effects separately after cutover; importing old records must not enroll reminders automatically.

All media metadata and exact draft/version/record references are validated, including historical references and same-app ownership. Every media-bearing export is a required unresolved issue: the tool does not fabricate ready assets, quotas, reservations, deterministic storage files or byte transfers. Original opaque asset IDs exceed Appwrite's row-ID limit and require a separate reference rewrite/resanitization plan. Binary checksums, actual decode/reencode/EXIF stripping, quota accounting, late-I/O cleanup, revocation and historical-media retention still need their own approved runner and proof.

The local safety bounds are 32 MiB source, 4 MiB mapping, 5000 total source rows, 50000 expanded planned operations, JSON depth 64, and 1–10000 simulated operations per invocation. Oversize inputs fail explicitly; they are not silently truncated or treated as a complete partial export. Duplicate operation checks use a set and dependency ordering uses a deterministic topological queue. These bounds are tool limits, not provider capacity or Cloud performance claims. Larger real exports require a separately reviewed streaming/snapshot design.

## Resume and unresolved outcomes

A simulation ledger binds exact source SHA, exact map SHA, target SHA and full plan SHA. Each operation carries sequence, operation key, payload SHA and `simulated_confirmed`/`unknown`. Missing/reordered/duplicated/changed operations or a foreign target cannot reuse progress. A restarted simulator reconstructs only confirmed local steps and checks the simulated row count and full-row checksum. Exact duplicate operations converge; conflicting target rows or changed payloads fail without overwrite. An `unknown` entry survives restart and blocks advancement; there is no “mark successful” or auto-replay shortcut.

These are simulated confirmations, not observed Appwrite receipts. The simulator's existing-workspace assertion requires an explicitly seeded in-memory row in tests; the CLI does not assume a real remote workspace exists. A real runner must reconcile uncertain external writes against destination row/receipt state, use maintenance fences and bounded atomic batches, respect Cloud quotas, maintain complete rollback/backup evidence, and require fresh approval. Do not repurpose this simulator ledger as proof that production rows exist.

## Verification and remaining acceptance

```sh
dart --suppress-analytics analyze tool/import test/import_dry_run_test.dart
dart --suppress-analytics format --output=none --set-exit-if-changed tool/import test/import_dry_run_test.dart
dart --suppress-analytics test test/import_dry_run_test.dart
```

Tests use synthetic exports and the in-memory simulator. They include all twelve supported canonical package fixtures, all three policies, typed member rewrites, int64 IDs, exact timestamp projections, capacity/claim invariants, historical media reference sets, real legacy worker states, output sanitization, strict malformed-input cases, partial/restarted batches, unknown outcomes, exact retries, collisions, changed source/mapping/target ledgers, and CLI credential/apply rejection. They do not claim real source export, password migration, storage transfer, native recovery, Appwrite transaction proof, or cutover acceptance.

Still required before G07/G08 can pass: an authorized consistent real export and archive verification, with source writers/workers quiesced and outstanding commands inventoried; complete bounded-engine preservation/conversion policy; explicit account linking/recovery; unresolved timestamp/personal-workspace/history/candidate/media strategies; live target identity/access/collision/quota inventory; reviewed approved write and rollback runners; actual source/destination counts and full-value checksum comparison; restart/uncertain-outcome reconciliation against real target state; verified media visibility/revocation; and explicit effect approvals with no imported-record enrollment. Original AppNest and existing bounded Tinkerloom data must remain preserved throughout. No such writes or cutover are authorized by this tool.
