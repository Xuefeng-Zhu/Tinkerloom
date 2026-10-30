# Tinkerloom backend

This directory contains Tinkerloom's trusted Appwrite Functions and service code. The Flutter client uses the Core Function for authenticated workspace, app, builder, publication and record operations. A separate private Worker handles background work such as generation, reminder reconciliation and media processing when those features are configured.

The backend is written in Dart. The Function runtime and backend checks use **Dart 3.11**; the Flutter workspace uses its own toolchain. See the [project README](../README.md) for running the application.

## Structure

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | Authenticated Core Function entry point |
| `lib/worker_main.dart` | Private Worker Function entry point |
| `lib/service.dart` and related `lib/` files | Service operations, authorization, storage, media and background work |
| `packages/appnest_spec/` | Backend copy of the declarative specification library |
| `schema.json` | Database tables, columns, indexes and Function scopes expected by the backend |
| `test/` | Service, contract and transport tests |

`schema.json` describes the required schema; it does not create or update Appwrite resources by itself. Its tables are configured with row security and empty client permissions. Keep direct table and private-file access restricted to the backend, and use the trusted service for application operations.

## Security and consistency

The Core Function requires an Appwrite user JWT and verifies the account before dispatching an operation. Workspace membership, app grants and action permissions are checked server-side. Deploy the Worker with no public execute permission or public domain. It validates its trigger and execution identity before processing private work.

App definitions are data interpreted by trusted code; model-generated code is never executed. Drafts are private to their authors, and publication is explicit. Mutations use operation IDs, revisions and receipts to detect conflicts and support recovery of the same command when a response is uncertain. Do not issue a new command with a new ID merely because a write response was lost.

Private images use the bounded chunked upload protocol through the service. Generation and reminder support depend on configured services and available workers; their presence in the code is not proof of a configured provider or a delivered notification.

## Function configuration

Appwrite supplies `APPWRITE_FUNCTION_API_ENDPOINT`, `APPWRITE_FUNCTION_PROJECT_ID`, the invoking user identity and the scoped Function execution key. Configure the following environment variables for the services you enable:

| Variable | Purpose |
| --- | --- |
| `PLATFORM_DATABASE_ID` | Database ID used by Core and Worker; required |
| `PLATFORM_WORKER_FUNCTION_ID` | Private Worker Function ID; required for Worker and used by Core to schedule background work |
| `PLATFORM_MEDIA_BUCKET_ID` | Private bucket ID; enables the media adapter when set |
| `PLATFORM_MEDIA_PROJECT_BYTES` | Optional positive project media quota in bytes |
| `PLATFORM_REMINDERS_ENABLED` | Set to `true` to enable reminder handling |
| `PLATFORM_TRANSACTION_DIAGNOSTICS` | Set to `true` to enable Core transaction diagnostic logging |

The required Function scopes are recorded in `schema.json`. Scope and storage permissions should match the features enabled. Keep provider credentials and service keys out of the Flutter app, version control and logs. Provider setup is separate from the default development configuration. See the [Nemotron guide](../docs/NEMOTRON.md) for NVIDIA-specific configuration and evidence boundaries.

The current development project uses on-demand Worker executions and has no periodic Worker schedule. Time-based reminder triggering and periodic recovery are deferred while the schedule is disabled. The client uses manual refresh by default to limit free-tier usage.

## Verify offline

From the repository root, with a Dart 3.11 executable available:

```sh
TINKERLOOM_BACKEND_DART=/path/to/dart-3.11 \
  bash scripts/verify.sh --backend-only
```

This runs backend and specification analysis, formatting checks, local service and contract tests, wire-fixture validation, and Function entry-point compilation. Tests use in-memory stores and local transport bridges; they do not deploy resources or call Appwrite Cloud. The checks may resolve package dependencies when needed.

For all repository checks, including Flutter, see the [project README](../README.md). Cloud verification, account creation and deployment are separate from normal tests and CI.
