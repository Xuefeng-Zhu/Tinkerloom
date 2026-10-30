# Tinkerloom Appwrite client

The `tinkerloom_client` package connects the Flutter app to Appwrite Account and Tinkerloom's trusted Core Function. It provides typed models, authentication, and adapters for app, builder, runtime, sharing, activity, and media flows.

## Configuration and security

`Client` takes the public Appwrite endpoint, project ID, and Function ID. The Flutter app reads these from its build configuration; passwords, service API keys, and AI-provider credentials must never be embedded in the app. Backend authorization is enforced by the Function, not by hiding controls in the client. See the [development guide](../../docs/DEVELOPMENT.md) for running the app and the [backend guide](../../appwrite_backend/README.md) for the server contract.

## Request behavior

- Entity IDs are opaque strings; revisions and counts are integers.
- Transport and authentication are injectable, so tests can use local services and controlled responses.
- Reads are session-scoped: identical concurrent requests can share work, and session changes discard stale results and queued work.
- Mutations are not automatically retried. When a result is uncertain, the original operation envelope is retained for explicit recovery; the response is checked before success is confirmed.
- Local invalidation follows acknowledged writes. Idle clients do not poll Cloud; refresh is manual by default.
- Published reminder approval metadata is not available from the current backend. Clients must treat approval state as unknown and request explicit acknowledgement when reapproving reminders.

## Test

From the repository root, resolve the workspace dependencies with `flutter pub get`, then run:

```sh
cd packages/tinkerloom_client
flutter test --no-pub
```

The suite exercises controlled transports and the real backend service against in-memory storage. It makes no Appwrite Cloud calls. An offline test cannot establish production, native-device, or live-service behavior.

The separate `live_smoke/` tools are opt-in and can create or change Cloud data. Do not run them as part of normal development or CI; the existing development setup has already been checked. Preserve ignored local credentials and recovery journals, and never print or commit their contents.
