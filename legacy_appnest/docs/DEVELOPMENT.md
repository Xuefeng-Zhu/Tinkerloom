# Local development

This guide describes the current repository workflow. [AGENTS.md](../AGENTS.md) governs coding-agent behavior. [Verification records](VERIFICATION.md) describe checks already executed; commands below are instructions, not a claim that they have all just run.

## Toolchain and first setup

Use the verified set: **Flutter 3.47.0, Dart 3.13.0, Serverpod CLI/server/client/auth 4.0.0**. The root [workspace](../pubspec.yaml), package manifests, and [lockfile](../pubspec.lock) are authoritative. Upgrade the Serverpod family together in a separately verified change.

Check the tools available in your shell:

```sh
flutter --version
dart --version
serverpod --version
```

If the matching Serverpod CLI is absent, install it with `dart pub global activate serverpod_cli 4.0.0` and put the Dart global executable directory on PATH.

From the repository root:

```sh
flutter pub get
dart run scripts/init_local.dart
cd appnest_server
serverpod start
```

The initializer creates ignored development/test secrets in `appnest_server/config/passwords.yaml` only when the file is absent; it never overwrites an existing file and does not configure AI. On supported Unix systems it sets owner-only permissions. Do not copy the example file over existing secrets. In a new worktree, copy matching ignored `.env*` files from the main checkout before local app/auth verification, without printing values; the server's passwords file is a separate prerequisite and AI does not read `.env` automatically.

`serverpod start` generates code, watches source changes, runs the backend, applies pending migrations during startup, and launches the companion Flutter app configured in the [server pubspec](../appnest_server/pubspec.yaml). The driver entrypoint is `appnest_flutter/lib/driver.dart`. Use the launched app or the URL shown in the terminal UI for development.

## Ports, storage, and lifecycle

| Service | Development port / location |
| --- | --- |
| Authenticated API | `http://localhost:8180/` |
| Insights | `http://localhost:8181/` |
| Backend web server | `http://localhost:8182/` |
| Managed PostgreSQL | `localhost:8190` |
| Development database files | `appnest_server/.serverpod/development/pgdata` |
| Test database files | `appnest_server/.serverpod/test/pgdata` |
| Restart smoke database files | `appnest_server/.serverpod/restart/pgdata` |

Port 8182 serves the last built Flutter release from `appnest_server/web/app` when that directory exists; otherwise it serves build guidance. The Flutter companion app can use a separate development URL. A static release build does not reflect subsequent Dart edits until rebuilt.

Serverpod manages real local PostgreSQL because [development](../appnest_server/config/development.yaml) and [test](../appnest_server/config/test.yaml) set `database.dataPath`. The first run may download PostgreSQL binaries. Docker Compose and Redis are not prerequisites for this workflow.

Keep the development terminal open. Stop its AppNest session before using another launch path, and preserve `config/passwords.yaml` and `.serverpod` data. Do not start a second listener or stop another repository's process; other projects can use port 8080.

For a physical device, `localhost` refers to the device itself. The Flutter host accepts `--dart-define=SERVER_URL=<reachable-backend-url>` when running/building. Choose an appropriate trusted local connection; a compiled app and a reachable URL do not establish native-feature acceptance.

## Synthetic demo accounts

From `appnest_server`, after stopping the existing session:

```sh
serverpod start -- --seed-demo
```

Arguments after `--` go to the server. Demo seeding refuses non-development run modes, is repeatable, and does not erase arbitrary data.

| Email | Public synthetic development password |
| --- | --- |
| `morgan@appnest.local` | `AppNest-local-demo-2026!` |
| `alex@appnest.local` | `AppNest-local-demo-2026!` |
| `sam@appnest.local` | `AppNest-local-demo-2026!` |

Sign in as Morgan and select **AppNest demo** in the workspace switcher. Each account also has a personal workspace. Use separate browser profiles for simultaneous users. Keep this seeded environment local. The [demo guide](DEMO.md) explains the authenticated RPC walkthrough and the records it intentionally leaves behind.

## Release-web demo and builds

For an operator-run static web demo, stop the watch session and run this from the repository root:

```sh
bash scripts/run-local.sh --seed-demo
```

The script preserves existing secrets, resolves dependencies, builds Flutter web with the local API URL, and starts the foreground server with pending migrations. Open `http://localhost:8182/`. It does not run the `serverpod start` source watcher or a companion Flutter development process. Omit `--seed-demo` to avoid creating demo accounts.

To build web without starting a server, run from the repository root:

```sh
cd appnest_flutter
flutter build web --release --dart-define=SERVER_URL=http://localhost:8180/ --output ../appnest_server/web/app
```

After adding or removing Flutter plugins, run `flutter clean` and `flutter pub get` in `appnest_flutter` before rebuilding. This refreshes generated plugin registration. Build output is ignored local output, not a deployment.

## Changing the platform

Read [architecture](../ARCHITECTURE.md), [requirements](REQUIREMENTS.md), and the applicable [feature contract](README.md#feature-contracts) first. Keep changes declarative and use trusted Serverpod services for backend behavior.

| Change | Source of truth / required follow-through |
| --- | --- |
| Definition or capability | `packages/appnest_spec`; preserve legacy canonical hashes, validate references, update schema/fixtures and both runtime adapters |
| Shared UI | `packages/appnest_renderer`; verify isolated preview and authenticated live behavior |
| Host/device behavior | `appnest_flutter`; maintain account/backend/app state scopes and local consent |
| Platform model or endpoint | `.spy.yaml`, endpoint/service source, or `lib/server.dart`; let Serverpod regenerate transport/protocol |
| Table shape | Create and apply a migration using Serverpod MCP; inspect non-destructive data evolution and companion integrity guards |

`serverpod start` normally performs incremental code generation and hot reload. Coding agents use Serverpod MCP for migration creation/application, repair, hot restart, and log tails. The user owns starting the development session; if MCP reports it is stopped, ask the user to start it. Do not independently launch another server.

Use the CLI generation/migration fallback only under the conditions in [AGENTS.md](../AGENTS.md), including a server that cannot start. Never hand-edit generated server/protocol/client library files. Hand-authored tools in `appnest_client/bin` are outside that generated library boundary. Generated migration `migration.sql` is a narrow exception for preserving data; keep the resulting schema identical to `definition.sql` and leave other generated migration files alone.

To refresh the exported spec schema and fixtures after an intentional contract change:

```sh
cd packages/appnest_spec
dart run tool/export.dart
```

Inspect the resulting diff and compatibility tests. New labels, optional fields, and supported view combinations do not require a per-mini-app deployment. New platform capabilities require reviewed implementation across the relevant layers.

## Verification

After source changes, follow the order in [AGENTS.md](../AGENTS.md): analysis, formatting, necessary migration creation/application, required hot restart, applicable tests, then server/Flutter log inspection.

The workspace entrypoint is:

```sh
bash scripts/verify.sh
```

It runs workspace analysis, checks authored formatting without changing files, runs the spec/renderer/Flutter/server suites, and executes the separate-process reminder recovery smoke. The server suite uses real managed test PostgreSQL and concurrency one. The recovery probe uses its own persistent database and deliberately exits a writer before scheduling, then opens a reader process.

Focused commands, each from its named package:

| Directory | Command |
| --- | --- |
| Repository root | `dart analyze --fatal-infos` |
| `packages/appnest_spec` | `TZ=America/Los_Angeles dart test` |
| `packages/appnest_renderer` | `flutter test` |
| `appnest_flutter` | `flutter test` |
| `appnest_server` | `dart test --concurrency=1` |
| Repository root | `dart run scripts/restart_smoke.dart` |

Do not run multiple server test invocations against the same managed test database simultaneously. The test lifecycle is separate from the user-run development application. Live RPC demos require the development application; unit/integration suites do not.

Release builds, authenticated browser flows, provider calls, physical-device behavior, and deployment checks are separate acceptance layers. Record them individually in [verification](VERIFICATION.md); do not infer them from a green test suite. The SDK mismatch in the [2026-10-07 architecture review](ARCHITECTURE_REVIEW.md#1-p1--ci-cannot-validate-this-workspace) is historical: all three workflows now pin Flutter 3.47.0/Dart 3.13.0. Published commit `7ba9d63586b90213d24b731058dfabe86487a2f3` passed Analyze, Format and Tests on 2026-10-11; this does not certify later working-tree changes.

The Docker build uses Dart 3.13.0 and a minimal workspace containing the server
and its path dependency, `packages/appnest_spec`. Build from the repository root
with `docker build -f appnest_server/Dockerfile .`. The allowlisted `.dockerignore`
keeps local passwords, environment files, embedded databases and caches out of
the context. Supply production secrets at runtime; do not add them to the image.
Container compilation/runtime and production configuration remain separate
checks from the local test suites.

Native production builds must set `--dart-define=APP_WEB_URL=https://your-appnest-web-host`.
Invitation links use that public web origin. Browser builds use their current
origin when the define is absent. Native development builds may derive web port
8182 from the configured API host on port 8180; phones reject loopback hosts.
The link opens the authenticated web launcher; this does not establish native
universal-link or physical-device acceptance.

The optional Compose databases are not used by normal development or tests.
If needed, provide distinct `APPNEST_DEV_DB_PASSWORD` and
`APPNEST_TEST_DB_PASSWORD` values outside source. Both ports bind to loopback.
For an existing Compose database volume, changing the environment does not
change its initialized PostgreSQL password: rotate that password through the
owner's database administration workflow before reusing the volume. Preserve
the data; do not delete a volume to rotate credentials.

To navigate a running Flutter app, use Serverpod MCP `get_flutter_app_dtd`, Dart MCP `connect_dart_tooling_daemon`, then `flutter_driver`. Text entry emulation is disabled in `driver.dart` for normal hand use; enable it explicitly and hot restart if driver typing is needed. If MCP tools are unavailable, report that evidence limit rather than inventing a driver result.

## Troubleshooting

| Symptom | Check / next step |
| --- | --- |
| Dependency resolution fails | Compare all three tool versions with the verified set and package constraints. |
| A visible page cannot load data | The browser can retain a page after its server stops. Start the user-owned development session and select **Retry**; reconnect retries reads, not business commands. |
| Source changes do not appear | Use the launched development app, or rebuild the static bundle served on 8182. Use MCP hot restart for changes that hot reload cannot apply. |
| New file picker/plugin does not work in release web | Clean, resolve dependencies, and rebuild plugin registration as described above. |
| AI is unavailable or fails | Check the server-side configuration and [AI troubleshooting](AI_SETUP.md); templates remain available. |
| Address already in use | Identify the existing AppNest owner/session; stop that session before relaunching. Preserve other projects. |
| Schema drift | Inspect migrations and companion tenant guards; use MCP repair migration rather than dropping custom guards or resetting data. |
| A command failed after a possible save | Use **Retry save** while the runtime remains open; it replays the retained key, exact input and original revision. Reconnect does not replay business commands. After browser reload, inspect existing records before creating again because pending UI commands do not survive reload. |

[Documentation index](README.md) · [Project README](../README.md)
