# Collaboration, private drafts, and invitation recovery

All tables remain private: table and row permissions are empty, and only the trusted Function uses its ephemeral `rows.read`/`rows.write` key. The Function verifies the user's Appwrite JWT against `/account`; caller-supplied account IDs never establish the actor. No new persistent key is required.

## Access policy

Workspace membership is necessary but does not reveal every app in that workspace. Each app also requires ownership or an explicit non-revoked app grant. The app's owner may differ from the workspace owner. A workspace owner cannot read another member's app solely through workspace ownership.

| Role    | Published app and records | Own private draft | Structure/publication | Sharing and non-owner grants | Archive |
| ------- | ------------------------- | ----------------- | --------------------- | ---------------------------- | ------- |
| Owner   | Read                      | Read/edit         | Yes                   | Yes                          | Yes     |
| Builder | Read                      | Read/edit         | Yes                   | Yes                          | No      |
| Member  | Read                      | No                | No                    | No                           | No      |
| Viewer  | Read                      | No                | No                    | No                           | No      |

The current bounded definition uses personal-tracker policy: only owners/builders write records. Membership does not enable generic workflow transitions, assignment, or capacity edits. Future business actions must retain the original AppSpec capability-policy checks. Archived apps remain readable to authorized actors; structure, publication, record writes, new invitations, and grant creation/promotion remain blocked. Owners/builders retain `revokeAccess: true`, allowing removal of existing access and revocation of invitation tokens after archival. Only the app owner can archive, and archive is permanent in this operation contract.

Every draft belongs to its author, including against other builders and the app owner. A non-owner cannot discover another author's unpublished app through app listing or `getApp`. App lists contain identity, role, archive state, and capability flags; they never contain candidate definitions. Members and viewers can read the authorized member directory, while invitation management requires owner/builder authority.

## Private draft and publication DTO

The existing app response retains `id`, `workspaceId`, `name`, `draftRevision`, `publishedRevision`, nullable `definition`, and nullable `publishedDefinition`. New ordinary responses additionally contain:

```json
{
  "role": "builder",
  "archived": false,
  "candidateRevision": 7,
  "basePublishedRevision": 4,
  "capabilities": {
    "editDefinition": true,
    "share": true,
    "writeRecords": true,
    "archive": false,
    "revokeAccess": true
  }
}
```

`draftRevision` is the requesting author's private local counter. Each saved candidate also receives a global `candidateRevision`, allocated under the common app guard. These counters are independent: `publishedRevision` may exceed the requesting author's `draftRevision`. A builder without a private candidate, or a member/viewer, receives `definition: null`, `draftRevision: 0`, and `candidateRevision: 0`. The current publication remains available separately.

`saveDraft` retains `appId`, `operationId`, `expectedRevision`, and `definition`; new clients also send `expectedPublishedRevision`. The returned local draft counter is `expectedRevision + 1`. `publishApp` retains `appId`, `operationId`, and `expectedRevision`; new clients also send `expectedPublishedRevision` and `candidateRevision`. Publication verifies the author, exact private candidate, and unchanged published base, then sets `publishedRevision` to that candidate's global revision. A stale private candidate cannot overwrite another author's intervening publication. Explicitly saving a candidate against the current publication is the rebase/review step; the backend does not silently rebase an old publication request.

Existing v1 owner rows are adopted atomically into owner-private drafts before collaboration mutations can publish. The optional `apps.headRevision` column must have **no default**, preserving null as the legacy marker; new apps explicitly start it at zero. Existing owner IDs, app/record IDs, and command receipts are preserved. A legacy receipt returns its original stored response, which may omit new capability/candidate fields. Such omissions are compatibility acknowledgments, not permission to elevate the client UI.

## Collaboration operations

All mutations retain the exact operation ID and input on an uncertain result. Revision inputs are nonnegative integers below 2,147,483,647. Grant creation starts at revision 1; the immutable owner directory entry has revision 0.

| Operation           | Input after `op`                                                             | Response                                                        |
| ------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `createInvitation`  | `appId`, stable `id`, `operationId`, `role`, nullable `recipientId`, `token` | `{ invitation }`                                                |
| `inspectInvitation` | `token`                                                                      | `{ invitation: { appId, appName, role, expiresAt, accepted } }` |
| `acceptInvitation`  | `token`, `operationId`                                                       | `{ appId }`                                                     |
| `listInvitations`   | `appId`, optional `afterId`                                                  | `{ invitations, nextCursor }`                                   |
| `revokeInvitation`  | `appId`, `invitationId`, `operationId`                                       | `{ invitation }`                                                |
| `listMembers`       | `appId`, optional `afterId`                                                  | `{ members, nextCursor }`                                       |
| `setGrant`          | `appId`, `actorId`, nullable `role`, `expectedRevision`, `operationId`       | `{ member: { actorId, role, revision } }`                       |
| `archiveApp`        | `appId`, `operationId`                                                       | `{ app }`                                                       |

`inspectInvitation` is an authenticated, read-only review step before explicit acceptance. It verifies token format/hash, current expiry/revocation, recipient binding, issuer authority and grant generation, and current access for the already-accepted actor. It returns no issuer account, email, token hash, workspace details, private candidate, or records. Unknown, expired, revoked, consumed-by-another-actor, and unauthorized tokens all return the same unavailable error. Inspection does not create membership, consume a token, or write a receipt.

Invitation/grant roles are `builder`, `member`, or `viewer`. A null role in `setGrant` revokes an existing grant. Grants cannot be used to add an actor who has never accepted an invitation, and the owner grant is immutable. Owners and builders may change other non-owner grants, including promotion to builder; this matches the original sharing policy.

Invitation metadata is `{ id, appId, issuerId, role, recipientId, createdAt, expiresAt, revoked, acceptedBy }`. Recipient and accepted actor IDs are nullable strings; revocation is a boolean. Creation and expiry are UTC ISO 8601 instant strings, with milliseconds and optional microseconds. The member DTO is `{ actorId, role, revision }`.

Invitation pages contain at most 25 entries. Member pages scan at most 50 grants and prepend the owner only on the first page, so at most 51 members are returned. Revoked or workspace-inactive grants are filtered. Therefore a short or empty member page can still have a cursor. Cursors are opaque underlying row IDs, not actor IDs; a cursor from another app is rejected. Continue until `nextCursor` is null to establish a complete directory.

## Token and revocation guarantees

The client generates 32 bytes from a cryptographically secure random source, encodes them as exactly 43 unpadded base64url characters, and retains that token with the pending invitation command. The backend verifies length and canonical encoding. Token secrecy is the bearer authorization for an unbound invitation; share it only with the intended recipient. Recipient-bound invitations additionally require the authenticated account ID to match.

Only the SHA-256 token hash is stored. The Function replaces the plaintext token with its hash before computing a receipt's canonical request, and returns metadata without either token or hash. This makes retries confirmable without storing a plaintext token in invitation rows or command receipts. The client displays/copies the retained token after a confirmed invitation acknowledgment; the server cannot recover it later.

An invitation expires seven days after issuance, is single-use, and can be revoked. Acceptance rechecks scope, expiry, revocation, recipient, current issuer membership/sharing authority, and the issuer's grant revision. Demoting/revoking an issuer invalidates their earlier invitation generation even if they are later made a builder again. Acceptance creates workspace membership and an app grant atomically with the consumed invitation and command receipt. A consumed token may confirm the same current recipient, but never recreates a later-revoked grant or workspace membership. Revoking an invitation after acceptance prevents token reuse; revoking the accepted actor's access requires the separate grant operation.

The original quota is 50 issued invitations per actor per rolling 24 hours, across apps/workspaces. Exact receipt retries count once. An affected actor-limit row serializes concurrent issuance; quota failure commits no invitation or receipt. Workspace creation and invitation admission are bounded at 100 joined/owned workspaces, and app creation at 100 apps per workspace including unpublished apps. Admission into an already joined workspace does not count again. New membership admission and workspace creation stage the same actor-limit guard before checking capacity, so concurrent invitations from different workspaces cannot both claim the final slot. A rejected admission creates no membership, app grant, consumed token, or receipt.

## Transactions and evidence boundary

Supported app mutations stage both workspace and app guards before rechecking membership, grant, role, and versions. App state, private draft/grant/invitation changes, and receipt commit atomically. Record `ownerId` remains the app owner's tenant identity when another builder edits; it is never replaced with the editor's account ID. Reads recheck authority and guard state after hydration. Every receipt return, including duplicate/conflict recovery, reauthorizes current membership, app grant, and the role required by the original operation. A currently authorized actor can recover an exact committed result after archive; the archive writable check runs only when no matching receipt exists and new work would execute. Revocation or role demotion therefore takes precedence over returning an old sensitive receipt. New grant/record increments are rejected before exceeding the client revision bound.

The combined backend suite has 51 check groups: the preceding 22 builder/rich-record checks and 29 collaboration checks. The latter cover the full role matrix; token hash-only persistence; recipient binding, expiry and revocation; private candidates and legacy adoption; revoked receipt hydration; issuer demotion/regrant; rolling quotas; barrier-controlled concurrent acceptance, revocation and publication; cross-app quota contention; read-only invitation review; archived access removal and exact receipt recovery; workspace admission limits and concurrent final-slot allocation; bounded revision increments; rollback; and committed-but-unconfirmed acceptance. These checks use a simulated optimistic transaction store. The separate transport check exercises actual HTTP encoding against a local fake server.

The [preserved rich-record evidence](evidence/2026-10-28/README.md) predates this collaboration backend. It does not establish live Appwrite acceptance, browser use, or native-device behavior for invitations, shared roles, or private builder drafts. Those remain separate deployment and acceptance checks.

The guard design follows Appwrite's [atomic transaction and affected-row conflict semantics](https://appwrite.io/docs/products/databases/tablesdb/transactions). Empty table/row permissions follow its [default-deny permission model](https://appwrite.io/docs/products/databases/tablesdb/permissions). The workspace guard conservatively serializes supported writes across apps in one workspace; this is a bounded MVP correctness choice, not a throughput claim.

## React Native client checkpoint

The client includes people/sharing and invitation-entry/review routes, explicit
acceptance, role-aware controls, member/invitation paging, grant removal, and
owner archive review. The signed-in workbench exposes the account ID for
recipient-bound invitations. A retained app-creation request names its original
workspace even after another workspace is selected. Pasted invitation URLs are
parsed locally; their origin is never opened or fetched. Sign-in and invitation
inspection do not accept an invitation.

Private draft counters and global publication candidates are independent. The
client reviews and retains the exact private revision, candidate revision and
published base for retry. Confirmed role loss immediately clears private editor
and sharing state, including if a following refresh fails. An archived app blocks
new changes while retaining authorized exact-command receipt recovery and access
removal. Account-scoped controllers fence late responses after disposal.

Invitation tokens use Expo Crypto's asynchronous native random-byte API with
32 bytes and canonical unpadded base64url encoding. The synchronous API's
development fallback is deliberately avoided. Android clipboard writes mark the
invitation URL sensitive; copying is an explicit user action. See the official
[Expo 58 Crypto](https://docs.expo.dev/versions/v58.0.0/sdk/crypto/) and
[Clipboard](https://docs.expo.dev/versions/v58.0.0/sdk/clipboard/) contracts.

On October 28, 2026, root `npm run verify` passed for this client checkpoint:
TypeScript, Expo lint, **101 client tests**, Prettier, and web/iOS/Android bundle
exports. These exports are not native builds. Live Cloud collaboration, rendered
browser sharing, and native execution remain separate acceptance work; the older
rich-slice deployment does not establish those checks.
