# Nemotron model evaluation

[Documentation index](README.md) · [AI configuration](AI_SETUP.md)

The opt-in benchmark defaults to NVIDIA's developer API and evaluates AppNest
declarative definitions and semantic patches with synthetic data. OpenRouter
remains available through an explicit provider option. It does not start
Serverpod, change the application's selected model, publish apps, or read
private records.

The explicit [Kimi, GLM and DeepSeek extension](FREE_MODEL_EVALUATION.md) uses
the same cases and strict scorer with separate NVIDIA profiles and a separate
output path. The default selection remains the four Nemotron models below.
The [GLM Flash, Gemma and Laguna comparison](NVIDIA_MODEL_COMPARISON.md) adds
an explicit response smoke before a separate full benchmark.
The [Nemotron tuning experiment](NEMOTRON_TUNING.md) compares opt-in creation
checklists and reasoning settings while preserving the original scorer and
configured application defaults.

## Completed NVIDIA serial evaluation — 2026-10-08 UTC

The immutable `appnest-nemotron-v2` run finished at **08:25:25 UTC**, with all
144 planned operations resolved: **72 passed, 62 failed and 10 sequence edits
skipped**, across **288 dispatch attempts**. A server-only NVIDIA credential
was configured in ignored development configuration; authenticated model
access was verified for all four routes before the live synthetic run.

The run was **serial, concurrency 1**, with thinking disabled for all models.
Each table cell below shows **first API-attempt passes → eventual passes**;
column headings give the full planned denominator. Sequence edits use that
model's own accepted creation and are skipped when their source creation fails.

| Model | Creation /12 | Fixed edits /12 | Guidance /4 | Unsupported /4 | Sequences /4 |
| --- | --- | --- | --- | --- | --- |
| Lightning 3.5 | 0 → 1 | 1 → 5 | 3 → 4 | 3 → 3 | 0 → 1; 3 skipped |
| Super 3 | 2 → 6 | 9 → 12 | 4 → 4 | 4 → 4 | 1 → 2; 2 skipped |
| Ultra 3 | 2 → 7 | 4 → 7 | 3 → 3 | 3 → 4 | 3 → 3; 1 skipped |
| Nano Omni 3 | 0 → 0 | 2 → 4 | 1 → 1 | 1 → 1 | 0 → 0; 4 skipped |

Super had the strongest observed fixed-baseline editing result, **12/12**
eventually and **9/12** on the first attempt, without a service failure.
Ultra accepted the most strict creations, **7/12**, but both Ultra and Nano had
operations without any model response. The report therefore withholds creation
and editing winners: complete comparable response coverage was not obtained.
These single-trial observations do not establish a definitive universal winner.

| Model | Service-failure attempts | Availability-only failed operations | Creation median / p95 | Edit median / p95 |
| --- | --- | ---: | --- | --- |
| Lightning 3.5 | 5 timeouts | 0 | 104.3 / 222.1 s | 72.4 / 178.8 s |
| Super 3 | 0 | 0 | 22.8 / 40.6 s | 1.9 / 5.7 s |
| Ultra 3 | 21 HTTP 503 | 3 | 34.2 / 110.0 s | 7.4 / 24.0 s |
| Nano Omni 3 | 66 HTTP 503 | 15 | 2.3 / 67.8 s | 2.4 / 4.6 s |

Availability-only failures are excluded from observed correctness rates but
remain in planned-denominator pass rates. Latencies sum every attempt in a
completed operation, including failed calls and local validation; four-second
pacing is excluded. Nano's short medians are dominated by fast HTTP failures,
so they do not establish fast usable generation. Provider-side waiting and
network time are included; queue timing was not measured. The checkpoint's
creation time includes an earlier credential wait and explicit resume, so it
does not measure uninterrupted model execution time.

Known usage totals **3,492,090 tokens** over 196 attempts; usage for the other
92 attempts is unknown. Per-model known totals are 1,387,255 for Lightning,
950,500 for Super, 838,007 for Ultra and 316,328 for Nano. No NVIDIA response
reported cost, so actual cost remains unknown; advertised free developer
access does not reveal account quota or verified unit prices.

The main failure patterns were unsupported properties/types/icons, invalid
form controls and incomplete requested features. Lightning also returned full
definitions where edits required semantic patches. Super's remaining creation
failures included missing rich-dashboard, photo-form and capacity controls.
Ultra had some invalid control bindings, unrelated edit changes and invalid
JSON in addition to service errors. Nano combined service errors with invalid
field types, incorrect unsupported responses and invalid JSON.

The frozen creation scorer uses strict parsing. Production first applies the
required-capability compiler, which can add supported missing declarations.
A separate [offline compiler diagnostic](evidence/nemotron/2026-10-08-nvidia-v2/posthoc-offline-compiler-diagnostic.md)
replayed saved responses through that compiler, production checks and the same
fixed assertions. Ultra's creation acceptance becomes **8/12**, compared with
the primary strict **7/12**; the only newly accepted operation is
`create-reminders-name`. Other models' operation counts stay unchanged. This
post-hoc diagnosis does not change primary scores, and its repair attempts were
conditioned on the original strict-parser diagnostics.
The diagnostic script checks the frozen source hashes before running; later
source changes require restoring that evaluated source to reproduce it.

Saved evidence: [immutable report](evidence/nemotron/2026-10-08-nvidia-v2/checkpoint.json.md),
[summary JSON](evidence/nemotron/2026-10-08-nvidia-v2/checkpoint.json.summary.json),
[checkpoint with synthetic responses](evidence/nemotron/2026-10-08-nvidia-v2/checkpoint.json),
[compiler diagnostic JSON](evidence/nemotron/2026-10-08-nvidia-v2/posthoc-offline-compiler-diagnostic.json),
and its [offline script](evidence/nemotron/2026-10-08-nvidia-v2/offline_compiler_diagnostic.dart).
Offline replay confirmed all **72 accepted synthetic results**. The scored
source identity and frozen transport profiles are retained in the checkpoint.

Separately, the serial NVIDIA integration passed analysis, formatting,
separate-process reminder recovery and **902 tests** (82 spec, 225 renderer,
205 Flutter host and 390 server) through `scripts/verify.sh` before this run.
That implementation proof and the synthetic provider evaluation establish
neither authenticated app persistence nor connected Flutter, reminder,
publication, device or production acceptance. Later parallel execution changes
require a new output path and separate validation; this full comparison did
not exercise parallel dispatch.

## Bounded parallel dispatch validation — 2026-10-08 UTC

A separate `--concurrency=4 --max-requests=4` NVIDIA smoke finished at
**08:36:38 UTC**. It dispatched exactly four requests and stopped at the
requested cap, with no in-flight requests remaining. The observed peak was
**three overlapping requests**, independently confirmed from UTC dispatch and
completion timestamps. Successive starts were 4.028, 4.016 and 4.023 seconds
apart; the first-dispatch-to-final-completion window was 26.216 seconds. This
validates bounded parallel scheduling and global pacing, rather than a full
parallel quality comparison or a measured speedup over the serial run.

The four outcomes were one accepted Ultra result, two validation failures and
one Nano HTTP 503. The checkpoint's `blocked` status is the expected request-cap
stop. The parallel changes separately passed 139 focused benchmark tests,
workspace analysis, formatting and invalid-CLI checks. Offline replay confirmed
the one accepted synthetic result. The frozen source fingerprint is retained
in the checkpoint.
Saved evidence: [smoke report](evidence/nemotron/2026-10-08-nvidia-parallel-smoke/checkpoint.json.md),
[summary JSON](evidence/nemotron/2026-10-08-nvidia-parallel-smoke/checkpoint.json.summary.json),
and [checkpoint](evidence/nemotron/2026-10-08-nvidia-parallel-smoke/checkpoint.json).
The 144-operation comparison above remains the preserved serial run.

## Historical OpenRouter run — 2026-10-08 UTC

Implementation validation passed **868 tests** (82 spec, 225 renderer, 205
Flutter host and 356 server), analysis, formatting and separate-process reminder
recovery through `scripts/verify.sh`. This verified the prior v1 working checkout,
including its existing unrelated local changes; it is not a v2 or production acceptance
claim.

The live run began with four free requests remaining and stopped at HTTP 429.
An explicit resume check confirmed **zero free requests remaining** and issued
no additional completion. The quota API reported 52 requests used against its
daily limit of 50. There were seven recorded dispatch attempts in this run:

| Model | Partial observation |
| --- | --- |
| Lightning 3.5 | First notes creation returned invalid JSON; two repair attempts timed out at 90 seconds |
| Super 3 | Three notes creation responses failed the requested search-control assertion |
| Ultra 3 | Quota-blocked before any completion was received |
| Nano Omni 3 | Not reached |

No accepted app definitions or edit/guidance/unsupported/sequence results were
obtained. These partial observations do **not** rank the models. Usage is known
for four received completions (41,270 total tokens; reported cost zero); timeout
and quota-response usage is unknown. All requests used the free-only profiles.

Saved evidence: [comparison report](evidence/nemotron/2026-10-08/checkpoint.json.md),
[summary JSON](evidence/nemotron/2026-10-08/checkpoint.json.summary.json), and
[checkpoint with synthetic responses](evidence/nemotron/2026-10-08/checkpoint.json).
The original checkpoint remains at `output/nemotron-eval/checkpoint.json`.
The current `appnest-nemotron-v2` provider/source contract cannot resume that
historical v1 checkpoint. It remains available for offline replay and evidence
review; new scored runs require a separate output path. Completed calls are
never silently repeated.

## Run and resume

Run from the repository root with the verified Dart 3.13 toolchain:

```sh
# Offline NVIDIA manifest: exact models, prompts and synthetic edit fixtures.
dart --suppress-analytics run scripts/nemotron_eval.dart --describe

# Offline three-case smoke manifest, preserving the requested order.
dart --suppress-analytics run scripts/nemotron_eval.dart --describe --models=z-ai/glm-5.3 --cases=create-notes-fields,edit-notes-fields,guidance-ambiguous-organize

# Public NVIDIA pages only; verifies advertised free endpoint availability.
dart --suppress-analytics run scripts/nemotron_eval.dart --catalog

# Uses development.NVIDIA_API_KEY from server config/passwords.yaml.
# Checks authenticated model access, then dispatches synthetic completions.
dart --suppress-analytics run scripts/nemotron_eval.dart --live

# Resume the same frozen run after quota/availability returns.
dart --suppress-analytics run scripts/nemotron_eval.dart --live --resume

# Reconstruct accepted candidates from their recorded synthetic responses.
dart --suppress-analytics run scripts/nemotron_eval.dart --replay

# A separate parallel run; never reuse the completed serial checkpoint.
dart --suppress-analytics run scripts/nemotron_eval.dart --live --concurrency=4 --output=output/nemotron-eval-nvidia-parallel/checkpoint.json

# Explicit alternative provider. Use a new path for a new v2 OpenRouter run.
dart --suppress-analytics run scripts/nemotron_eval.dart --provider=openrouter --catalog
dart --suppress-analytics run scripts/nemotron_eval.dart --provider=openrouter --live --output=output/nemotron-eval-openrouter-v2/checkpoint.json

# Offline historical OpenRouter replay; does not dispatch completions.
dart --suppress-analytics run scripts/nemotron_eval.dart --provider=openrouter --replay --output=docs/evidence/nemotron/2026-10-08/checkpoint.json
```

`--provider=nvidia` is the default. Its output is
`output/nemotron-eval-nvidia/checkpoint.json`, with `.summary.json` and `.md`
reports alongside it. `--provider=openrouter` defaults to the historical
`output/nemotron-eval/checkpoint.json` location. Use `--output=PATH` for a
separate run; existing checkpoints cannot be overwritten by a new run.
`--models=ID,ID` selects exact registered IDs for the selected provider, shown
by `--describe`. NVIDIA defaults to the four Nemotron models and also permits
the explicitly selected [Kimi, GLM and DeepSeek profiles](FREE_MODEL_EVALUATION.md)
and [GLM Flash, Gemma and Laguna profiles](NVIDIA_MODEL_COMPARISON.md);
OpenRouter retains its four Nemotron routes.
`--max-requests=N` bounds completion requests in one invocation, including
retries; resume continues the remainder.

`--cases=ID,ID` selects exact case IDs from `--describe` in the supplied order.
Empty, duplicate and unknown IDs are rejected before catalog or credential
access. A sequence case requires its source creation earlier in the selected
order; for example, `create-notes-fields,sequence-notes-fields` is valid.
Without `--cases`, the default remains all 36 cases per model. Selected cases
and their order are part of the frozen manifest: a smoke checkpoint cannot be
resumed as a full benchmark. Use a fresh output path and omit `--cases` for the
full run, selecting only the models admitted by the smoke protocol.

`--concurrency=1..4` selects the dispatch concurrency; the default is 1. Calls
for each model remain sequential, while different model queues can overlap.
Parallel dispatch starts are globally spaced by at least four seconds across
the queues. The historical serial runner waited four seconds after attempts
and operations. Concurrency
is part of the frozen run contract: source or concurrency changes require a new
output path, and resume cannot reinterpret the completed serial run. Offline
`--replay` remains available for preserved checkpoints without new live calls.

## Providers, credentials and request profiles

| Model | NVIDIA ID | OpenRouter ID |
| --- | --- | --- |
| Lightning 3.5 | `nvidia/nemotron-3.5-lightning-30b-a3b` | `nvidia/nemotron-3.5-lightning:free` |
| Super 3 | `nvidia/nemotron-3-super-120b-a12b` | `nvidia/nemotron-3-super-120b-a12b:free` |
| Ultra 3 | `nvidia/nemotron-3-ultra-550b-a55b` | `nvidia/nemotron-3-ultra-550b-a55b:free` |
| Nano Omni 3 | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` |

Keep `NVIDIA_API_KEY` only under `development` in ignored
`appnest_server/config/passwords.yaml`. The application uses
`AI_BASE_URL: https://integrate.api.nvidia.com/v1` and
`AI_MODEL: nvidia/nemotron-3-ultra-550b-a55b`; the evaluator selects all four
NVIDIA models independently. OpenRouter uses the separate `AI_API_KEY` and
`https://openrouter.ai/api/v1` for the application. The evaluator first checks
`OPENROUTER_API_KEY`; it accepts legacy `AI_API_KEY` only when `AI_BASE_URL`
identifies OpenRouter. Set the explicit OpenRouter key when keeping the
application configured for NVIDIA. Credentials stay server-only and are never
printed or copied between providers.

NVIDIA's public model pages advertise an available free developer endpoint for
each selected model. Before dispatch the evaluator checks that advertisement,
then checks the authenticated model listing. The checkpoint records
`freeEndpoint: true`, the official source URL, `pricingVerified: false`, and
unknown supported parameters. **Free developer endpoint, account limits
unknown:** these checks establish public availability and credential access,
not numerical free-trial allowance or verified token prices. Omitted reported
cost remains unknown.

Official endpoint references: [Lightning](https://build.nvidia.com/nvidia/nemotron-3.5-lightning-30b-a3b),
[Super](https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b),
[Ultra](https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b), and
[Nano Omni](https://build.nvidia.com/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning).

All four NVIDIA models use instruction schemas, nonstreaming requests and
`chat_template_kwargs.enable_thinking: false`. Their shared profile is
`nvidia-instruction-schema-thinking-off-v1`; local validation remains
authoritative, with no provider-side schema enforcement claim.

OpenRouter accepts only catalog entries with verified zero pricing. Its
completions disable fallbacks and set zero prompt/completion price ceilings;
catalog availability and account quota are checked before live dispatch. Super
uses structured output; the other routes receive the schema in instructions.
Super and Ultra request medium reasoning; Lightning and Nano Omni use model
defaults. These historical OpenRouter settings are distinct from the NVIDIA
profile.

Neither provider permits paid plugins, tool calls, alternate-model routing or
redirects. A reported nonzero cost permanently stops the run. Missing reported
cost is unknown. No automatic credit purchase or paid fallback exists.

## Cases and scoring

Each model has 32 fixed scenarios and four separately reported sequences:

| Category | Count | Checks |
| --- | ---: | --- |
| Creation | 12 | Notes, reminders, calendars, focus utilities, rich dashboard, multi-step photo form, shared workflow and capacity signup |
| Fixed-baseline edits | 12 | Requested feature, stable IDs, compatibility and unchanged unrelated settings |
| Guidance | 4 | Two actionable requests need no questions; two ambiguous ideas need bounded clarification |
| Unsupported | 4 | Arbitrary executable code, external automation, payments and background phone alarms |
| Creation-to-edit sequences | 4 | Edits to that model's own accepted creation; skipped if creation fails |

The original eight customization cases retain their historical assertions.
Fixed-baseline edit results use identical validated fixtures across models.
Creation requests use the fixed public reading example, rather than the target
fixture. A sequence never substitutes a template for a failed creation.

These are model-and-transport comparisons; provider and profile differences are
recorded with identical local validation and repair rules.
Generation requests have a 90-second deadline, guidance 20 seconds. Existing
8000-token output limits and the single bounded 12000-token truncation-repair
allowance remain unchanged. There are at most three attempts per operation.
The completed serial comparison interleaved models by scenario with rotating
order, waiting four seconds after attempts and operations. Optional parallel
execution uses independent sequential model queues and globally spaces request
starts by at least four seconds.

Reports separate first-attempt and eventual correctness, full planned coverage,
quota/transport errors, median/p95 operation latency, and cumulative usage from
every attempt. Missing usage is never treated as zero. Single trials are
exploratory; recommendations require complete comparable category coverage.

## Recovery and evidence boundaries

Every request has a durable in-flight marker written before dispatch and an
atomic checkpoint replacement after its result. A process lock prevents two
evaluators from dispatching against the same checkpoint. An interrupted
in-flight request becomes indeterminate on resume and is never replayed.
HTTP 202 also records an indeterminate operation: the provider accepted
asynchronous work but returned no final result. Dispatch stops without an
automatic replay, so an accepted request cannot be duplicated by a retry.
Quota/authentication errors pause the run; completed calls are retained.

Source hashes cover builder/spec source, evaluator/report/scenarios, dependency
manifests and lockfile, and Dart version. Changed contracts require a new run.
The commit and tracked working-tree diff hash are also recorded. Synthetic raw
responses and candidates are retained for offline replay and failure review.
No prompts, assertions or adapter settings are tuned during a scored run.

Passing this benchmark establishes provider-and-definition behavior only.
Authenticated persistence, Flutter rendering, reminder delivery, publication
and physical-device behavior need separate acceptance checks. The historical
[customization evaluation](CUSTOMIZATION_AI_CHECK.md) used evolving assertions
and targeted reruns, so its percentages are not directly comparable.
