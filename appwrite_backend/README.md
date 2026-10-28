# Appwrite backend: first slice

This is a **partial** backend for authenticated creation and listing of owner-only workspaces and app shells. It does not yet create AppSpec definitions, publish or run mini-apps, share workspaces, handle media or run reminders. Existing AppNest accounts and data are not migrated. Do not use this slice as a production replacement.

The function verifies the invoking user's JWT against Appwrite's `/account` endpoint. It uses the ephemeral execution key solely inside the function for TablesDB operations, checks workspace ownership for every app operation, filters lists by the verified user, and returns no stored data to a caller who does not own the workspace. Clients must provide a stable random row ID for each creation attempt. Retrying the same ID and payload returns the original result; reusing it for different data returns `id_conflict`. This limited guarantee holds only while rows remain present and is not the durable general-purpose command receipt system from AppNest. Lists return `too_many_results` beyond 100 rows rather than silently omit data.

## Appwrite setup (manual, not performed)

Use a compatible Appwrite instance with TablesDB and Dart Functions. Create a serverless database and record its ID. Create two tables with **no client table permissions** and row security enabled. Do not grant direct create/read/update/delete permissions to client roles; the function uses a scoped execution key. Create these required string columns and wait until they are available:

| Table ID | Column | Maximum length |
| --- | --- | --- |
| `workspaces` | `ownerId` | 36 |
| `workspaces` | `name` | 128 |
| `apps` | `ownerId` | 36 |
| `apps` | `workspaceId` | 36 |
| `apps` | `name` | 128 |

Create a key index for `workspaces.ownerId` and a composite key index for `apps.ownerId, workspaceId`. Verify index status and the `ownerId` column length against the target Appwrite version. Do not put credentials in this repository.

Create a Dart Function, for example ID `appnest-core`, with this directory as root and `lib/main.dart` as entrypoint. Use a Dart runtime supported by your instance (the implementation targets Dart 3.5 or later). Configure an environment variable `PLATFORM_DATABASE_ID` with the database ID, grant the function `rows.read` and `rows.write` scopes, and permit execution by authenticated users. Appwrite supplies its endpoint, project ID, ephemeral key and the invoking user's JWT. For Flutter web, configure the Appwrite platform and origin correctly. No account, table, function, schema, or deployment was created by these instructions.

Invoke the function synchronously with a JSON body:

```json
{"op":"createWorkspace","id":"clientGeneratedUniqueId","name":"My workspace"}
```

The other operations are `listWorkspaces`, `createApp` (also requires `workspaceId`), and `listApps` (requires `workspaceId`). A successful response has a `workspace`, `workspaces`, `app`, or `apps` property. Errors have an `error` code and a non-2xx status. Client-generated IDs must match Appwrite's ID constraints: 1–36 alphanumeric, period, hyphen or underscore characters and start with an alphanumeric character.

## Local checks and missing verification

Run `dart analyze` and `dart run test/service_check.dart`. These check local Dart source and simulated business logic, not the Appwrite runtime, real authentication, table permissions, persistence, or network behavior. The function must be exercised against a real isolated Appwrite instance with two accounts, including direct table-denial and cross-user checks, retry-after-lost-response, and persistence across fresh sessions before treating this slice as verified. Further work must reproduce AppNest's grant, concurrency, revision, atomic audit/outbox, and reminder recovery guarantees before migration can be considered complete.

References: [Function development](https://appwrite.io/docs/products/functions/develop), [Function environment](https://appwrite.io/docs/products/functions/environment-variables), [Appwrite REST queries](https://appwrite.io/docs/apis/rest), [TablesDB](https://appwrite.io/docs/products/databases/tablesdb).
