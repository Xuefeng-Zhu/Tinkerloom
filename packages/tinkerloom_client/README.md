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

The original existing-account runner in `live_smoke/final_smoke.dart` is excluded
from normal test discovery. It requires `TINKERLOOM_LIVE_SMOKE=1` plus runtime
environment variables
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
Cloud networking. This was the original restoration’s approved scope; do not run
it in addition to the fresh-project check below.

The user separately authorized a fresh Free development setup in FRA project
`6ae4175600137449b25e` after the old SFO account exhausted its quota. Provisioning
is in progress; its Cloud smoke is pending. Preserve the old project and data.
`live_smoke/new_project_smoke.dart` permits at most one new synthetic account, one
workspace, one published Notes app and one synthetic text record. It requires
both `TINKERLOOM_NEW_PROJECT_SMOKE=1` and
`TINKERLOOM_ALLOW_ACCOUNT_CREATION=1`, plus runtime environment variables
`TINKERLOOM_SMOKE_ENDPOINT`, `TINKERLOOM_SMOKE_PROJECT`,
`TINKERLOOM_SMOKE_FUNCTION`, `TINKERLOOM_SMOKE_EMAIL` and
`TINKERLOOM_SMOKE_PASSWORD`. This runner does not require an existing app ID.

The successful fresh-project flow expects 8 Core Function dispatches, 3 Account
requests and 3 business mutations. Its central client limits are 10 Core dispatch
attempts, 3 Account attempts and 3 mutations. With reminders enabled, two private
worker reconcile deliveries are also expected; worker retries and hourly recovery
are outside the client budget. Verify and report actual private worker executions
separately. Neither client nor worker request counts are database-operation
counts. No image upload, AI call, reminder-rule scheduling or automatic client
retry is included. Quota errors or uncertain writes stop the flow.

Before any account or business write, the runner exclusively creates a recovery
journal at `TINKERLOOM_NEW_PROJECT_RECOVERY` (default
`output/new-project-smoke-recovery`). Existing recovery state blocks a second
bootstrap, including after an uncertain reply. Exact workspace/app identities and
operation envelopes remain available for manual recovery; credentials and session
tokens are omitted. Keep credentials in ignored local configuration and pass them
only through the runtime environment. `TINKERLOOM_SMOKE_REPORT` can name an
exclusive sanitized result file. Normal tests and CI never enable either Cloud
runner; the manual setup and smoke must be reported separately from earlier
zero-Cloud verification.
