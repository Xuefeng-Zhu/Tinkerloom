# Appwrite owner-only builder and records

This is the trusted owner-only builder and records backend for Tinkerloom: workspaces and apps, saved declarative drafts, exact-revision publication, and published live records. Its bounded React Native definition supports `text`, `longText`, `boolean`, `choice`, `number`, and civil `date` fields, plus optional list, table, or agenda presentation. It is not the full AppNest AppSpec/renderer port. Sharing, role revocation, capacity allocation, private media, AI, deletion/archival, reminders, and audit/outbox workers remain to be migrated. Existing accounts and data are not automatically transferred.

The Function verifies the invoking user's JWT against Appwrite's `/account` endpoint. Its ephemeral execution key stays inside the Function. Every app operation checks the verified owner and the owning workspace; all data tables deny direct client access. The Function execute permission must be authenticated users only. No Appwrite credentials belong in Flutter, React Native, Git, documentation, or logs.

## Required database schema

`schema.json` records the exact table/column/index contract. It is descriptive provisioning input, not a command that runs automatically. Provision a **serverless** database with ID `tinkerloom`, or use another ID via `PLATFORM_DATABASE_ID`. Every table has row security enabled and `permissions: []`; all created rows also have `permissions: []`.

- `workspaces`: required varchar `ownerId` (36), `name` (128); owner index.
- `apps`: required varchar `ownerId` (36), `workspaceId` (36), `name` (128); optional `guard` varchar 36, optional/default-zero integer `draftRevision` and `publishedRevision`; optional mediumtext `draftJson` and `publishedJson`; owner/workspace composite index.
- `records`: required varchar `ownerId` (36), `appId` (36); required integer `revision` and `definitionRevision` with minimum 1; required mediumtext `valuesJson`; owner/app composite index.
- `receipts`: required varchar `actorId` (36), `appId` (36); required mediumtext `requestJson` and `responseJson`. Lookup is by Appwrite row ID, the client's stable operation ID.

Use off-page `mediumtext` for JSON. Appwrite's `text` maximum is 16,383 characters, while this service permits 16,384 encoded UTF-8 bytes for definitions/values. Varchar JSON columns would also consume the database's inline row-width budget. Service validation bounds definitions and values to 16 KiB, requests to 32 KiB canonical JSON, receipt responses to 64 KiB, and record pages to 10 rows.

Add the optional/default app columns non-destructively for an existing initial-slice database. Existing app shells are treated as draftRevision 0/publishedRevision 0 with null definitions. Do not recreate tables or delete existing rows to add this slice.

## Function configuration

Create a Dart Function, suggested ID `tinkerloom-core`, with this directory as root and `lib/main.dart` as entrypoint. Use a Dart runtime supported by your instance; the source requires Dart 3.5 or later and is compatible with the selected Cloud Dart 3.11 runtime. Configure `PLATFORM_DATABASE_ID` with the database ID. Grant **`rows.read` and `rows.write` only**. The TablesDB transaction create/commit handlers use the same `rows.write` scope; there are no extra `transactions.*` scopes needed by this implementation. Appwrite supplies `APPWRITE_FUNCTION_API_ENDPOINT`, `APPWRITE_FUNCTION_PROJECT_ID`, the scoped ephemeral key, and the invoking user's JWT.

Register native platform IDs matching `apps/mobile/app.json` and the actual web hostname. The React Native client calls this Function synchronously with POST and JSON bodies. The Function accepts at most 64 KiB per request. Provisioning/deployment and service acceptance are separate from the presence of this source.

## Operations

Initial operations remain `createWorkspace` (`id`,`name`), `listWorkspaces`, `createApp` (`id`,`workspaceId`,`name`), and `listApps` (`workspaceId`). Creation IDs must remain identical while retrying an uncertain initial creation. These initial operations retain their original row-identity retry behavior.

The builder/runtime operations are:

| Operation     | Input after `op`                                                                      | Response                                  |
| ------------- | ------------------------------------------------------------------------------------- | ----------------------------------------- |
| `getApp`      | `appId`                                                                               | `{app}`                                   |
| `saveDraft`   | `appId`, `operationId`, `expectedRevision`, `definition`                              | `{app}`                                   |
| `publishApp`  | `appId`, `operationId`, `expectedRevision`                                            | `{app}`                                   |
| `listRecords` | `appId`, `definitionRevision`, optional `afterId`                                     | `{records,definitionRevision,nextCursor}` |
| `saveRecord`  | `appId`, `id`, `operationId`, `expectedRevision`, `definitionRevision`, full `values` | `{record,definitionRevision}`             |

An app response contains `id`, `workspaceId`, `name`, `draftRevision`, `publishedRevision`, nullable `definition`, and nullable `publishedDefinition`. A record contains `id`, `revision`, and normalized `values`. `expectedRevision` in `saveDraft`/`publishApp` refers to the draft revision being edited/reviewed. Publishing sets the published revision to that exact draft revision. `saveRecord` uses expectedRevision 0 to create; edits require the stored record revision. `definitionRevision` must match the current published revision. Cursor IDs must belong to the authorized app. Lists are deterministically ordered by row ID and return ten rows with an optional next cursor.

Example definition:

```json
{
  "title": "Tasks",
  "description": "A shared little list",
  "primaryFieldId": "title",
  "fields": [
    { "id": "title", "label": "Task", "kind": "text", "required": true },
    { "id": "done", "label": "Completed", "kind": "boolean" }
  ]
}
```

This slice is still owner-only despite the example's intended future collaboration. Each definition has 1–10 fields with unique stable IDs, a required text primary field, title up to 80 characters, description up to 240, labels up to 64, choices up to 12 unique options, short text up to 200, and long text up to 4000. JSON byte bounds apply in addition to field bounds.

`number` values must be actual finite JSON numbers between −1e15 and +1e15 inclusive. Zero is valid; numeric strings, booleans, non-finite values, and values beyond the bound are rejected. `date` values must be exact civil `YYYY-MM-DD` strings with a Gregorian year from 0001 through 9999. Leap years and month lengths are checked directly; whitespace, timestamps, timezone suffixes, and rollover dates are rejected. Civil dates are not converted into UTC instants. Missing or empty optional number/date values normalize to `""`; required values cannot be empty.

An optional `view` has `kind` equal to `list`, `table`, or `agenda`. Agenda requires `dateFieldId` naming an existing date field; the field may itself be optional so an undated group can be shown. List and table reject `dateFieldId`. Unknown view properties are rejected. An absent view remains absent in the canonical definition, preserving the request identity and responses of legacy receipts.

Publication may rename labels/title/description, add optional fields, add choice options, or change presentation views. Removing fields/options, changing types or requiredness, adding required fields, or changing the primary ID is rejected to preserve live records. Table and agenda presentation use only the records loaded by the client; they do not establish complete calendar coverage or whole-database totals. See [rich records](../docs/RICH_RECORDS.md) for the client and validation contract.

## Transactions and recovery

A mutation first verifies app ownership, checks for a stored receipt, creates an Appwrite transaction, and **stages a fresh common app guard before reading the versions it will validate**. Draft/published/record changes and the matching command receipt are staged and committed atomically. Appwrite checks affected rows for changes since staging. A conflicting shared guard makes concurrent supported writes fail rather than overwrite one another. The Function does not blindly retry mutations.

An exact retry with the same actor/app/operation ID and input returns the original committed response, even after later edits or publication. Reusing that ID for different input returns `operation_conflict`. If a commit response is lost, the outcome remains unknown; the client retains the original command and resolves it through an explicit retry. Transaction conflicts are retryable with that same command. Any failed staging path attempts rollback; if commit had already succeeded, rollback cannot undo it and the stored receipt remains authoritative.

There is no business audit/outbox yet, so this does not establish the original AppNest reminder or multi-user guarantees. The app guard is an Appwrite optimistic-transaction strategy, not a claim of PostgreSQL row-lock equivalence. The preserved live smoke reports cover concurrent owner writes against the selected development instance; they do not establish production load or distributed-worker acceptance.

## Verification

```sh
dart analyze lib test
dart format --output=none --set-exit-if-changed lib test
dart run test/service_check.dart
```

The 22 backend check groups cover owner isolation, retained receipts, exact publication, value/record/schema revisions, simulated concurrent writers, atomic rollback, committed-but-unconfirmed recovery, optional schema evolution, cursor paging, bounded input, and the actual HTTP request encoding against a local fake HTTP server. They include 52 shared contract fixture cases: 18 definition cases and 34 value cases, consumed by Dart and TypeScript. The shared cases include U+0085 trimming for titles, field labels, choice options, and text/long-text/choice values while preserving descriptions. Additional direct checks reject non-finite numbers, verify Gregorian century boundaries, preserve absent-view canonical definitions, and exercise rich publication without changing legacy records or receipts. The optimistic in-memory store models only the documented staging contract; it is not real Appwrite proof.

The [rich-records live smoke](../docs/evidence/2026-10-28/appwrite-smoke-rich-records.json) passed 33 checks and 305 assertions against the free development project. The later [Unicode normalization smoke](../docs/evidence/2026-10-28/appwrite-smoke-rich-unicode.json) retained that suite and passed 34 checks and 314 assertions, including real U+0085 record normalization and exact replay. It retains the initial owner/session/permission/concurrency assertions and adds rich field/view publication, typed record persistence/replay, invalid input preservation, and cross-account denial checks. The React Native client separately passed 54 tests, TypeScript, lint, and formatting after the Unicode acknowledgment fix. The full client verification, including web/iOS/Android JavaScript exports, passed again after the Unicode fix; native builds and device behavior remain separate checks. A separate [rich browser receipt](../docs/evidence/2026-10-28/rich-browser-qa.md) records the exercised UI and pagination checks; these are not claims made by the REST report. See the [evidence index](../docs/evidence/2026-10-28/README.md) for deployment/archive identity and preserved earlier reports.

References: [TablesDB transactions](https://appwrite.io/docs/products/databases/tablesdb/transactions), [explicit text types](https://appwrite.io/blog/post/new-string-types), [Function development](https://appwrite.io/docs/products/functions/develop), [TablesDB transaction create scope](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Databases/Http/TablesDB/Transactions/Create.php), [commit scope](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Databases/Http/TablesDB/Transactions/Update.php).
