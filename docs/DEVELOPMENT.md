# Development guide

Tinkerloom is a Flutter workspace with an Appwrite backend. This guide covers local development and verification. Run commands from the repository root unless a different directory is shown.

## Prerequisites

- Flutter 3.47.0 with Dart 3.13.0 for the app and shared packages. Check with `flutter --version`.
- Chrome for the web commands. Android builds require the Android SDK and Java 17; iOS builds require macOS and Xcode. Flutter's platform setup may require additional platform tools.
- The backend checks use a separate Dart 3.11 SDK. Node.js is also needed for their local transport tests. Node.js and npm are optional for the Flutter commands themselves.

Install the workspace dependencies:

```sh
flutter pub get
```

## Explore without Appwrite

The preview runs entirely in memory with sample data. It does not sign in or call Appwrite, and its changes do not persist to a live app.

```sh
cd apps/flutter
flutter run -t lib/preview.dart -d chrome --web-hostname localhost --web-port 8426
```

Open `http://localhost:8426`. The preview is useful for working on templates and UI without using a development project's quota.

## Run the connected app

The connected client needs a configured Appwrite project with the Tinkerloom backend deployed. The checked-in `apps/flutter/config/appwrite.dev.json` contains public configuration for the existing development project; running against it uses that project's resources. To use a different project, run `mkdir -p output` from the repository root, then create the ignored file `output/appwrite.local.json`:

```json
{
  "APPWRITE_ENDPOINT": "https://YOUR_APPWRITE_ENDPOINT/v1",
  "APPWRITE_PROJECT_ID": "YOUR_PROJECT_ID",
  "APPWRITE_FUNCTION_ID": "tinkerloom-core"
}
```

Replace the placeholders with your own endpoint and project ID, and use the ID of your deployed Core Function if it differs. Register the hostname `localhost` as a web platform in that Appwrite project. Setting these client values does not create or deploy backend resources.

From `apps/flutter`, launch with your local configuration:

```sh
flutter run -d chrome --web-hostname localhost --web-port 8426 \
  --dart-define-from-file=../../output/appwrite.local.json
```

Alternatively, `npm run dev` from the repository root uses the checked-in development configuration. The native Android and iOS app identifier is `com.tinkerloom.app`; register the relevant platform identifiers in the target project before testing on those platforms.

The endpoint, project ID, and Function ID are public client configuration and are included in the compiled application. **Never put API keys, passwords, session tokens, or AI-provider credentials in a Dart define file or client build.** Keep local secrets and test credentials in ignored files, and do not commit or print them. Client calls use Appwrite Account sessions; privileged operations belong in the authenticated backend Function.

## Verify changes

The default verification scripts do not call Appwrite Cloud. They test the service with in-memory stores and local transports, so they can be run without consuming Appwrite request or database-operation quota. Dependency resolution and tool installation may still need network access.

```sh
# Flutter app, shared packages, formatting, tests, and a web build
bash scripts/verify.sh --client-only

# Backend and local contract tests using the separate Dart 3.11 SDK
TINKERLOOM_BACKEND_DART=/path/to/dart-3.11/bin/dart \
  bash scripts/verify.sh --backend-only
```

`npm run verify` runs both sets; `npm run verify:client` and `npm run verify:backend` select one. GitHub Actions runs the client and backend checks in separate offline jobs. To run individual Flutter tests, use the package as the working directory; in particular, run app tests from `apps/flutter` so assets resolve correctly:

```sh
(cd packages/tinkerloom_client && flutter test --no-pub)
(cd apps/flutter && flutter test --no-pub)
```

## Build

From `apps/flutter`, use a public configuration file for connected release builds:

```sh
flutter build web --release --dart-define-from-file=config/appwrite.dev.json
flutter build apk --release --dart-define-from-file=config/appwrite.dev.json
flutter build ios --release --no-codesign \
  --dart-define-from-file=config/appwrite.dev.json
```

Replace the config path with `../../output/appwrite.local.json` to target your own project. From the root, `npm run build:web`, `npm run build:android`, and `npm run build:ios` use the checked-in configuration. The Android release build currently uses a development debug signing key; the iOS command produces an unsigned build. Distribution requires appropriate signing. A successful build alone does not verify native installation, device permissions, or hardware behavior.

## Appwrite quota and background work

Use the in-memory preview and offline tests for routine work. The connected app defaults to manual refresh. Treat live sign-ins, Function calls, and data writes as quota-consuming operations: a Function execution can make multiple database calls. Do not run the separately gated live smoke tools, create test accounts or records, or schedule background jobs without an explicit need and authorization. The development worker runs on demand; periodic recovery and time-based reminder triggering are not enabled. AI-provider configuration is also not set up by the client.
