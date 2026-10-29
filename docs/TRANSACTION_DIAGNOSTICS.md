# Bounded transaction diagnostics

A transaction observer for the operator's existing authenticated development probes.
Importing this ES module performs no I/O. It has no dependencies or credentials.

```js
import { makeTransactionObserver } from "./transaction_observer.mjs";
const observer = makeTransactionObserver(globalThis.fetch);
// Existing probe configuration: { fetchImpl: observer.fetch }
// After the probe has completed all requests:
await observer.settled();
const sanitizedObservation = observer.snapshot();
```

`fetch` forwards the identical original argument references, preserves thrown error
identity, and resolves to the identical original Response without consuming its
body. The observer adds no HTTP request and never retries. Clone inspection runs
in the background; callers do not wait for it. `settled()` waits only for current
inspections, so call it after the probe's requests have finished.

Only POST `/v1/functions/tinkerloom-core/executions` (also the unversioned path)
is inspected. Request operation is read only from an Appwrite `{body: "{op:…}"}`
JSON envelope or `{data:{op}}`, and retained only when it matches the exported
fixed `operationNames`. String and bounded binary body inputs are supported.
An outgoing init.body stream is never consumed/replaced; its op is unavailable.

Snapshots contain fixed operation/status/error/diagnostic counters and at most 80
conflict-related events. An event is included for a 409, transaction_conflict, or
recognized transaction diagnostic (including a successful recovered execution).
Deployment is only `present | absent | invalid`; deployment IDs are never retained.
Unknown ops/errors/statuses become fixed fallback categories. No execution, app,
actor, workspace, version, record, or deployment ID, request/response header, raw
log, raw body, error message, cookie, token, or credential is included.

Diagnostics match entire trimmed lines `transaction_diagnostic:<category>` only.
The thirteen exported category names exactly match the Core Dart enum. Combined
errors/logs accept at most twelve marker lines per execution; unknown or embedded
markers are ignored. Arbitrary Function logs must not be appended to this output.

Hard bounds: 256 KiB request input, 1 MiB response clone, 64 KiB nested Function
body, 16 KiB each errors/logs field, 2.5-second stream deadline, eight concurrent
inspections, eighty events, and counters saturating at 1,000,000. Over-limit,
unreadable, timed-out, and malformed clone data is ignored with a fixed counter.
Only the clone reader is cancelled; tee cancellation is never awaited and does
not cancel the original response. A skipped/failed observation is not evidence
that a diagnostic or conflict did not occur. This observer does not determine
commit certainty or authorize replay.

Offline verification: `node --test scripts/transaction_observer.test.mjs` — 21 passing
tests, including original fetch/Response identity, ignored secrets/unknown
categories, binary input, Request clone, untouched outgoing stream, ArrayBuffer
and multichunk response byte caps, failing/hanging reads, cap12/cap80, and snapshot
isolation. The offline tests make no Cloud calls. Hosted probe receipts are recorded separately.
