# AI provider setup

[Documentation index](README.md) · [Creation flow](CREATION_FLOW.md) ·
[Architecture](../ARCHITECTURE.md)

This guide describes the current source contract, including local working-tree
changes. It does not confirm the configured live provider, provider availability,
or a deployed build. Historical provider results are linked below.

## Configure the server

Without a configured provider, AppNest shows **Template mode — AI provider not
configured**. Templates, manual editing, publication and existing apps remain
available. `FakeAiProvider` is a test helper; it is not a runtime fallback.

For NVIDIA development, add these entries under `development` in the ignored
`appnest_server/config/passwords.yaml`, preserving its existing database and
authentication secrets:

```yaml
development:
  # Keep existing database/authentication entries here.
  AI_BASE_URL: https://integrate.api.nvidia.com/v1
  AI_MODEL: nvidia/nemotron-3-ultra-550b-a55b
  NVIDIA_API_KEY: YOUR_SERVER_ONLY_NVIDIA_KEY
```

Keep the NVIDIA credential under `development` only. The NVIDIA adapter reads
`NVIDIA_API_KEY`; other providers read `AI_API_KEY`. Preserve any existing
OpenRouter credential under its original name. The evaluator also accepts an
explicit `OPENROUTER_API_KEY` for OpenRouter; its legacy `AI_API_KEY` fallback
requires `AI_BASE_URL` to identify OpenRouter. The base URL, model and matching
provider credential must all be nonblank. The adapter appends `/chat/completions`;
provide the API base rather than the completed request path. Use HTTPS for a
remote service. `.env` files alone are not read by this adapter, and these names
are Serverpod password entries rather than Flutter build settings.

Keep `passwords.yaml` ignored and owner-readable only (`chmod 600`). Never put
keys in definitions, Flutter assets, screenshots or committed configuration.
Restart the existing server through the project's Serverpod workflow so it
loads changed passwords. See the [example password file](../appnest_server/config/passwords.example.yaml)
and [local startup instructions](../README.md#start-developing).

## Provider request contract

| Operation | Normal request | Context sent |
| --- | --- | --- |
| Fresh creation | `response_format.type: json_schema` for a complete AppSpec or explicit unsupported response | User request, public schema/authoring contract, fixed public examples and any bounded repair context |
| Definition edit | `response_format.type: json_schema` for typed semantic patches or explicit unsupported response | User request, current declarative definition and any bounded repair context |
| Optional **Help shape my idea** | `response_format.type: json_object` | Idea and, for follow-up help, the authorized draft definition |

Fresh creation sends neither the internal placeholder definition nor starter
templates. Selecting a template explicitly establishes edit context. A
successful generated candidate also establishes edit context for follow-up
requests, including after later failures or manual edits. None of these
operations sends stored mini-app records or device readings to the provider.

The normal adapter requires the configured provider to support its requested
response formats. The NVIDIA and scoped OpenRouter adaptations below are
explicit exceptions.
Provider enforcement is supplementary: AppNest always validates the returned
JSON and semantic references locally. One outer JSON fence is tolerated; prose
and arbitrary embedded-object extraction are rejected.

Fresh creations may add supported `requires` declarations derived by the strict
parser from the already-authored graph. This creation-only compiler changes no
feature, field, action, policy, automation rule or grant. It parses the completed
definition strictly again and records raw-output, input-definition and candidate
hashes plus added declarations in private job metadata. Manual definitions and
edits retain their strict parsing path. Preview remains separate from explicit
publication and reminder approval.

## NVIDIA development route and benchmark

The NVIDIA route uses the exact API base `https://integrate.api.nvidia.com/v1`.
The example configuration above selects Ultra. The optional
[Nemotron benchmark](NEMOTRON_EVALUATION.md) defaults to NVIDIA and compares all
four exact allowlisted model IDs without changing the application's selection:

| Model | NVIDIA model ID |
| --- | --- |
| Lightning 3.5 | `nvidia/nemotron-3.5-lightning-30b-a3b` |
| Super 3 | `nvidia/nemotron-3-super-120b-a12b` |
| Ultra 3 | `nvidia/nemotron-3-ultra-550b-a55b` |
| Nano Omni 3 | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` |

All four use the `nvidia-instruction-schema-thinking-off-v1` transport profile.
Generation supplies its schema in instructions rather than `response_format`;
guidance supplies its bounded JSON contract in instructions. Calls are
nonstreaming and set `chat_template_kwargs.enable_thinking: false`. AppNest's
local parsing, semantic validation, unsupported-request checks and bounded
repairs remain authoritative. These settings do not establish provider-side
schema enforcement or successful generation.

The application also supports the exact NVIDIA model ID `z-ai/glm-5.3-flash`.
To select GLM 5.3 Flash, keep the NVIDIA base and credential above and set
`AI_MODEL: z-ai/glm-5.3-flash`, then restart the server. Its baseline transport
supplies the JSON contract in instructions, uses low reasoning effort and sets
`chat_template_kwargs.clear_thinking: true`; local validation remains required.
Other comparison models, including GLM 5.3, Gemma and Laguna, remain explicit
evaluation routes and are not accepted by NVIDIA application configuration.
The separate [GLM Flash live application check](GLM_FLASH_LIVE_CHECK.md) records
dated browser, publication and authenticated record-persistence evidence; the
synthetic benchmark below does not establish those application layers.

The separate [Nemotron tuning experiment](NEMOTRON_TUNING.md) exposes
`--nemotron-profile` only in the evaluation CLI. These experimental profiles
do not change the application transport: configured Nemotron models keep their
baseline thinking-off profile, and GLM Flash keeps its baseline profile above.

The public NVIDIA model pages advertise available free developer endpoints.
The evaluator verifies that advertisement before a live run and records each
source URL and `freeEndpoint: true`. An authenticated model-listing request
checks credential access without making a completion request. These checks do
not reveal numerical account quota or verified token pricing: metadata records
`pricingVerified: false`, `accountLimitsKnown: false`, and unknown free-request
counts. The trial endpoint is expected to be free; omitted usage cost remains
unknown.

The **2026-10-08 serial NVIDIA benchmark** completed all 144 planned operations
with 72 passes, 62 failures and 10 skipped sequence edits over 288 attempts.
The server-only development key was configured, and authenticated model access
was verified for all four routes. These synthetic checks establish provider
and definition behavior rather than connected Flutter or app persistence.

| Model | Strict creations /12 | Fixed-baseline edits /12 |
| --- | ---: | ---: |
| Lightning 3.5 | 1 | 5 |
| Super 3 | 6 | 12 |
| Ultra 3 | 7 | 7 |
| Nano Omni 3 | 0 | 4 |

Super had the strongest observed editing result, with 9/12 first-attempt and
12/12 eventual passes. The report withholds definitive creation/editing winners
because service failures left some models without comparable response coverage.
Ultra and Nano encountered 21 and 66 HTTP 503 attempts; Lightning had five
timeouts. Short failure latency is not evidence of fast usable generation.
NVIDIA cost remained unreported and unknown.

Production's capability compiler is broader than the frozen strict scorer:
an offline post-hoc check accepts 8/12 Ultra creations versus the primary 7/12,
without changing the scored run. See the
[complete category results, timings and evidence](NEMOTRON_EVALUATION.md#completed-nvidia-serial-evaluation--2026-10-08-utc)
and [compiler diagnostic](evidence/nemotron/2026-10-08-nvidia-v2/posthoc-offline-compiler-diagnostic.md).
The separate 902-test implementation check predates later parallel execution
changes. The full comparison used concurrency 1; `--concurrency=1..4` in the
benchmark defaults to 1, keeps each model's calls sequential and applies global
four-second dispatch pacing. Parallel comparisons require a separate run.

A separate bounded parallel smoke on 2026-10-08 UTC used concurrency 4 and a
four-request cap. It observed a peak of three overlapping calls, starts at
least four seconds apart and a 26.216-second dispatch-to-completion window,
then stopped at the cap with no request in flight. One Ultra response passed,
two responses failed validation and one Nano request received HTTP 503. This
establishes scheduling behavior, not a full parallel quality comparison or
speedup measurement. The changes passed 139 focused benchmark tests, workspace
analysis, formatting and invalid-CLI checks. See the
[smoke report](evidence/nemotron/2026-10-08-nvidia-parallel-smoke/checkpoint.json.md)
and [checkpoint](evidence/nemotron/2026-10-08-nvidia-parallel-smoke/checkpoint.json).
Offline replay confirmed the one accepted synthetic result; the frozen source
fingerprint is retained in the checkpoint.

The explicit [Kimi, GLM and DeepSeek benchmark extension](FREE_MODEL_EVALUATION.md)
stopped at NVIDIA HTTP 429 on 2026-10-08 UTC. Of 108 planned operations,
80 reached terminal outcomes: 42 passed and 38 failed. Separately, one was
blocked and 27 remain pending, over 168 attempts. GLM finished at 35/36, Kimi at 7/36 planned
and DeepSeek at 0/36 with no completion received. GLM provides the strongest
observed practical signal for this bounded setup; service failures and
unfinished coverage prevent a categorical quality winner. The separate
image-upload and optional-reminder diagnoses do not change primary scores.
Its concurrency 3 and reasoning profiles differ from the historical serial
thinking-disabled run, so latency is not a controlled comparison. Actual cost,
account allowance and reset time remain unknown. See the linked guide for
archived evidence, the seven-model category table and 42-result offline replay.
These explicit `--models` selections do not change the configured application
model or the default four-model Nemotron benchmark. Do not resume until
the provider block is resolved.

The separate [GLM Flash, Gemma and Laguna comparison](NVIDIA_MODEL_COMPARISON.md)
used a three-case response smoke before a fresh full phase. GLM Flash and the
GLM 5.3 control each passed 36/36; GLM had lower observed overall operation time
and Flash needed fewer validation repairs in this exploratory single trial.
Gemma passed the smoke but returned no full-phase output; its lane was stopped
after 12 completed timeouts, with one active request's outcome unknown and 31
cases pending. Laguna returned no smoke output and was excluded. These two
availability outcomes provide no full-phase quality score. The raw full
checkpoint and separate operational-stop receipt preserve the partial coverage.
The comparison does not select an application model. GLM Flash can now be
configured explicitly through the application route described above; the
default benchmark selection remains the four Nemotron models.

If the evaluator receives HTTP 202, the provider has accepted asynchronous
work without returning a final result. It records that operation as
indeterminate, stops dispatching, and never automatically replays the request.

Official endpoint references: [Lightning](https://build.nvidia.com/nvidia/nemotron-3.5-lightning-30b-a3b),
[Super](https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b),
[Ultra](https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b), and
[Nano Omni](https://build.nvidia.com/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning).

## Scoped OpenRouter development route

The adapter recognizes this exact host/model pair:

```yaml
development:
  # Keep existing database/authentication entries here.
  AI_BASE_URL: https://openrouter.ai/api/v1
  AI_MODEL: nvidia/nemotron-3-ultra-550b-a55b:free
  AI_API_KEY: YOUR_SERVER_ONLY_OPENROUTER_KEY
```

For this pair, the adapter removes `response_format`, supplies generation's
complete schema through system instructions with shared local references, and
requests medium reasoning. Both generation and guidance disable provider
fallbacks and send zero prompt/completion token price limits. This is an
intentional compatibility adaptation, not evidence that the provider enforces
the schema. Local validation remains authoritative.

The generation deadline is 90 seconds for this pair and for the supported NVIDIA
routes, and 45 seconds otherwise. Other host/model combinations use the normal
response-format path. Use synthetic requests for development and review the provider's
current data-handling terms before sending other material. The
[model listing](https://openrouter.ai/nvidia/nemotron-3-ultra-550b-a55b:free)
is an external reference; this guide does not establish current availability,
free quota, pricing or successful live generation.

## Limits and worker behavior

| Limit | Current source behavior |
| --- | --- |
| Active generation jobs | One per signed-in actor |
| Generation jobs | 30 per actor per rolling 24 hours |
| Generation attempts | At most three per job |
| Generation input | At most 16 KiB UTF-8 at the server; the composer also limits characters |
| Worker pool | Eight Future Call slots per process, shared by generation, reminders and reconciliation |
| Generation provider duration | 45 seconds normally; 90 seconds for the scoped OpenRouter route and supported NVIDIA routes |
| Generation lease | 120 seconds, with expiration and stale-result fencing |
| Output token allowance | 8,000 normally; a fresh-creation retry after a recognized truncation diagnostic gets a fixed 12,000 allowance |
| Definition output | 128 KiB; provider response envelope is bounded separately to three times that size |
| Guidance requests | 20 per actor per rolling 24 hours, reserved before the provider call |
| Guidance input and duration | 2,000 characters and 4,000 UTF-8 bytes; approximately 20 seconds total |

Jobs are persisted before scheduling. Reconciliation repairs missed generation
wakeups; leases, draft mutation/hash and base-version checks fence duplicate or
obsolete results. No provider request runs while an app transaction is held.
Generation retries honor bounded `Retry-After` hints, capped at 120 seconds, and
classify terminal provider failures. Bounded semantic repair context can survive
an intervening transient provider failure within the same scoped job.

Different actors can generate concurrently. Excess work waits for a shared
worker slot; the pool does not impose a distributed provider request/token
limit or guarantee reminder latency. The [architecture review](ARCHITECTURE_REVIEW.md)
records scheduler isolation and automation retry defects that remain open.

## Inspect failures and verify configuration

Use the builder's **Build details** for the recorded job status, attempt count
and bounded validation diagnostic. A failed create never exposes its internal
placeholder as a successful generated app. A failed edit retains its previous
preview; publication still requires a validated candidate or explicitly keeping
the prior edit preview.

Read server/Flutter logs through the connected Serverpod MCP tools. Provider
telemetry records failure category, timing, byte/token counts and safe correlation
metadata, rather than prompt/response bodies or credentials. Rejected response
text is private database repair context, never routine log content or part of
the builder snapshot. Do not publish raw development logs.

Configuration checks and provider unit tests establish adapter behavior, not
current provider availability or generation quality. To verify a live setup,
use an authorized synthetic request, inspect its durable job/provider metadata,
and distinguish preview success from publication and authenticated record writes.
Never infer a current success rate from the historical examples below.

## Historical evidence

| Record | What it establishes for that dated build |
| --- | --- |
| [AI creation check — 2026-09-22](AI_CREATION_CHECK.md) | Nebius-backed browser creation, refinement, publication and synthetic live CRUD for Plant Corner and Trip Kit |
| [Creation flow — historical verification](CREATION_FLOW.md#historical-verification--2026-09-22) | Earlier automatic clarification and Pocket Library prompt-to-preview behavior |
| [Planner failure investigation — 2026-09-23](GENERATION_FAILURE_CHECK.md) | Bounded provider repair and isolated preview checks; no connected browser recovery claim |
| [Customization evaluation — 2026-09-23](CUSTOMIZATION_AI_CHECK.md) | Targeted creation/edit outcomes with explicit AI-generated versus template baselines |

The Nebius model and endpoint in those records were tested on those dates.
They are evidence, not a promise of current routing. An operator configuring
another environment should verify its approved model and endpoint independently.

## Source map

- [Provider adapter and request builders](../appnest_server/lib/src/modules/builder/provider.dart)
- [Builder authorization, quotas and publication](../appnest_server/lib/src/modules/builder/builder.dart)
- [Durable generation leases and retries](../appnest_server/lib/src/modules/automation/worker.dart)
- [Fresh-creation capability compiler](../appnest_server/lib/src/modules/builder/creation_compiler.dart)
- [Shared definition limits](../packages/appnest_spec/lib/appnest_spec.dart)
