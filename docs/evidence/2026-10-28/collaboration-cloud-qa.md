# Collaboration Cloud verification checkpoint — October 28, 2026

The Free SFO project is `6ae1928a003a65851e95`, database `tinkerloom`,
Function `tinkerloom-core`. The collaboration source from `d4ae76f` was
uploaded as `tinkerloom-collaboration-d4ae76f.tar.gz` (SHA-256
`c7d750055d886df9e048e3e6eb316f0a4270c6b9583d1f5115db16cd8cbb65e0`).
The console showed deployment `6ae2632251983dea38b0` **Active**, Dart3.11,
9-second build, 4.15MB. This archive predates the full-engine source; it
does not deploy AppSpec actions, queries, workers or media.

The five new collaboration tables were created privately with row security,
plus additive optional guard/revision/archive columns and the workspace app
index. `apps.headRevision` was independently read as available with
`default: null`, preserving legacy adoption. The original rich-slice
resources, rows, and receipts remain. No persistent service key was created.

## Live REST results

All reports are retained verbatim after their built-in secret scan. They use
synthetic account IDs, in-memory credentials and user sessions; no admin key.
Each run caps itself at240 HTTP requests and signs out reachable QA sessions.
These probes are not mounted browser/native or full migration acceptance.

- [Initial failure](appwrite-collaboration-initial-failed.json): 15 passed,
  3 failed,13 blocked,152 assertions/47 requests. Stored Appwrite datetime
  columns return `+00:00`; the client/probe incorrectly required `Z`.
  A selected-column console read confirmed the actual UTC representation
  without reading invitation tokens/hashes. The parser now accepts exactly
  those two UTC spellings, preserves date/precision validation, and rejects
  non-UTC offsets and rollover. Regression checks cover both formats.
- [After UTC correction](appwrite-collaboration-utc-failed.json):30 passed,
  1 failed,0 blocked,932 assertions/211 requests. Roles, unpublished/private
  isolation, grants, concurrent publication/acceptance/revocation, archival,
  exact receipts and fresh sessions passed within this suite. The remaining
  quota inventory assertion omitted the third unpublished app for which the
  suite itself had issued one invitation. It now enumerates all three apps
  and additionally checks every issued ID/app against the persisted inventory;
  no quota assertion was removed.
- [Next attempt](appwrite-collaboration-rate-limited.json): Appwrite returned
  HTTP429 `general_rate_limit_exceeded` for new QA account creation. The
  run stopped dependent checks and preserved the failed receipt. No passing
  result was available at that checkpoint; this failed run remains retained.

Natural seven-day expiry,100-workspace/app admission filling, and actual
network-loss injection remain explicitly unverified live. Their local checks
are separate. No rate-limit bypass, paid upgrade or production deployment
was used. Resume the corrected probe only after the service allows normal
account creation, or through an explicitly authorized test-account workflow.

## Corrected passing run

[Complete passing report](appwrite-collaboration-passed.json), run
`qa-collab-mvso7okp-e9eac88e`, completed October28 at22:16:38UTC after the
normal account-creation cooldown: **31 passed,0 failed,0 blocked,940 assertions,
212 HTTP requests**. All five synthetic sessions were signed out. The full
50-invitation rolling quota inventory included all three issuing apps and
checked each issued ID/app. This used the same active deployment and source
archive identified above. The previously listed live coverage exclusions remain.
