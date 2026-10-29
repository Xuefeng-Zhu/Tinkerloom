# Tinkerloom

- The active frontend is the original Flutter application restored in `apps/flutter`, using Flutter 3.47 / Dart 3.13. React Native is preserved on `codex/react-native-backup-20261029`.
- Appwrite remains the backend. The injectable hand-authored Dart client is `packages/tinkerloom_client`; trusted Core Function and private worker source remain in `appwrite_backend` with their separate Dart 3.11 toolchain.
- Reuse the shared declarative contract and renderer in `packages/appnest_spec` and `packages/appnest_renderer`. Never execute model-generated code. Entity IDs are opaque strings; revisions and counts remain integers.
- Preserve original AppNest files, ignored configuration, data and credentials. `legacy_appnest` and the old prototype are historical references, not current acceptance evidence.
- Preserve isolated previews, server authorization, explicit publication, expected revisions and operation IDs. Never put service keys or AI credentials in Flutter.
- Normal verification is offline: `scripts/verify.sh --client-only` and `TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 scripts/verify.sh --backend-only`. No Cloud probe, new account, deployment or seed belongs in normal tests or CI.
- Development refresh is manual by default. Optional polling must share reads, respect the negotiated minimum interval, and stop when hidden, disposed or signed out. Never restore the original two-second generation or ten-second inbox polling loops against Appwrite.
- The one authorized final smoke has a global maximum of 12 Function executions, 2 Account requests and one synthetic text-record creation. Reuse an existing account/app; no uploads, AI, reminder scheduling, new accounts/apps or automatic retries. Stop on quota errors or uncertain writes. Function request counts are not database operation counts.
- Use `scripts/verify.sh` for analysis, format checks, tests and a web build; it does not deploy. Native compilation and actual device/UI acceptance must be reported separately. Commit progressively; preserve the pushed React Native backup before removing its active source.
