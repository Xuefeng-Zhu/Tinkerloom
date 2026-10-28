# AI creation check — 2026-09-22

[Documentation index](README.md) · [Current AI setup](AI_SETUP.md) ·
[Current creation flow](CREATION_FLOW.md)

This is a historical verification record. Provider selection, response formats,
test counts and browser behavior describe the 2026-09-22 build. Consult
[AI setup](AI_SETUP.md) for the current adapter contract and
[the architecture review](ARCHITECTURE_REVIEW.md) for outstanding issues.

The check used the authenticated local AppNest browser chat and the configured
real provider. It did not select a template tile or inject a fake provider.
Prompts and records contained synthetic examples only. Published examples were
private local apps, not deployments.

## Initial findings from that investigation

The first Plant Corner request, a smaller Plant Corner retry, and a Trip Kit request exhausted their bounded generation attempts. The UI reported either an invalid response/timeout or an unsupported capability. The failures did not publish the placeholder definition or create live records.

The persisted generation metadata identified the real Nebius provider and Nemotron model. Completion token counts were well below the output limit; the available evidence did not establish output truncation. The worker's generic exception handling combined malformed JSON with transport timeouts, while capability validation did not name the invalid capability. Those diagnostics gave subsequent repair attempts too little information.

At the start of the investigation, new-app requests also included the current
placeholder definition and all starter templates. The generation output was a
complete replacement definition, but that context could bias it toward an
existing app. This motivated the fresh-creation/edit-context separation below.

## Prompts

- **Plant Corner:** houseplants with name, room, light level, care status, notes, a garden list, a care view and a status overview. Plant-specific labels and green styling; no reminders or external services.
- **Trip Kit:** packing items with name, category, quantity and packing status, dedicated editing/details, packing and progress tabs. Blue styling; no reminders or external services.

## Changes made during that investigation

- Fresh creation omits the placeholder and templates from the provider request. The platform schema and semantic binding rules remain available. Selected-template edits retain the selected definition, and successful AI drafts retain their definition for follow-up edits even after a failed request or manual change. The optional API flag preserves older client behavior.
- Strict parsing tolerates only one complete outer `json` fence. It still rejects prose, arbitrary embedded objects and invalid definitions. JSON, envelope, HTTP, timeout, truncation and schema failures have separate bounded diagnostics. Logs contain timing, response size and token/finish metadata, never the prompt, response content or credential.
- AI instructions explain exact capabilities versus policies, action IDs, required form bindings, reachable create/edit controls, one workflow action per behavior and exact semantic-patch JSON.
- Arbitrary status values use neutral transition icons. Only exact Open/Done choices use completion icons. Actions omitted by linked details remain available on rows, including a secondary workflow.

## Connected outcomes recorded on 2026-09-22

| App | AI result and live behavior |
| --- | --- |
| **Plant Corner** (local app 47, version 39) | AI authored a plants collection, sage theme, Garden/Care/Overview tabs and dedicated details/form pages. An initially valid preview lacked reachable create/edit controls; a more precise chat prompt corrected it. Preview-only creation stayed isolated. Published empty, then added Monstera and Snake plant; edited Monstera's notes and changed Healthy to Needs care. Care showed Monstera; Overview correctly showed two plants split 50%/50%. |
| **Trip Kit** (local app 48, initially version 40) | The original plain-language packing prompt succeeded on the first attempt after the instruction fixes. AI authored item/category/quantity/status fields, blue theme, Pack/Progress tabs, search, filters and details/editor pages. Published empty, then added Passport and USB charger. Packed/unpacked/repacked Passport and edited its name to Passport wallet. Progress correctly showed one Packed and one To pack. |

Provider metadata identifies `api.tokenfactory.us-central1.nebius.com` and `nvidia/Nemotron-3-Ultra-550b-a55b` for the successful jobs. Plant refinement job 9 completed on attempt 1 in 8.976 seconds; Trip creation job 10 completed on attempt 1 in 10.416 seconds. Both returned HTTP 200 and `finish_reason=stop`.

Trip's first natural-language follow-up failed validation without changing the candidate. A precise chat retry renamed the Item Name field to Item: job 12 used edit mode, succeeded on attempt 1 in 2.691 seconds, and produced a semantic patch. Reverting only that label reproduces the entire previous canonical hash, proving all IDs and other definition values were preserved. The field was visibly renamed in both preview and the published form. This is live AI editing evidence, not a manually injected patch.

After adding exact patch-shape guidance, the plain-language request “Rename the Save Changes action to Edit item. Keep everything else unchanged.” succeeded on the first attempt (job 13, 1.883 seconds). Live review exposed a separate omission: action-label changes were not listed by the publication diff. That omission was fixed and regression-tested. A fresh proposal showed **Rename action Save Changes to Edit item** in both Changes and the exact publication dialog. Publishing it preserved the saved Passport wallet and USB charger records; the live details page showed **Edit item** afterward. The older loaded browser client also exercised omission of the new nullable flag successfully.

At the end of the check, both apps were private in **My workspace**, with two
synthetic live records each and no enabled automations. Existing Daily Planner
data remained intact. These checks establish working examples, not universal
one-shot generation quality. Generated labels can still need refinement; human
preview/review remains necessary.

Screenshots: [Plant overview](evidence/ai-created/plant-overview.jpg), [Trip packing list](evidence/ai-created/trip-pack.jpg), [Trip progress](evidence/ai-created/trip-progress.jpg), [Trip details after AI editing and release-build reload](evidence/ai-created/trip-detail.jpg). These are actual authenticated browser captures of synthetic records in the local PostgreSQL database, using the browser's narrow 504×674 layout. Large-text and desktop layout coverage is separately supplied by automated renderer tests. Both inspected browser consoles contained no warning/error entries at the final check.

## Verification recorded on 2026-09-22

The full repository verification passed with 123 tests: 29 AppSpec, 40 renderer, 25 Flutter host and 29 server/provider tests, plus both independent-process reminder recovery checks. Static analysis and formatting passed. The release web build and Wasm compatibility dry run succeeded. The new tests cover strict AI parsing, safe diagnostics, request context, successful/failed draft edit modes, template-first edits, arbitrary workflows, action reachability and publication action-label diffs.

Serverpod/Dart MCP tools were unavailable. The official Serverpod 4.0.0 generator produced transport changes; no generated code was manually edited. The existing authorized local development job was reloaded with unchanged configuration and persistent data. No deployment, authentication shortcut, provider change, credential disclosure or database reset was performed.

Server logs retain the initial generation failures, the one-generation-at-a-time guard encountered during parallel prompting, and stream queries reporting PostgreSQL shutdown during a planned development reload. These are not counted as clean server logs. Subsequent authenticated writes, AI edits, publication and the final record URL reload succeeded; the final provider jobs completed without generation errors.
