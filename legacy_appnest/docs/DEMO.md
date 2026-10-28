# Local demo

This is a repeatable local walkthrough, not a record of a newly executed demo.
Historical results are in [verification](VERIFICATION.md) and the
[connected rich-component check](RICH_COMPONENTS_LIVE_CHECK.md).

Follow the [development guide](DEVELOPMENT.md) to prepare the local configuration
and start the application yourself. From `appnest_server`, the seeded development
workflow is `serverpod start -- --seed-demo`. Open the companion Flutter URL shown
by the Serverpod TUI. The manual `scripts/run-local.sh --seed-demo` fallback is a
separate workflow that builds and serves the release web app at
`http://localhost:8182/`; it has no development watchers. Do not run both workflows
against the same development database at once.

Use the synthetic account details in that guide and sign in as Morgan. Use
separate browser profiles for Alex and Sam when demonstrating simultaneous people.
Keep this seeded environment on a trusted local machine. The endpoint scripts
below expect the running API at `http://localhost:8180/` and seeded Morgan, Alex
and Sam accounts. They do not start the server. Preserve
`appnest_server/config/passwords.yaml` and the ignored database directories.

## UI walkthrough

1. Select AppNest demo. Open each of Reading Journal, Chore Board and Volunteer Shifts. They are interpreted by the same renderer; add/edit records and reload.
2. Use a template to open the builder. Preview records are visibly synthetic and local; joining a preview shift does not create a live claim.
3. If the operator has configured a real provider, describe “Volunteer shifts for our food pantry, with one place per shift and an in-app reminder.” Inspect the persisted job state and resulting validated preview; polling can skip brief intermediate stages. Without credentials, use the visibly labeled template/manual path. Do not narrate it as AI generation.
4. Review the exact candidate, policy/capabilities, optional existing-record scope and reminder requests. Publish explicitly. Create a live shift with capacity one.
5. Copy separate member invitation links for Alex and Sam. Both open the same app, not copies. Have them join concurrently. One is confirmed; the other sees exhausted capacity. There is no optimistic reservation guarantee.
6. Owner: Edit with AI, request an optional preparation field (credentialed path), or Edit manually → AddField (explicit manual fallback). Review and publish. Sign-ups and stable IDs survive.
7. In the accelerated automated demo, the shift starts in one hour plus 35 seconds, so its approved one-hour-before reminder is intended to become due in about 35 seconds. Scheduler load can delay delivery. This is synthetic demo timing, not a changed platform clock. Close clients, wait, reopen the winner's Inbox and owner's Activity and reminder history.

## Automated real-endpoint walkthrough

```sh
cd appnest_client
dart run bin/local_demo.dart --accelerated-template-demo
```

Run each command block in this guide from the repository root. This creates a new
app on each run and leaves it available for inspection. It uses real
email/password logins and generated clients, role-specific invitation acceptance,
concurrent capacity commands, explicit candidate publication and the running
server's scheduled work. It does not call worker internals or a live AI provider.
The winner is nondeterministic. The script waits 48 seconds before its delivery
check; a successful run prints one notification and one successful run after
clients close/reopen. That fixed wait is not a delivery-time guarantee.

For private-image transport, workflow conflicts and database-wide aggregates:

```sh
cd appnest_client
dart run bin/rich_components_smoke.dart --run-rich-smoke
```

This second script also leaves fresh synthetic apps and records in the development
database. Its [2026-09-23 results](RICH_COMPONENTS_LIVE_CHECK.md) are historical;
rerunning it does not verify Flutter interaction, native devices or production
storage.

## Crash recovery

```sh
dart run scripts/restart_smoke.dart
```

Unlike the endpoint demos, this test deliberately starts isolated probe
processes. It uses `appnest_server/.serverpod/restart/pgdata` /
`appnest_restart_smoke`, separate from the development database. Process one
commits a run and exits immediately before scheduling. Process two starts
independently and reconciles it, then repeats the wakeup and checks one persisted
notification. It checks claimant and owner reminder scenarios. Each run uses
unique synthetic identities and retains its database. A passing run validates
that process boundary, not general crash, backup or retry-timing correctness.

## Known limitations while demonstrating

The [architecture review](ARCHITECTURE_REVIEW.md#confirmed-findings) records
unresolved command-retry, legacy UI authorization-state, idle-stream cancellation,
reminder backoff and revoked-assignment defects. For example, a revoked chore
assignee must currently be changed before unrelated note/status edits succeed.
Do not describe successful happy-path demos as acceptance of those failure paths.

Live AI credentials, production email delivery, native-device installation and public deployment are outside the evidence collected here.
