# Authenticated activity verification

`scripts/live_activity_smoke.mjs` exports an import-safe `runActivitySmoke` function. Importing it does not authenticate, make requests, create accounts, or write reports. It verifies the additive `spec.listActivity` service through normal Appwrite client sessions. Running it requires explicit operator authorization, a current deployment receipt, and five existing synthetic accounts held in memory.

## Operator inputs

Call `runActivitySmoke(configuration, { actorCredentials, onProgress })` from the authorized account-pool runner. Supply these public configuration fields explicitly:

```js
{
  enableLiveActivity: true,
  endpoint: "https://sfo.cloud.appwrite.io/v1",
  origin: "http://localhost:8426",
  projectId: "PUBLIC_PROJECT_ID",
  functionId: "tinkerloom-core",
  databaseId: "tinkerloom",
  coreDeploymentId: "CURRENT_ACTIVE_DEPLOYMENT_ID",
  preflightAppId: "EXISTING_OWNER_READABLE_QA_APP_ID",
  sourceCommit: "COMMIT_HEX",
  sourceSha256: "64_HEX_ARCHIVE_SHA256",
  maxHttp: 180,
  timeoutMs: 45000,
}
```

The operator supplies the mapping between the current active deployment, source commit, and archive hash. The probe verifies every completed Function response against `coreDeploymentId`; it cannot independently attest the uploaded archive. A settings-only redeployment changes the deployment ID even when the code archive stays unchanged. Use the current receipt rather than an earlier ID. No exact frontend source revision is required.

`preflightAppId` must already have at least one audit entry and be readable by the pooled owner. An archived QA app is suitable. Before creating test workspaces or apps, the probe reads one activity entry from this app and checks deployment identity and the complete metadata whitelist. An unavailable operation, wrong deployment, or unexpected private field stops setup.

The required callback is `async actorCredentials(label, { runId }) => ({ id, email, password })`, with labels `owner`, `builder`, `member`, `viewer`, and `outsider`. Credentials must have the existing strict synthetic-account shape, including a `tinkerloom-…@example.test` email. The five IDs and case-insensitive emails must be distinct. The callback and its return values stay in memory; there is no CLI, file, environment-variable, or default account-creation path. The probe creates a fresh email/password session per account, then independently verifies its identity with `GET /account`. It never uses admin headers, an API key, user JWT overrides, worker proofs, or a supplied server clock.

`onProgress` receives only a fixed phase name and request count. Persist only the returned sanitized report, using an exclusive new file with restrictive permissions such as mode `0600`. Preserve failed reports verbatim. Do not serialize the callback, credentials, request bodies, raw HTTP responses, or console-held account pool.

## Checks and bounds

The probe uses at most 180 HTTP requests and reserves six for session cleanup. Configuration permits a smaller budget down to 80, which can finish as `blocked` after exhausting the normal-request allowance. Each of the five fresh sessions is signed out once in `finally`; account deletion is never attempted. The viewer's deliberate expired-session check uses its already-revoked session cookie only for a read.

The activity contract is exactly:

```text
spec.listActivity { appId, limit: 1..50, cursor? }
→ { appId, items: [{ id, action, createdAt, status: "committed" }], nextCursor }
```

The probe pages with limit two. Entries use stable ascending audit-ID order, which is not chronological order. A cursor contains only the public scope hash, revision, and last audit ID; the hash binds the actor, app, workspace and page size, and is not a secret or authorization token. Current membership and app access must still be checked on every page.

Eight reported phases cover:

1. Five reused, normally authenticated and identity-verified synthetic accounts.
2. Read-only preflight against the current activity deployment.
3. Three new synthetic template apps in two new workspaces, explicit builder/member/viewer invitations, one unpublished private draft label, and three private record values.
4. All pages for owner, builder, member and viewer, with exact equality of the metadata-only results.
5. Same-workspace ungranted-app denial, other-workspace denial, outsider denial, cursor actor/app/page-size/anchor isolation, direct reads of a known existing private audit row by all five accounts, and anonymous denial.
6. Stale-cursor rejection after one confirmed record write, exactly one new activity entry for that write, and immediate read denial after member grant revocation, including the member's previously issued cursor.
7. Owner and viewer history after app archive, followed by expired-session denial.
8. Cleanup of the five probe-created sessions.

The strict response parser rejects unknown row/page/cursor keys, noncanonical timestamps, impossible dates, duplicate or unordered audit IDs, unsupported status values, and invalid cursor encoding. Pages and decoded cursors are checked against in-memory credentials, actor IDs, session cookies, invitation tokens, operation IDs, and seeded private content. The report contains only deployment provenance, synthetic resource IDs, fixed check classifications, and numeric counts. It never includes audit entries or private values.

Only a completed, matching-deployment read returning exactly `409 { error: "transaction_conflict" }` is retried, at most twice with the same query. Mutations are sent once. A timeout, lost response, incomplete execution, deployment mismatch, server failure, or transaction conflict on a mutation stops the run with `observation_pending`; it does not generate a new operation ID or automatically replay the command. Known pre-dispatch budget exhaustion is `blocked`, not an uncertain write.

The probe neither approves reminders nor enrolls recipients, calls providers, processes media, sends email/push, or invokes privileged worker modes. Reminder capability flags may already be enabled; no assumption that they are disabled is needed. Templates are instantiated with effects disabled, and the chosen record action has no approved automation. The tested primary app is archived at the end. Other synthetic setup data is retained for inspection and is identified only by its app/workspace IDs in the report; the probe does not delete data.

## Local verification and remaining acceptance

Run the new checks from the repository root after resolving backend dependencies with the supported Dart SDK:

```sh
TINKERLOOM_TEST_DART=/path/to/dart node --test scripts/live_activity_smoke.test.mjs
```

The seven local test groups exercise a real `PlatformService` and `MemoryStore` through the test-only stdio bridge `appwrite_backend/test/activity_probe_bridge.dart`. The bridge is not an HTTP endpoint or production authentication path. Its fixed synthetic clock and enabled reminder flag exist only in the offline fixture. Authentication HTTP and direct private-table denial responses are explicit test stubs; the local test does not establish Cloud session or table permissions.

The positive orchestration verifies actual service invitation receipts, role authorization, cursor parsing, audit projection, revocation, and archived reads. Negative tests cover deployment/metadata preflight rejection before setup writes, duplicate pooled identities before authentication, narrow read-conflict recovery, a real committed mutation with its response deliberately lost and no automatic replay, and cleanup after budget exhaustion.

Only a separately authorized execution against the current Cloud deployment can prove the hosted activity slice, index/projection behavior, and real account/table denial responses. Mounted browser/native history UI, device behavior, provider execution, real data import, and production cutover remain separate acceptance layers.
