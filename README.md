# Tinkerloom

Tinkerloom is a mini-app platform built with **React Native, Expo, TypeScript, and Appwrite**. Start with Planner, Notes, Tasks, or Reading, customize a saved draft, review and publish its exact version, then create and edit live records in a list, table, or agenda.

The rewrite includes the full declarative app engine, private drafts and visual editing, explicit publication, shared records, role-based access, collection queries and aggregates, capacity workflows, private media, activity, in-app reminders and native capability adapters. See the [current migration status](docs/MIGRATION_STATUS_CURRENT.md) for implemented behavior, known issues and remaining acceptance gates.

The current checkpoint passed 730 client tests and all three CI jobs. The authenticated Appwrite development suite passed 48 checks and 1,956 assertions; separate activity, reminder and media reports preserve their own source versions and limits. Android and iOS simulator packages compiled and passed an independent source/package audit. Native installation, UI and hardware validation remain pending. [Verification evidence](docs/migration-evidence-index.json) records each layer separately.

Tinkerloom uses **fresh Appwrite development data**. The original AppNest users, records and credentials remain in the original project. AI generation is implemented but disabled on this development backend until a provider is configured.

## Run the React Native client

Use Node.js 24 and npm. From the repository root:

```sh
npm run setup
npm run web
```

Without Appwrite configuration, the app opens an isolated local template preview. Preview records stay in memory, reset when the preview closes, and are never copied into live storage.

For the configured development backend, copy `apps/mobile/.env.example` to the ignored `apps/mobile/.env.local` and set these public values:

```dotenv
EXPO_PUBLIC_APPWRITE_ENDPOINT=https://sfo.cloud.appwrite.io/v1
EXPO_PUBLIC_APPWRITE_PROJECT_ID=6ae1928a003a65851e95
EXPO_PUBLIC_APPWRITE_FUNCTION_ID=tinkerloom-core
EXPO_PUBLIC_APPWRITE_PLATFORM_ID=com.tinkerloom.app
```

The Appwrite Free development project is in SFO, with database `tinkerloom`. Its three platform registrations cover web `localhost`, Android, and Apple; the native identifier is `com.tinkerloom.app`. Use `http://localhost:8426` for the exported web preview. Server API keys and AI credentials never belong in mobile configuration. Follow [the client setup](apps/mobile/README.md), [backend setup](appwrite_backend/README.md), and [cloud checklist](docs/CLOUD_VERIFICATION.md) when configuring another project.

`npm run dev` starts Expo. `npm run ios` and `npm run android` open local development sessions. The custom device module requires a native development build; Expo Go only includes its bundled modules. See [native verification](docs/NATIVE_VERIFICATION.md) for compiled development packages and the remaining installation, UI and hardware checks.

## Build and use an app

Sign in, create a workspace, and choose a starter app. Open its live version, or switch to Build and select **Edit published version** to create your own private candidate. Customize fields, views, actions, pages, appearance and requested reminders with the manual editor. Save, prepare an exact publication review, and publish the reviewed version. Isolated previews use synthetic records that never become live records.

The app engine supports typed records, complete-query sorting and aggregates, calendars, boards, galleries, forms and record navigation. Sharing grants owner, builder, member or viewer capabilities. Reminder requests need explicit approval and eligible records; delivered notifications appear in the in-app inbox.

Trusted Functions validate authentication, current access, definitions, compatibility and revisions. Supported mutations commit receipts, audit and outbox changes atomically. An unconfirmed request retains its original identity and input for explicit recovery. The [current status](docs/MIGRATION_STATUS_CURRENT.md) distinguishes local tests, Cloud behavior, browser checks and native verification.

## Repository layout

- `apps/mobile/` is the active React Native client for iOS, Android, and web.
- `appwrite_backend/` contains the trusted Dart Core Function and private worker for app definitions, records, access, media and durable effects.
- `scripts/live_full_smoke.mjs` and the activity, reminder and media probes verify the isolated development backend. Earlier bounded smoke scripts remain for their original contracts.
- `appwrite_flutter/` is the superseded Flutter/Appwrite prototype, retained as reference.
- `packages/` contains the original Dart definition language and Flutter renderer as migration references; React Native does not import them.
- `legacy_appnest/` preserves the original Serverpod implementation for behavioral reference.

## Verify

```sh
npm run verify
```

This runs TypeScript, lint, focused tests, formatting, and web/iOS/Android JavaScript bundle exports. `npm run preview:web` serves the exported web app on port 8426. The GitHub workflow also analyzes and checks the Dart backend; it does not call Appwrite or deploy. Bundle exports do not establish native compilation or device acceptance.

Live probes are separate from `npm run verify`. They require an explicitly authorized development project and create or reuse labelled synthetic accounts and rows. Preserve failed reports alongside later results. Follow the [Cloud verification guide](docs/CLOUD_VERIFICATION.md) and [current evidence index](docs/migration-evidence-index.json) for each probe’s source, prerequisites and limits.
