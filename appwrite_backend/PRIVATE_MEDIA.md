# Private images on Appwrite Free

This checkpoint ports the original M01–M06 server behavior to the authenticated
Function broker. It uses real JPEG/PNG/WebP decoding, orientation correction,
reencoding and metadata removal. It includes proof-bound private worker dispatch and scheduled cleanup. It does
**not** establish deployed Storage/worker configuration, browser upload, native
picker/cache, or Free-memory acceptance.
Those require the integration and live receipts below.

## Trust and limits

`PrivateFileStore` owns one bucket. Bucket permissions and every file's
permissions are empty; file security is enabled. Signed-in app users receive no
Storage create/read/update/delete permission, provider file IDs, storage URLs,
paths or bearer tokens. The broker uses the execution's injected, scoped server
key, never a stored admin key or user-supplied credential. A server key's empty
multipart permission default is confirmed against the resulting file metadata.
The [official Storage action](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Storage/Http/Buckets/Files/Create.php)
adds a current-user default only for a nonprivileged user. Permission checks also
reject unexpected grants before downloading or adopting an existing file. A bucket grant can
independently expose a file; empty file metadata alone does not prove bucket
privacy. Verify the empty bucket grants during provisioning.
[Storage permissions](https://appwrite.io/docs/products/storage/permissions)

The original per-app limits remain 500 assets and 250 MiB, with original uploads
up to 5 MiB, display images up to 5 MiB, and thumbnails up to 512 KiB. Reservations
charge the declared original plus both maximum variants before Storage I/O.
One atomic project ledger additionally defaults to 1 GiB for this Free development
setup. `PlatformService.mediaProjectBytes` / trusted
`PLATFORM_MEDIA_PROJECT_BYTES` can configure it; no client operation can raise it.
This ledger is an application guard, not the provider's storage meter. The actual
Free project currently shares 2 GB of storage, one bucket, and two Functions and
uses 512 MB / 0.5 CPU compute. [Appwrite pricing](https://appwrite.io/pricing)

All reservation, reference, ready-state and quota transitions share the app guard;
the project ledger also serializes reservations across apps and actors. Quota
underflow aborts the transaction. Failed admission leaves no partial asset,
receipt or ledger change. Storage and TablesDB have no joint transaction: failed
or uncertain external writes retain deterministic identities and charged bytes
for recovery.

## Authenticated transport

The core Function continues validating the caller's Appwrite JWT through
`/account`; opaque asset IDs alone never authorize a read or write. Operations use
`spec.media.*` and strict input keys. Original bytes travel in canonical base64
chunks of at most 262,144 bytes through authenticated JSON execution. Each chunk
is a separate immutable private staging file, at most 20 files for a 5 MiB input.
This avoids depending on arbitrary small `Content-Range` parts or a large binary
Function request. Sanitized variants fit the
[official Dart SDK's 5 MiB single-request threshold](https://github.com/appwrite/sdk-for-dart/blob/main/lib/src/client_io.dart).
Storage's [REST reference](https://appwrite.io/docs/references/cloud/client-rest/storage)
documents multipart files and larger-file chunking.

Upstream Dart Open Runtimes currently reads at most 20 MiB per request; that is
an upstream implementation fact, not a verified Cloud gateway guarantee. The
chosen chunk envelope is approximately 350 KiB, under the existing core limits.
The runtime's `json(body, status, headers)` signature supports the explicit
`Cache-Control: private, no-store` header used by the core.
[Runtime server](https://github.com/open-runtimes/open-runtimes/blob/main/runtimes/dart/versions/latest/src/server.dart),
[response type](https://github.com/open-runtimes/open-runtimes/blob/main/runtimes/dart/versions/latest/src/function_types.dart)

| Operation             | Request beyond `op`, `appId`                                                                  | Response / invariants                                                                                                                                                            |
| --------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec.media.begin`    | `operationId`, `byteLength`, `contentType`, whole-file `sha256`, and one upload context below | `{asset, chunkBytes, expiresAt}`; exact durable receipt reserves once; altered reuse conflicts.                                                                                  |
| `spec.media.chunk`    | `assetId`, aligned `offset`, chunk `sha256`, `dataBase64`                                     | `{assetId, uploadedBytes}`; sequential exact sizes; identical acknowledged offset is replayed without another Storage write; changed bytes conflict.                             |
| `spec.media.complete` | `assetId`, `operationId`                                                                      | `{asset}`; requires all bytes acknowledged; marks `queued`; image becomes usable only after the worker commits `ready`.                                                          |
| `spec.media.status`   | `assetId`                                                                                     | `{asset}`; nonready status is uploader-private and includes input/uploaded byte counts; safe failure category only. Ready info includes dimensions, MIME, byte count and digest. |
| `spec.media.read`     | `assetId`, `variant: display\|thumbnail`, aligned `offset`                                    | One authenticated bounded base64 chunk, with exact `assetId`, `variant`, `offset`, `nextOffset`, whole `byteLength`, MIME, dimensions, whole `sha256`, and `chunkSha256`.        |
| `spec.media.usage`    | none                                                                                          | Builder-only charged `reservedBytes`, `assetCount`, `pendingReleaseBytes`, and per-app maxima. Pending removal does not claim freed space.                                       |

Upload contexts are either `draftRevision` for the actor's own unconsumed private
candidate, or exact `versionId`, approved `actionId` and image `fieldId` for a
current `records.create.v1` / `records.patch.v1` action. Patch also binds
`targetRecordId` and `expectedRecordRevision`; create rejects a target. These
contexts cannot be mixed. The caller must still have current workspace AND app
authority and the required action/policy. Every new upload stage rechecks the
context; archive, demotion, revocation, changed draft, changed publication or
changed record blocks new work. Successful begin/complete receipts still require
current authority against their captured intent before replay.

The current read path rehydrates and verifies the whole stored variant before
returning each chunk. This is bounded by 5 MiB per call, but a full twenty-chunk
download can read about 100 MiB internally. A Free bandwidth/performance pass is
not established; verified range/chunk storage optimization remains part of that
resource gate.

A client must verify each chunk's identity, MIME, offset, length and digest, keep
the whole digest consistent across chunks, and verify the final assembled byte
count and digest. It must discard partial images on any mismatch, account/app
change or access failure. Never log base64/request/response bodies or persist
provider credentials. Delivered bytes cannot be recalled; every subsequent
broker chunk rechecks access before and **after** Storage hydration. Native cache
and web blob URL eviction remain client integration gates.

## Sanitization and retention

The copied original `image_preflight.dart` validates supported still-image
headers, structure, dimensions and PNG expansion before the decoder allocates a
full image. Unsupported formats, animation, duplicated/inconsistent streams,
side lengths over 8,192, and more than 16,000,000 pixels fail closed. Original
MIME and complete SHA-256 must match the declared intent. A separate isolate
has a 30-second deadline. `image: 4.10.1` performs actual decode, EXIF orientation
baking, EXIF/ICC/text removal, display downsampling to edge 2,048 and thumbnail
downsampling to edge 384. Alpha uses PNG; opaque output uses JPEG quality 85,
with further bounded shrinking when encoded output exceeds its limit.

Durable processing admission allows at most two active image jobs project-wide
and one per actor, independent of containers. Two-minute tokenized leases renew
around I/O and processing. The final transaction checks the exact lease token,
deadline and current upload authority before committing dimensions, hashes,
charged bytes, `ready`, and atomic audit/outbox data. A stale execution can leave
only unreachable deterministic output for cleanup. Trusted maintenance retries
only confirmed optimistic transaction conflicts, at most four attempts; unknown
commit/transport results and external I/O are not automatically replayed there.

Each private candidate, immutable version, or record owns one atomic set of
references. Draft/version references retain historical bytes, but only a current
publication or a live record grants runtime viewers access. Current builders can
read same-app ready images; an uploader can read its own unreferenced ready
image. Cross-app, nonready and invented references fail. Detaching the last live
reference starts a fresh 24-hour unreferenced grace; retained immutable versions
continue protecting their images. The grouped reference representation avoids
per-field reference writes and stays within the Free transaction budget for
normal 40-field record updates; live maximum-shape acceptance is still required.

Original staging files are removed after sanitization, while their charged bytes
remain reserved through a 16-minute drain period. Unreferenced expired/ready
cleanup marks `deleting`, removes every deterministic file, and preserves quota
through the same period before final release. Deploy both Functions with timeout
at most 900 seconds; this drain exceeds that configured execution bound plus a
normal bounded Storage request. Provider-side late-commit behavior still needs
live acceptance. Private `deleted` tombstones remain available for later sweeps.
Removal failures preserve charged bytes and paths. Maintenance has bounded
candidate batches (1–50), no internal scheduler/timer/self-loop; metadata scans
are currently complete linear scans and need a separate scale/timeout gate.

`validateGeneratedMedia(actor, access, source, candidate, tx)` permits only ready,
same-app, authorized references already present in the job's exact captured
source; a fresh generation has none. Call it after the worker's final lease/base
check, then persist the candidate and call `syncGeneratedMedia` in that same
transaction. Never send bytes, filenames, paths, storage URLs or tokens to AI.
Structure-only remix continues stripping assets. Preview stays an isolated
memory adapter and must never call these live operations or native/storage APIs.

## Integration and acceptance

The core and private worker share the scoped Storage adapter and trusted project
quota configuration. Media tables are an additive schema union with lifecycle
and workers; `timestampValue: varchar64`, `numberValue: double`, private
shortcuts/drafts and worker tables remain intact. Dependencies retain both the
worker/provider stack and pinned image 4.10.1, resolved with Dart 3.11.

Provision exactly one private bucket, then set `PLATFORM_MEDIA_BUCKET_ID` in both
Functions. Both execution keys require `rows.read`, `rows.write`,
`executions.write`, `files.read`, and `files.write`; core uses execution scope for
optional immediate private-worker wakeups. Core and
private worker remain the only two Functions. No Cloud provisioning is implied
by these source changes.

The integrated source does the following:

1. `media.complete` atomically queues a proof-bound `media` dispatch for one asset.
2. The existing private dispatch allowlist includes `media` and `media_cleanup`.
   Stored app/asset identities must match. A public request body cannot select a
   trusted mode; only the existing dispatch ID and short-lived hash proof are
   accepted. Asset state is authoritative; handled validation failures remain
   failed and never claim an image became ready.
3. Ready and deleting transactions queue one-shot cleanup at the persisted quiet
   deadline. Hourly reconciliation schedules bounded eligible asset work without
   decoding images or accessing Storage in that pass. Each cleanup execution
   targets one asset. There is no in-process wait, self-loop or third Function.
4. Generation validates the candidate against the exact captured source both
   before final processing and after the final guarded lease/base check, then
   persists candidate and media retention in the same transaction. Another ready
   same-app image is still rejected when absent from that captured source.
5. The core emits the actual runtime no-store response header. The RN typed
   broker, picker, preview host and session-scoped native/blob caches still need
   integration and live verification. Client code must not use direct Storage
   SDK upload/download or retain a public bearer URL.

Local verification commands:

```sh
dart pub get --offline
dart analyze lib test
dart format --output=none --set-exit-if-changed lib test
dart run test/service_check.dart
dart test test/providers test/workers_test.dart test/fanout_test.dart
dart test test/image_resource_test.dart test/image_sanitizer_test.dart test/media_worker_test.dart
dart compile exe lib/main.dart -o /private/tmp/tinkerloom-media-core
```

The recorded local verification used official Dart **3.11.0 stable, macos_arm64**.
The SDK archive matched its published SHA-256
`223245a42eab1b811e502e15625b867075ffe012de9eb5374a4cdde2ee087534`.
[Official SDK metadata](https://storage.googleapis.com/dart-archive/channels/stable/release/3.11.0/VERSION),
[official checksum](https://storage.googleapis.com/dart-archive/channels/stable/release/3.11.0/sdk/dartsdk-macos-arm64-release.zip.sha256sum)

The isolated focused media suite passes **25 service groups**, including a
simulated physical-write counter for forty-image-field edits and concurrent
cross-app/actor project reservations in the simulated row store. The full checkpoint baseline plus those
groups totals **118 backend checks**. Analyze, formatting (27 files, no changes) and a standalone core AOT build
also passed at the isolated source freeze; the original image suite already
passes **123/123 on Dart 3.11.0**. A local standalone core AOT compilation measured
153,518,080 bytes peak resident memory; this measures the local compiler, **not**
Cloud build/runtime memory or image-processing acceptance. The merged worker
integration adds five focused tests for proof-bound processing, future cleanup,
metadata-only hourly scheduling, terminal failures, and exact-source AI media.
The persistent merged checkpoint passes 118 service groups, **302 tests**
(174 retained provider/worker/fanout + 123 original image + five media-worker),
and all 87 standalone AppSpec tests on Dart 3.11. Both core and private worker
compile to AOT. Analyze passes on both Dart 3.11 and Dart 3.13 after freezing
captured mutable values into final locals; this is source/toolchain proof, not
live Appwrite or native proof.
The 123 original image-resource/sanitizer cases preserve their original crafted
vectors and assertions; the old process-local admission case is replaced by
service tests for durable cross-execution admission. Service checks use a
simulated optimistic row store, real synthetic-image decoding and localhost
Storage HTTP transport; they are not Cloud proof.

Pending live gates: private bucket/file/direct-table denials with two accounts;
full 5 MiB multipart/chunk upload and complete digest download; no preview/AI
side effects; actual private dispatch and scheduled recovery; concurrent quota,
claim and revocation races; interruption and original/variant cleanup; quiet
period/counter receipts; actual Free 512 MB processing bounds and timeouts;
web session/cache eviction; iOS and Android picker/upload/display/revocation.
Use synthetic images only for those development probes and preserve failed
receipts before any concrete correction and rerun.
