# Appwrite Flutter migration slice

This prototype is superseded by `../apps/mobile`, the active React Native client. It is retained as migration reference.

This is a separate, early Flutter web client for the Appwrite backend. It signs
in through Appwrite Account and calls the `appnest-core` Function to create and
list owned workspaces and empty app shells. It is not the completed AppNest
rewrite: the builder, renderer integration, records, sharing, AI, media and
reminders are not migrated here.

Register the Flutter web hostname in the Appwrite project, configure an
Appwrite backend and deploy the matching `appwrite_backend` Function before
running this client. The client contains no server API key. The endpoint,
project ID and function ID are public application configuration:

```sh
flutter pub get
flutter run -d chrome \
  --dart-define=APPWRITE_ENDPOINT=https://YOUR_REGION.cloud.appwrite.io/v1 \
  --dart-define=APPWRITE_PROJECT_ID=YOUR_PROJECT_ID \
  --dart-define=APPWRITE_FUNCTION_ID=appnest-core
```

Consult Appwrite's SDK compatibility table for the exact version of any
self-hosted instance; the selected SDK has not been verified against one.
Browser cookie and
platform configuration may require a suitable domain. No credentials, endpoint,
or account are preconfigured. A workspace or app creation attempt retains its
ID and submitted name for retries while its dialog remains open. Pending
requests are not persisted across reloads: if a result is unknown, refresh the
list before starting a new request.

Run `flutter analyze` and `flutter test` once dependencies are available. A
widget test covers retrying an uncertain creation request using the same ID.
It uses a fake backend and is not proof of a live Appwrite deployment.
