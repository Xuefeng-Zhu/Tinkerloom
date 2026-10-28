# Serverpod 4.0.0 feature → product map

This maps the current checked-out source to Serverpod capabilities. Evidence
references are dated local checks, not a claim that these checks were rerun for
this documentation update. Read the [architecture](../ARCHITECTURE.md),
[review](ARCHITECTURE_REVIEW.md) and [verification history](VERIFICATION.md)
together.

| Feature | AppNest use | Evidence / limit |
| --- | --- | --- |
| Generated typed endpoints/models | Apps, builder, records/actions, invitations, streams, inbox | Generated from .spy.yaml and endpoint source; actual RPC demo |
| Auth modules / JWT / email IDP | Real account sign-in and session identity | Seeded credentials work in browser and independent clients; production mail not verified |
| Embedded PostgreSQL / migrations | Persistent local platform tables | Serialization spike, native FK migrations, restart test; no Docker substitute |
| Transactions / row locks | Receipts, grants, publication, capacity | 20 independent claim sessions, rollback and revision tests |
| Dynamic JSONB | Validated flexible record payload | ORM round-trip spike; typed projection query adapter avoids raw-envelope assumptions |
| Serverpod streams | Small authenticated revision invalidations | Revocation regression and historical browser refresh; DB polling. Idle cancellation defect remains open in the architecture review. |
| Future Calls | Wake reminder execution by run ID | Live scheduled demo with clients closed |
| Recurring Future Calls | Outbox/job/run reconciliation | Two-process interruption recovery; reminder retry deadlines are persisted but not enforced at execution. Eight slots are shared with AI work. |
| Integration-test tools | Generated endpoint harness and sessions | Real PostgreSQL tests; concurrency tests disable rollback wrapper |
| Structured logging / Insights | Request IDs, job/run/action diagnostics | Local logs; hosted Insights and operational dashboards not verified |
| Redis/shared messages | Not required for current monolith | Deferred cross-instance configuration/testing |
| Storage API / private images | Authenticated upload tickets, sanitized image variants, private reads and owner references | [Connected local image checks](RICH_COMPONENTS_LIVE_CHECK.md), HTTP upload and PostgreSQL regressions; external production storage, arbitrary files and video remain unverified/deferred. |

The implementation used the official documentation below alongside installed
4.0.0 package source/signatures. Links are retained for reference; they were not
revalidated as release-specific documentation during this update:

- [Quickstart](https://docs.serverpod.dev/quickstart), [embedded PostgreSQL](https://docs.serverpod.dev/concepts/data-and-the-database/database/embedded-postgres)
- [Dynamic fields](https://docs.serverpod.dev/concepts/data-and-the-database/models/dynamic-fields), [transactions](https://docs.serverpod.dev/concepts/data-and-the-database/database/transactions), [row locking](https://docs.serverpod.dev/concepts/data-and-the-database/database/row-locking)
- [Future Calls](https://docs.serverpod.dev/concepts/scheduling/future-calls), [recurring tasks](https://docs.serverpod.dev/concepts/scheduling/recurring-tasks)
- [Streaming](https://docs.serverpod.dev/concepts/endpoints-and-apis/streaming), [integration testing](https://docs.serverpod.dev/concepts/testing/get-started)

Documentation URLs can advance; installed pinned package source, generated signatures and running integration tests are the release-matched authority for this repository.
