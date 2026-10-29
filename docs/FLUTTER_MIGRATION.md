# Flutter frontend restoration

## Scope and source

The active client is `apps/flutter`, restored from the original AppNest Flutter source, assets, platform bridges and relevant tests. The import includes its local startup-recovery improvements. `evidence/2026-10-29/flutter-source-import.json` records source file hashes and the source commit before adaptation. The original AppNest checkout and its data remain untouched.

The React Native checkpoint was pushed as commit `3a9fe4a` on `codex/react-native-backup-20261029` before removing it from the active frontend. Its historical verification results are retained with their original meaning. The Flutter port must have its own verification receipts; 730 React Native tests and earlier native artifacts do not establish Flutter results.

Appwrite remains the backend. No original users, records, passwords or media are imported: the user selected fresh development data. Existing trusted Core Function and private worker deployments remain unchanged unless an independently demonstrated wire incompatibility requires a scoped follow-up. AI-provider setup and production release are outside this restoration.

## Integration contract

The original UI is retained, with Tinkerloom branding and `com.tinkerloom.app` native identifiers. A hand-authored, injectable Dart client replaces generated Serverpod transport and authentication widgets. It translates launcher/sharing, draft/generation/review/publication, runtime/action/query, activity/inbox/reminder and private-media operations to the existing authenticated Appwrite Function protocol.

Application, workspace, draft, version and record IDs are opaque strings throughout DTOs, routes and renderer interfaces. Counts and revisions remain integers. Commands preserve stable operation IDs, expected revisions/version IDs, explicit publication and uncertain-result recovery. Synthetic preview data remains isolated from live services.

The public configuration keys are `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`, and `APPWRITE_FUNCTION_ID`. `apps/flutter/config/appwrite.dev.json` contains only these public development identifiers and disables automatic refresh. No service keys or private credentials are packaged.

## Verification policy

All normal automated tests and CI run offline through injected transports, service fixtures, `MemoryStore` and local bridges. The portable backend retains Dart 3.11 independently of the Flutter 3.47 / Dart 3.13 workspace. The shared service fixture now lives at `appwrite_backend/test/fixtures/client_wire.json` and is checked by `export_client_wire.dart` without Cloud calls.

Run `scripts/verify.sh --client-only` for analysis, formatting checks, shared spec/renderer tests, Appwrite adapter tests, restored widget tests and a release web build. Use `TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 scripts/verify.sh --backend-only` for backend/spec, probe-contract and local-service regressions plus AOT compilation. The GitHub workflow runs these as separate jobs and contains no deployment or live smoke command.

The Flutter acceptance matrix covers opaque ID/deep-link handling, startup and session switches, access loss, stale revisions, duplicate commands, uncertain replies, private-image attachment and preview isolation. Original template layout tests include narrow and desktop widths and 150% text. Native builds are recorded separately from native installation/UI/permission/hardware checks.

## Bounded final Cloud check

Only one final Cloud smoke is authorized for this restoration. It reuses an existing account and app and has a central hard cap of 12 Function executions, 2 Account requests and one text-record creation. It may sign in, open the existing app, create one labelled synthetic text record, then reload/read it. No new accounts, workspaces or apps, no uploads, no AI and no reminder scheduling are part of this check. Automatic polling and automatic retries are disabled. Quota errors, cap exhaustion or an uncertain write stop the run, preserving the uncertain operation identity rather than submitting another command.

Count all Function requests, including reads used for startup/reload, against the same budget. The result must report actual counts and whether the optional creation occurred. A Function execution can issue multiple underlying database operations; do not label its request count as the number of database operations. If the quota is already exhausted, retain the blocked result rather than extending the budget or repeating broad probes.

The explicit runner is outside the normal `test/` directory at `packages/tinkerloom_client/live_smoke/final_smoke.dart`. It reads `TINKERLOOM_SMOKE_ENDPOINT`, `TINKERLOOM_SMOKE_PROJECT`, `TINKERLOOM_SMOKE_FUNCTION`, `TINKERLOOM_SMOKE_APP_ID`, `TINKERLOOM_SMOKE_EMAIL` and `TINKERLOOM_SMOKE_PASSWORD` only from the ephemeral process environment. `TINKERLOOM_SMOKE_REPORT` optionally names a sanitized result file. Never pass credentials as Dart defines or save them in checked-in configuration.

```sh
TINKERLOOM_LIVE_SMOKE=1 flutter test --no-pub \
  packages/tinkerloom_client/live_smoke/final_smoke.dart
```

Without the explicit enable flag this test is skipped. Its server-state reload is an SDK/service persistence check, separate from rendered Flutter UI, browser cold reopen and native device acceptance. Do not automatically rerun it after a failure or exhausted quota.

## Current verification record

Restoration work is in progress. Final receipts must identify the exact accepted Flutter source, commands, test totals, build hashes and the bounded Cloud result. Record failures and unavailable native tooling separately; do not overwrite older receipts or infer current acceptance from historical React Native or Serverpod reports.
