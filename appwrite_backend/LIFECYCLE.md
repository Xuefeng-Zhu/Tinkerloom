# App lifecycle and discovery API

This additive checkpoint builds on `SPEC_ENGINE.md`. It keeps the existing bounded `listApps`, draft, record, publication and receipt APIs unchanged. New operations use the `spec.` namespace but explicitly distinguish full AppSpec and bounded apps where the host needs a mixed launcher.

| Operation           | Input after `op`                                                                           | Response                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| `spec.appAccess`    | `appId`                                                                                    | `{ app: AppSummary }` with common identity/role/engine/archive/capabilities only |
| `spec.launcher`     | `workspaceId`, optional `cursor`, optional `limit` 1–50 (default20), optional `pinnedOnly` | `{ apps: [LauncherApp], nextCursor }`                                            |
| `spec.listDrafts`   | `workspaceId`, optional `cursor`, optional `limit` 1–50                                    | `{ drafts: [PrivateDraftSummary], nextCursor }`                                  |
| `spec.listVersions` | `appId`, optional `beforeNumber`, optional `limit` 1–50                                    | `{ versions: [VersionSummary], currentVersionId, nextBeforeNumber }`             |
| `spec.getVersion`   | `appId`, `versionId`                                                                       | `{ version: VersionSummary + {spec}, currentVersionId }`                         |
| `spec.instantiate`  | new `id`, `workspaceId`, `templateKey`, `operationId`                                      | `{ app }`, with independent immutable version1 and no records/effects            |
| `spec.remix`        | new `id`, destination `workspaceId`, `sourceAppId`, exact `sourceVersionId`, `operationId` | `{ app }`, with independent immutable version1, structure only                   |
| `spec.setPinned`    | `appId`, `pinned` boolean, `expectedRevision`, `operationId`                               | `{ shortcut: {appId, pinned, revision} }`                                        |

Every operation is authenticated through the existing Function JWT/account path. App access requires current workspace membership and ownership or an explicit current app grant. No new client table permissions, administrative keys, external service or paid dependency is introduced.

## Mixed launcher and private discovery

`spec.appAccess` is a small sharing/control-plane read. It selects app metadata, rechecks current access, and commits a workspace guard. It never reads either private draft table or selects legacy app candidate columns. Full AppSpec `writeRecords` is computed from the current published policy/actions; an unpublished full shell has no writable actions. It returns no definitions, candidates, job contents or private author state.

`LauncherApp` contains common `AppSummary` fields (`id`, `workspaceId`, `name`, `engine`, `role`, `archived`, `capabilities`), actor-private `pinned` and `pinRevision`, UTC-normalized Appwrite `$createdAt` as `createdAt`, complete `recordCount` and `availablePlaces`, and nullable `draft`. A full app additionally has actual policy-derived `allowedActions` and nullable `version: VersionSummary`. A bounded app has `version: null` and its existing `publishedRevision`; no immutable version identity is invented for legacy data.

`VersionSummary` is `{ id, number, hash, name, theme, icon, publisherId, createdAt }`. It never includes a private draft or full spec. `spec.getVersion` adds the authorized immutable published `spec`. Only that separate endpoint returns historical definition content. Metadata instants may arrive from Appwrite with `+00:00` and are normalized to UTC. Missing creation metadata in simulated/legacy fixtures is returned as null and sorts last; a timestamp is never fabricated. Real Appwrite rows supply `$createdAt`.

Launcher order is newest-created first, with deterministic descending ID tie breaking. Counts scan every applicable metadata/pool page before returning the selected app page. Full record totals exclude soft-deleted rows; available places sum capacity minus allocation only for live records. Bounded record totals retain the original app/tenant owner scope and available places are zero because that engine has no capacity pools. These are complete collection values rather than loaded-row counts. The adapter remains a linear correctness foundation; actual synchronous Cloud latency/scale limits require separate measurement.

Each private draft summary is discriminated by `engine` and is returned only to its author with current builder/owner access. Archived apps, consumed/published candidates and demoted/revoked authors are excluded. Full summaries carry `{ appId, workspaceId, name, revision, candidateHash, baseVersionId, currentVersionId, stale, updatedAt }`. Bounded summaries retain `{ appId, workspaceId, name, revision, candidateRevision, basePublishedRevision, currentPublishedRevision, stale, updatedAt }`. Unadopted owner-only bounded v1 candidates remain discoverable. No other author's candidate, prompt or job is exposed. Generation-job recovery remains a separate worker/client contract.

Catalog reads stage one workspace guard before loading current app/grant/shortcut/draft metadata. Every supported mutation in that workspace stages the same guard. A concurrent authority/publication/data change therefore conflicts at commit rather than returning a mixed private catalog or inconsistent count. This avoids staging more than the Free plan's100 operations when a workspace contains100 apps. Cursors bind the authenticated actor, workspace, catalog kind and pin filter; they anchor in the current authorized result. Removed/unpinned/consumed anchors yield a revision conflict for an explicit refresh.

## Structure creation and personal shortcuts

Explicit Instantiate/Remix preserves the original `Apps.create` workflow: it creates an immediately usable immutable published structure, an empty data instance and a creator shortcut in one transaction. Remix binds the exact current source version, destination workspace, new app ID and retained operation ID. It strips private static image IDs using the original `Media.withoutAssets` rule. It copies no records, projections, pool allocations/claims, grants, invitations, private drafts, jobs, notifications or automation approvals. Template automation requests remain definition requests; empty approval/enrollment arrays accompany the structure event. They never enable effects.

Source and destination workspace guards plus the source app guard serialize remix against publication/revocation/quota changes. The new app, immutable version, shortcut, receipt, audit and outbox commit together. A fresh stale-source request fails; an exact successful receipt remains the original outcome after later source publication/archive. Receipt recovery reauthorizes current source and destination ownership/membership again, including after hydration. A revoked source reader cannot recover that operation, while an already-created independent copy remains owned by its creator.

`spec.setPinned` works for both engines and all current readers, including authorized archived-app readers. Pin state belongs only to the actor. Unpin changes the shortcut only; it never deletes records, structure, access or effects. Its revision check and exact receipt are atomic with the workspace/app guards. The original implementation treated pinning as private preference state, so it emits no shared business audit/outbox or effect-enrollment event. This avoids exposing one reader's bookmark choices to collaborators. Ordinary template/remix business creation still emits both audit and outbox.

History is read only. It lists immutable publications by number and rechecks current app authorization on every page/get. Private candidates do not become historical versions. Viewing a definition does not restore records, undo delivered effects, reactivate old approvals or grant private asset access. Publication of a new edited candidate continues to use normal compatibility and explicit review/publish rules.

## Provisioning and integration

The base schema adds one private `shortcuts` table, optional canonical `spec_drafts.updatedAt`, `author_workspace` indexes on both draft tables, and `actor_workspace` on grants/shortcuts. The manifest preserves lossless `spec_values.timestampValue: varchar(64)` and Appwrite bulk `numberValue: double`. Merge schema entries by table/column/index identity with the worker schema; do not replace another checkpoint's newly added tables. Every table keeps row security and empty permissions.

Source merge points are `lib/service.dart` (one part), `lib/spec_runtime.dart` (dispatch branches and saved-draft metadata), new `lib/spec_lifecycle.dart`, schema additions, `test/service_check.dart` (one import/call), and new `test/lifecycle_check.dart`. Root should merge those small existing-file hunks with worker changes, not overwrite an evolved service/runtime file.

## Local verification and pending evidence

```sh
dart analyze lib test
dart format --output=none --set-exit-if-changed lib test
dart run test/service_check.dart
```

The new suite has 22 passing lifecycle groups: all twelve templates; exact and concurrent creation retries; private structure/assets/data isolation; source/destination authority and revoked-receipt races; quota/rollback/unknown commit recovery; personal pin policy/revisions; complete filtered catalogs; author-private/consumed/stale/legacy draft discovery; guarded catalog races; immutable history; UTC metadata order; mixed-engine routing; complete101-row/pool counts; metadata-only sharing reads; and provider schema spellings.

All 93 combined backend groups pass locally on Dart 3.13.0, with analysis and formatter checks passing. The intended Cloud SDK is Dart 3.11; that exact SDK build remains a separate integration check. These use the simulated store (including focused optimistic races) and source contracts. They do not establish a provisioned/deployed lifecycle API, actual Appwrite contention/guard visibility, Cloud latency/body limits, mounted launcher/history/remix/native flows, worker execution or completion of the whole migration matrix. Existing failed Cloud receipts must remain preserved when those layers are tested.
