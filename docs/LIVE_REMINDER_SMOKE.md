# Gated reminder and inbox probe

This is a prepared probe. Its offline tests do not establish Cloud delivery,
one-shot execution support, worker restart recovery, or device notification
behavior. Importing its modules performs no requests.

`scripts/live_reminder_smoke.mjs` uses ordinary Appwrite account sessions and the
public core Function. It never calls the private worker, supplies an API key,
worker proof, forged execution headers, client clock override, provider, email,
or push service. It creates at most two synthetic accounts and makes at most
300 HTTP requests, including reserved session cleanup requests. Signout affects
only sessions opened by this run. Synthetic accounts and app data are retained;
the probe does not delete accounts or data.

## Operator gate

Do not enable reminders merely to run this script. First obtain permission for
the actual configuration change, verify the deployed private worker, and inspect
an accepted one-shot execution associated with real work. The probe requires
both `--enable-live-reminders=true` and a SHA-256 bound, fresh configuration
receipt. No default, environment variable, or capability inference enables it.

The receipt has exactly these fields, with actual inspected metadata:

```json
{
  "schemaVersion": 1,
  "capturedAt": "2026-10-29T08:00:00.000Z",
  "projectId": "actual-project-id",
  "coreFunctionId": "actual-core-function-id",
  "coreDeploymentId": "actual-core-deployment-id",
  "workerFunctionId": "actual-worker-function-id",
  "workerDeploymentId": "actual-worker-deployment-id",
  "execute": [],
  "domains": [],
  "intervalMinutes": 60,
  "configuredWorkerIdentityMatches": true,
  "remindersEnabled": { "core": true, "worker": true },
  "executionScopesVerified": { "core": true, "worker": true },
  "oneShot": { "accepted": true, "executionId": "actual-work-execution-id" }
}
```

The operator verifies both Functions' execution scopes, their configured mutual
worker identity, empty private-worker execution roles and domains, the supported
recovery interval, and reminders enabled on both deployments. The receipt must be
less than 24 hours old and match every target/deployment argument. It contains no
key, proof, cookie, or credential. This is operator provenance, not cryptographic
server attestation or public-client proof of which worker executed a delivery.

The CLI accepts the full smoke probe's endpoint/project/database/origin/source
and deployment arguments, plus:

```sh
node scripts/live_reminder_smoke.mjs \
  --enable-live-reminders=true \
  --worker-configuration-receipt /absolute/path/verified-worker.json \
  --worker-configuration-sha256 VERIFIED_SHA256 \
  --endpoint https://REGION.cloud.appwrite.io/v1 \
  --project-id PROJECT_ID --database-id DATABASE_ID \
  --function-id CORE_FUNCTION_ID --core-deployment-id CORE_DEPLOYMENT_ID \
  --worker-function-id WORKER_FUNCTION_ID --worker-deployment-id WORKER_DEPLOYMENT_ID \
  --source-commit COMMITTED_SOURCE --max-http 300 --wait-seconds 300
```

The default wait is zero, which prepares and invalidates the synthetic work and
reports delivery as pending. The only nonzero waits accepted are 180–300 seconds.
The live clock is never replaced. A deadline also bounds each HTTP request during
observation. Progress contains only phase names and HTTP counts. Redacted reports
are written to `output/live-reminders/<runId>/report.json` and standard output.
Exit codes are 0 for passed, 1 for failed, and 2 for blocked or observation pending.

## In-memory account reuse

An authorized pooled runner can avoid unnecessary account creation:

```js
const report = await runReminderSmoke(configuration, {
  actorCredentials: async (label, { runId }) => {
    // Return one existing synthetic account from the runner's in-memory pool.
    // label is "owner" or "member". Never persist or print this value.
    return poolForThisRun[label]; // exactly { id, email, password }
  },
});
```

This hook is programmatic only: no CLI, environment, or credential-file option.
IDs and emails must be distinct; email must use `@example.test`; fields are
bounded. The probe sends a normal session request and verifies the authenticated
account ID with `GET /account`. It never sends `POST /account` when the callback
is present, including invalid or unavailable callback results. The report uses
`creationStatus: "reused_verified"` and a
`budget.reusedVerifiedSyntheticAccounts` count, without identities or passwords.
Default execution still creates at most two new synthetic accounts. This does
not bypass account creation or signin rate limits.

## Observed behavior and limits

The probe first requires operational `notifyOwner` and `notifyAssignee`
capabilities. It explicitly publishes approval and bounded old-record enrollment,
accepts recipient-bound member invitations, sets real future timestamps, and
performs the member's self-assignment. Three separate apps let it retain a
successful member delivery while revoking access to another app before due time.

It observes public run history and each account's private inbox. Before due time
it clears a reminder timestamp, changes a workflow condition, and revokes the
other app grant. Stale-run suppression is claimed only when pending runs were
actually observed before invalidation. It checks current-recipient suppression,
cross-recipient read denial, read-receipt replay, a confirmed historical command
receipt, and at most one notification/run for the same occurrence after an
unrelated edit and a bounded additional observation.

Only whitelisted reads retry a transient conflict, at most twice after the first
attempt. Mutations with unknown outcomes are never automatically repeated. The
deliberate receipt checks repeat commands only after their success was confirmed.
An unobserved delivery or insufficient remaining time produces
`observation_pending`. It does not turn hourly recovery into a five-minute claim.

This targets portions of migration D02, D04, D05, D07 and original acceptance 11.
It does not establish D01 atomic rollback, D03 interrupted scheduling recovery,
D06 backoff, D08 reconnect behavior, or D09 provider isolation. Original acceptance
10 (interrupted scheduling recovery) and 12 (reconnect behavior) need separate
evidence. Private worker restart, durable retry/backoff exhaustion,
provider starvation, 500-claimant fanout, hourly timing, scheduling causality,
external delivery, native permission prompts, and device UI are unverified here.

## Offline evidence

Run `node --test scripts/live_reminder_contract.test.mjs` for 16 contract and
orchestration groups. The positive and five-minute pending paths use only a test
HTTP emulator and Node test timers; neither is live scheduling evidence.

Generate the fixture with the Cloud-compatible Dart SDK from `appwrite_backend`:

```sh
dart run test/export_reminder_probe_wire.dart ../scripts/fixtures/reminder_service_wire.json
```

That program uses the actual `PlatformService` and trusted `WorkerEngine`, with
synthetic `MemoryStore` and a test clock. It validates six real state DTOs,
explicit enrollment, repeated worker drains, one owner notification, one member
notification, cross-recipient isolation, matching read receipts, and a revoked
recipient count of zero. It has no Cloud or provider adapter. The JSON fixture
contains synthetic wire data, never deployed credentials or private recipients.


## First real development probe

The preserved `evidence/2026-10-28/reminder-cloud-a05b362.observation-pending.json` confirms authenticated operational effects against the redeployed Core, then stops during synthetic setup with an uncertain write outcome. Eleven HTTP requests included both own-session signouts. No delivery assertion ran and no uncertain mutation was replayed. This receipt lacks the failed operation and execution status; the reporter now retains only allowlisted operation names and sanitized HTTP/Function diagnostics, with idempotent sanitization and no-retry regression checks. A later run cannot retroactively pass this receipt.

`reminder-development-deployments.json` and the SHA-bound worker configuration receipt document current flags, private worker permissions and the redeployment chain. Variable changes alone were not treated as runtime configuration proof.
