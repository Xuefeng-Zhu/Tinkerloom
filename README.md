# Tinkerloom

Tinkerloom is a mini-app platform built with **React Native, Expo, TypeScript, and Appwrite**. Start with Notes, Tasks, or Reading, customize a saved draft, review and publish its exact version, then create and edit live records.

The current migration delivers an owner-only vertical slice: accounts, workspaces, apps, a bounded field builder, publication, and persistent records. The Appwrite development deployment passed **26 live checks and 181 assertions** on October 28, 2026, including two-account isolation, direct-table denial, stale revisions, command receipts, concurrent writes, and fresh-session persistence. See the [preserved receipts](docs/evidence/2026-10-28/README.md) and [migration status](docs/REACT_NATIVE_MIGRATION.md) for coverage and remaining work. Existing AppNest accounts and data have not been transferred.

A separate manual browser flow verified sign-up, template customization, first publication, and record creation/editing on `127.0.0.1`; after moving to `localhost`, it verified a compatible field addition, version 2 publication, full reload, and sign-out/sign-in persistence. Native-device testing remains pending.

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

`npm run dev` starts Expo. `npm run ios` and `npm run android` open a local development session with a compatible Expo Go or development build. Native builds require platform toolchains; paid EAS builds are optional. Xcode/Gradle compilation, installation, and physical-device behavior remain unverified.

## Build and use an app

Sign in, create a workspace and app, then open its builder. Choose a template, edit its title, description, field labels and choice options, and add optional text, long-text, boolean, or choice fields, up to ten fields. Save the draft, review the saved revision, and publish it before adding live records. Live lists support pagination and record editing.

The trusted Function validates ownership, definitions, compatibility, and expected revisions. Supported mutations commit their changes and operation receipts in Appwrite transactions. A stale write is rejected, and retrying an unconfirmed save retains the original operation ID, input, and versions. Unsaved edits and pending commands last for the current signed-in app session; reloads and process termination do not preserve them.

Full AppSpec/rendering parity, sharing and grant revocation, richer queries/actions/aggregates, AI, private media, capacity workflows, deletion/archival, and durable reminders/outbox workers remain to be migrated.

## Repository layout

- `apps/mobile/` is the active React Native client for iOS, Android, and web.
- `appwrite_backend/` is the trusted Dart Appwrite Function for workspaces, saved drafts, publication, and live records.
- `scripts/live_smoke.mjs` probes the isolated development deployment using two synthetic client accounts, without an admin key.
- `appwrite_flutter/` is the superseded Flutter/Appwrite prototype, retained as reference.
- `packages/` contains the original Dart definition language and Flutter renderer as migration references; React Native does not import them.
- `legacy_appnest/` preserves the original Serverpod implementation for behavioral reference.

## Verify

```sh
npm run verify
```

This runs TypeScript, lint, focused tests, formatting, and web/iOS/Android JavaScript bundle exports. `npm run preview:web` serves the exported web app on port 8426. The GitHub workflow also analyzes and checks the Dart backend; it does not call Appwrite or deploy. Bundle exports do not establish native compilation or device acceptance.

For an explicitly authorized isolated development project, run the live smoke suite separately:

```sh
node --env-file=apps/mobile/.env.local scripts/live_smoke.mjs --database-id tinkerloom
```

The suite creates labelled synthetic QA accounts and rows and leaves them in place. It emits a sanitized JSON report; preserve failed reports alongside later results. See [cloud verification](docs/CLOUD_VERIFICATION.md) for the precise scope and setup.
