# Kimi, GLM and DeepSeek evaluation

[Documentation index](README.md) · [AI configuration](AI_SETUP.md) ·
[Historical Nemotron evaluation](NEMOTRON_EVALUATION.md)

The later [GLM Flash, Gemma and Laguna comparison](NVIDIA_MODEL_COMPARISON.md)
uses a separate smoke gate and full-run checkpoint with GLM 5.3 as its control.
The dated results below remain preserved independently.

## Blocked evaluation — 2026-10-08 UTC

This opt-in NVIDIA developer API comparison has **108 planned operations: 36 per
model**, using the same synthetic cases and strict scorer as the preserved
Nemotron evaluation. NVIDIA returned HTTP 429 and stopped further dispatch.
The preserved run is **blocked and incomplete**, rather than a completed
108-operation comparison.
The application's configured Ultra model and the benchmark's default four
Nemotron models remain unchanged; these three models require explicit
`--models` selection.

The selected current endpoints were checked against NVIDIA's official public
pages and authenticated model listing during preparation. The evaluator checks
public free availability and authenticated access again before dispatch. These
checks establish endpoint identity and access, not completion quality, numerical
account quota or verified token pricing.

| Family | Exact API model ID | Official free endpoint | Request documentation |
| --- | --- | --- | --- |
| Kimi | `moonshotai/kimi-k3` | [Kimi K3](https://build.nvidia.com/moonshotai/kimi-k3) | [Model reference](https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3), [HTTP parameters](https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer) |
| GLM | `z-ai/glm-5.3` | [GLM 5.3](https://build.nvidia.com/z-ai/glm-5-3) | [Model reference](https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3), [HTTP parameters](https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer) |
| DeepSeek | `deepseek-ai/deepseek-v4.1-flash` | [DeepSeek V4.1 Flash](https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash) | [Model reference](https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash), [HTTP parameters](https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer) |

The GLM page uses the slug `glm-5-3`; its API model ID uses `glm-5.3`. The
DeepSeek reference page uses an `nvidia` documentation prefix; its API model ID
uses `deepseek-ai`. The exact IDs above are frozen into the run contract.

### Preserved blocked results — 10:22:38 UTC

The final checkpoint and summary agree at `2026-10-08T10:22:38.092014Z`.
There are **80 terminal outcomes out of 108 planned operations: 42 passed and
38 failed**. Separately, **one operation is blocked and 27 are pending**, over
**168 attempts**. No request
remained in flight when the process exited with the expected guard status 3.
HTTP 429 occurred on Kimi's first guidance case; the remaining active DeepSeek
request settled before exit. Numerical account allowance and reset time are
unknown. Do not resume until the provider's rate/quota block has been resolved.

| Model | Terminal / planned | Passed / planned | Failed | Blocked | Pending | Attempts |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kimi K3 | 24 /36 | 7 /36 | 17 | 1 | 11 | 65 |
| GLM 5.3 | 36 /36 | 35 /36 | 1 | 0 | 0 | 41 |
| DeepSeek V4.1 Flash | 20 /36 | 0 /36 | 20 | 0 | 16 | 62 |

GLM supplies the **strongest observed practical signal for an AppNest pilot**:
35/36 eventual passes, 32/36 on the first API attempt, and all 12 fixed-baseline
edits passing on their first attempt. This is an observational judgment within
these application bounds. The report withholds categorical creation/editing
winners because Kimi and DeepSeek lack comparable response coverage. DeepSeek
returned no completion at all, so its model-output quality is unknown.

Kimi completed creation and fixed-edit cases, but guidance is blocked and its
unsupported and sequence cases were not reached. DeepSeek completed all
creation cases and eight fixed edits; four edits and all guidance, unsupported
and sequence cases remain pending. One pending DeepSeek edit already has two
timeouts; the global stop prevented its third attempt. There are no skipped
sequences in this partial run: unvisited sequence rows remain pending.

### Seven-model category observations from two NVIDIA runs

Each numeric cell gives **first API-attempt passes → eventual passes**, with the
full planned denominator in the heading. The historical Nemotron cohort used
serial dispatch and thinking disabled. The new cohort used parallel client
concurrency 3 with the reasoning profiles documented below. All 36 scenario
definitions match, but source contracts, profiles and service conditions differ.
These are descriptive observations from two runs, not a pooled controlled trial.

| Model | Cohort | Creation /12 | Fixed edits /12 | Guidance /4 | Unsupported /4 | Sequences /4 |
| --- | --- | --- | --- | --- | --- | --- |
| Lightning 3.5 | Historical serial | 0 → 1 | 1 → 5 | 3 → 4 | 3 → 3 | 0 → 1; 3 skipped |
| Super 3 | Historical serial | 2 → 6 | 9 → 12 | 4 → 4 | 4 → 4 | 1 → 2; 2 skipped |
| Ultra 3 | Historical serial | 2 → 7 | 4 → 7 | 3 → 3 | 3 → 4 | 3 → 3; 1 skipped |
| Nano Omni 3 | Historical serial | 0 → 0 | 2 → 4 | 1 → 1 | 1 → 1 | 0 → 0; 4 skipped |
| Kimi K3 | Blocked parallel | 5 → 7 | 0 → 0; all timeout-only | 1 blocked, 3 pending | 4 pending | 4 pending |
| GLM 5.3 | Blocked parallel | 8 → 11 | 12 → 12 | 4 → 4 | 4 → 4 | 4 → 4 |
| DeepSeek V4.1 Flash | Blocked parallel | 0 → 0; no responses | 0 → 0; 8 terminal, 4 pending | 4 pending | 4 pending | 4 pending |

The historical [Nemotron report](NEMOTRON_EVALUATION.md) retains its service
failures, sequence skips and separate compiler diagnosis. Super and GLM both
passed all 12 fixed edits in their respective runs. GLM's stronger observed
creation count does not establish a universal quality winner: some competitors
returned no response within the deadline, and reasoning configurations differ.
Historical serial timings are not a controlled latency comparison with this
parallel run, and these results do not measure each model's maximum capability.

### Availability, latency and usage

Of the 38 failed operations, **36 are availability-only** and two received
responses that failed fixed feature assertions. Observed correctness excludes
operations with no model response; full planned-denominator rates retain them.
Kimi's observed eventual rate is 7/8 response-bearing terminal operations,
versus 7/36 planned. DeepSeek's observed correctness rate is unknown, not zero.

| Model | Service-failure attempts | Availability-only failed operations | Known total tokens / attempts with usage | Attempts with unknown usage |
| --- | --- | ---: | --- | ---: |
| Kimi K3 | 55 timeouts, 1 HTTP 429 | 16 | 147,494 /9 | 56 |
| GLM 5.3 | 1 timeout | 0 | 598,251 /40 | 1 |
| DeepSeek V4.1 Flash | 62 timeouts | 20 | Unknown /0 | 62 |

Known usage totals **745,745 tokens from 49 attempts**; usage for 119 attempts
is unknown. These sums include failed and repair attempts. No response reported
cost, so actual cost remains unknown. A timeout does not establish that remote
work stopped or that no provider usage or cost occurred. Advertised free access
does not reveal numerical quota, reset time or verified unit prices.

| Model | Creation median / p95 | Fixed-edit median / p95 | Completed latency samples, create / edit |
| --- | --- | --- | --- |
| Kimi K3 | 261.0 / 270.0 s | 270.0 / 270.0 s | 12 /12 |
| GLM 5.3 | 10.7 / 159.8 s | 2.0 / 5.3 s | 12 /12 |
| DeepSeek V4.1 Flash | 270.0 / 270.1 s | 270.0 / 270.0 s | 12 /8 |

Latency is the sum of attempt durations for each completed operation, including
failures and local checks; queue time and dispatch pacing are excluded. GLM's
all-category operation median/p95 is 2.7/17.5 seconds. Kimi and DeepSeek timings
are dominated by exhausted 90-second deadlines and do not measure usable
inference speed. Provider waiting and network time are included; there is no
serial-versus-parallel speedup or provider compute-time claim.

### Separate offline scoring diagnoses

All 36 creation cases are terminal. The diagnostic records **54 creation
attempts without a response**: 17 Kimi, one GLM and 36 DeepSeek. **16 of 18
failed creation operations are timeout-only**.

| Model | Primary strict creations /12 | Production checks alone | Compiler + the same fixed assertions |
| --- | ---: | ---: | ---: |
| Kimi K3 | 7 | 8 | 7 |
| GLM 5.3 | 11 | 12 | 11 |
| DeepSeek V4.1 Flash | 0; no responses | 0; quality unknown | 0; quality unknown |

Production checks alone accept 20/36 creations versus 18/36 under the frozen
feature assertions. Capability compilation adds **zero passing operations**
under those same assertions: one repaired GLM focus response belongs to an
operation that later passed strict scoring anyway. The
[full compiler diagnostic](evidence/nvidia-free-models/2026-10-08/posthoc-offline-compiler-diagnostic.md),
[JSON](evidence/nvidia-free-models/2026-10-08/posthoc-offline-compiler-diagnostic.json)
and [helper](evidence/nvidia-free-models/2026-10-08/offline_compiler_diagnostic.dart)
are post-hoc explanations and do not replace primary scores or rerun the models.
Original repair attempts were conditioned on the strict scorer's diagnostics.

GLM's sole failed case, `create-multistep-form`, supplies a schema- and
production-valid image field but omits the explicit `controls` entry with
`control: imageUpload` required by the fixed assertion. Renderer source selects
its image-upload editor directly from `FieldType.image`, so the omitted entry
is not source-level evidence that the upload UI would be absent. The primary
result stays **35/36**. The [separate assertion diagnostic](evidence/nvidia-free-models/2026-10-08/posthoc-offline-glm-multistep-assertion.md),
[JSON](evidence/nvidia-free-models/2026-10-08/posthoc-offline-glm-multistep-assertion.json)
and [helper](evidence/nvidia-free-models/2026-10-08/offline_glm_multistep_diagnostic.dart)
establish offline validation and source behavior, without executing the
renderer or verifying authenticated upload, persistence or device behavior.

Kimi's `create-reminders-name` has a different qualification. Its first
response passes strict schema and production checks but makes the independent
reminder timestamp required. The prompt expressly makes due dates optional;
the fixed scorer additionally requires optional reminder times. Production's
literal requirement extractor accepts the response for that wording. A required
reminder has a real form behavior consequence: the definition prevents saving
an unscheduled task. Capability compilation cannot change field optionality,
and the primary failed operation stays unchanged. See the
[Kimi assertion diagnostic](evidence/nvidia-free-models/2026-10-08/posthoc-offline-kimi-reminder-assertion.md),
[JSON](evidence/nvidia-free-models/2026-10-08/posthoc-offline-kimi-reminder-assertion.json)
and [helper](evidence/nvidia-free-models/2026-10-08/offline_kimi_reminder_diagnostic.dart).
No live form, reminder delivery, persistence or device execution was verified.

### Archived evidence and verification

The blocked run is preserved as exact byte copies:
[checkpoint](evidence/nvidia-free-models/2026-10-08/checkpoint.json),
[summary JSON](evidence/nvidia-free-models/2026-10-08/checkpoint.json.summary.json),
[report](evidence/nvidia-free-models/2026-10-08/checkpoint.json.md), and the nine
separate diagnostic files linked above. The [audit receipt](evidence/nvidia-free-models/2026-10-08/README.md)
and [SHA-256 manifest](evidence/nvidia-free-models/2026-10-08/SHA256SUMS) record
integrity and verification scope. Historical Nemotron evidence is unchanged.

Offline replay exited successfully for **all 42 accepted results**. Independent
checks reconciled every model/category count, usage sum and latency quantile;
all **28 frozen source-file hashes**, the source contract hash and run fingerprint
matched. A sweep of all 168 dispatch/completion timestamp pairs found a peak of
three active client invocations, no same-model overlap and a minimum dispatch
gap of 4.011 seconds. This establishes client scheduling, not provider-side
concurrency or cancellation after timeouts.

Separately, the final source passed **287 focused tests**, workspace analysis
and formatting before the live run; frozen source hashes did not change during
the run. Diagnostic helpers also passed offline execution, analysis and format
checks. These implementation and synthetic provider checks do not establish
connected Flutter, authenticated persistence, reminders, publication or device
acceptance.

The isolated publication excludes an unrelated pre-existing `builder.dart`
fix that was present in the scored working tree. Consequently **27 of the 28
frozen source files match the published checkout**; the benchmark, provider,
scenario and validation code is unchanged. Historical evidence and checksums
remain immutable. The strict offline diagnostic helpers require the original
scored source snapshot and can intentionally reject this narrower publication.
Primary `--replay` uses the archived accepted responses and works without
credentials or an untracked working checkpoint. See the
[publication provenance and diagnostic setup](evidence/nvidia-free-models/2026-10-08/README.md#publication-source-scope).

The isolated publication checkout was checked separately: workspace analysis
reported no issues, formatting 16 authored Dart files made zero changes,
the same 287 focused tests passed, and archived primary replay accepted all
42 saved results. These fresh publication checks made no live provider requests,
do not rescore the historical run and establish no new runtime acceptance.

## Fixed request profiles and application bounds

All three use `https://integrate.api.nvidia.com/v1/chat/completions`,
`stream: false` and `temperature: 0`. No `top_p` override is sent. Generation's
complete schema and guidance's JSON contract are supplied in instructions;
`response_format` is omitted. AppNest parses and validates the final content
locally. A model's advertised structured-output support does not establish
provider-side enforcement of this instruction schema.

| Model | Frozen profile | Additional request fields | Reasoning behavior |
| --- | --- | --- | --- |
| Kimi K3 | `nvidia-kimi-k3-instruction-schema-low-v1` | `reasoning_effort: low` | Thinking is always enabled; low effort is requested |
| GLM 5.3 | `nvidia-glm-5.3-instruction-schema-low-v1` | `reasoning_effort: low`, `chat_template_kwargs: {clear_thinking: true}` | Low effort is requested and previous thinking is cleared |
| DeepSeek V4.1 Flash | `nvidia-deepseek-v4.1-flash-instruction-schema-default-v1` | None | Model default; no effort field or thinking switch is sent |

Kimi's [reference](https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3)
states that thinking is always enabled. GLM's
[reference](https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3) documents
low/high/max effort, default max, and explicitly recommends `clear_thinking=true`
for chat. DeepSeek's [model reference](https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash)
describes numeric effort in its source-model encoding; that is insufficient
evidence to send it as an NVIDIA HTTP parameter. The benchmark uses the documented
HTTP request fields and records this limitation.

| Application limit | Frozen evaluation value |
| --- | --- |
| Generation deadline | 90 seconds per attempt |
| Guidance deadline | 20 seconds per attempt |
| Generation output allowance | 8,000 tokens initially; 12,000 only for a fresh-creation retry after a recognized truncation diagnostic |
| Guidance output allowance | 2,048 tokens |
| Attempts | At most three per operation, with the same bounded repair rules |
| Parallel scheduling | Client concurrency 3; one active client invocation per model; global dispatch starts at least four seconds apart |

These are application feasibility settings. They differ from publisher examples
and recommendations: [Kimi's example](https://build.nvidia.com/moonshotai/kimi-k3)
uses temperature 1, max effort and 16,384 output tokens;
[GLM's example](https://build.nvidia.com/z-ai/glm-5-3) uses temperature 0.5, while
its model reference defaults effort to max;
[DeepSeek's reference](https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash)
recommends temperature 1 and at least 256K output tokens. The common temperature
0, lower effort where documented, short deadlines and 8K/12K generation budgets
do not measure each model's maximum capability. Reasoning settings also differ
across these three profiles.

Concurrency is a ceiling, so three client calls need not overlap throughout the run.
`--concurrency=4` would still permit at most three active client invocations for this
selection, because each model has one sequential queue. Concurrency 3 is part
of this run's frozen execution contract. Concurrency and observed peak count
active client invocations only. After a timeout, remote completion, continued
provider work and cost are unknown; client timeout does not establish provider
cancellation or a provider-side concurrency bound.

## Cases and scoring

| Category | Per model | All three | Checks |
| --- | ---: | ---: | --- |
| Creation | 12 | 36 | Requested features, strict AppSpec parsing and semantic references |
| Fixed-baseline edits | 12 | 36 | Same validated fixtures, requested changes, stable IDs and unchanged unrelated settings |
| Guidance | 4 | 12 | Actionable ideas versus bounded clarification for ambiguous ideas |
| Unsupported | 4 | 12 | Explicit rejection of unsupported executable code, external automation, payments and background phone alarms |
| Creation-to-edit sequences | 4 | 12 | Edits to that model's own accepted creation; skipped if the source creation fails |
| **Total planned** | **36** | **108** | Up to three attempts per operation; retries are additional calls |

The 36 scenario definitions match the archived serial Nemotron run. Creation
uses the fixed public reading example; edits use identical validated baselines.
Sequence edits never substitute a template for a failed model creation. The
strict creation scorer parses the returned AppSpec directly. Production's
creation-only required-capability compiler can accept some definitions that
this strict scorer rejects; see the separate historical
[compiler diagnostic](evidence/nemotron/2026-10-08-nvidia-v2/posthoc-offline-compiler-diagnostic.md).
Any similar post-hoc diagnosis must remain separate from primary scores.

The report separates first API-attempt and eventual passes, planned coverage,
availability-only failures, model validation failures, median/p95 operation
latency and cumulative usage from every attempt. Skipped sequences retain their
planned denominator. Missing usage or reported cost remains unknown. Service
failures do not establish incorrect model output; recommendations require
complete comparable category coverage. Single trials remain exploratory.

Historical Nemotron timing came from a serial run with thinking disabled,
different transport profiles and different service conditions. It is not a
controlled latency comparison with this parallel run. A later side-by-side
summary must retain those limits; it cannot establish a parallel speedup or a
universal model ranking.

## Run, resume and preserve evidence

Run from the repository root with the verified Dart toolchain. Keep
`NVIDIA_API_KEY` only under `development` in ignored
`appnest_server/config/passwords.yaml`; follow [AI setup](AI_SETUP.md) without
changing the application's selected model. The evaluator does not start
Serverpod, publish apps or send stored private records.

```sh
evaluation_models='moonshotai/kimi-k3,z-ai/glm-5.3,deepseek-ai/deepseek-v4.1-flash'
evaluation_output='output/nvidia-free-model-eval/checkpoint.json'

# Offline manifest: inspect exact profiles, 108 planned operations and pacing.
dart --suppress-analytics run scripts/nemotron_eval.dart --describe \
  --provider=nvidia --models="$evaluation_models" --concurrency=3 \
  --output="$evaluation_output"

# Public NVIDIA pages only; no completion request or credential required.
dart --suppress-analytics run scripts/nemotron_eval.dart --catalog \
  --provider=nvidia --models="$evaluation_models" --concurrency=3 \
  --output="$evaluation_output"

# Rechecks public availability and authenticated /models access, then scores.
dart --suppress-analytics run scripts/nemotron_eval.dart --live \
  --provider=nvidia --models="$evaluation_models" --concurrency=3 \
  --output="$evaluation_output"

# Continue the same frozen run after resolving a recoverable block.
dart --suppress-analytics run scripts/nemotron_eval.dart --live --resume \
  --provider=nvidia --models="$evaluation_models" --concurrency=3 \
  --output="$evaluation_output"

# Offline replay of saved accepted candidates; no provider request.
dart --suppress-analytics run scripts/nemotron_eval.dart --replay \
  --provider=nvidia --output="$evaluation_output"
```

Use a new output path for each new source/profile/execution contract. Existing
checkpoints cannot be overwritten. Before scored dispatch, freeze source hashes,
scenario definitions, model IDs, profiles and concurrency; the checkpoint keeps
that identity and its run fingerprint. Resume requires the same frozen contract.
No prompts, assertions or transport settings are tuned during the scored run.
`--max-requests=N` can cap one invocation's dispatches, including retries; it
does not change the planned denominator or establish account quota.

The public preflight records each official URL and `freeEndpoint: true`.
Authenticated `/models` access is checked separately. Metadata retains
`pricingVerified: false` and unknown account limits. A reported nonzero cost
stops dispatch; no paid fallback, tool call, plugin or alternate-model route is
permitted. Advertised free developer access does not turn missing cost into zero.

Requests have durable in-flight markers and atomic checkpoint saves. An
interrupted in-flight request or HTTP 202 becomes indeterminate and is never
automatically reissued. HTTP 202 means the provider accepted asynchronous work
without a final result. Authentication/quota blocks stop new dispatches;
already-started parallel calls are allowed to settle. Incomplete or indeterminate
coverage prevents a definitive recommendation.

The run writes the checkpoint plus `.summary.json` and `.md` alongside it.
The preserved blocked artifacts are archived above; resume only after the
provider block is resolved and the frozen contract still matches. A later
resume must retain this dated blocked snapshot as history. Keep historical
Nemotron serial and parallel-smoke evidence intact. Synthetic
provider/schema acceptance remains separate from authenticated persistence,
Flutter rendering, reminders, publication and physical-device acceptance.
