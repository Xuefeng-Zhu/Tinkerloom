# GLM Flash, Gemma and Laguna evaluation

[Documentation index](README.md) · [Evaluation CLI](NEMOTRON_EVALUATION.md) ·
[Earlier Kimi, GLM and DeepSeek run](FREE_MODEL_EVALUATION.md)

## Full phase outcome — 2026-10-08 UTC

**GLM 5.3 Flash and the GLM 5.3 control each passed all 36 cases.** Flash needed
fewer validation repairs, while GLM had lower observed overall latency. Gemma
returned no output during the full phase despite passing the earlier smoke.

| Model | Eventual checks passed | First-attempt passes | Completed attempts | Median operation time | p95 operation time |
| --- | --- | --- | --- | --- | --- |
| GLM 5.3 Flash | 36/36 | 31/36 | 41 | 15.744 s | 129.744 s |
| GLM 5.3 control | 36/36 | 29/36 | 43 | 5.944 s | 43.787 s |
| Gemma 4 31B | Unscored: no full-phase output | — | 12; one additional request unknown | — | — |

Operation time sums the recorded attempts for each case, including failed
attempts and repairs; it excludes dispatch waiting. It is not a single-response
latency or isolated provider-speed measurement. The median uses the midpoint
and p95 uses nearest rank. Flash had four validation failures and one timeout
before successful repairs; GLM had six validation failures and one timeout.

| Category | GLM Flash eventual passes (first attempt) | GLM control eventual passes (first attempt) |
| --- | --- | --- |
| Creation | 12/12 (8/12) | 12/12 (6/12) |
| Fixed-baseline edits | 12/12 (11/12) | 12/12 (11/12) |
| Guidance | 4/4 (4/4) | 4/4 (4/4) |
| Unsupported requests | 4/4 (4/4) | 4/4 (4/4) |
| Sequences using each model's accepted creation | 4/4 (4/4) | 4/4 (4/4) |

### Partial coverage and operational stop

The 108-operation full phase was **administratively interrupted at 14:45:16
UTC** after the two GLM lanes completed. Gemma's 12 completed attempts all timed
out at the 90-second generation deadline, exhausting three attempts on each of
four creation cases. Its next request, `create-calendar-category` attempt 1,
was in flight when the evaluator stopped. No full-phase Gemma quality score can
be calculated; the lack of output measures availability within these bounds.

This operational stopping decision was added during the trial, after an optional
runtime-preference question received no reply; it was not the original smoke
gate. The process exited with code 130 after SIGINT. The unchanged raw checkpoint
retains `status: running` and the in-flight marker; the separate
[stop receipt](evidence/nvidia-model-candidates/2026-10-08/operational-stop.json)
records the interruption and verified process exit. Remote completion or
cancellation of the active request is unknown. No resume or further provider
request was attempted after the stop.

Final coverage is **76 terminal operations: 72 passes and four availability-only
failures**, plus one request with an unknown outcome and 31 pending operations.
There were 96 completed attempts and 97 dispatches. Token usage was reported for
82 completed attempts, totaling 1,233,504 known tokens; 14 completed attempts and
the interrupted request have unknown usage. Actual cost, remaining quota and
reset time remain unknown.

Both GLM models met the same eventual definition checks in this exploratory
single trial. Their first-attempt and latency differences support a practical
comparison under these settings, without establishing a universal quality
winner. Gemma's changed availability after the smoke also shows why three smoke
cases cannot establish sustained reliability. Laguna was excluded by the smoke
gate and has no full-phase result.

Saved evidence: [full report](evidence/nvidia-model-candidates/2026-10-08/full.json.md),
[summary](evidence/nvidia-model-candidates/2026-10-08/full.json.summary.json),
[raw checkpoint](evidence/nvidia-model-candidates/2026-10-08/full.json), and
[operational stop](evidence/nvidia-model-candidates/2026-10-08/operational-stop.json).

## Protocol — 2026-10-08 UTC

This synthetic NVIDIA developer API comparison adds three explicitly selected
models and reruns GLM 5.3 as a contemporaneous control. It evaluates AppNest
definitions, semantic patches and guidance with the original strict scorer.

| Model | Exact API ID | Fixed request profile |
| --- | --- | --- |
| [GLM 5.3 Flash](https://build.nvidia.com/z-ai/glm-5-3-flash) | `z-ai/glm-5.3-flash` | Low reasoning effort; `clear_thinking: true` |
| [Gemma 4 31B](https://build.nvidia.com/google/gemma-4-31b-it) | `google/gemma-4-31b-it` | `enable_thinking: false` |
| [Laguna XS 2.1](https://build.nvidia.com/poolside/laguna-xs-2.1) | `poolside/laguna-xs-2.1` | Model default reasoning; no undocumented toggle |
| [GLM 5.3 control](https://build.nvidia.com/z-ai/glm-5-3) | `z-ai/glm-5.3` | Low reasoning effort; `clear_thinking: true` |

Public model pages must advertise an available free endpoint, and an authenticated
model listing must confirm access before each live invocation. These checks do
not reveal account quota, reset times or numerical token prices. This benchmark
does not change application model selection or the default four-model Nemotron
benchmark.

The current application configuration separately supports the exact NVIDIA
model ID `z-ai/glm-5.3-flash` with its baseline low-effort, clear-thinking
transport. Set that `AI_MODEL` alongside the NVIDIA base and server-only key,
then restart the server; see [AI setup](AI_SETUP.md#nvidia-development-route-and-benchmark).
GLM 5.3, Gemma and Laguna remain evaluation-only routes. This runtime support is
a later implementation change and does not alter the frozen benchmark results
or establish live application acceptance for the dated benchmark.

### Smoke and eligibility

The smoke test selects exactly `create-notes-fields`, `edit-notes-fields` and
`guidance-ambiguous-organize`: 12 operations across four models, with at most
36 attempts. A model is eligible for the full benchmark when every smoke operation
has at least one nonempty response from a completed call, recorded as `received`
or `validation`. Validation failures remain eligible. Partial completions,
timeouts and HTTP errors do not satisfy this response-availability gate.

A blocked or incomplete smoke run, nonzero reported cost, or HTTP
202/401/402/403/429 prevents launch of the full run. Quota stops are not
automatically resumed. The full run uses a fresh checkpoint and all 36 original
cases per eligible model; smoke scores are reported separately.

### Smoke results

The smoke completed at **14:24:37 UTC**: all 12 operations resolved across
21 attempts, with nine passes and three availability-only failures. No global
stop was triggered.

| Model | Cases with a response | Smoke checks passed | Attempts | Availability failures | Full-run eligibility |
| --- | --- | --- | --- | --- | --- |
| GLM 5.3 Flash | 3/3 | 3/3 | 5 | 2 timeouts | Eligible |
| Gemma 4 31B | 3/3 | 3/3 | 4 | 1 timeout | Eligible |
| Laguna XS 2.1 | 0/3 | Unscored: no output | 9 | 2 timeouts, 7 HTTP 503 | Excluded |
| GLM 5.3 control | 3/3 | 3/3 | 3 | None observed | Eligible |

Laguna returned no model output, so this run establishes endpoint availability
failure within the shared deadlines rather than a model-quality score. Flash,
Gemma and the GLM control each returned output for creation, edit and guidance;
they were admitted to a separate 108-operation full run. Three smoke cases do
not establish statistical reliability or a quality ranking.

Saved evidence: [smoke report](evidence/nvidia-model-candidates/2026-10-08/smoke.json.md),
[checkpoint](evidence/nvidia-model-candidates/2026-10-08/smoke.json), and
[eligibility receipt](evidence/nvidia-model-candidates/2026-10-08/smoke-gate.json).

### Common bounds and interpretation

- Client concurrency 4, one active invocation per model, and global dispatch
  starts at least four seconds apart.
- Nonstreaming requests, temperature 0, and at most three attempts per operation.
- Generation deadline 90 seconds; guidance deadline 20 seconds.
- Initial generation allowance 8,000 tokens; 12,000 only after recognized
  creation truncation. Guidance allowance 2,048 tokens.
- The complete JSON contract is supplied in instructions and validated locally;
  no provider-side `response_format` enforcement is claimed.

Reasoning settings differ by documented endpoint support. These are application
feasibility bounds, not each model's maximum capability. Timeouts cannot identify
provider queueing, inference time or remote cancellation. Known token usage
includes repair attempts; missing usage or cost remains unknown. This is one
exploratory trial with a response-availability selection gate, not a universal
model ranking.

### Implementation checks

Workspace analysis found no issues. Formatting five authored Dart files made zero
changes, and 315 focused evaluator/provider/generation tests passed before live
dispatch. The new `--cases` option rejects empty, duplicate, unknown and
dependency-invalid case selections before network or credential access. Omitting
it retains the original 36 cases.

Offline replay passed for all nine accepted smoke results and all 72 accepted
full-phase results. Replay reconstructs accepted definitions and guidance from
the recorded synthetic responses; it does not complete pending operations or
resolve the interrupted request.

The independent [audit](evidence/nvidia-model-candidates/2026-10-08/audit.json)
reconciled model/category totals, usage, latency, the response gate and stop
receipt. All 29 frozen source hashes and both run fingerprints matched; all 36
full-run scenarios matched the earlier benchmark. See the
[evidence receipt](evidence/nvidia-model-candidates/2026-10-08/README.md) for
integrity checks and the reproducible audit helper.

No app server was started. Synthetic provider and offline validation evidence
does not establish Flutter rendering, authenticated persistence, image uploads,
reminder delivery, physical-device behavior or production acceptance.

## Reproduce the protocol

From the repository root, with the existing server-only `NVIDIA_API_KEY` configured
in ignored `appnest_server/config/passwords.yaml`:

```sh
evaluation_models='z-ai/glm-5.3-flash,google/gemma-4-31b-it,poolside/laguna-xs-2.1,z-ai/glm-5.3'
evaluation_cases='create-notes-fields,edit-notes-fields,guidance-ambiguous-organize'

dart --suppress-analytics run scripts/nemotron_eval.dart --describe \
  --provider=nvidia --models="$evaluation_models" --cases="$evaluation_cases" \
  --concurrency=4 --output=output/nvidia-candidates-new-trial/smoke.json

dart --suppress-analytics run scripts/nemotron_eval.dart --live \
  --provider=nvidia --models="$evaluation_models" --cases="$evaluation_cases" \
  --concurrency=4 --max-requests=36 \
  --output=output/nvidia-candidates-new-trial/smoke.json
```

Inspect smoke availability before running the full suite. Select only eligible
exact model IDs in `evaluation_models`, omit `--cases`, and use a fresh output:

```sh
dart --suppress-analytics run scripts/nemotron_eval.dart --live \
  --provider=nvidia --models="$evaluation_models" --concurrency=4 \
  --output=output/nvidia-candidates-new-trial/full.json
```

Changing cases, model selection, concurrency, source hashes or source commit
changes the frozen contract. Do not resume a smoke checkpoint as a full run or
resume a historical checkpoint after source changes. Use a new output path for
a new trial and retain the earlier evidence.

Replay the archived accepted results offline, without credentials or provider
requests:

```sh
dart --suppress-analytics run scripts/nemotron_eval.dart --replay \
  --provider=nvidia \
  --models=z-ai/glm-5.3-flash,google/gemma-4-31b-it,poolside/laguna-xs-2.1,z-ai/glm-5.3 \
  --cases=create-notes-fields,edit-notes-fields,guidance-ambiguous-organize \
  --output=docs/evidence/nvidia-model-candidates/2026-10-08/smoke.json

dart --suppress-analytics run scripts/nemotron_eval.dart --replay \
  --provider=nvidia \
  --models=z-ai/glm-5.3-flash,google/gemma-4-31b-it,z-ai/glm-5.3 \
  --output=docs/evidence/nvidia-model-candidates/2026-10-08/full.json
```
