# Confirmed transaction-abort retry

The development worker and user operations deliberately share app/workspace
guards. A worker can therefore invalidate a user's staged snapshot. Only
`spec.instantiate` with a starter template and `acceptInvitation` opt into the
new retry path. Their transaction closures perform database operations only,
including receipts, audit, outbox and persisted dispatch intent. No provider,
Storage, delivery or wakeup HTTP call runs in those closures. Remix, generic
mutations, reads and worker handlers receive no new opt-in.

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
local Appwrite REST simulation backed by optimistic `MemoryStore`. Its identical
worker-versus-instantiation and worker-versus-acceptance positive regressions
fail on the pristine backend baseline and pass with this candidate. Negative
cases cover classification, terminal-state timeout/error/schema, exhausted
attempts, changed authorization/invitations/issuer generation/quotas, lost
successful commit replies and default opt-out operations. Database effects and
receipts are counted to reject duplicate application.

These tests use only synthetic local storage and time. They are not Cloud
transaction or scheduling proof. The original reminder and activity Cloud runs
remain preserved as pending. A new deployment and authorized bounded live checks
must establish hosted behavior; they cannot retroactively pass those receipts.
