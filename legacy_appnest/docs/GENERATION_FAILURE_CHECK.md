# Planner generation failure — 2026-09-23

[Documentation index](README.md) · [Current AI setup](AI_SETUP.md) ·
[Current creation flow](CREATION_FLOW.md)

This is a historical failure investigation and verification record. The provider
configuration, response-format behavior and test counts below belong to the
2026-09-23 build. Current edits use a typed patch schema; guidance uses a JSON
object, and one scoped development adapter omits provider response-format
enforcement. See [AI setup](AI_SETUP.md#provider-request-contract) for those
current distinctions. The [architecture review](ARCHITECTURE_REVIEW.md) records
outstanding defects; this historical investigation does not mark them fixed.

## Confirmed failure

The user's browser showed a failed new-app request:

> Build a daily planner where I can organize tasks by day, set priorities, and track what I finish.

Expanding **Build details** showed that the AI response was not valid JSON.
The main UI instead suggested a simpler request, obscuring the response-format
failure. This observation does not establish which syntax error the original
response contained; the provider response body was not available in that UI.

The request builder asked for JSON only through prompt text. It did not set a
provider response format. Direct, bounded checks against the configured
development provider showed that JSON-object mode was accepted, but could still
return an invalid AppSpec root or run out of output tokens during repair.

## Changes made during that investigation

- New-app creation supplies a provider-compatible AppSpec schema, with an
  explicit unsupported-response alternative. Instructions distinguish an app
  instance from a schema and request a compact, complete app.
- A fixed public, validated reference demonstrates collection, action, view and
  page links. It is documentation, not a starting definition or fallback.
  Generated data views explicitly declare their action bindings, including an
  empty array for read-only sections.
- Guidance and semantic edits request JSON-object output. Existing token limits,
  response-size bounds and bounded repair attempts remain in place.
- Generation uses `temperature: 0` for more focused output. Creation explicitly
  omits reminders and automations unless requested. This avoids adding an
  unrelated notification workflow to the simple planner request.
- Retries retain the rejected response as private, size-bounded repair context
  for the same job, draft mutation, base definition, version, mode and attempt.
  It is sent as untrusted data with the diagnostic, rather than asking the model
  to reconstruct the failed response. It is never promoted into the preview,
  exposed in the builder snapshot or logged. Success, stale jobs and terminal
  failure clear it. Provider usage metadata cannot supply this reserved context.
- The configured provider rejected conditional schema keywords (`if`, `then`,
  `else`) and `uniqueItems`. The provider schema expresses those component
  conditions as concrete alternatives for each view type, preserving their
  allowed settings and required collection bindings. Only the unsupported
  uniqueness keyword is omitted. The canonical schema and authoritative AppSpec
  validation rules remain unchanged; returned definitions still undergo complete
  semantic validation, including uniqueness checks.
- Choice, board, timestamp-filter, primary-action and form-control diagnostics name the broken
  binding and explain how to fix it. Relative days use a view's `dateFilter`;
  timestamp query values require actual timestamps with timezone.
- Failure status and chat explain unreadable, incomplete, oversized or
  unavailable AI responses in plain language. A format failure permits retrying
  the same request. Technical repair instructions remain under **Build details**.
  Failed edits retain the existing preview.

The response-format API follows [Nebius's structured-output documentation](https://docs.tokenfactory.nebius.com/ai-models-inference/json).
The sampling parameter follows [Nebius's chat completion API](https://docs.tokenfactory.nebius.com/api-reference/inference/create-chat-completion).
At the time of the check, other configured providers needed to support the
requested response-format modes; rejection did not silently downgrade generation.
The current scoped OpenRouter adaptation is documented in [AI setup](AI_SETUP.md).

## Verification recorded on 2026-09-23

- Workspace analysis passed. Final provider analysis and formatting passed.
- Flutter suite: **135 tests passed**, including visible failure explanations,
  same-request retry and retention of the prior preview after a failed edit.
- Shared definition suite: **64 tests passed**, including actionable repair
  diagnostics without weakening data validation.
- Private repair integration suite: **14 tests passed** against real PostgreSQL,
  including stale-context isolation, UTF-8 byte bounds, metadata collisions and
  terminal cleanup. Combined server suite: **72 tests passed**, including
  **17 provider tests**. The renderer suite passed **115 tests**. The full
  verification script also passed reminder recovery across two independent
  processes. These four package suites total **386 tests**.
- Release Flutter web build passed and was written to the local server's
  `web/app` directory. Loading that rebuilt UI in the user's browser remains
  unverified.
- The final application request builder, with no test-only request overrides,
  generated a valid planner through the configured Nebius
  `nvidia/Nemotron-3-Ultra-550b-a55b` provider on attempt **2 of 3**. Attempt 1 was
  rejected as truncated at 8,000 tokens; attempt 2 returned a complete definition
  in 7.5 seconds. It has a task collection, Date/Priority/Status/Notes fields,
  reversible completion, a list and an add/edit form, with no automations.
  The synthetic [generated definition](evidence/generation/generated-planner.json)
  is retained as evidence. This is one successful bounded run, not a measured
  generation success rate.
- That exact definition passed **3 additional isolated Flutter preview tests**:
  desktop (1440×1000), mobile (390×844) and mobile with 150% text. Each test
  created a synthetic task, edited its title and priority while preserving its
  date, completed it through the declared workflow, and navigated its tab and
  create/edit form without rendering errors. No details page was generated.
  These checks use the isolated preview adapter, not an authenticated browser.

The live probes read the existing development credentials in memory and sent
only the synthetic planner request, public platform contract and rejected
synthetic definitions for repair. They did not publish an app, mutate live
records, print credentials or log raw provider response bodies. Selected
synthetic definition bindings were inspected locally to diagnose failures.

Serverpod and Dart MCP tools were unavailable. No development server restart or
server-log check was performed. The running backend must load these changes
before a browser retry can exercise them; that runtime state has not been
verified in that check. An isolated provider probe does not establish recovery
of the user's existing browser draft.
