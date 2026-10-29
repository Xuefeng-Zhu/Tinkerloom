# Tinkerloom

Tinkerloom restores the original **Flutter** mini-app interface with the existing **Appwrite** backend. The shared declarative renderer powers templates, live records, isolated previews, the visual builder, explicit publication, sharing and native device capabilities. The Flutter port replaces the Serverpod transport; it does not generate or execute per-app code.

The previous React Native implementation is preserved on [`codex/react-native-backup-20261029`](https://github.com/Xuefeng-Zhu/Tinkerloom/tree/codex/react-native-backup-20261029). Its 730-test, native-build and Cloud receipts remain historical, source-specific evidence and are not Flutter acceptance results. See [Flutter migration and verification](docs/FLUTTER_MIGRATION.md) for the new client’s checks and remaining gates.

Tinkerloom uses **fresh Appwrite development data**. The original AppNest checkout, users, records and credentials remain preserved. AI-provider configuration and production release are deferred.

## Run Flutter

Use **Flutter 3.47.0 / Dart 3.13.0**. Resolve the workspace from the repository root:

```sh
flutter pub get
cd apps/flutter
flutter run -d chrome --web-hostname localhost --web-port 8426 \
  --dart-define-from-file=config/appwrite.dev.json
```

The checked-in development configuration contains only public endpoint/project/Function identifiers. It targets the existing SFO Appwrite Free development project and keeps automatic refresh off. Native applications use `com.tinkerloom.app`. Server API keys, passwords and AI credentials do not belong in application configuration.

To explore the original templates without any Appwrite calls:

```sh
cd apps/flutter
flutter run -t lib/preview.dart -d chrome --web-port 8426
```

Preview records are synthetic and memory-only. They are never copied into live storage. The live client shows a configuration/startup screen when its public Appwrite configuration is absent.

The restored interface retains the original theme, fonts, launcher, authoring tools, navigation and native capability bridges. Appwrite Account owns sign-in sessions; authenticated Functions enforce current access, definitions, revisions and command receipts. Private uploads use the existing bounded image protocol.

## Protect the Free development quota

Normal tests and CI are **offline**. Development uses manual refresh by default; do not leave old React Native or Flutter polling sessions running against Cloud. Optional automatic refresh must share requests, honor the negotiated minimum interval, and stop when the app is hidden, disposed or signed out.

A single final Cloud smoke is separate from normal verification. Its hard cap is **12 Function executions, 2 authentication requests, and at most one synthetic text-record creation** using an existing account and app. It excludes uploads, AI, new accounts/apps and reminder scheduling; quota errors or uncertain writes stop the run without automatic retries. A Function execution may perform multiple database operations, so the request cap is not a database-operation count. Existing broad Cloud probe suites are retained for their historical contracts and are not part of the Flutter port’s live acceptance run.

## Verify and build

```sh
bash scripts/verify.sh --client-only
TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 \
  bash scripts/verify.sh --backend-only
```

Client verification analyzes the restored application and shared packages, checks formatting, runs spec/renderer/adapter/widget tests, and builds release web assets. Backend verification uses its separate Dart 3.11 toolchain, in-memory services and local transport bridges, checks the shared wire fixture, and compiles both Function entry points. Neither command deploys or calls Appwrite Cloud. `npm run verify` is a convenience wrapper for both checks and needs the backend Dart path when the default `dart` is 3.13.

```sh
cd apps/flutter
flutter build apk --release
flutter build ios --release --no-codesign
```

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
