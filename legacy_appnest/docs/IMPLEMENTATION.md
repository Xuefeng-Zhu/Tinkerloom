# Implementation status and decisions

This is a source-oriented implementation map, updated after the 2026-10-07
architecture review. It replaces the initial build checklist, whose provider,
template and attachment notes described an earlier stage. A feature being present
does not mean every acceptance layer is verified. See [requirements and evidence
boundaries](REQUIREMENTS.md), [dated verification](VERIFICATION.md), and
[known defects and recommended work](ARCHITECTURE_REVIEW.md).

## Implemented surfaces

| Area | Current source | Evidence and remaining boundary |
| --- | --- | --- |
| Declarative platform | Pure-Dart AppSpec contract, shared semantic renderer, isolated preview, stable platform tables and typed generated clients | Canonicalization, compatibility and preview/runtime tests; no per-app code or table generation |
| Multi-user runtime | Serverpod authentication, workspace membership plus app grants, invitations, policies, capacity, revisions and action receipts | Real PostgreSQL contention and authorization tests; client retry identity and revoked-assignment lifecycle still need fixes |
| Durable effects | Atomic audit/outbox writes, reminder runs, Future Calls and recurring reconciliation | Historical connected reminders and two-process recovery; execution currently ignores persisted retry deadlines |
| Builder and evolution | Server-only AI adapter, durable jobs/leases, semantic edits, manual and visual authoring, exact-candidate publication | Historical live AI examples and synthetic concurrent-job tests; no current provider or universal generation-quality claim |
| Mini-app UI | Launcher, templates, navigation, forms/details, summaries/charts, customization, clock/focus and private images | Dated renderer/host and connected component evidence; legacy authorization-state and idle-stream cancellation defects remain open |
| Native capabilities | Fixed Android/iOS device bridge and local consent through the renderer adapter | [Mobile contract and dated build checks](MOBILE_FEATURES.md); physical-device and complete iOS acceptance remain separate |

## Architectural decisions

- Use the verified Flutter 3.47.0 / Dart 3.13.0 / Serverpod 4.0.0 toolchain.
  Generate protocol, clients and test tools from `.spy.yaml` models and endpoint
  source; generated files are not hand-authored extension points.
- Keep one Serverpod backend and a shared interpreter. Definitions describe
  bounded capabilities and presentation; they cannot grant access, execute code,
  choose network destinations or contain provider credentials.
- Use Serverpod embedded PostgreSQL locally for development and isolated tests.
  Redis is disabled in the local single-process configuration. Multi-instance
  behavior requires separate configuration and verification.
- Serialize app mutations, publication and grant changes on the app control row.
  Reads currently share that exclusive lock; sequential record hydration and full
  ranking amplify contention. The review recommends batching before relaxing
  consistency boundaries; no load capacity has been measured.
- Store flexible records through the framework's dynamic JSONB serialization.
  Maintain typed field projections atomically for parameterized filtering,
  sorting and database-wide aggregates.
- Persist command outcomes, audit and outbox writes with business state.
  Notification effects commit with their successful run and a unique delivery
  key. Definition history preserves structure; it is not a backup of records or
  a way to undo already delivered effects.
- Read AI configuration only on the server from ignored environment-specific
  `config/passwords.yaml`. Provider availability is an operator-controlled runtime
  fact. Templates/manual creation remain available when no provider is configured.
  Private records and device readings stay out of AI prompts.
- Use Serverpod private storage for bounded still images with sanitization,
  references and rechecked read access. General attachments/video and production
  storage verification remain outside the implemented acceptance claim.
- Keep native readings, consent and fixed device actions in the local host/adapter
  boundary. Preview remains synthetic and cannot invoke the native bridge.

## Development and verification

Use the [development guide](DEVELOPMENT.md) for the user-started Serverpod workflow,
MCP operations, manual fallback, migration rules and preserved local state.
[The demo guide](DEMO.md) explains authenticated endpoint walkthroughs and their
side effects. `scripts/verify.sh` is the repository validation entrypoint; a dated
passing run proves only its recorded layers.

The architecture review found the committed CI workflows could not resolve this
workspace's SDK constraints and omitted several package suites. Local passing
checks do not establish passing GitHub checks. No production deployment is
authorized or claimed; operational release gates are listed in
[SECURITY.md](SECURITY.md).
