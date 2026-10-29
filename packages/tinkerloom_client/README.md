# Flutter Appwrite client

This package preserves the original Flutter presentation interfaces while using
Appwrite Account sessions and the existing trusted Tinkerloom Function protocol.
It has no Serverpod dependency or client-side database/service key.

`Client` accepts public endpoint/project/Function configuration. `transport` and
`ClientAuth` are injectable. SDK construction is lazy, so fake clients and local
service tests neither initialize native storage nor contact Cloud. Missing live
configuration fails locally.

All entity identifiers are opaque strings. Revisions/counts stay integers. The
compatibility endpoint facade translates explicit authenticated operations,
version/revision checks, exact idempotency keys and private image chunks. Known
reads share a session-scoped FIFO and identical concurrent reads coalesce.
Session changes discard stale results and queued work. Mutations are never
retried automatically; uncertain results retain their frozen operation envelope.
Mutation response schemas are checked before confirming success.

Live streams are local invalidations after acknowledged writes. Idle clients do
not poll Cloud. Refresh is explicit. Published reminder approval metadata is not
provided by the current backend; `approvalsKnown` therefore defaults to false.
Publication UI must request explicit acknowledgement when reapproving a published
app's reminders rather than treating an empty list as known server state.

`flutter test packages/tinkerloom_client/test` uses the actual backend service,
worker and image sanitizer over an in-memory optimistic database and in-memory
file store, plus controlled transport tests. This is offline semantic evidence,
not Appwrite Cloud or native device evidence.

The optional runner in `live_smoke/final_smoke.dart` is excluded from normal test
discovery. It requires `TINKERLOOM_LIVE_SMOKE=1` plus runtime environment variables
`TINKERLOOM_SMOKE_ENDPOINT`, `TINKERLOOM_SMOKE_PROJECT`,
`TINKERLOOM_SMOKE_FUNCTION`, `TINKERLOOM_SMOKE_APP_ID`,
`TINKERLOOM_SMOKE_EMAIL`, and `TINKERLOOM_SMOKE_PASSWORD`. Never supply credentials
through Dart defines, logs, committed files, or build artifacts.

The runner reuses one existing account/app, creates at most one text record in a
collection without effects, reads it back and reloads it, then signs out. Its
central budget is 12 Function dispatch attempts, 2 Account attempts and 1 business
mutation; quota or uncertain writes freeze the run. A Function request can perform
multiple database operations. The planned successful flow uses 6 Functions and 2
Account requests. SDK cookies use an isolated temporary directory removed on
completion. The HTTP override enabling this explicit runner is verified against a
local loopback server and restores its enclosing scope. Normal tests do not enable
Cloud networking. Run this only once within the user's approved live-test budget.
