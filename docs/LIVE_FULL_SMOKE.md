# Full AppSpec REST smoke

`node scripts/live_full_smoke.mjs` is an opt-in, real authenticated REST probe for the full engine. Importing it performs no I/O against Appwrite. This checkpoint was verified offline only; no Cloud requests, resources, deployments or Git state were changed while authoring it.

Review the target, live execution permission and expected synthetic data budget before running. Use Node 22+ (`fetch`, streaming `Response`, `Headers.getSetCookie` and `AbortSignal.timeout`). The script uses no packages, persistent credentials, admin keys, auth bypass or privileged table adapter. It loads only the three public `EXPO_PUBLIC_APPWRITE_*` configuration fields from `apps/mobile/.env.local`; it never loads arbitrary environment file assignments.

```sh
node --test scripts/live_full_contract.test.mjs
node --check scripts/live_full_smoke.mjs
```

A future authorized invocation needs the public endpoint/project/function/database values and the exact deployed core and worker IDs. The `--source-commit` should identify the deployed source (the prepared checkpoint is `b542d9f`); optional `--source-sha256` records its reviewed deployment archive hash. This example is not an execution receipt:

```sh
node scripts/live_full_smoke.mjs \
  --endpoint "$PUBLIC_APPWRITE_ENDPOINT" \
  --project-id "$PUBLIC_APPWRITE_PROJECT_ID" \
  --function-id "$PUBLIC_CORE_FUNCTION_ID" \
  --database-id "$PUBLIC_DATABASE_ID" \
  --source-commit "$DEPLOYED_SOURCE_COMMIT" \
  --core-deployment-id "$CORE_DEPLOYMENT_ID" \
  --worker-deployment-id "$WORKER_DEPLOYMENT_ID" \
  --worker-function-id "$PUBLIC_WORKER_FUNCTION_ID" \
  --max-http 600
```

`--origin` defaults to `http://localhost:8426`; supply an exact registered origin if needed. `--timeout-ms` defaults to 45000. Core Function execution metadata must report the supplied deployment ID and `completed`; an outer API 2xx alone does not pass a business check. Source/archive and worker provenance are operator declarations, not server-attested source proof. The worker Function is not invoked and its deployment is explicitly reported unobserved. The private database ID must be supplied from the reviewed deployment configuration: the user-facing full API does not attest its internal database binding. A known-row denial checks that declared database; it cannot independently prove that declaration matches the Function configuration. Database/table/project/function-not-found errors fail, including when they use a 401 or 403 status.

## Resource and request bounds

The default mode attempts five fresh synthetic accounts: owner, builder, member, viewer and outsider. Passwords, emails, session cookies and invitation bearer tokens remain in memory. It creates two workspaces, one manual full app, all twelve immutable template instances, one remix, one outsider app, 115 reading records, one workflow record and one capacity record. It creates nine bound invitations in the default successful path. Failed runs retain data and sanitized reports; there is no resource/account/record deletion. A final block signs out every temporary session for which the client received a cookie. Lost sign-in responses may leave an unobserved session until Appwrite expiry; this limitation is not reported as successful cleanup.

Every HTTP call, including auth, private-row denials, receipt reads and session signouts, consumes one shared counter. The hard maximum is 600; the CLI may reduce it to 100–600. Remaining signout allowance is reserved before business requests. Budget exhaustion is a failure with dependent checks blocked, never a skipped pass. There is no automatic mutation retry, new-operation repair, reduced fixture size or weaker assertion after failure. Deliberate exact receipt replays and deliberate new conflicting inputs are explicit scenario steps.

The twenty final-capacity requests always use twenty unique operation IDs and are launched together without an application-side throttle. The default mode has **three eligible authenticated actors** (owner, builder and member); it reports this actual count. Multiple successful responses for one already-active claimant are legitimate idempotent behavior, so the test verifies exactly one distinct claimed actor and allocation one rather than asserting exactly one 200 response. It records peak client HTTP concurrency, not a server-side execution barrier or throughput proof. Loser results must be `exhausted_capacity` or `transaction_conflict`; no losing trial request is retried.

Only an explicitly authorized run with `--twenty-distinct-capacity-actors` creates seventeen additional eligible member accounts. That means **22 accounts total**, twenty eligible trial actors and 26 invitations. Its actual HTTP requests still cannot exceed 600. Only this explicit mode may retry an auth 429 using the same exact user identity/credentials, a known server `Retry-After`/rate-limit reset, at most three attempts and at most 120 seconds total wait per auth call. Unknown/long cooldowns fail. No function/business mutation is automatically retried in either mode.

## Assertions

| Area               | Live assertions when the script is run                                                                                                                                                                                                                                                                                       |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full definitions   | Exact twelve-template catalog, empty manual shell, author-private manual drafts, exact review hash and approval arrays, immutable publications 1–3, stale publication rejection, original save/publish/create/instantiate receipts and changed-input conflicts.                                                              |
| Policies           | Actual owner/builder/member/viewer/outsider sessions; personal member/viewer mutation denial; workflow member actions; capacity member claim/release policy; author draft/job absence for readers; outsider and cross-workspace denial. Initial app grants come from explicit invitation acceptance.                         |
| Complete reads     | 115 persisted records, six ranked filtered pages with unique records, case-insensitive text matching, null-last numeric order, global choice totals, sum/average excluding missing numbers, unset query, changed-query cursor rejection and an anchor which ceases to match producing a revision conflict.                   |
| Typed actions      | Finite numeric magnitude/integer rejection, preserved timestamp microseconds, rejection of a civil date used as a full-engine timestamp, half-open UTC aggregate bucket boundaries. Legacy bounded civil dates remain a separate contract and are not reinterpreted here.                                                    |
| Workflow           | Generic workflow/assignment field patches rejected, invalid transition rejected, explicit transition/assignment/ordinary patch committed, stale record revision and outsider assignment rejected.                                                                                                                            |
| Capacity           | Twenty concurrent independent command IDs; current-actor-specific claim readback; exact claim receipt; member configure denial; shrink-below-allocation denial; repeated release counter safety; old receipt does not reclaim; explicit configure and reactivation; exhausted loser rejection.                               |
| Lifecycle          | Every template starts without copied records, immutable paginated version history/get, independent empty remix without inherited grants, actor-private pin/unpin with revision and exact receipts, stale author draft discovery.                                                                                             |
| Privacy/durability | Known-created app/version/record/receipt/draft/pool/claim/audit/outbox direct rows denied, direct row creation denied, wrong app/version/record parent substitution rejected, fresh cookie session reloads persisted state.                                                                                                  |
| Archive/revoke     | Minimal archive acknowledgment followed by authoritative full read; exact old save/publish/record receipts remain replayable while new writes are denied; viewer keeps read access; revoked builder cannot read or recover an old publication receipt. Historical receipt permissions never substitute for a fresh manifest. |

Local validators enforce exact DTO envelope fields, ID/hash/revision limits, reader-private absence and record/aggregate shapes. They do not duplicate the entire Dart AppSpec semantic parser. No AI generation/guidance, provider spend, media execution, reminder delivery, `spec.watch`, UI/native device, Cloud maximum payload or production scale assertion is made. The transport locally enforces the full-engine 6 MiB semantic request and 8 MiB Function response bounds; it does not claim the Cloud gateway accepts those maxima.

## Reports and offline verification

Each attempt writes `output/live-full/<run-id>/report.json` with exclusive creation and mode 0600. Standard output is the same sanitized report. Failed and blocked check entries are retained, including on auth throttling or missing configuration. A write failure changes the exit status to failure. Reports contain fixed allowlisted check names/codes/statuses, public target/provenance, synthetic account/resource IDs, assertion counts, budgets and actual concurrency observations. They exclude request/response bodies, headers, cookies, passwords, emails, tokens, source error messages and arbitrary server strings. A final in-memory secret scan makes the report fail, clears target/account/resource details and retains the failed/blocked check record if a registered private value appears.

The offline suite injects HTTP; it never contacts Appwrite. Eleven tests cover inert imports/configuration/provenance, cookie-only auth transport, cleanup-budget enforcement, exact deployment metadata, transport-vs-business denial classification, body bounds, explicit-only auth cooldown, private-row error classification/leak detection, strict DTO/review contracts, report allowlists/secret scan, and whole-run failure/block retention without auth retries. These results establish local script behavior only.

The script reuses unchanged `scripts/live_collaboration_contract.mjs` and `scripts/live_smoke_denial.mjs`. Its new contract/transport modules do not alter existing collaboration smoke semantics or any failed prior receipt.


## Preserved first Cloud run and concrete probe corrections

The [initial failed report](evidence/2026-10-28/full-cloud-fc71-initial.failed.json)
remains verbatim: 45 passed, three failed, 1,844 assertions, 368 HTTP requests,
five synthetic accounts and peak concurrency twenty with three eligible actors.
The [diagnosis](evidence/2026-10-28/full-cloud-fc71-initial-diagnosis.md) separates
the two setup/expectation errors: applying NUMBER's 1e15 limit to a valid safe
INTEGER, and expecting an owner shortcut that the probe had never pinned.
The fresh-session count failure is consistent with the extra accepted create.

The corrected probe retains numeric and pin-isolation assertions, adds separate
real INTEGER/NUMBER boundary checks, and explicitly establishes the owner's pin.
Thirteen Node contract groups and four actual-service/MemoryStore groups with
36 assertions pass. No backend behavior changed. A new live report is required
to establish the corrected Cloud outcome; offline checks do not replace it.


## In-memory synthetic account reuse

The programmatic `runFullSmoke` and `runMediaSmoke` options accept an optional
`actorCredentials(label, {runId})` callback. It is restricted to bounded synthetic
identities under `example.test`. Every probe still creates its own normal user
session, checks GET/account against the expected identity, and signs out only
that session. Reused identities are reported as `reused_verified`; new and
reused counts remain separate. No CLI/file/environment credential option exists.

`EphemeralSyntheticAccounts` creates at most five synthetic users through the
normal client account endpoint. Concurrent requests for one label coalesce, and
unknown or rate-limited creates are never retried under a replacement identity.
Only in-memory callbacks share credentials between sequential probes. Default
standalone account creation and each probe's HTTP cap remain unchanged. The
twenty-distinct-actor mode cannot use this five-account helper. `forget()` drops
references; it does not claim cryptographic erasure of immutable JS strings.
Offline auth stubs verify this plumbing and do not prove Cloud authentication.


## Corrected full Cloud pass

The [fresh passing receipt](evidence/2026-10-28/full-cloud-fc71-pooled.passed.json)
records48 passed checks, zero failures/blocked checks and1,948 assertions against
core deployment6ae289f866af0d0d2ba7. It used382 probe HTTP requests plus five
separately recorded normal client account creations (387 observed total). Five
provided synthetic identities were freshly authenticated and verified, and all
probe sessions were signed out. Original failed reports remain unchanged.

The capacity trial sent twenty distinct operation IDs at peak HTTP concurrency
twenty using three eligible authenticated actors. Exactly one committed claimant
and one allocation were observed. This is not a twenty-distinct-actor or server
execution-barrier proof. Provider, media, reminders, native/device and actual
data import retain separate acceptance gates.

A prior [network-isolated harness attempt](evidence/2026-10-28/full-probe-network-isolated.failed.json)
made zero probe HTTP requests and confirmed no backend accounts. Its runtime DNS
check returned ENOTFOUND. It was preserved and its in-memory pool closed; the
actual passing run used the approved local Node runtime and ordinary endpoints.
