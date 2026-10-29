# Durable generation and in-app reminder workers

This isolated checkpoint implements trusted generation, reminder planning and delivery, and an actor-private inbox. It has not been deployed or tested against a live AI provider. It extends the AppSpec engine; bounded apps and existing receipt envelopes retain their behavior.

## Deployment boundary and Free plan timing

Use exactly two Functions: the authenticated core (`lib/main.dart`) and one private worker (`lib/worker_main.dart`). The worker must have `execute: []`, no public domain, its own `APPWRITE_FUNCTION_ID` matching `PLATFORM_WORKER_FUNCTION_ID`, and injected execution credentials. Do not create a third Function or a permanent API key.

The private Function serves separate executions for generation, reminder delivery, and reconciliation. The hourly reconciliation execution never waits for a provider response. Generation runs outside every database transaction and uses two durable provider leases. Actual hosted concurrency and execution duration still need verification.

Appwrite's [January 8, 2026 announcement](https://appwrite.io/changelog/entry/2026-01-08) limits Free projects to two Functions. Its [October 15 announcement](https://appwrite.io/changelog/entry/2026-10-15-1) requires a paid plan for cron from October 19 and sets Free intervals to at least 60 minutes. Configure the private recovery interval to 60 minutes or longer. This checkpoint does not claim minute-level hosted recovery.

`AppwriteWorkerWakeups` uses asynchronous execution creation, with a one-shot `scheduledAt` only for actual future work. It rounds up to a whole future minute, at least 60 seconds away. This is not a recurring timer or self-rescheduling reconciliation loop. The [official execution source](https://github.com/appwrite/appwrite/blob/main/src/Appwrite/Platform/Modules/Functions/Http/Executions/Create.php) declares the `executions.write` scope, requires delayed executions to be asynchronous, validates scheduling, and strips reserved headers before injecting platform identity. Whether the current Free Cloud deployment accepts one-shot delayed execution remains unverified. A rejected wakeup retains pending domain work and a bounded dispatch error; hourly recovery can still process due reminders. An unavailable scheduler cannot be reported as successful delivery.

Both Functions need private row read/write access. Add the ephemeral `executions.write` scope only when enabling wakeups. The core never exposes a privileged worker operation. Public requests still require an account JWT; the worker rejects user JWTs/user IDs, wrong Function identity, wrong method, and unsupported trigger. HTTP work additionally requires a 32-byte random proof whose SHA-256 hash is stored privately. It cannot select a mode or target through its body. These application checks complement the required private deployment permissions; they do not prove Appwrite's gateway permissions. Live negative permission tests are still required.

## Persistence and atomicity

`schema.json` is the exact additive schema. All new tables have row security enabled and empty permissions:

| Table | Purpose |
| --- | --- |
| `generation_jobs` | Actor-private request, base/mutation binding, status, attempts, lease generation, safe diagnostics, bounded repair context |
| `generation_sessions` | Latest job and whether successful generation established an edit baseline |
| `worker_leases` | Two bounded provider concurrency slots |
| `worker_dispatches` | Planned/sending/scheduled/running/delivered/failed wakeup receipts, hash-only proof, retry/lease/error state |
| `automations` | Explicit approved rule JSON, enable state, generation and execution actor |
| `enrollments` | Explicit existing-record enrollment batches bound to rule generation |
| `automation_runs` | Unique occurrence/signature, due time, retry budget and atomic outcome |
| `notification_batches` | One atomic recipient batch per delivered occurrence |
| `notification_reads` | Actor-scoped notification read markers |

Optional fields extend `actor_limits` (rolling guidance/generation admission and active job), `spec_records` (creation control revision), and `outbox` (planning progress and errors). Worker instants use canonical `varchar(64)`, preserving microseconds; they are not Appwrite `datetime` projections. `spec_values.numberValue` uses the Cloud-supported bulk column type `double`, and its timestamp remains lossless `varchar(64)`.

Every app write, domain job transition, approval change and delivery stages the workspace/app guard and rechecks the relevant current context. Dispatch receipts and global provider leases serialize on their own affected rows. Actor quota guards serialize admission across apps. Optimistic conflicts during pure worker database transitions retry the same already computed result, up to five tries; they never repeat an HTTP provider call inside the transaction. Unknown commits remain recoverable through authoritative job/run state or public exact receipts. A public unknown response still requires retrying the identical command envelope.

Dispatch rows are wakeup evidence, not business receipts. An execution ID confirms that scheduling was accepted; `delivered` confirms that its handler returned. Generation success and notification delivery are established only by the corresponding domain state. Each dispatch has at most five scheduling attempts; its errors and prior attempts persist. An hourly recovery pass can create a fresh dispatch for still-pending generation work after exhausted or lost wakeups, preserving the earlier trail. There is no short reconciliation loop.

## Generation and provider secrets

The provider adapter, strict output parser, creation compiler, requirement/experience checks, typed edit prompts, scoped repair binding and NVIDIA/OpenRouter profiles are ports of the original AppNest modules. Requests contain the user's idea and allowed definition structure, never live app records. Edits use typed patches with trusted ID allocation and compatibility checks; model-generated code is never executed. A fresh creation never stores a reference template as the user's candidate. The last valid candidate remains intact on failed edits.

Configure server-only `AI_BASE_URL` (HTTPS), `AI_MODEL` and the matching `AI_API_KEY`. NVIDIA requires its separate `NVIDIA_API_KEY` and exact supported route/profile; an existing generic key is never silently sent to NVIDIA. Use protected secret environment configuration in Appwrite and do not put credentials in React Native, table rows, receipts, source, or logs. No secret has been provisioned or provider call authorized by this checkpoint. Original AppNest used protected server password configuration, not a client-editable credential vault; this port preserves that server-only boundary.

Admission reserves one active generation job per actor and 30 requests per rolling day. A job allows three provider attempts, with bounded backoff/Retry-After and 120-second fenced leases. Repair output is bounded and binds job, mutation, base version/hash and mode; transient transport failures retain the last semantic repair context. Terminal, stale and successful jobs clear it. Public diagnostics discard provider envelopes and internal metadata. Guidance is independently limited to 20 requests per actor per rolling day and cannot create a draft, job or record.

Generation installs a valid private candidate only when the author, current role, base publication, draft mutation and lease generation still match. Manual save supersedes active work. Another publication, archive, revocation, lease expiry or later mutation fences a stale completion. A generated candidate never auto-publishes. Review/publish fails with `generation_pending` until the latest job is `preview ready`; a failed edit can explicitly keep its last valid candidate, which increments its private revision and requires a fresh review.

## Reminder semantics

Definitions merely request effects. A publication must explicitly approve `enabledRuleIds`; template/remix/instantiate publication does not enroll or enable effects on its own. Selected old record IDs are enrolled under the approved rule generation. New records created after activation enroll automatically using app control revisions, without depending on timestamp precision. Explicit enrollment persists even when a record's timestamp is currently unset. Unchanged presentation publications preserve generation/enrollment; disabled/re-enabled or changed rules use a new generation and do not silently enroll old records.

Outbox planning processes four record targets per transaction: at most 40 new runs and 40 dispatches, plus guards/progress, below the Free 100-operation transaction limit. Each occurrence is unique for app, rule generation, record and timestamp/due signature. Trigger offsets and conditions preserve the original source semantics.

At delivery the transaction rechecks archive, rule generation, date/signature, condition, approving builder authority, and recipient membership plus explicit app grant. Recipients are resolved then: app owner, current assignee, or current active claimants. Released/revoked claimants receive nothing. Changed or disabled contexts are suppressed. Five failed writes exhaust the run retry budget. A delivery batch and run success commit atomically, so a database failure cannot leave partial inbox success.

The original fanout cap is 500. One private recipient batch supports that cap without staging 500 row inserts in a Free transaction. A notification's stable logical ID derives from run+actor; actors cannot enumerate the batch or other recipient IDs. Inbox queries filter recipient membership, reauthorize current access, and expose a generic unavailable target when the record no longer exists. Read receipts are actor-scoped and reauthorized, including exact retries. These are in-app notifications, not email/push-provider delivery.

## Wire contract

All operations below require the normal authenticated core. Mutations retain the entire original envelope and operation ID on an unknown response or `transaction_conflict`. Replaying never relaxes current authority. Non-current commands receive the existing revision/definition errors.

- `spec.generate {appId, operationId, expectedRevision, expectedVersionId, request, startFromScratch}` → `{generation, app}`. The request is nonempty, preserved untrimmed, at most 16 KiB. Own draft revision is zero when absent. A fresh job has no placeholder draft; a valid completion installs mutation 1. Existing drafts increment their private revision immediately, retaining their last valid spec while pending.
- `spec.getGeneration {appId, jobId}` → `{generation, app}`. The job's author must still be a builder; another builder cannot read it.
- `spec.keepPrevious {appId, jobId, expectedRevision, operationId}` → `{generation, app}`. Only the current failed edit's retained candidate qualifies.
- `spec.guidance {workspaceId, appId?: null|string, request}` → `{questions:[{question, options}]}`. Request limits are 2,000 characters and 4,000 UTF-8 bytes.
- `spec.reminderState {appId, versionId, recordId}` → `{states:[{ruleId, state, scheduledAt, eligible, recipientCount}], versionId}`. State is `unset`, `disabled`, `unenrolled`, `pending`, `delivered`, `suppressed` or `failed`.
- `spec.inbox {afterId?: null|string}` → `{items:[{id, appId, runId, recordId, collectionId, title, body, createdAt, isRead}], nextCursor}`. Page size is 100; target IDs may be null.
- `spec.readNotification {appId, runId, notificationId, operationId}` → `{notificationId, isRead:true}`.
- `spec.runs {appId, afterId?: null|string}` → `{runs:[{id, ruleId, recordId, status, dueAt, nextAttemptAt, attempts, errorCategory, recipientCount}], nextCursor}`. Builder-only, page size 50.

`generation` is `{id,status,mode,mutation,attempts,requestText,diagnostics,provider,model,nextAttemptAt,failureCategory}`. Status is `queued`, `generating`, `validating`, `preview ready`, `failed` or `stale`; mode is `create` or `edit`. Provider/model/failureCategory are nullable. App DTOs add an author-private nullable `generation`.

`spec.capabilities` adds `generation:boolean`, `guidance:boolean`, and an `effects` array containing only currently enabled `notifyOwner`, `notifyAssignee`, `notifyActiveClaimants`. Missing provider configuration returns `provider_unavailable` (409); `generation_active` is 409 and `quota_exceeded` is 429. Parser vocabulary does not imply installed or configured execution. Private media remains fail-closed in this isolated base until the separate media implementation is merged and its scoped reference checks replace the existing guard.

## Verification and remaining live proof

Merged lifecycle/worker local checks: 93 retained backend groups; 31 worker service/transport tests plus 6 fanout regressions; 137 original provider/compiler/quality/requirements/repair tests; 87 bundled AppSpec tests. Analyzer and formatting pass. Provider tests deny actual network access and use injected/mock HTTP clients. Worker business/race/fanout tests use a simulated optimistic store; the wakeup transport test uses a local HTTP server. These are not live Appwrite or provider receipts.

Run:

```sh
dart analyze lib test
dart format --output=none --set-exit-if-changed lib test
dart run test/service_check.dart
dart test test/providers test/workers_test.dart
cd packages/appnest_spec
dart test
```

Before claiming hosted completeness, verify the merged lifecycle/media integration, actual Cloud schema/transactions, private execution permissions and forged-request denials, Free one-shot scheduling support/timing, hourly recovery, provider/profile behavior under an explicitly authorized credential and spend limit, and React Native generation/approval/inbox flows. Cloud request/gateway limits remain separate from local envelope limits. This checkpoint creates no cloud resources and makes no paid or production claim.

The additive [fanout optimization](FANOUT.md) preserves authorization while
reducing the simulated 500-recipient path from 2,024 to 36 transport calls.


## Interval and one-shot trigger distinction

Appwrite marks both interval executions and `scheduledAt` one-shot executions
with the `schedule` trigger. Only an empty interval body enters reconciliation.
A scheduled body containing exactly `dispatchId` and `proof` follows the same
durable proof validation as an immediate HTTP dispatch. Authentication,
`execute:[]`, no user JWT, the 4 KiB body limit, nonce hashes and dispatch leases
remain required. Unknown fields/triggers and empty HTTP bodies remain rejected.

The initial Cloud media probe accepted twenty chunks, and later operator reads
observed the actual asset ready and its cleanup execution scheduled. That
revealed the original worker entrypoint would reject the nonempty delayed body.
Six transport regression groups cover this correction in addition to retained
worker tests. A new deployed delayed-execution receipt is required; an accepted
schedule is not evidence that cleanup or a reminder was delivered.
