# Tinkerloom React Native client

Expo SDK 58, React Native 0.88, React 19.3, TypeScript, and Expo Router. This is the active client; the previous Flutter prototype is retained for reference. The home route is `/`, the sample shelf is `/preview`, and each template has a `/preview/:templateId` route.

## Start locally

```sh
npm ci
npm run web
```

Without configuration, the app shows an explicitly local template preview. Notes, Tasks, and Reading can be edited with sample records, required text/choice/boolean validation, title/field-label customization, and reset. Preview records are not persisted and never call Appwrite.

For iOS and Android, start Expo with `npm start`, or use `npm run ios` / `npm run android`. Expo Go must support the selected SDK. A local development build can be made with `npx expo run:ios` or `npx expo run:android` when Xcode/Android tooling is installed; no cloud build account is required. Neither native compilation nor device installation has been verified for this rewrite.

## Connect Appwrite

Copy `.env.example` to `.env.local` and fill in:

- `EXPO_PUBLIC_APPWRITE_ENDPOINT`: your instance's HTTPS API endpoint ending in `/v1`.
- `EXPO_PUBLIC_APPWRITE_PROJECT_ID`: your project ID.
- `EXPO_PUBLIC_APPWRITE_FUNCTION_ID`: the deployed function ID; the suggested name is `tinkerloom-core`.
- `EXPO_PUBLIC_APPWRITE_PLATFORM_ID`: `com.tinkerloom.app`, matching `app.json`. If you change it, also update the iOS bundle identifier and Android package in that file.

Register Apple and Android platforms with the same identifiers in Appwrite. For web, register the actual hostname and use a suitable domain/protocol for session cookies. Only the native adapter sets the platform identifier; web uses Appwrite's browser SDK. Restart Expo after changing environment values.

Deploy/configure the separate `../../appwrite_backend` function and tables before testing cloud features. Its execute permission must allow authenticated users and its tables must deny direct client reads/writes as documented there. Client-side code contains only public configuration and uses Appwrite Account sessions. It creates no service keys.

The cloud flow supports sign-up, sign-in, session restoration, sign-out, owned workspaces, and empty app shells. Unknown creation results retain the original ID, name, and workspace for explicit retry while this app session remains open. Closing and reopening the dialog retains the attempt; returning from a preview also retains it. Pending commands are not durable across reloads or process termination. Inspect the server list before starting a new creation after reopening the app. A failed sign-out keeps the account visible and reports the error.

After an auth response is lost, sign-in makes one read-only account check and accepts it only for the attempted email. It does not repeat the sign-in mutation automatically. Unconfirmed account creation directs the user to Sign in; Check existing session can recover a transient startup failure without creating another session. The retry sheet shows an app creation's original workspace even after the workspace selection changes.

## Checks

```sh
npm run typecheck
npm run lint
npm test
npm run format:check
npx expo export --platform all
```

After exporting, `npm run preview:web` serves the web bundle locally with route handling. The root provider keeps the session controller alive across routes so exploring templates does not discard an unconfirmed cloud save.

Unit tests use injected SDK adapters or local models; they are not evidence of live authentication or persistence. Native exports verify the JavaScript/asset pipeline, not an Xcode/Gradle build. The local preview model intentionally supports a bounded subset of the original Dart AppSpec; it does not claim schema or rendering parity.

References: [Expo project setup](https://docs.expo.dev/get-started/create-a-project/), [Appwrite React Native integration](https://appwrite.io/docs/quick-starts/react-native).
