# Confirmed transaction-abort retry

The development worker and user operations deliberately share app/workspace
guards. A worker can therefore invalidate a user's staged snapshot. Explicit
opt-ins are `spec.instantiate` with a starter template, `acceptInvitation`,
`createInvitation`, `spec.saveDraft`, `spec.publish`, `setGrant`,
`revokeInvitation`, `archiveApp`, `spec.setPinned`, and `spec.readNotification`.
`spec.execute` opts in only after authorization explicitly checks one of the
seven registered capabilities: `records.create.v1`, `records.patch.v1`,
`assignment.assign.v1`, `workflow.transition.v1`, `capacity.configure.v1`,
`capacity.claim.v1`, or `capacity.release.v1`.
Their transaction closures perform database operations only,
including receipts, audit, outbox and persisted dispatch intent. No provider,
Storage, delivery or wakeup HTTP call runs in those closures. Every unlisted
operation remains opted out, including remix, reads, media/file operations,
guidance, generation and worker handlers. The generic helper still defaults to
false; there is no operation-name wildcard.

An eligible request gets at most two extra attempts, with fresh transactions and
100/200 ms backoff. Its actor, operation ID, payload and concurrency expectations
remain unchanged. Existing checks inside each transaction re-read authorization,
issuer grant generation, invitation state, quotas and receipts. A changed rule or
permission can reject the next attempt; a retry never grants extra authority.

## Required evidence before retry

`AppwriteRest.finishTransaction` classifies a confirmed abort only when all of
the following hold:

1. The exact commit PATCH returns HTTP 409.
2. Its JSON error body is at most 8 KiB, uses only supported error keys, and has
   integer `code: 409` and `type: transaction_conflict`.
3. A separate bounded GET of the same transaction returns the matching `$id`
   and terminal status `failed` or `rolled_back`.

A confirmed terminal transaction is not sent another rollback request. Its
staged work cannot be committed again. Unknown state, malformed bodies, another
transaction ID, HTTP 403/404/5xx, timeout, or pending/committing/committed status
does not enter this retry path. Noncommit errors and other HTTP 409 responses
also remain ordinary errors. Existing cleanup for an unconfirmed attempt runs
once; no uncertain write is automatically replayed by this new path. Error-body
drains and transaction-state responses are bounded. No raw error text, type or
transaction state is added to the public wire response or application logs.

The public API remains unchanged, including the conservative final
`transaction_conflict` response after exhausted or unconfirmed attempts. The
client retains its original pending command; this change adds no public retry
flag. Matching receipts still require current authorization before replay.

## Development diagnostics

The operator may set `PLATFORM_TRANSACTION_DIAGNOSTICS=true` when deploying the
development Core. The default emits nothing. Each execution emits at most twelve
`transaction_diagnostic:` events followed by a fixed enum category. Categories
distinguish a staging conflict, accepted/rejected commit error classification,
unavailable/denied state lookup, unconfirmed terminal identity/state, confirmed
abort, retry or exhaustion, opt-out, and unconfirmed cleanup. No transaction,
app, actor or operation IDs, raw bodies, messages, upstream error types or state
values enter these events. Failed logging never changes the command outcome.
There are no new public DTO fields, request flags, permissions, or scopes.

The complete category allowlist is `stagingConflict`, `commitBodyAccepted`,
`commitBodyRejected`, `commitResponseOther`, `terminalLookupDenied`,
`terminalLookupUnavailable`, `terminalIdentityMismatch`, `terminalNotConfirmed`,
`abortConfirmed`, `retryStarted`, `retryExhausted`, `retryNotEnabled`, and
`cleanupUnconfirmed`. Only the fixed prefix and one of these exact names may be
retained by a probe observer; arbitrary Function logs remain outside its report.

The preserved hosted `1b6d8a5` run failed at `createInvitation` and a builder's
`spec.saveDraft`, which were then opted out. Its assertion counts do not establish
failure of the strict commit classifier. That report remains unchanged. The
three additional opt-ins retain the same confirmed-abort requirement. Explicit
rollback confirmation after a staging conflict remains a reviewed design option
only; it is not implemented. An unknown commit or unconfirmed cleanup never
becomes permission to restage.

## Primary-source basis and limits

[Appwrite's TablesDB transaction guide](https://appwrite.io/docs/products/databases/tablesdb/transactions)
describes atomic staged commits, external-change conflict detection, and
re-fetching/re-staging after a conflict. The official
[commit implementation](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Databases/Http/Databases/Transactions/Update.php)
executes staged operations within a database transaction and reports a conflict
before its post-commit section. The additional terminal-state read avoids relying
on HTTP status alone. The documented
[transaction model](https://appwrite.io/docs/references/cloud/models/transaction)
defines the terminal states. The official
[TablesDB GET transaction route](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Databases/Http/TablesDB/Transactions/Get.php)
uses the existing `rows.read` scope; no extra scope or persistent key is needed.
These public sources do not attest the exact Cloud server version. An unsupported
or denied state lookup falls back safely without retry.

## Verification

`test/confirmed_abort_test.dart` exercises the actual REST adapter against a
loopback-only HTTP server, plus `PlatformService` and `WorkerEngine` through a
local Appwrite REST simulation backed by optimistic `MemoryStore`. The original
instantiation and acceptance race regressions remain. Three additional
byte-identical positive race proofs for invitation creation, draft save and
publication fail on the pristine `1b6d8a5` backend and pass with this candidate.
Negative
cases cover classification, terminal-state timeout/error/schema, exhausted
attempts, changed authorization/invitations/issuer generation/quotas, lost
successful commit replies and default opt-out operations. Database effects and
receipts are counted to reject duplicate application. New cases preserve builder
authority, private candidate revision, publication base/candidate/review checks,
receipt identity, invitation quota accounting, and default opt-out behavior.
The diagnostics logger is tested disabled, capped, and throwing.

`test/db_mutation_retry_test.dart` adds twenty groups. Twelve positive worker
races cover every registered record/action capability and each newly included
metadata mutation; the byte-identical tests fail on the pristine `1b6d8a5`
baseline and pass here. Focused negatives preserve record/publication CAS,
assignee access, current capacity allocation, grant/shortcut revisions,
notification recipient authority, and current authorization before historical
receipt replay. Pinning still creates no business audit/outbox events. Capacity
commands preserve their pool/claim guard semantics and do not invent record CAS.
Generation enqueue and media reservation/chunk-lease tests remain opted out,
with one aborted attempt and zero provider/Storage calls. The previous archive
opt-out assertion is intentionally replaced by an archive positive race and a
read opt-out assertion; remix remains opted out.

These tests use only synthetic local storage and time. They are not Cloud
transaction or scheduling proof. The original reminder and activity Cloud runs
remain preserved as pending. A new deployment and authorized bounded live checks
must establish hosted behavior; they cannot retroactively pass those receipts.
