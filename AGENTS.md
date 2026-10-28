# Tinkerloom

- The active frontend is React Native with Expo and TypeScript in `apps/mobile`.
- Appwrite is the backend. Trusted operations use Functions; never put service keys or AI credentials in the client.
- `legacy_appnest`, `appwrite_flutter`, and the Dart `packages` are migration references. Do not treat their historical tests or Serverpod behavior as proof of the replacement.
- Preserve explicit preview/live separation, authorization, revisions, safe retries, and durable execution guarantees when migrating behavior.
- Use `npm run verify` from the root for client checks. Native JavaScript bundles can be checked with `npx expo export --platform all` from `apps/mobile`; report native build and device validation separately.
- Keep cloud provisioning, deployment, and public pushes within current user authorization. Do not overwrite existing ignored configuration or log secret values.
