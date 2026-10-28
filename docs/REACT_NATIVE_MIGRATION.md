# React Native migration status

The primary frontend is `apps/mobile`, built with React Native, Expo, and TypeScript. Appwrite Functions are the trusted backend; the deployed Function is Dart. Tinkerloom now has a saved builder and live-record slice, while the full AppNest feature set remains a migration reference.

## Implemented

- Native and browser Appwrite SDK adapters with validated public configuration and safe error messages.
- Account sign-up, sign-in, session restoration, sign-out, and account-change response fencing.
- Owner-only workspace/app creation and listing, plus saved app retrieval through authenticated Function operations.
- Notes, Tasks, and Reading templates for both isolated previews and saved drafts. Template sample records remain local.
- A saved draft builder for title, description, field labels, choice options, and optional field additions. Definitions support 1–10 fields of type `text`, `longText`, `boolean`, or `choice`, with a required text primary field and bounded JSON.
- Explicit review and publication of the exact saved draft revision. Compatibility checks protect existing records from destructive schema changes.
- Published record creation, cursor-based paginated listing, and editing with server-side value validation, definition revisions, and record revisions.
- Transactional operation receipts and shared app guards for supported mutations. Changed-payload receipt reuse, stale writes, and competing revisions are rejected. Exact command replay returns the original stored response.
- Explicit retry after an unconfirmed save, preserving the original operation ID, input, and expected versions. Unsaved drafts and pending commands survive navigation in the current signed-in app session, including refresh without silently rebasing unsaved edits; they are not durable across reload/process termination.
- React Native layouts with safe areas, keyboard-aware forms, accessible labels, and responsive web/tablet views. These are implementation details rather than full accessibility acceptance.

## Appwrite development deployment

The owner-authorized Appwrite Free development setup recorded on October 28, 2026 is:

| Setting                    | Recorded value                                                     |
| -------------------------- | ------------------------------------------------------------------ |
| Region/API                 | SFO — `https://sfo.cloud.appwrite.io/v1`                           |
| Project                    | `6ae1928a003a65851e95`                                             |
| TablesDB database          | `tinkerloom`                                                       |
| Function                   | `tinkerloom-core`                                                  |
| Active deployment          | `6ae2259d95aa17a2f1a2`                                             |
| Deployment archive SHA-256 | `3b55fac16f249e8a3409373702d2ba556f9d9eb9276542452fd11b1b7e6a1946` |

Use web hostname `localhost` and origin `http://localhost:8426` for local setup. The Free project's three platform registrations cover web, Android, and Apple, with native identifier `com.tinkerloom.app`. These identifiers are public client configuration, not credentials. No admin key is required by the client or the live smoke script.

The deployment receipt identifies the uploaded backend archive. It does not imply that later documentation/client-only changes were redeployed. [Dated evidence](evidence/2026-10-28/README.md) preserves the live reports and their original target origins.

## Verified layers

The corrected live REST suite completed on **2026-10-28 at 16:48:08 UTC: 26 checks passed, 181 assertions, zero failures or blocked checks**. It used two real synthetic accounts, client sessions, and the deployed Function. Coverage includes owner isolation; anonymous/direct-table denial; saved drafts and exact-revision publication; invalid/stale request rejection; live record creation/editing/query; unchanged command replay after later changes; changed-payload conflicts; concurrent initial drafts and same-revision record writes; and persistence after a fresh session.

The first run is retained unchanged: **25 passed, one failed, 180 assertions**. Its sole failure was the probe expecting only 401/403 for a private direct row read, while Appwrite returned `404 row_not_found`. The corrected probe accepts that exact concealment result only for a workspace already proved to exist through Function creation/listing and rejects response bodies containing row data keys. Four offline classification tests cover this correction. No unrelated live assertion was removed or relaxed.

Both preserved live runs used the then-registered `http://127.0.0.1:8426` origin in a Node REST cookie jar. Subsequent local setup uses `localhost` to share one web registration. The receipts remain unchanged; they do not prove browser cookie/CORS behavior at the new origin.

A [separate manual browser flow](evidence/2026-10-28/browser-qa.md) began at `http://127.0.0.1:8426` while that hostname was registered. This phase verified actual sign-up, workspace/app creation, template title/label customization, draft 1 save/review/publication, and live record creation/editing. After replacing the redundant IP-host registration with the final `localhost` setup, adding optional boolean “Keep for later” at `http://localhost:8426` produced draft/published version 2 while preserving the existing record. Its edited values and boolean remained visible after a full route reload and after sign-out/sign-in on localhost. This establishes the browser paths exercised at each origin; it does not establish native-device behavior or full parity.

Local TypeScript, controller/adapter/model tests, and JavaScript platform exports are separate from the live suite. The Dart service checks use an in-memory store and a local HTTP transport, while the real live concurrency probes exercise Appwrite transactions. CI has read-only repository permissions and runs local checks without Appwrite credentials or deployment.

## Remaining migration and acceptance

The TypeScript definition model is an independent bounded subset. Porting the original Dart AppSpec validator/schema, semantic widgets, and renderer still requires parity and fixture compatibility tests. Rich queries/actions/aggregates, the full visual/AI builder, multi-user sharing and grant revocation, capacity allocation, private media, deletion/archival, durable reminders/audit/outbox workers, and device capabilities remain unimplemented.

Existing accounts and records have not been migrated. The retained legacy code and historical AppNest results do not establish acceptance of the new implementation.

Xcode/Gradle compilation, simulator/physical-device interaction, native authentication/session persistence, release signing, full accessibility, performance/load, and production operations remain unverified. The REST smoke suite does not force an actual lost network response, prove durable offline recovery, or establish full feature parity.

The initial Expo dependency tree reports upstream audit advisories in Expo and local-preview tooling. The suggested npm automatic fix downgrades Expo across major versions and was not applied. The local preview server binds only to loopback and disables compression; compatible upstream fixes still need review before production delivery.
