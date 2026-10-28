# Semantic watch snapshots

`spec.capabilities.invalidations` advertises
`{mode: "poll.v1", minimumIntervalMs: 15000}`. This negotiates authenticated
foreground polling. It does not grant private row access or promise Realtime,
ordered events, or an event replay cursor.

`spec.watch` accepts exactly `{op: "spec.watch", appId}` and returns only:

```json
{
  "appId": "app",
  "versionId": null,
  "controlRevision": 1,
  "role": "owner",
  "archived": false
}
```

The service validates current workspace membership and app authority through the
existing guarded `_specRead` path, then applies `_publishedOrOwner`. Only an owner
can watch an unpublished shell. Archived apps retain authorized snapshots;
revoked or foreign actors receive `not_found`. Unsupported legacy engines fail
closed. No private candidate, definition, record, receipt, guard nonce, or token
is returned.

`controlRevision` is the existing semantic write counter. Record actions, draft
saves, publications and app control changes invalidate state. Normal reads,
repeated watches and actor-private shortcut changes leave the semantic snapshot
unchanged. Read fences still renew internally; they are never a client watch
token. Concurrent authorization changes conflict or deny instead of committing a
stale snapshot.

Clients negotiate capability availability, poll no faster than the advertised
minimum, deduplicate in-flight reads, pause in the background, and back off on
transient failures. Account/app changes fence late responses. Access loss clears
authorized caches. Snapshot changes trigger ordinary authorized reloads; they
never replay a mutation or resolve an uncertain command without its own receipt.
The minimum is a client polling contract, not a new server-side rate limiter.

Local `test/watch_test.dart` checks metadata-only reads, owner-only shells,
normal/repeated read stability, semantic actions/publication, current roles,
archival, independent workspace authority, strict ID/key handling, cross-tenant
rejection, hydration revocation, and concurrent duplicate reads. These use the
simulated optimistic row store; actual Cloud polling and RN/native foreground
behavior need their separate receipts.
