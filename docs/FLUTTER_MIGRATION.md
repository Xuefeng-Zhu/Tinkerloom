# Flutter frontend restoration

## Scope and source

The active client is `apps/flutter`, restored from the original AppNest Flutter source, assets, platform bridges and relevant tests. The import includes its local startup-recovery improvements. `evidence/2026-10-29/flutter-source-import.json` records source file hashes and the source commit before adaptation. The original AppNest checkout and its data remain untouched.

The React Native checkpoint was pushed as commit `3a9fe4a` on `codex/react-native-backup-20261029` before removing it from the active frontend. Its historical verification results are retained with their original meaning. The Flutter port must have its own verification receipts; 730 React Native tests and earlier native artifacts do not establish Flutter results.

Appwrite remains the backend. No original users, records, passwords or media are imported: the user selected fresh development data. The original trusted Core Function and private worker deployments remain preserved. The separately authorized fresh-account follow-up below provisions the same backend contract in a new project. AI-provider setup and production release are outside this restoration.

## Integration contract

The original UI is retained, with Tinkerloom branding and `com.tinkerloom.app` native identifiers. A hand-authored, injectable Dart client replaces generated Serverpod transport and authentication widgets. It translates launcher/sharing, draft/generation/review/publication, runtime/action/query, activity/inbox/reminder and private-media operations to the existing authenticated Appwrite Function protocol.

Application, workspace, draft, version and record IDs are opaque strings throughout DTOs, routes and renderer interfaces. Counts and revisions remain integers. Commands preserve stable operation IDs, expected revisions/version IDs, explicit publication and uncertain-result recovery. Synthetic preview data remains isolated from live services.

The public configuration keys are `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`, and `APPWRITE_FUNCTION_ID`. `apps/flutter/config/appwrite.dev.json` contains only these public development identifiers and disables automatic refresh. No service keys or private credentials are packaged.

## Verification policy

All normal automated tests and CI run offline through injected transports, service fixtures, `MemoryStore` and local bridges. The portable backend retains Dart 3.11 independently of the Flutter 3.47 / Dart 3.13 workspace. The shared service fixture now lives at `appwrite_backend/test/fixtures/client_wire.json` and is checked by `export_client_wire.dart` without Cloud calls.

Run `scripts/verify.sh --client-only` for analysis, formatting checks, shared spec/renderer tests, Appwrite adapter tests, restored widget tests and a release web build. Use `TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 scripts/verify.sh --backend-only` for backend/spec, probe-contract and local-service regressions plus AOT compilation. The GitHub workflow runs these as separate jobs and contains no deployment or live smoke command.

The Flutter acceptance matrix covers opaque ID/deep-link handling, startup and session switches, access loss, stale revisions, duplicate commands, uncertain replies, private-image attachment and preview isolation. Original template layout tests include narrow and desktop widths and 150% text. Native builds are recorded separately from native installation/UI/permission/hardware checks.

## Original bounded Cloud check

The original restoration authorized one final Cloud smoke under the following existing-account policy. This is historical scope; use the separately authorized fresh-project check below for the current setup, without running both. That check reuses an existing account and app and has a central hard cap of 12 Function executions, 2 Account requests and one text-record creation. It may sign in, open the existing app, create one labelled synthetic text record, then reload/read it. No new accounts, workspaces or apps, no uploads, no AI and no reminder scheduling are part of this check. Automatic polling and automatic retries are disabled. Quota errors, cap exhaustion or an uncertain write stop the run, preserving the uncertain operation identity rather than submitting another command.

Count all Function requests, including reads used for startup/reload, against the same budget. The result must report actual counts and whether the optional creation occurred. A Function execution can issue multiple underlying database operations; do not label its request count as the number of database operations. If the quota is already exhausted, retain the blocked result rather than extending the budget or repeating broad probes.

The explicit runner is outside the normal `test/` directory at `packages/tinkerloom_client/live_smoke/final_smoke.dart`. It reads `TINKERLOOM_SMOKE_ENDPOINT`, `TINKERLOOM_SMOKE_PROJECT`, `TINKERLOOM_SMOKE_FUNCTION`, `TINKERLOOM_SMOKE_APP_ID`, `TINKERLOOM_SMOKE_EMAIL` and `TINKERLOOM_SMOKE_PASSWORD` only from the ephemeral process environment. `TINKERLOOM_SMOKE_REPORT` optionally names a sanitized result file. Never pass credentials as Dart defines or save them in checked-in configuration.

```sh
TINKERLOOM_LIVE_SMOKE=1 flutter test --no-pub \
  packages/tinkerloom_client/live_smoke/final_smoke.dart
```

Without the explicit enable flag this test is skipped. Its server-state reload is an SDK/service persistence check, separate from rendered Flutter UI, browser cold reopen and native device acceptance. Do not automatically rerun it after a failure or exhausted quota.

## Fresh-account development follow-up

After the old SFO account exhausted its quota, the user separately authorized a fresh Free development setup using the new account. The target is FRA project `6ae4175600137449b25e` at `https://fra.cloud.appwrite.io/v1`. Provisioning and the bounded SDK/service persistence check are complete. See the separate [2026-10-30 public validation summary](evidence/2026-10-30/flutter-fra-validation.json); internal deployment manifests remain local and ignored. Preserve the old project and its data. Normal tests and CI retain the zero-Cloud policy, but the completed manual provisioning and smoke are Cloud activity recorded separately.

This exception permits at most one new synthetic application account, one workspace, one published Notes app and one synthetic text record. The Notes template must have no existing records, collection effects or automation requests. The runner creates only the required text fields, then verifies the saved record by reading and reloading it. Image uploads, AI calls and reminder-rule scheduling are excluded.

The expected successful flow uses **8 Core Function dispatches, 3 Account requests and 3 business mutations**. The central client caps are **10 Core dispatch attempts, 3 Account attempts and 3 mutations**. With reminders enabled, two private worker reconcile deliveries are expected as a consequence of app instantiation and record creation. Worker dispatch retries and hourly recovery are outside this client budget; verify actual private Function executions separately in Console. These caps do not bound all backend executions or database operations. Report actual request counts, and stop on quota errors or uncertain writes without automatic retries or cleanup requests.

The separate opt-in runner is `packages/tinkerloom_client/live_smoke/new_project_smoke.dart`. It requires `TINKERLOOM_NEW_PROJECT_SMOKE=1` and `TINKERLOOM_ALLOW_ACCOUNT_CREATION=1`, plus the runtime endpoint/project/Function/email/password variables listed above; it does not use `TINKERLOOM_SMOKE_APP_ID`. Never package credentials in Dart defines, logs, committed files or build artifacts.

```sh
TINKERLOOM_NEW_PROJECT_SMOKE=1 TINKERLOOM_ALLOW_ACCOUNT_CREATION=1 \
  flutter test --no-pub \
  packages/tinkerloom_client/live_smoke/new_project_smoke.dart
```

`TINKERLOOM_NEW_PROJECT_RECOVERY` optionally selects the durable recovery directory. Before any account or business write, the runner exclusively creates its journal and freezes the workspace/app identities and operation envelopes. Existing recovery state blocks another bootstrap, including after an uncertain reply; inspect the retained identities rather than creating replacements. The journal excludes credentials and session tokens. `TINKERLOOM_SMOKE_REPORT` optionally names an exclusive sanitized result file. SDK cookies remain isolated and temporary. This proves only the SDK/service path if it passes; rendered UI and native device acceptance remain separate.

## 2026-10-29 restoration verification (historical)

Final runtime source: `6c57a753d338c13303362953750024cca3e04203`. The Dart/Android code is unchanged from the passing `1b87197` checkpoint; the final source additionally records the iOS plugin integration used by the successful build.

- **589 offline tests passed:** shared AppSpec 90, renderer 247, Appwrite adapter/smoke guards 19, and restored application 233. Analysis and formatting passed. [Verification receipt](evidence/2026-10-29/flutter-port-verification.json).
- The unchanged backend passed **405 standard tests**, **118 service checks**, and **17 local service-bridge tests**. Backend and Flutter GitHub jobs both passed for `1b87197`; [CI receipt](evidence/2026-10-29/flutter-ci-1b87197.passed.json).
- Release web and the standalone offline preview built successfully. A browser check opened the original Project Hub form and saved one synthetic task in memory. [Browser receipt](evidence/2026-10-29/flutter-offline-browser.json).
- Android Release APK and unsigned iOS arm64 Release compiled successfully. All **274 tracked inputs** and both artifacts were independently rehashed. Android uses a development debug certificate; iOS requires signing before installation. [Native receipt](evidence/2026-10-29/flutter-native-6c57a75.passed.json), [independent rehash](evidence/2026-10-29/flutter-native-root-rehash.json).
- **Zero Appwrite Cloud requests** were made in the restoration verification recorded on 2026-10-29. At that checkpoint the existing-account smoke was prepared but had not run because credentials were unavailable. This historical receipt does not describe the later manual fresh-project provisioning. [Historical pending receipt](evidence/2026-10-29/flutter-cloud-smoke.pending.json).
- The original AppNest source remains unchanged across all 187 imported source-file hashes. Existing users, records, credentials and database directories were not imported or modified. [Preservation receipt](evidence/2026-10-29/original-appnest-preserved.json).

The first Android build failed because the new SDK dependency required Java library desugaring; that failure is preserved and the corrected build passed. One extra local widget invocation from the workspace root could not find app font assets; the required app-directory rerun passed all 233 tests. Neither failure was hidden by removing tests.

Existing reminder approvals are not exposed by the unchanged Appwrite wire contract. The publication review labels selections for the next publication and requires explicit acknowledgement before editing an existing app with reminders; it does not pretend that unavailable approval state is known. Upload processing uses manual Check/Discard recovery, with no status polling.

Compilation and offline tests do not establish native UI, hardware permissions, live account persistence or production readiness. Native device checks, AI-provider setup and store/production release remain separate work.

## 2026-10-30 fresh-account result

The initial run created the sole synthetic account, workspace and Notes app, then stopped on a definitive `transaction_conflict` during the first record query (4 Core / 2 Account / 2 mutations). The completed worker and local guard-write paths support a concurrency explanation, without proving the exact cause. A single explicit continuation preserved those identities and receipt hashes, exclusively reserved its recovery journal, used the remaining budget, created one text record and verified two reads across a manifest reload. It passed with cumulative **10 Core / 3 Account / 3 mutations**; Console separately showed **2 private Worker executions**, for **12 total Functions**. No automatic retries or additional account/app creation occurred.

The continuation tool rejects uncertain/quota outcomes and any prior record attempt, and cannot restart with its retained journal. All **13 new offline guard tests**, analysis and formatting passed. It made no signout request because the final Account slot was used for sign-in; temporary local cookies were removed, while synthetic server sessions may remain. No further Cloud verification is needed for this setup.

Worker execution is on demand, with **no periodic schedule**. This avoids idle database scans; time-based reminder triggering and periodic recovery remain deferred. Reminder-rule scheduling, uploads and AI were excluded from this smoke. Web, Android Release and unsigned iOS Release were rebuilt from `733439f` with the new public config; each compiled payload contains the new FRA target and no old SFO target. These are compilation results, separate from native-device/UI and store-signing acceptance. Old SFO artifacts remain historical.
