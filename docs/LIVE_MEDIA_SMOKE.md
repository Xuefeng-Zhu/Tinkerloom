# Live private-media and worker probe

`scripts/live_media_smoke.mjs` is a prepared authenticated REST probe for the Appwrite Free development project. Importing the module performs no request. It has **not been run against Cloud** by its author. Its offline tests and service-generated fixtures are local proof only. The [private-media contract](../appwrite_backend/PRIVATE_MEDIA.md) and [full migration gates](FULL_MIGRATION.md) still require actual deployed receipts.

The probe uses the existing read-only `live_full_transport.mjs` user-cookie transport and HTTP budget, plus the existing full/collaboration DTO and observation helpers. It never supplies an admin API key, persists a password/cookie/token, loads provider credentials, invokes AI/reminder operations, deletes a resource, changes server clocks, or retries an uncertain write. It creates two fresh labeled synthetic QA accounts and one workspace with two isolated apps. The main app receives three synthetic assets: a 5 MiB PNG, a tiny EXIF JPEG, and a second tiny JPEG uploaded by the temporary builder to test that uploader's own receipts after revocation. Accounts/apps/records/assets remain labeled QA; only temporary sessions are signed out.

## Invocation after deployment verification

From the repository root, supply **actual** deployment and archive provenance. Do not reuse example hashes or infer that a commit prefix proves the deployed archive. Node 24 supplies `Headers.getSetCookie()`.

```sh
node --env-file=apps/mobile/.env.local scripts/live_media_smoke.mjs \
  --database-id tinkerloom \
  --bucket-id ACTUAL_PRIVATE_BUCKET_ID \
  --worker-function-id ACTUAL_PRIVATE_WORKER_FUNCTION_ID \
  --core-deployment-id ACTUAL_ACTIVE_CORE_DEPLOYMENT_ID \
  --worker-deployment-id ACTUAL_ACTIVE_WORKER_DEPLOYMENT_ID \
  --source-commit ACTUAL_CORE_SOURCE_COMMIT \
  --source-sha256 ACTUAL_CORE_ARCHIVE_SHA256 \
  --worker-source-commit ACTUAL_WORKER_SOURCE_COMMIT \
  --worker-source-sha256 ACTUAL_WORKER_ARCHIVE_SHA256 \
  --expected-provider none --expected-reminders false
```

Endpoint, project, and core Function can instead be supplied with `--endpoint`, `--project-id`, and `--function-id`; the only environment values read by the probe are their `EXPO_PUBLIC_APPWRITE_*` equivalents. No `.env` is read automatically by the script. Default origin is `http://localhost:8426`, which must be the registered development web platform.

Configuration requires explicit distinct core/private-worker IDs, both deployment IDs, both source commits, both archive SHA-256 values, database ID, bucket ID, and a credential-free HTTPS `/v1` endpoint. API-key/password/JWT/provider/deletion flags and duplicate/unknown arguments are rejected. Core executions must report exactly the configured core deployment. The private worker's configured source/deployment and bucket/database binding remain **operator-supplied attestations**: ready state is indirect evidence of worker processing and does not reveal which private deployment executed it. Console deployment/configuration receipts must accompany a live report.

The default hard cap is **300 HTTP requests**, with six slots reserved for session signout. `--max-http` may lower it to 120–300. This counts client HTTP requests, not internal Appwrite database/storage operations. Core requests have a 45-second timeout (configurable 1–60 seconds). Ready polling defaults to at most 24 successful read-only status calls per asset, 5 seconds apart. `--ready-polls` permits 1–24; `--poll-ms` permits 1000–10000. Polling never retries HTTP errors, transaction conflicts, unknown mutations, or transport loss. Auth is not automatically retried/cooldown-looped; preserve a rate-limit failure and rerun only after resolving it.

A new `output/live-media/<runId>/report.json` is written with exclusive creation and mode 0600. Existing reports are never overwritten. Stdout contains only the sanitized report: fixed status/issue codes, counts, dimensions, hashes and synthetic resource IDs. Raw bodies, base64, input pixels, passwords, email addresses, cookies, invitation/proof tokens and exception strings are excluded and scanned against in-memory private values. Keep failed and blocked reports. Exit 0 means the executed functional checks passed; the optional 16-minute release gate can still be explicitly **pending**. It does not mean the whole migration or resource-performance gate passed.

## Actual probe behavior

1. Build a deterministic **5242880-byte valid still PNG**, with twenty 262144-byte chunks. Its actual source SHA is `58062ab01b2915dadd0ce35d4fd8b9f76e01da93ceba50ecc391a10e04b84580`. It contains 16×8 RGBA pixels, correct PNG CRCs, a deterministic stored-DEFLATE pixel stream, a text marker and a safe ancillary padding chunk. This exercises maximum original-byte transport and metadata stripping, **not worst-case 16MP decode/memory cost**. No declared-length substitute or fake checksum is used.
2. Create/sign in the two accounts and verify `/account` identity. Require the actual core capability response to say private media available, generation/guidance false, and no enabled effects. Read the current Photo Journal template; create a private unpublished saved candidate and a separate same-workspace app.
3. Begin against the author's own candidate. Confirm the exact begin receipt, deterministic asset identity, unchanged quota on replay, changed-payload conflict and upfront charged reservation. Deny nonready reads, cross-actor status and cross-app substitutions.
4. Submit all twenty chunks sequentially. Test out-of-order rejection, incomplete complete, exact acknowledged retry, changed bytes at the same acknowledged offset, and the documented cumulative acknowledgement when an old chunk is retried after later chunks. Complete and replay its exact receipt without repeating unknown work.
5. Poll actual readiness. Only an exact `{error:"transaction_conflict"}` from a completed execution matching the configured deployment with outer 2xx and inner 409 consumes another existing poll slot and the same configured delay (default five seconds). Per-phase and total `readConflicts` are explicit. The 24-read ceiling and HTTP budget do not grow. HTTP uncertainty, other/malformed 409s, `failed`, wrong deployment and timeout remain failures; no mutation is retried and nothing manufactures ready state. Read every chunk of both display and thumbnail. Check identity/variant/offset/next offset, MIME, dimensions, per-chunk SHA, canonical base64, whole SHA and actual final byte count. Also require the Function execution's actual `Cache-Control: private, no-store` header and the typed body cache directive. Decode the entire returned PNG locally, verify all pixels and that padding/text chunks were stripped.
6. Attach the ready image to the saved candidate, perform explicit empty-effect review/publication, create a real record containing it and read it back. Upload the tiny JPEG through the published `editRecord` image-field context with exact record revision. Reusing the first complete operation for this second asset must conflict. The original carries **EXIF orientation 6**, 12×6 pixels; actual sanitizer fixtures expect 6×12 JPEG output, no EXIF marker, and exact full display/thumbnail digests. Read and hash both entire outputs, then attach it through the normal revision-checked record edit.
7. Before sharing, deny cross-actor and cross-app reads. Invite the second user as viewer; confirm visible version/record-backed media and forbidden upload. Upgrade that user to builder; let them perform their own small upload/complete with exact receipts. Confirm another actor cannot complete that upload. Revoke their grant and require their own captured begin/complete receipts, read/status and chunk attempts to be denied by current authority.
8. Against known resources proven through successful broker reads, require direct private bucket/file/table reads and writes to be denied for both users, including the builder. Storage probes use the official `GET`/`PUT` routes and TablesDB uses row `GET`/`PATCH`. File writes repeat the existing `private.bin` name and row writes repeat the known original `inputBytes`; they are not deletion probes. The bucket write repeats the configured ID as its requested name, so an unexpected successful permission breach may change that development bucket's display name and will fail the probe. No permission mutation or destructive write is requested. Storage/table error bodies must contain only error fields; no metadata/rows/files/bytes may leak. Wrong database/project/table/bucket routes do not count as denials. Known existing file/row concealment only accepts the precise not-found type, not arbitrary 404s.
9. Attempt anonymous and ordinary user execution of the private Function; both must receive outer 401/403 authorization rejection. Separately classify the forged proof/reserved-header request: it must receive either outer 401/403 or an exact outer 400 `general_argument_invalid` error-only response whose message identifies reserved `x-appwrite` header validation. That 400 does not count as an authorization denial. Report `publicWorkerDenials`, `forgedWorkerHeaderRejections` and `forgedWorkerPermissionDenials` separately. A 201/created execution, arbitrary 400, leaked execution fields or inner-only authentication rejection fails the gate. The probe never obtains an execution key or real dispatch proof. Public-boundary denial does **not** independently prove a forged proof reached the internal dispatcher; that guard retains its separate backend tests.
10. Inspect actual charged usage after readiness. Source staging may already be physically removed, but bytes must remain charged before the legitimate quiet period. Report `pendingReleaseBytes` and never claim early space release.

The expected ready MIME, limits, chunk contracts, current DTO keys and EXIF reference hashes are checked using a fixture produced by **the real Dart service and image sanitizer over MemoryStore/private in-memory files**. The test fixture does not assert anything about Cloud deployment configuration, Appwrite permissions, scheduling, storage timing or resource limits.

Direct-route method references: [Storage REST](https://appwrite.io/docs/references/cloud/client-rest/storage), [Storage server REST](https://appwrite.io/docs/references/cloud/server-rest/storage), and [TablesDB row permissions](https://appwrite.io/docs/products/databases/tablesdb/rows). They define the routes/permission model; an actual receipt is still required for this project.

## Optional legitimate quiet-period observation

Add `--observe-staging-release` only when a bounded extra observation window is wanted. The probe performs at most twenty extra read-only usage requests, one minute apart, and observes real elapsed wall time. It never changes server clocks or sends cleanup/worker commands. Success requires both zero pending original bytes and exact remaining charged variant bytes after at least sixteen minutes from the **last** observed ready transition. Default execution leaves this gate pending. If the interval ends without release, preserve the failure; the private worker's hourly fallback may require a later separately authorized observation. One-shot execution scheduling, hourly reconciliation, late-provider commits, 24-hour unreferenced retention, full deletion/tombstone sweeps and quota release under all failure modes remain separate live gates.

The current broker rehydrates and verifies the **whole stored variant for every returned read chunk**. A maximum twenty-chunk display read can therefore incur about 100 MiB of internal reads. This probe's small sanitized outputs do not prove bandwidth efficiency, maximum stored-variant reads, 512 MiB worst-case memory, Cloud gateway throughput, concurrency, or production scale. No result should be promoted to those performance gates. Delivered bytes cannot be recalled; revocation proof concerns subsequent broker requests.

## Offline checks and fixture regeneration

```sh
node --test scripts/live_media_smoke.test.mjs
TINKERLOOM_TEST_DART=/absolute/path/to/dart \
  node --test scripts/live_media_pipeline.test.mjs
```

The first suite tests strict contracts against actual service-produced DTOs, exact image bytes/pixels/CRC, metadata stripping, EXIF reference evidence, malformed responses, changed counts/digests/MIME/headers, provenance, report sanitization, request budget and no retry after transport uncertainty. The second runs the whole orchestration against the actual Dart business service/sanitizer through a **test-only stdio bridge**. Authentication, private-worker HTTP rejection and direct-storage HTTP boundaries in that test are explicit stubs. It catches script/backend contract and receipt drift; it is not live-worker or permission evidence. No test binds an HTTP server or calls the network.

Regenerate the synthetic bytes and actual-service fixture locally (no Cloud):

```sh
node --input-type=module -e '
import {maximumSyntheticPng} from "./scripts/live_media_fixture.mjs";
import {writeFileSync} from "node:fs";
writeFileSync("/private/tmp/tinkerloom-media-synthetic.png", maximumSyntheticPng().bytes);
'
cd appwrite_backend
dart --suppress-analytics run test/export_media_probe_wire.dart \
  /private/tmp/tinkerloom-media-synthetic.png \
  ../scripts/fixtures/live_media/serviceWire.json
dart --suppress-analytics analyze test/export_media_probe_wire.dart test/media_probe_bridge.dart
dart --suppress-analytics format --output=none --set-exit-if-changed \
  test/export_media_probe_wire.dart test/media_probe_bridge.dart
```

The 5 MiB input is generated in memory at runtime and is not committed. The checked-in fixture includes only synthetic DTOs and a tiny synthetic JPEG vector; do not replace it with real user images. Regeneration is never permission to weaken a failed live assertion or replace a historical live report.

## Diagnostic corrections and evidence limits

The initial `fc71` Cloud report remains **failed** (10 passed, 2 failed, 10 blocked and one optional pending check). Its first status execution returned inner 409, but a double-sanitization bug replaced its actual backend code with `unrecognized_error`; that lost detail cannot be reconstructed. A later Console READY observation is separate evidence and does not turn the earlier run into a pass. This probe update does not edit that report or infer which code it originally contained.

Reports now preserve an allowlisted `backendCode` independently of a check's probe `code` (for example `assertion_failed`). Repeated sanitization is idempotent, and blocked checks no longer acquire a fictitious backend error. Media-specific codes are classified before the full-engine allowlist can erase them. A read-only status `transaction_conflict` can arise from the broker's guarded read transaction competing with a worker commit; the narrowly bounded polling exception above handles that exact known code only. The media state, failed read and mutation receipt checks otherwise remain strict.

For header classification, the official [Create execution API](https://appwrite.io/docs/references/cloud/client-web/functions#createExecution) returns an execution object on successful creation. The current official [Create route implementation](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Functions/Http/Executions/Create.php) validates `headers` and throws `GENERAL_ARGUMENT_INVALID` before checking function execution permission and before allocating/enqueueing an execution. The [Headers validator](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Functions/Validator/Headers.php) reserves `x-appwrite-`; [Appwrite PR 14185](https://github.com/appwrite/appwrite/pull/14185) includes outer 400 regression coverage and explicitly describes rejection before enqueueing. This supports classifying a matching future error-only 400 as rejection before execution, not proof that execution permission was tested or that a forged proof reached the private worker. It does not independently attest which Appwrite source revision Cloud deployed. The initial report's erased 400 type is not retroactively assumed to match this classifier.

The correction's offline suite retains all prior checks and adds idempotent diagnostic preservation, exact reserved-header/error-envelope classification, a complete injected auth/header-boundary run, conflict→queued→ready polling, malformed/other-code/wrong-deployment/uncertain-transport failures and exact 24-read exhaustion. No Cloud call, permission adjustment, backend change, mutation retry or report rewriting occurs while preparing these corrections.


### Second preserved Cloud run: execution-header wire correction

The [second failed report](evidence/2026-10-28/media-cloud-worker7e01.failed.json)
records twelve passed checks, one failure and nine blocked checks. Actual worker
readiness and private anonymous/user execution denial passed; one definite
read-only transaction conflict was counted and handled within the existing bound.
The next failure was the third assertion of the first variant read: cache header
extraction expected a dictionary. The official [Execution model](https://appwrite.io/docs/references/cloud/models/execution)
uses an array of [Headers objects](https://appwrite.io/docs/references/cloud/models/headers),
each with name/value. The HTTP stub had incorrectly modeled that field too.

The parser and offline orchestration now use the official array shape and reject
dictionaries, malformed entries, and duplicate case-insensitive cache directives.
The required `private, no-store` value is unchanged. This fixes the test wire, not
the deployed media header policy. The failed report remains unchanged; a later
Cloud read is still required to confirm the actual header value and all pixels.
