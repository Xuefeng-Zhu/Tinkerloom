# Reminder fanout transport optimization

This follow-up changes only recipient authorization in `lib/reminders.dart`.
The frozen worker baseline remains unchanged in its staging directory; this integration applies the additive follow-up. No public API, table, index,
transaction TTL, private worker permissions or domain receipt contract changes.

The previous 500-claimant path called `_workerHasAccess` for every recipient.
For an ordinary actor that reads the app, workspace, membership and grant: four
sequential HTTP GETs. The adapter's transaction TTL is 60 seconds, so the 120/130
second worker leases cannot make an overlong transaction safe.

An instrumented RowStore boundary counted the same complete 500-recipient drain:

| Version | Transport calls | Individual membership/grant GETs | Recipients |
| --- | ---: | ---: | ---: |
| Frozen baseline | 2,024 | 1,000 | 500 |
| Optimized | 36 | 0 | 500 |

The outer drain uses two reads. A single delivery therefore falls from 2,022 to
34 calls. Its guarded transaction has 2,020 versus 32 calls after transaction
creation. At a hypothetical 30ms per sequential call, those portions consume
60.6s versus 0.96s before other latency. These are budget calculations, not
measured Cloud latency or a hosted timing guarantee. [`docs/fanout-budget.json`](docs/fanout-budget.json)
contains the full simulated call breakdown for both implementations.

For recipient sets above eight actors, the helper scans workspace memberships
and app grants in complete 100-row pages under the already staged app/workspace
guards. For 501 memberships and 500 grants this takes six pages each; exact
100-row multiples include a terminal empty page. With M workspace membership
rows and G app grant rows, authorization requires `floor(M/100)+1` plus
`floor(G/100)+1` list calls. Larger workspaces still need a live latency probe.
Small sets retain the existing keyed reads to avoid scanning a large unrelated
workspace for one recipient.

The helper preserves keyed authorization exactly: workspace owner implicit
membership, otherwise active canonical membership; app owner implicit app
access, otherwise canonical non-revoked builder/member/viewer grant in the same
app and workspace. Workspace ownership alone never grants an app, and an app
owner in another owner's workspace still needs membership. Canonical row IDs
are checked so a duplicate/noncanonical row cannot replace a revoked or absent
keyed membership/grant. Active claims are still evaluated at delivery, and
unrelated actors do not enter the recipient batch.

All supported membership/grant mutations update the same workspace/app guards.
A revocation concurrent with batch insertion conflicts and retries the entire
authorization snapshot; it cannot leave a committed notification for an actor
whose revocation won. The batch and run outcome remain atomic, with the same
500-recipient bound and five-failure retry budget.

Verification adds six focused tests: transport-call bound, malformed and
noncanonical membership/grants, distinct owner exceptions, unrelated members
and inactive claims, and grant revocation during batch insertion. All 31 worker
checks remain intact. This is simulated optimistic-store proof. Actual Free
Cloud RTT, transaction lifetime, function duration and 500-recipient delivery
remain separate live verification work.
