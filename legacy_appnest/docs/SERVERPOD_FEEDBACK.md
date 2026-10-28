# Serverpod 4.0.0 feedback

Reviewed on 2026-09-22 while building AppNest with Flutter 3.47.0, Dart 3.13.0, and Serverpod CLI/server/client/auth packages pinned to 4.0.0.

The initial six feedback items retain that historical scope. A 2026-10-07 documentation
cross-check adds current AppNest ownership notes where the
[architecture review](ARCHITECTURE_REVIEW.md) reproduced application defects.
It does not upgrade these observations to claims about newer Serverpod releases,
submitted upstream issues or production behavior.

The original report records one confirmed diagnostic issue, three enhancement requests, and two additional feedback candidates from the AI-app creation trial. Items 7–10 add a startup-state discrepancy, two scheduler enhancement requests and streaming documentation guidance from a fresh 2026-10-07 source review. Items 11–14 add a session-cleanup candidate and three development/deployment tooling requests reviewed on 2026-10-11. Item 15 records the project owner's feedback about manual startup friction. Items 16–17 request clearer preview freshness and restart guidance, reviewed on 2026-10-12. Evidence comes from the installed 4.0.0 packages, official documentation, and AppNest's recorded local verification. Candidates distinguish source observations from runtime behavior still needing an isolated reproduction. This is a local feedback draft; no upstream issues have been submitted.

## Feedback categories

All 17 items are grouped below by their primary request type. These categories
describe the evidence and requested response; they do not assign severity or
turn enhancement requests into confirmed bugs. Individual items retain their
version, reproduction and ownership boundaries.

| Category | Items | Evidence and next step |
| --- | --- | --- |
| Confirmed diagnostic issue | [1](#1-browser-transport-failures-report-a-misleading-response-code-message) | Observed browser failure plus framework source; request more accurate error wording. |
| Candidates requiring isolated validation | [5](#5-clarify-defaulted-endpoint-parameters-and-generated-api-compatibility), [6](#6-classify-expected-websocket-close-races-more-quietly), [7](#7-make-startup-completion-reflect-completed-initialization), [11](#11-guarantee-session-cleanup-when-a-close-listener-throws) | Preserve observed/source-backed behavior and add focused reproductions. Item 7's source discrepancy is confirmed; its runtime/probe impact is unverified. |
| API and scalability enhancements | [2](#2-allow-future-calls-to-be-enqueued-in-a-business-transaction), [3](#3-provide-a-supported-query-path-for-dynamic-jsonb-fields), [8](#8-isolate-future-call-workload-concurrency), [9](#9-bound-due-call-acquisition-before-queuing-the-backlog) | Request transaction-aware scheduling, supported dynamic queries, workload isolation and bounded acquisition; no measured capacity failure is claimed. |
| Documentation and examples | [4](#4-make-committed-concurrency-tests-easier-to-discover), [10](#10-show-cancellation-safe-idle-polling-in-streaming-examples) | Demonstrate committed concurrency and cancellation-safe polling using existing APIs. |
| Development and deployment tooling | [12](#12-provide-one-diagnostic-report-for-agent-setup), [13](#13-add-a-physical-phone-connection-preflight), [14](#14-validate-custom-docker-inputs-before-building), [15](#15-reduce-manual-development-server-startup-friction), [16](#16-make-preview-freshness-visible), [17](#17-reduce-restart-ambiguity) | Request agent diagnostics, phone connection checks, custom Docker validation, opt-in startup automation, preview freshness and restart guidance; environment/application configuration remains separately owned. |

## Subsystem index

Each item appears once in this routing index, under its primary subsystem.
Some requests also improve documentation or diagnostics in another subsystem.

| Serverpod subsystem | Items | Focus |
| --- | --- | --- |
| Client transport and streaming | [1](#1-browser-transport-failures-report-a-misleading-response-code-message), [6](#6-classify-expected-websocket-close-races-more-quietly), [10](#10-show-cancellation-safe-idle-polling-in-streaming-examples) | Network diagnostics, WebSocket teardown and idle-stream cleanup guidance. |
| Session lifecycle and readiness | [7](#7-make-startup-completion-reflect-completed-initialization), [11](#11-guarantee-session-cleanup-when-a-close-listener-throws) | Startup completion semantics and cleanup after callback failure. |
| Future Calls and scheduling | [2](#2-allow-future-calls-to-be-enqueued-in-a-business-transaction), [8](#8-isolate-future-call-workload-concurrency), [9](#9-bound-due-call-acquisition-before-queuing-the-backlog) | Transactional enqueueing/retries, concurrency isolation and backlog acquisition. |
| Database query API | [3](#3-provide-a-supported-query-path-for-dynamic-jsonb-fields) | Supported queries and projections for dynamic JSONB data. |
| Code generation and API compatibility | [5](#5-clarify-defaulted-endpoint-parameters-and-generated-api-compatibility) | Endpoint defaults and generated/wire optionality. |
| Integration testing | [4](#4-make-committed-concurrency-tests-easier-to-discover) | Independent committed-transaction race examples. |
| CLI, MCP and Flutter development | [12](#12-provide-one-diagnostic-report-for-agent-setup), [13](#13-add-a-physical-phone-connection-preflight), [15](#15-reduce-manual-development-server-startup-friction), [16](#16-make-preview-freshness-visible), [17](#17-reduce-restart-ambiguity) | Agent setup diagnostics, physical-phone connections, opt-in startup automation, preview freshness and required restart actions. |
| Custom hosting and build tooling | [14](#14-validate-custom-docker-inputs-before-building) | Docker SDK, dependency-context and secret-exclusion checks. |

## 1. Browser transport failures report a misleading response-code message

**Classification: confirmed diagnostic issue in `serverpod_client`.**

When the browser HTTP client throws `http.ClientException`, Serverpod wraps it in `ServerpodClientNetworkException` with the message `Unknown server response code. (...)`. A request can reach this branch without receiving any HTTP response, so the wording incorrectly directs developers toward response-code handling.

AppNest encountered this with a failed fetch to its local API. The supplied browser evidence showed the response-code message alongside `ClientException: Failed to fetch`. The installed source confirms how that message is constructed:

- Package: `serverpod_client` 4.0.0.
- File: `lib/src/serverpod_client_browser.dart`, lines 92–96.
- The `http.ClientException` catch constructs the message; the adjacent timeout catch already uses a distinct timeout message.

### Reproduction recipe

1. In an isolated development setup, keep the Flutter web page available while its configured API origin is unreachable.
2. Invoke a generated client endpoint.
3. Inspect the resulting `ServerpodClientNetworkException.message`.

This recipe describes the observed failure path; it was not rerun by deliberately stopping a server during this documentation update.

### Requested improvement

Use wording such as “Network request failed before a usable response was received,” retaining the underlying diagnostic and, where possible, the original exception as a programmatically accessible cause. Avoid claiming that the browser can reliably distinguish a stopped server, offline connectivity, or a CORS rejection when it only exposes a generic fetch failure.

**Ownership boundary:** Serverpod already supplies a typed network exception. AppNest was responsible for rendering a raw exception, including its minified class name, directly to users. AppNest now maps exception types to readable recovery states in [HomeLoadFailure](../appnest_flutter/lib/features/home/home_load_failure.dart). This feedback concerns the framework's diagnostic wording, not a claim that Serverpod must supply our product's error screen.

## 2. Allow Future Calls to be enqueued in a business transaction

**Classification: API enhancement request, with an additional retry-policy request.**

The 4.0.0 public scheduling methods accept scheduling information and an optional identifier, but no caller transaction. `FutureCallManager.scheduleFutureCall` inserts the scheduled entry through its internal session. Consequently, committing an application row and enqueuing its related reminder are separate operations. A process failure between them requires application-level recovery.

Installed package evidence:

- `serverpod` 4.0.0, `lib/src/server/future_call_dispatch.dart`: `callAtTime` and `callWithDelay` signatures.
- `lib/src/server/future_call_manager/future_call_manager.dart`, lines 163–186: the scheduling method and its insert through `_internalSession`.
- The same file, lines 366–382: an invocation exception is reported, and the scheduled entry is removed in `finally`.

The [4.0.0 scheduling overview](https://docs.serverpod.dev/concepts/scheduling/overview) correctly distinguishes recovery after process interruption from an exception thrown by the method: exceptions do not automatically retry that call. The [Future Calls documentation](https://docs.serverpod.dev/concepts/scheduling/future-calls) also explains that an identifier groups calls for cancellation; it is not a deduplication key.

### Requested improvement

- Offer transaction-aware enqueueing so application changes and their scheduled intent can commit or roll back together.
- Consider an optional bounded retry policy with backoff and inspectable terminal failure state.
- Provide an official example combining an outbox, idempotent effects, retries, and restart recovery, with cancellation identifiers clearly distinguished from deduplication keys.

AppNest currently persists an outbox and run state, then reconciles and schedules work through [its worker](../appnest_server/lib/src/modules/automation/worker.dart). That design is application code, not evidence that the scheduler's documented behavior is broken. Transaction-aware enqueueing would reduce coordination code; it would not remove the need for idempotent effects or current authorization checks.

**Current AppNest limitation:** the 2026-10-07 architecture review reproduced
execution before a run's persisted `nextAttemptAt` retry deadline, through both
direct scheduled execution and reconciliation. That is an AppNest execution-guard
defect, separate from this framework API request. Persisting backoff alone does
not establish that the application's execution path honors it.

**2026-10-11 AppNest remediation:** retry eligibility is now checked again under
the app lock, and both callers share generation-fenced failure/backoff handling.
The [PostgreSQL regressions](../appnest_server/test/integration/planner_runtime_test.dart)
pass for early wakeups, contention, rollback and exhaustion. This repairs the
application defect without changing the framework enhancement request above.

## 3. Provide a supported query path for dynamic JSONB fields

**Classification: query API and documentation enhancement request.**

Serverpod's dynamic fields preserve runtime types across serialization and persistence. The [4.0.0 dynamic-field documentation](https://docs.serverpod.dev/concepts/data-and-the-database/models/dynamic-fields) explicitly treats the stored type metadata as an implementation detail. Developers therefore should not assume that a stored dynamic map can be queried with paths derived directly from its external JSON shape.

AppNest's [serialization spike](../appnest_server/test/integration/persistence_spike_test.dart) verifies round trips for mixed and nested JSON values. For filtering and sorting, AppNest maintains typed field projections rather than depending on the internal serialization envelope; see the [query architecture](../ARCHITECTURE.md) and [query implementation](../appnest_server/lib/src/modules/runtime/queries.dart).

### Requested improvement

Provide a supported query abstraction for dynamic JSONB content, or release-matched examples that show a recommended projection strategy. Examples should cover field lookup, equality/range filters, sorting, indexes, null versus missing values, and parameterization without relying on private serialization details.

**Ownership boundary:** No serialization defect was found here. Shape validation, authorized field selection, query limits, and tenant filtering remain application responsibilities. The request is to make legitimate querying of flexible data easier to implement and maintain.

## 4. Make committed concurrency tests easier to discover

**Classification: testing documentation and example request.**

The [testing quickstart](https://docs.serverpod.dev/concepts/testing/get-started) explains automatic transaction rollback, which is useful for isolated endpoint tests. Contention tests need an additional distinction: concurrent Dart futures do not by themselves demonstrate competition between independent database transactions that actually commit.

AppNest's [runtime tests](../appnest_server/test/integration/runtime_test.dart) use `RollbackDatabase.disabled`, distinct authenticated sessions, and independent command transactions. The test named `20 independent actors competing for final place accept exactly one` checks both the accepted-result count and the persisted allocation and active-claim counts.

### Requested improvement

Add a prominent recipe for a final-place reservation or inventory-decrement race. Show how to disable the rollback wrapper, create independent sessions and transactions, coordinate competing requests, inspect committed invariants, and isolate or clean up fixtures. Link it from the testing quickstart and row-locking documentation.

**Ownership boundary:** This is not a test-tool defect or a claim that the option is unavailable. The request is to make the correct pattern prominent enough that developers do not mistake shared-transaction tests for evidence of concurrency safety.

## 5. Clarify defaulted endpoint parameters and generated API compatibility

**Classification: observed generation behavior; API compatibility documentation and possible generator enhancement candidate.**

During AppNest's AI-app creation work, adding the named endpoint parameter `bool startFromScratch = true` produced a generated client parameter declared as `required bool startFromScratch`. Existing client call sites then failed static analysis with a missing required argument. An optional parameter in Dart endpoint source therefore did not remain optional in the generated client contract.

AppNest changed the endpoint parameter to `bool? startFromScratch` and applies `startFromScratch ?? true` inside the endpoint. See [BuilderEndpoint.generate](../appnest_server/lib/src/endpoints/builder_endpoint.dart) and the [generated client](../appnest_client/lib/src/protocol/client.dart). The older loaded browser client successfully omitted the new nullable flag during a live AI edit; this compatibility check is recorded in [AI creation check](AI_CREATION_CHECK.md).

### Requested improvement

Clarify whether defaulted, non-nullable named parameters are intended to be supported across the RPC boundary. The [backward compatibility guidance](https://docs.serverpod.dev/concepts/backward-compatibility) permits adding named parameters that are not required; an explicit example should distinguish a Dart default from an optional generated/wire parameter and show the supported nullable-parameter fallback.

If preserving endpoint defaults is intended, carry them consistently into generated client and server dispatch behavior. Otherwise, emit a clear generator diagnostic when a source-level optional parameter becomes required in the generated API.

**Validation boundary:** The generation and analyzer failure were observed in AppNest, and the nullable workaround was exercised by an older client. A standalone generator fixture and omitted-argument wire test are still needed before filing this as a confirmed generator defect. No isolated reproduction was run for this documentation update, and this observation makes no claim about versions beyond 4.0.0.

## 6. Classify expected WebSocket close races more quietly

**Classification: framework diagnostic candidate; no confirmed shutdown correctness defect.**

Local stream teardown produced `WebSocketConnectionClosed` errors while Serverpod attempted to send a final `cmsc` stream-close frame with reason `done`. The local stderr log shows the send occurring after the socket was already closed; these entries lack timestamps, so not every occurrence can be attributed to a development restart. The [AI creation check](AI_CREATION_CHECK.md) and [verification notes](VERIFICATION.md) retain the runtime caveats.

Installed `serverpod` 4.0.0 source explains the diagnostic path:

- `lib/src/server/websocket_request_handlers/method_websocket_request_handler.dart`, lines 180–193: the output-stream close callback sends a final close command.
- The same file, lines 548–568: `tryAdd` catches send failures, logs an error, and reports a framework exception.

### Requested improvement

Distinguish an expected already-closed socket during teardown from an unexpected send failure. Suppress or lower the severity of the expected close race while preserving diagnostics for other transport failures. An isolated streaming endpoint reproduction is still needed to establish the exact trigger and suitable classification.

**Ownership boundary:** The logs also contain PostgreSQL error `57P03` (database system shutting down) from AppNest's polling stream, timestamp-correlated with a planned process restart. Those errors are not established as a Serverpod shutdown-ordering defect. Process-manager and embedded-database termination order are also possible contributors. Installed Serverpod source already closes and awaits WebSockets before stopping the database pool (`lib/src/server/server.dart`, lines 649–659; `lib/src/server/serverpod.dart`, lines 1275–1329). Subsequent authenticated writes, AI edits, publication, and record reloads succeeded. No development restart was performed for this documentation update.

**2026-10-07 application follow-up:** a direct
[RuntimeEndpoint.events](../appnest_server/lib/src/endpoints/runtime_endpoint.dart)
subscription against real PostgreSQL failed to finish cancellation within 2.5
seconds while its app revision stayed unchanged. Cancellation completed after an
app mutation produced another yield. The endpoint needs explicit subscription and
session-close cleanup. This confirms an AppNest stream-lifecycle problem; it does
not establish that the historical WebSocket diagnostic has the same cause or
that Serverpod's shutdown ordering is defective. A live transport cancellation
test remains outstanding. See the [review reproduction and recommendation](ARCHITECTURE_REVIEW.md#4-p2--cancelling-an-idle-event-stream-does-not-stop-polling-promptly).

**2026-10-11 AppNest remediation:** the endpoint now uses a cancellation-aware
controller and a session-close hook. Its [controller regressions](../appnest_server/test/revision_events_test.dart)
pass for idle/pending cancellation, pause/resume, closure and access failure.
Actual WebSocket transport cleanup remains unverified; these application tests
do not establish the cause of the historical framework diagnostic.

## 7. Make startup completion reflect completed initialization

**Classification: source-confirmed semantic discrepancy; runtime/probe impact needs an isolated reproduction. Reviewed 2026-10-07.**

In installed `serverpod` 4.0.0, `isStartupComplete` is documented as true after
`start()` completes successfully, but it returns `_startedTime != null`.
`start()` sets that timestamp immediately on entry, before awaiting startup.
The built-in startup health indicator uses this getter and promises that the
server is fully initialized. Listeners start before Future Call and health-manager
initialization finishes, so the predicate alone cannot establish that contract.

Source pointers in `serverpod` 4.0.0:

- `lib/src/server/serverpod.dart`, lines 70–74, 764–765 and 894–940.
- `lib/src/server/health/serverpod_startup_indicator.dart`, lines 4–9 and 29–33.

**Requested improvement:** track successful startup completion separately from
the start timestamp. Test the predicate while startup is pending, after a startup
failure, and after success. Align the [health-check documentation](https://docs.serverpod.dev/concepts/operations/health-checks)
with those semantics. A premature HTTP probe success was not dynamically
reproduced; this is not a confirmed deployment incident.

Custom startup/readiness indicators already exist through `HealthConfig`.
AppNest must use those or an appropriate traffic gate for its own post-start
integrity setup; that application responsibility is separate from the getter.

## 8. Isolate Future Call workload concurrency

**Classification: scheduler API enhancement request. Reviewed 2026-10-07.**

Installed 4.0.0 has one FIFO task scheduler per Future Call manager and one global
concurrency limit. The inspected scheduling API/configuration offers no named
execution groups, priorities, per-class limits or reserved slots. Long external
AI calls can therefore occupy the same slots needed by short reminders and
reconciliation. Raising the global limit does not provide workload isolation.

Source pointers:

- `serverpod_shared` 4.0.0, `lib/src/config.dart`, lines 990–1018.
- `serverpod` 4.0.0, `lib/src/server/future_call_manager/future_call_manager.dart`, lines 83–93.
- `serverpod` 4.0.0, `lib/src/server/future_call_manager/serverpod_task_scheduler.dart`, lines 24–27 and 105–119.

**Requested improvement:** support named execution groups with separate bounded
concurrency or reserved capacity, plus queue-delay and saturation diagnostics.
Provide a long-external-request versus short-reminder example. Existing
[concurrency configuration](https://docs.serverpod.dev/concepts/scheduling/configuration)
and [server roles](https://docs.serverpod.dev/concepts/scheduling/overview#where-future-calls-run)
remain useful, but roles do not route individual call classes to separate queues.

This is a framework enhancement opportunity. AppNest still owns its workload
choices and reminder retry guard. No starvation or latency benchmark was run.

## 9. Bound due-call acquisition before queuing the backlog

**Classification: scheduler scalability enhancement request; no measured capacity failure. Reviewed 2026-10-07.**

The installed scanner queries every due Future Call row without a limit or
database ordering, sorts the result in Dart, and dispatches all callbacks into
the in-memory queue. A call is claimed when its callback executes, rather than
when the scanner loads it. A concurrency limit bounds execution but does not
bound this loaded batch. Multiple instances can load overlapping due work even
though claims prevent normal duplicate execution.

Source pointers in `serverpod` 4.0.0:

- `lib/src/server/future_call_manager/future_call_scanner.dart`, lines 68–78.
- `lib/src/server/future_call_manager/future_call_manager.dart`, lines 216–236, 285–328 and 345–351.
- `lib/src/server/future_call_manager/serverpod_task_scheduler.dart`, line 65.

**Requested improvement:** use database-ordered, bounded acquisition with
claim-aware selection and queue backpressure. Preserve crash recovery and the
documented at-least-once execution contract. Expose backlog size and oldest-due
age so operators can distinguish scheduling delay from execution time.

This is source-backed design feedback, not evidence of exhausted memory, duplicate
effects or a throughput regression. A large-backlog, multi-instance benchmark is
needed before making capacity claims.

## 10. Show cancellation-safe idle polling in streaming examples

**Classification: documentation and example request; cancellation hooks already exist. Reviewed 2026-10-07.**

The [streaming lifecycle guide](https://docs.serverpod.dev/concepts/endpoints-and-apis/streaming#lifecycle-of-a-streaming-method)
describes cancellation and session closure, but its echo example does not address
an idle database-polling loop that may spend many iterations without yielding.
AppNest's conditional-yield loop demonstrated why this distinction matters.

**Requested improvement:** add a polling or change-notification example that
explicitly stops pending polling, timers and subscriptions on cancellation and
session closure, using existing cleanup hooks. Demonstrate cleanup while the
revision stays unchanged, client disconnect, authentication revocation and
server shutdown. Explain how to avoid awaiting cleanup that depends on the same
stream producing another event.

Installed `serverpod` 4.0.0 already exposes `Session.addWillCloseListener` in
`lib/src/server/session.dart`, lines 14–34; this is not a request for a missing
cancellation API. AppNest's direct endpoint reproduction establishes its own
loop defect, not a framework transport defect. A live transport cancellation
reproduction remains outstanding.

## 11. Guarantee session cleanup when a close listener throws

**Classification: source-backed framework defect candidate; standalone runtime reproduction required. Reviewed 2026-10-11.**

In installed `serverpod` 4.0.0, `Session.close()` marks the session closed, copies
and clears its close listeners, then awaits each listener before entering the
framework cleanup `try` block. If a listener throws, that control flow skips the
remaining listeners, message-central listener removal and session-log
finalization. A later `close()` returns immediately because the closed flag is
already set.

Source pointers in `lib/src/server/session.dart`:

- Lines 203–210: set `_closed`, snapshot listeners and await callbacks.
- Lines 213–227: framework cleanup and log finalization follow the callback loop.
- Lines 23–34: public callback registration/removal API.

**Requested improvement:** isolate errors from individual callbacks so later
callbacks still run, and guarantee framework cleanup independently of callback
success. Preserve and report the original errors. Add a regression with two
listeners where the first throws; verify that the second runs and framework
listeners/logs are finalized even if closure reports an error.

**Validation boundary:** the control flow was independently read and checked
against the pinned package. No standalone execution, live connection leak or
failure in newer releases was reproduced. Application callbacks still own
their cleanup; this request concerns the framework's behavior when one fails.

## 12. Provide one diagnostic report for agent setup

**Classification: CLI/MCP developer-experience enhancement request. Reviewed 2026-10-11.**

The [MCP bridge documentation](https://docs.serverpod.dev/concepts/cli/commands/mcp-server)
explains project auto-detection and explicit `--server-dir` selection. During
AppNest work, the required Serverpod/Dart tools were unavailable in the agent
environment, requiring a documented fallback. That observation does not establish
a Serverpod connection bug.

**Requested improvement:** provide a read-only preflight report showing the
resolved server directory, CLI/package versions, development-runner state, MCP
bridge reachability and configured companion apps. Each failed check should name
the exact next action and distinguish an absent runner, wrong project selection,
missing agent configuration and failed handshake. A machine-readable form would
let agents explain the problem without guessing or starting a duplicate server.

The report should redact credentials and leave process startup under the user's
control. This requests clearer diagnostics around the supported bridge, not a
replacement for configuring an agent environment correctly.

## 13. Add a physical-phone connection preflight

**Classification: development workflow enhancement request. Reviewed 2026-10-11.**

The [endpoint connection guide](https://docs.serverpod.dev/concepts/working-with-endpoints/)
already explains that physical phones need the development machine's network
address, with `SERVER_URL` and `publicHost` configured accordingly. The
[companion-app configuration](https://docs.serverpod.dev/concepts/server-fundamentals/running-your-server)
also supports choosing a Flutter device. These capabilities exist; the request
is to make their combined workflow easier to verify.

**Requested improvement:** when a physical phone is selected, show the resolved
API address and `publicHost`, warn about loopback addresses, offer an explicit
LAN-address choice and a connectivity check, and explain any mismatch before
launching the app. Apply configuration changes only after the developer chooses
the address; multiple interfaces and VPNs make silent selection unreliable.

AppNest still owns its share-link origin and build configuration. Apple signing,
developer trust and device unlock prompts are outside this request. No new
physical-device connectivity reproduction was performed for this addition.

## 14. Validate custom Docker inputs before building

**Classification: custom-hosting tooling enhancement request. Reviewed 2026-10-11.**

The [custom-hosting guide](https://docs.serverpod.dev/deployments/custom-hosting/hosting-elsewhere)
documents the generated Dockerfile and repository-root build context. Serverpod
Cloud already [includes workspace packages](https://docs.serverpod.dev/cloud/reference/private-dependencies)
in its deployment package; this request targets validation of customized Docker
builds rather than a claim that workspace deployment is unsupported.

AppNest's audit found its Docker SDK below the application's declared minimum,
a missing shared-package path dependency, and build-context inputs needing
explicit secret exclusions. Those were application configuration problems and
were repaired locally; they are not established framework-template defects.

**Requested improvement:** add a pre-build check that compares Docker SDK inputs
with package constraints, verifies required workspace/path dependencies enter
the context, and warns when local password/environment/database files could be
copied. Report actionable file paths without printing secret values. Include a
small custom-workspace example and a safe context manifest developers can review.

The developer remains responsible for customized Dockerfiles and runtime secret
delivery. AppNest's equivalent minimal workspace compiled locally; a Linux Docker
image/runtime check remains unverified because no Docker daemon was available.

## 15. Reduce manual development-server startup friction

**Classification: user-reported developer-experience feedback and workflow enhancement request.**

The project owner described the problem directly:

> it is annoying to start the serverpod manually

In this project's agent workflow, the user must start `serverpod start` in a
terminal before connected development tools can proceed. Switching away from
the IDE or chat to start and maintain that session interrupts the development
flow, especially when an agent pauses to request startup during testing.

The [start command](https://docs.serverpod.dev/concepts/cli/commands/start)
already manages code generation, the server and companion Flutter apps together.
The [MCP bridge](https://docs.serverpod.dev/concepts/cli/commands/mcp-server)
connects an assistant to that runner. This feedback requests smoother integration
around those capabilities, not a claim that the command is broken.

**Requested improvement:** offer an explicit project-level opt-in for the IDE
or agent integration to start the local development stack when needed. Remember
that choice so subsequent development/test workflows do not repeatedly require
manual terminal startup or another startup prompt. Reuse an existing project
runner, show startup progress and actionable errors, expose logs, and provide a
visible stop control. Keep the developer in control of the saved preference.

This complements item 12's setup diagnostics: identifying an absent runner is
useful, but completing an already-approved startup would remove the interruption.
AppNest's current user-startup instruction is a project workflow policy, not
proof of a universal Serverpod restriction. This addition records feedback; it
does not change that policy or start a development process.

## 16. Make preview freshness visible

**Classification: development workflow enhancement request. Reviewed 2026-10-12.**

AppNest's [development guide](DEVELOPMENT.md#ports-storage-and-lifecycle) documents
two distinct web paths: a companion Flutter development app and the last built
release bundle served on port 8182. Dart edits do not update that release bundle
until it is rebuilt. A developer can therefore open a working page while viewing
an older build than the source they just changed.

The [Serverpod runner documentation](https://docs.serverpod.dev/concepts/server-fundamentals/running-your-server)
already describes Flutter hot reload, static-file browser refresh and companion
app selection. The request is to make the relationship between the active
preview and those update mechanisms easier to inspect.
Here, preview means the development frontend, not AppNest's isolated mini-app
preview adapter.

**Requested improvement:** show each preview's URL, launch mode, watched status
and last successful reload or build, including pending or failed update actions,
in the development runner and MCP status.
Offer an action to open the running development app and clearly indicate when
a configured static bundle needs rebuilding. For custom build paths, allow
projects to supply build metadata; show unknown freshness when it cannot be
established rather than implying the page reflects current source.

AppNest owns its release-bundle path and rebuild command. No isolated Serverpod
stale-page defect was reproduced; this requests visibility around development
and static preview modes, not automatic compilation of arbitrary custom assets.

## 17. Reduce restart ambiguity

**Classification: CLI/MCP and Flutter development enhancement request. Reviewed 2026-10-12.**

The [Serverpod 4.0.0 runner guide](https://docs.serverpod.dev/concepts/server-fundamentals/running-your-server)
documents that `config/` changes are not watched and require pressing R. In
watch mode, R performs a hot restart for changes that cannot be hot reloaded,
such as startup-only code. A running companion Flutter app also retains its
previous launch settings until restarted from the launch panel.

These rules leave the developer or agent to determine whether a saved change
is active, needs a restart, or requires relaunching the selected app. The
[AppNest troubleshooting guide](DEVELOPMENT.md#troubleshooting) consequently
includes separate hot-restart and static-rebuild checks when changes do not
appear.

**Requested improvement:** surface pending configuration or companion-app
setting changes with a clear reason and the required action: server restart,
Flutter hot restart, or app relaunch. Expose the same status through MCP so an
agent can choose the appropriate existing operation. Provide the action next
to the warning and confirm when the affected process has loaded the new
settings. Explain reload failures and fallback restarts in the same status
view; do not claim to detect every startup-only code change automatically.

This is guidance and state visibility around documented behavior. No new
hot-reload failure was reproduced, and the request does not change migration
approval or imply that every file should trigger an automatic restart.

## Findings outside Serverpod's ownership

The AI trial's malformed responses, prompt context, semantic validation, unreachable generated actions, and missing action-label publication diffs were AppNest/provider issues. They are not evidence of Serverpod defects. Unavailable Serverpod/Dart MCP tools were an environment limitation, not a demonstrated framework failure.

## What worked well

Generated Dart endpoints and clients, embedded PostgreSQL, explicit transactions and row locks, and the integration-test harness fit this application well. AppNest's [recorded verification](VERIFICATION.md) includes real database persistence, a 20-participant capacity race, and a two-process restart check. The [feature map](SERVERPOD_FEATURE_MAP.md) connects these capabilities to product behavior.

The original results remain historical. The 2026-10-11 remediation notes point
to application regression coverage, not proof of framework transport behavior.
Items 7–10 were
cross-checked against installed 4.0.0 source and current official documentation;
no new tests or development-server starts were performed for those additions.
This report makes
no throughput, production-readiness, or multi-instance deployment claim. Item 1
has direct framework diagnostic evidence; items 2–4 request APIs and examples
around supported behavior; items 5–7 retain their stated runtime validation gaps;
items 8–10 request scheduler capabilities and documentation.
Items 11–14 were added from a 2026-10-11 pinned-source and official-documentation
review. Item 11 needs a standalone runtime reproduction; items 12–14 are tooling
requests. No new framework tests, development-server starts, deployments or
upstream submissions were performed for these additions.
Item 15 records direct user feedback and an opt-in workflow request. No startup
automation was implemented or exercised for that addition.
Items 16–17 were added from the development guide and official 4.0.0 runner
documentation on 2026-10-12. They request preview and restart visibility; no new
framework tests, server starts or runtime defect reproductions were performed.
