# Tinkerloom

Tinkerloom is an early-stage rewrite of AppNest using **React Native, Expo, TypeScript, and Appwrite**. Its goal is to let people build and use shared mini-apps from declarative definitions.

**Migration status: incomplete.** This repository is being assembled. The existing AppNest application has not yet been migrated to Appwrite, and its user accounts, data, sharing rules, concurrency controls, and reminders have not been transferred or verified here. Do not treat this repository as a production-ready replacement.

## Run the React Native client

Use Node.js 24 LTS and npm. From the repository root:

```sh
npm run setup
npm run web
```

The unconfigured app opens a local template preview. Notes, Tasks, and Reading support sample record creation/editing and title/label customization. Preview data stays in memory and is reset when the preview closes. It is separate from Appwrite.

For Appwrite sign-in and saved workspace/app shells, copy `apps/mobile/.env.example` to `apps/mobile/.env.local` and supply your public endpoint, project ID, and function ID. Follow [the client setup](apps/mobile/README.md) and [backend setup](appwrite_backend/README.md). Server API keys and AI credentials never belong in the mobile configuration.

`npm run dev` starts Expo. `npm run ios` and `npm run android` open a local development session; use a compatible Expo Go or development build. Native builds require the platform toolchains. This project does not require paid EAS builds.

## Repository layout

- `apps/mobile/` is the active React Native client for iOS, Android, and web.
- `appwrite_backend/` contains the initial Appwrite Function: owner-only workspace and app-shell creation and listing.
- `appwrite_flutter/` is the superseded initial Flutter/Appwrite prototype, retained as reference.
- `packages/` contains the original Dart definition language and Flutter renderer as migration references. They are not imported into React Native.
- `legacy_appnest/` is a committed-source snapshot retained as a reference for behavior and migration. It is the original Serverpod implementation, not the Tinkerloom backend.

The React Native client has Appwrite authentication, workspace/app-shell lists, safe creation retries, and isolated template previews. The full mini-app builder, live records, sharing, AI, private media, and durable reminders remain to be migrated. No Appwrite project or infrastructure is created by this repository. See the [migration status](docs/REACT_NATIVE_MIGRATION.md) for exact verification boundaries.

## Verify

```sh
npm run verify
```

This runs TypeScript checks, lint, focused tests, formatting checks, and web/iOS/Android bundle exports. `npm run preview:web` serves the exported web app locally on port 8426. Bundle exports do not establish native compilation, installation, physical-device behavior, or live backend acceptance.
