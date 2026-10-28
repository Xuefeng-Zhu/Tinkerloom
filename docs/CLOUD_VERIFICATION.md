# Appwrite development verification

This checklist separates local checks from actual Appwrite acceptance. An unchecked item is pending until a result and non-secret receipt are recorded. The checklist itself does not establish that a resource was created, a deployment succeeded, or a live probe passed.

The current development deployment has [dated receipts](evidence/2026-10-28/README.md): the corrected REST suite passed 26 checks/181 assertions. A separate browser flow verified initial sign-up/builder/record operations on `127.0.0.1`, then version 2 publication, reload, and sign-out/sign-in persistence on `localhost`. The initial failed REST report is also retained. The checklist below remains broader than those exercised cases; forced network-response loss, native builds/devices, and full feature parity are still pending.

## What CI checks

The root `verify` workflow uses Node.js 24 for `npm ci` in `apps/mobile` and `npm run verify` at the repository root. This covers TypeScript, lint, focused tests, formatting, and the web/iOS/Android JavaScript exports configured by the project. The Dart job uses the latest patch of Dart 3.11, matching a currently documented Appwrite Cloud runtime family, and checks the authored backend.

CI has read-only repository permissions, no Appwrite credentials, and no deployment step. Injected SDK responses, in-memory stores, and exported Hermes bundles do not establish live service behavior, native compilation, or physical-device acceptance. The retained AppNest implementation and historical results are reference material only.

## Live smoke command

Once the owner-authorized development deployment is ready, configure the three public Appwrite client values in the ignored `apps/mobile/.env.local`, then run from the repository root:

```sh
node --env-file=apps/mobile/.env.local scripts/live_smoke.mjs --database-id YOUR_DEVELOPMENT_DATABASE_ID
```

The origin defaults to `http://localhost:8426`; use `--origin` only when the registered development web origin differs. Use one web registration for `localhost` so the Free project's three platform slots can also cover Android and Apple. `TINKERLOOM_DATABASE_ID` can supply the database ID instead of the argument. No admin key is accepted or used.

This command creates two synthetic accounts labelled QA, workspaces, apps, receipts, and records in that development project. It leaves the synthetic accounts and rows in place. Passwords, cookies, and session data remain in process memory; the script emits a bounded sanitized JSON report to stdout. Capture that report without replacing prior failed receipts. A failure or blocked prerequisite produces a nonzero exit code and is never relabelled as a pass.

The probes exercise real REST client sessions, private-table denial, owner isolation, draft/publication/record operations, stale revisions, same-command receipt replay, changed-payload denial, independent parallel requests against the same draft/record revision, and persistence across a fresh session. The receipt replay probe deliberately reuses a confirmed command; it does not claim to have forced a network response loss. The Node cookie jar does not prove browser cookie/CORS behavior or native session persistence. CI syntax-checks this script and tests denial classification with local fixtures; it never executes the remote probes.

Appwrite conceals unreadable rows with `404 row_not_found`. The direct-read probe accepts this exact pair only after the same workspace ID has been verified through trusted Function creation and listing. It continues accepting `401` and `403`, rejects unrelated `404` types, and rejects any response containing `$id`, `ownerId`, `name`, or `rows` keys at any depth. This correction does not turn a missing-table or missing-route response into permission evidence.

## Development setup

- [ ] Confirm the organization and project remain on the Free plan; record the chosen region and any applicable resource limits without adding billing details to the repository.
- [ ] Use a serverless TablesDB database. A dedicated PostgreSQL or other paid specification is not part of this development setup.
- [ ] Provision the tables, column types and sizes, and indexes required by the current [backend setup](../appwrite_backend/README.md). Wait for every column and index to be available before probing the function. Record the schema revision and source commit.
- [ ] Keep table permissions empty and row security enabled. Do not grant all authenticated users direct access to backend-owned tables. Table and row grants are alternatives, not an intersection.
- [ ] Select an actual Cloud-supported Dart runtime visible in the console. The current runtime reference lists Dart 3.11 on Cloud; being listed among all runtimes does not mean a version is offered on Cloud.
- [ ] Package the function with `pubspec.yaml` and `lib/` at the archive root. Inspect the archive before uploading; exclude credentials, `.dart_tool`, local output, and dependency caches.
- [ ] Configure `lib/main.dart` as the entrypoint, a compatible Dart dependency-install command, and the database identifier as function configuration. Keep server secrets out of React Native configuration.
- [ ] Permit function execution only by the intended authenticated users and grant only the ephemeral-key scopes required by the current adapter. Do not create or persist an extra service key when the function's execution key is sufficient.
- [ ] Create the deployment, wait for a successful build, activate that exact deployment, and record its source commit, runtime, and deployment status. Environment or build-setting changes require a new deployment.
- [ ] Register web hostnames and native platform identifiers matching `apps/mobile/app.json`. Restart/rebuild the client after changing public environment configuration.

## Two-account live probes

Use isolated synthetic test data in the development project. Authenticate through real Appwrite client-user sessions. Console users and API keys do not produce the invoking user's `x-appwrite-user-jwt`; a Console execution rejected by the handler is not a failed client-authentication test.

- [ ] Sign up, sign in, restore a session, and sign out with account A. Reopen a fresh client session and confirm the state comes from Appwrite.
- [ ] Repeat with a separate account B. Confirm account B cannot list, read, modify, publish, or create records in account A's workspace/app by substituting its IDs.
- [ ] Confirm an anonymous client cannot access authenticated operations or private data.
- [ ] Try direct table reads and writes with a client session and confirm they are denied. Successful trusted Function operations do not prove direct table denial.
- [ ] Verify the function derives identity from the validated session; client-supplied ownership fields must not grant access.
- [ ] Create a workspace and app, close the client, sign in again, and read both back. A local card or success message alone is insufficient persistence evidence.

## Builder and live-record probes

Run each item only once its operation exists in the current implementation. Missing operations stay pending rather than receiving a manual pass.

- [ ] Create a definition from a supported template, customize it, save the draft, and read back the saved draft from a fresh request/session.
- [ ] Reject invalid or unsupported definitions without replacing the prior valid draft.
- [ ] Publish the exact reviewed draft revision. Reject a stale revision or changed candidate; repeating the same confirmed publication command must return the stored outcome.
- [ ] Keep unpublished changes separate from the published definition used by the live runtime.
- [ ] Create and edit a live record, then read it back after reopening the client. Validate required values, choices, stable field identities, and record revision checks on the server.
- [ ] Attempt the same command ID with identical input after an unknown response; verify the stored outcome and absence of a duplicate effect. Reusing an ID with different input must fail.
- [ ] Race conflicting operations against the same app guard/record revision through independent live requests. Verify the committed outcomes and stored state, not just the number of successful UI callbacks.
- [ ] Force a transaction failure and confirm no partial record, revision, receipt, or audit change remains. A fake-store rollback test is separate evidence.
- [ ] Verify cross-app record IDs cannot be used to read or modify another app's records.
- [ ] Exercise preview edits and sample records while observing the live app separately; preview activity must create no live record, publication, receipt, or reminder work.
- [ ] Reproduce lost-response recovery in the client. Retry must retain the original operation ID, payload, revision, and workspace; switching screens must not silently start a different command.
- [ ] Recheck compatibility before enabling schema changes that could invalidate existing records. Do not infer full AppSpec parity from the bounded initial definition model.

## Receipts and outstanding layers

For each completed probe, record the date, source commit, runtime/deployment identity, operation or invariant tested, expected result, observed result, and a non-secret evidence location. Keep passwords, JWTs, ephemeral keys, session cookies, private record bodies, and account information out of public logs and documentation. Record failures and incomplete probes as such.

CI run URLs, build status, and live results are separate receipts. Release signing, Xcode/Gradle builds, physical devices, full accessibility, performance/load, multi-user sharing, private media, AI providers, capacity constraints, and durable reminder/recovery behavior remain separate acceptance layers until implemented and verified.

## Official references

- [Function development and authenticated execution context](https://appwrite.io/docs/products/functions/develop)
- [Function configuration and scopes](https://appwrite.io/docs/products/functions/functions)
- [Injected environment variables and redeployment](https://appwrite.io/docs/products/functions/environment-variables)
- [Cloud runtime availability](https://appwrite.io/docs/products/functions/runtimes)
- [TablesDB permissions](https://appwrite.io/docs/products/databases/tablesdb/permissions)
- [Unreadable rows return 404 row_not_found](https://appwrite.io/blog/post/build-a-permission-aware-ai-copilot#turn-permission-errors-into-answers)
- [TablesDB transactions](https://appwrite.io/docs/products/databases/tablesdb/transactions)
- [Checkout action release](https://github.com/actions/checkout/releases/tag/v7.0.1)
- [Node setup action release](https://github.com/actions/setup-node/releases/tag/v7.1.0)
- [Dart setup action release](https://github.com/dart-lang/setup-dart/releases/tag/v1.8.1)
