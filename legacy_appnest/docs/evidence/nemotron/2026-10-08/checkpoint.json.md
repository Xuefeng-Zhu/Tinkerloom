# AppNest Nemotron evaluation

Status: blocked. Benchmark: appnest-nemotron-v1. Planned operations per model: 36.

Pause reason: Free daily request quota is exhausted; no completion calls made..
Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning:free | 1 / 36 | 3 | 0 | 0.0% | 0.0% / 0.0% | 0 / 35 / 0 / 0 | 2 attempts | 182650 / 182650 | 16955 | 2 |
| nvidia/nemotron-3-super-120b-a12b:free | 1 / 36 | 3 | 0 | 0.0% | 0.0% / 0.0% | 0 / 35 / 0 / 0 | 0 attempts | 54215 / 54215 | 24315 | 0 |
| nvidia/nemotron-3-ultra-550b-a55b:free | 0 / 36 | 1 | 0 | unknown | unknown / 0.0% | 0 / 35 / 1 / 0 | 1 attempts | unknown / unknown | unknown | 1 |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | 0 / 36 | 0 | 0 | unknown | unknown / 0.0% | 0 / 36 / 0 / 0 | 0 attempts | unknown / unknown | unknown | 0 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning:free | create | 1 / 12 | 1 | 0 | 0.0% | 0.0% / 0.0% | 8.3% |
| nvidia/nemotron-3.5-lightning:free | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning:free | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning:free | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning:free | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b:free | create | 1 / 12 | 1 | 0 | 0.0% | 0.0% / 0.0% | 8.3% |
| nvidia/nemotron-3-super-120b-a12b:free | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b:free | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b:free | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b:free | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b:free | create | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b:free | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b:free | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b:free | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b:free | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | create | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

Expected route price: USD 0. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **nvidia/nemotron-3.5-lightning:free:** known prompt / completion / total / reasoning tokens: 16897 / 58 / 16955 / 60; usage complete: false; reported cost USD: 0 (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 2}.
- **nvidia/nemotron-3-super-120b-a12b:free:** known prompt / completion / total / reasoning tokens: 17232 / 7083 / 24315 / 5249; usage complete: true; reported cost USD: 0 (complete: true); availability-only outcomes: 0; availability kinds: {}.
- **nvidia/nemotron-3-ultra-550b-a55b:free:** known prompt / completion / total / reasoning tokens: unknown / unknown / unknown / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {rate_limit: 1}.
- **nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free:** known prompt / completion / total / reasoning tokens: unknown / unknown / unknown / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **nvidia/nemotron-3.5-lightning:free / create-notes-fields** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **nvidia/nemotron-3-super-120b-a12b:free / create-notes-fields** (create, failed): validation: On a reachable record view such as notesList, set titleFieldId:"title" and filterFieldIds:["category"]. The search control requires BOTH view.titleFieldId referencing the existing text title and view.filterFieldIds:[EXISTING_CATEGORY_FIELD_ID]. Include views.configured.v1 in requires; do not create another title or category field.
- **nvidia/nemotron-3-ultra-550b-a55b:free / create-notes-fields** (create, blocked): rate_limit HTTP 429: AI provider could not complete the request (HTTP 429).

## Provenance

- Commit: `7a4b402480fe6b16bc695d280e306a9722963b11`
- Tracked dirty diff SHA-256: `6800bd23b4b5c3cbda030095e56dd2d88431cd5ea8cd655428022e5eac3e6b02`
- Frozen run fingerprint: `8e75ee4d557abd362bb1f1d85927046b4d8f71aa0f1037dd713e544173eb2898`
- Updated: 2026-10-08T05:40:14.205414Z.

## Frozen route configuration

Exact free routes and transport adaptations were frozen for the scored run. Schema-in-instructions and structured-output profiles use the same local validation and repair rules.

| Model | Pricing | Supported parameters | Transport profile |
| --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning:free | {prompt: 0, completion: 0} | [include_reasoning, max_tokens, reasoning, seed, temperature, tool_choice, tools, top_p] | {profile: openrouter-free-instruction-schema-v1, reasoning: model default, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} |
| nvidia/nemotron-3-super-120b-a12b:free | {prompt: 0, completion: 0} | [include_reasoning, max_tokens, reasoning, reasoning_effort, response_format, seed, structured_outputs, temperature, tool_choice, tools, top_p] | {profile: openrouter-free-json-schema-v1, reasoning: medium, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} |
| nvidia/nemotron-3-ultra-550b-a55b:free | {prompt: 0, completion: 0} | [include_reasoning, max_tokens, reasoning, reasoning_effort, seed, temperature, tool_choice, tools, top_p] | {profile: openrouter-free-instruction-schema-v1, reasoning: medium, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | {prompt: 0, completion: 0} | [include_reasoning, max_tokens, reasoning, seed, temperature, tool_choice, tools, top_p] | {profile: openrouter-free-instruction-schema-v1, reasoning: model default, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} |
