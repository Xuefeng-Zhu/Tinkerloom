# Tinkerloom

Tinkerloom is a platform for building and sharing small apps. Start from a template or use the visual builder, preview changes in isolation, and publish when the app is ready. The Flutter client runs on web, Android, and iOS; Appwrite provides accounts, private data, and trusted backend functions.

## What you can do

- Explore templates such as Notes, Project Hub, Habit Tracker, and Photo Journal.
- Edit an app's pages, fields, and appearance; save drafts and publish explicitly.
- Use published apps to create and manage records.
- Share apps with other people using invitations and role-based access.
- Use supported device integrations and private image attachments.

The offline preview is a useful place to explore the interface: it uses temporary in-memory data and does not require an account or contact Appwrite.

## Get started

### Requirements

- Flutter **3.47** with Dart **3.13**.
- Chrome for the web commands below. Android and iOS builds also need the relevant platform toolchains.
- An Appwrite account and configured project only if you want to use the connected app.

From the repository root, resolve dependencies:

```sh
flutter pub get
```

To explore the offline preview:

```sh
cd apps/flutter
flutter run -t lib/preview.dart -d chrome --web-hostname localhost --web-port 8426
```

Open <http://localhost:8426>. Preview data is lost when the app is restarted.

To run the connected app instead, from `apps/flutter`:

```sh
flutter run -d chrome --web-hostname localhost --web-port 8426 \
  --dart-define-from-file=config/appwrite.dev.json
```

The repository's development config identifies the existing Appwrite project; it does not provision a project or create a login for you. To use your own project, configure the public endpoint, project ID, and Function ID in `apps/flutter/config/appwrite.dev.json` and register the appropriate app platforms. Never put passwords, API keys, or AI-provider credentials in Flutter configuration or build defines.

You can also run the connected web client with `npm run dev` from the repository root. See the [development guide](docs/DEVELOPMENT.md) for configuration, platform builds, and troubleshooting.

## How it works

- **Flutter app** (`apps/flutter`) — screens, builder, app runtime, and device integrations.
- **Shared packages** (`packages/appnest_spec`, `packages/appnest_renderer`) — the declarative app definition and renderer used by previews and published apps.
- **Appwrite client** (`packages/tinkerloom_client`) — authentication, typed operations, and session-aware request handling.
- **Backend** (`appwrite_backend`) — trusted Core Function and private worker for authorization, app definitions, records, media, and background work.

Apps are represented as data, rather than generated executable app code. Server-side operations enforce access, revisions, and command identity. See the [backend guide](appwrite_backend/README.md) for implementation details and the [Nemotron guide](docs/NEMOTRON.md) for AI configuration and evaluation context.

## Verify and build

Tests and CI use fixtures and local in-memory services; they do not call Appwrite Cloud. From the repository root:

```sh
bash scripts/verify.sh --client-only
TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 \
  bash scripts/verify.sh --backend-only
```

The backend checks require a separate Dart 3.11 SDK and Node.js. Release builds for web, Android, and unsigned iOS are described in the [development guide](docs/DEVELOPMENT.md). A successful build does not establish native device, hardware-permission, or store-signing acceptance.

## Current limitations

- AI-provider setup is not configured in the development deployment.
- Refresh is manual by default to protect the Appwrite Free quota. The current deployment has periodic worker scans disabled, so time-based reminder delivery and scheduled recovery are deferred.
- The connected app uses live backend resources; avoid running Cloud probes or creating test data unnecessarily. The offline preview and normal test suite are the recommended ways to explore and verify changes.
