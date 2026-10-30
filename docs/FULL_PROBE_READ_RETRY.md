# Bounded full-probe read recovery

The preserved Core43d4334 full report
remains **35 passed / 1 failed / 11 blocked / 724 assertions / 152 HTTP**. Its
47 actual check entries remain unchanged. Failure assertion 21 was the owner's
`spec.getApp` after two successful draft saves and a successful review. The
observer recorded one `spec.getApp` transaction conflict; two `spec.execute`
conflicts belonged to the capacity trial. That trial used 20 attempts/20 keys and
three actors, with three successful receipts but one distinct allocated actor.
It was not a 20-distinct-actor test or a server execution barrier.

This correction changes only the offline/live probe, not the backend or mobile
client. The original report is also copied verbatim in the tmp patch's preserved
folder, SHA256 `4feba0406bb9470edafdef69d6c0280866f8146e20a53f08ec616cc13d79a203`.
A new run must produce its own receipt; this does not turn that failure into a pass.

`executeFullProbeOperation` may repeat an identical JSON snapshot for only the
reads already used in the full probe: `inspectInvitation`, `spec.capabilities`,
`spec.templates`, `spec.getApp`, `spec.getRecord`, `spec.getVersion`,
`spec.launcher`, `spec.listDrafts`, `spec.listVersions`, `spec.query`,
`spec.summary`, `spec.aggregate`, and `spec.review`. Review computes a guarded
snapshot/hash; it does not approve/enroll/publish or call a provider.

All conditions are required: expected status 200, outer integer 2xx, completed
Execution in both parsed/actual envelope, matching actual deployment ID and
transport match, Function integer 409 in both envelope/parsed result, and exact
`{error:"transaction_conflict"}` data. At most two extra reads are made, paced
250 ms apart. The original payload/IDs are retained even if the caller changes its
object while awaiting the read. No new operation ID or cursor is allocated.

Mutations are always single-call. Transport uncertainty, incomplete execution,
wrong deployment, outer error,403/404, revision/definition/cursor errors, extra
error fields, or expected-denial checks never qualify. A new read rechecks current
server authority; revocation can return404 and stop immediately. This read policy
does not determine whether an unknown business write committed and does not
broaden the backend's confirmed-abort classifier.

The existing final `expect` runs once, after recovery/exhaustion. No logical
check/`verify` is added or removed; the successful 48-check suite plan remains.
Actual HTTP requests, including retries, consume the same hard budget and cleanup
reserve. Fixed report counters `budget.readConflicts` and `budget.readRetries`
record qualifying responses (including final exhaustion) and dispatched extra
reads separately. A pre-dispatch budget rejection is not counted as a retry.
No raw diagnostic/body/ID is added; transaction observer output remains separate.

Offline verification: nine new pure groups cover all eligibility/negative bounds,
retained bytes/IDs, exhaustion, failures/authority, actual transport hard budget,
and report counts. Three new stdio bridge groups use actual PlatformService,
WorkerEngine, loopback AppwriteRest simulation and optimistic MemoryStore: the
same race fails at assertion 21 without recovery, recovers with the same 29 healthy
phase assertions and one extra read, creates no new business receipt/audit/outbox,
and denies a revoked builder on the next read. Synthetic local time/auth and REST
simulation are explicit; this is not Cloud scheduling/commit proof. The bridge
uses no provider/Storage/network beyond local loopback.

CI adds this bridge test to the existing backend Node 24/Dart 3.11 step. The pure
contract tests stay in the Dart-free client job. No Cloud runner is invoked by CI.


Verification records are preserved in the [evidence directory](evidence/).
