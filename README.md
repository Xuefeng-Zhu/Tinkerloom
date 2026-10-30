# Tinkerloom

Tinkerloom restores the original **Flutter** mini-app interface with the existing **Appwrite** backend. The shared declarative renderer powers templates, live records, isolated previews, the visual builder, explicit publication, sharing and native device capabilities. The Flutter port replaces the Serverpod transport; it does not generate or execute per-app code.

The previous React Native implementation is preserved on [`codex/react-native-backup-20261029`](https://github.com/Xuefeng-Zhu/Tinkerloom/tree/codex/react-native-backup-20261029). Its 730-test, native-build and Cloud receipts remain historical, source-specific evidence and are not Flutter acceptance results. See [Flutter migration and verification](docs/FLUTTER_MIGRATION.md) for the new client’s checks and remaining gates.

Current development setup now uses the new Appwrite Free account in FRA. One synthetic Notes app passed SDK/service save-and-reload verification after a manually continued read conflict: **12 total Function executions (10 Core + 2 private Worker), 3 Account requests, and one text record**. The original 589 offline Flutter/spec and 405 backend checks remain dated evidence; this follow-up added and passed **13 offline guard tests** and rebuilt web, Android and unsigned iOS with the new configuration. [Current results](docs/evidence/2026-10-30/flutter-fra-validation.json).

Tinkerloom uses **fresh Appwrite development data**. The original AppNest checkout, users, records and credentials remain preserved. AI-provider configuration and production release are deferred.

## Run Flutter

Use **Flutter 3.47.0 / Dart 3.13.0**. Resolve the workspace from the repository root:

```sh
flutter pub get
cd apps/flutter
flutter run -d chrome --web-hostname localhost --web-port 8426 \
  --dart-define-from-file=config/appwrite.dev.json
```

`npm run dev` runs the same configured web client. Open it at <http://localhost:8426>; `localhost` is the registered web hostname. Android and iOS applications use `com.tinkerloom.app`.

The checked-in development configuration contains only public endpoint/project/Function identifiers and keeps automatic refresh off. Server API keys, passwords and AI credentials do not belong in application configuration.

To explore the original templates without any Appwrite calls:

```sh
cd apps/flutter
flutter run -t lib/preview.dart -d chrome --web-hostname localhost --web-port 8426
```

Preview records are synthetic and memory-only. They are never copied into live storage. The live client shows a configuration/startup screen when its public Appwrite configuration is absent.

The restored interface retains the original theme, fonts, launcher, authoring tools, navigation and native capability bridges. Appwrite Account owns sign-in sessions; authenticated Functions enforce current access, definitions, revisions and command receipts. Private uploads use the existing bounded image protocol.

## Protect the Free development quota

Normal tests and CI are **offline**. Development uses manual refresh by default; do not leave old React Native or Flutter polling sessions running against Cloud. Optional automatic refresh must share requests, honor the negotiated minimum interval, and stop when the app is hidden, disposed or signed out.

The explicitly authorized fresh-account setup is complete. Do not rerun its bootstrap or the historical broad Cloud suites. It created one synthetic account, one workspace, one Notes app and one text record. Client requests were cumulatively capped at 10 Core, 3 Account and 3 mutations; the separately observed two private Worker deliveries brought the total to 12 Function executions. The first read was definitively rejected with a transaction conflict; one manual continuation reused the same identities and remaining budget. There were no automatic retries, image uploads, AI calls or reminder-rule scheduling. Function counts are not database-operation counts. Internal provisioning manifests and private credentials/recovery remain in ignored local files. Periodic worker scans are off; time-based reminder triggering/recovery is deferred. Synthetic server sessions may remain because the final Account slot was used for sign-in; temporary local cookies were removed.

## Verify and build

```sh
bash scripts/verify.sh --client-only
TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 \
  bash scripts/verify.sh --backend-only
```

Client verification analyzes the restored application and shared packages, checks formatting, runs spec/renderer/adapter/widget tests, and builds release web assets. Backend verification uses its separate Dart 3.11 toolchain, in-memory services and local transport bridges, checks the shared wire fixture, and compiles both Function entry points. Neither command deploys or calls Appwrite Cloud. `npm run verify` is a convenience wrapper for both checks and needs the backend Dart path when the default `dart` is 3.13.

```sh
cd apps/flutter
flutter build web --release --dart-define-from-file=config/appwrite.dev.json
flutter build apk --release --dart-define-from-file=config/appwrite.dev.json
flutter build ios --release --no-codesign \
  --dart-define-from-file=config/appwrite.dev.json
```

`npm run build:web`, `npm run build:android`, and `npm run build:ios` use the same public development configuration. To run on a connected native device, use `flutter run --dart-define-from-file=config/appwrite.dev.json` from `apps/flutter`.

Compilation does not establish installation, native UI, permission handling or hardware acceptance. Signed distribution and production operations remain separate work.

## Repository layout

- `apps/flutter/` — active Flutter application, original assets and native bridges.
- `packages/tinkerloom_client/` — injectable Appwrite client, typed DTOs and transport tests.
- `packages/appnest_spec/` and `packages/appnest_renderer/` — declarative definition language and shared Flutter widgets with opaque string entity IDs.
- `appwrite_backend/` — trusted Dart Core Function and private worker. [Full engine contract](appwrite_backend/SPEC_ENGINE.md).
- `appwrite_backend/test/fixtures/client_wire.json` — shared wire fixture exported by the real local service.
- `scripts/` — offline verification plus preserved, separately gated historical Cloud probes.
- `legacy_appnest/` — preserved original implementation for reference.
- `docs/evidence/` — dated results with explicit source and verification-layer boundaries.
