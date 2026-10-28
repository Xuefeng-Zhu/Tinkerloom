# AppNest scoped pipeline evaluation (nvidia)

Creation pipeline: scoped. This measures the combined pipeline; individual serving models are recorded per attempt.
Status: completed. Benchmark: appnest-nemotron-v2. Planned operations per model: 6.

Execution: concurrency 1; serial-delay pacing 4000 ms; operations within each model are sequential.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | 6 / 6 | 16 | 1 | 16.7% | 16.7% / 16.7% | 0 / 0 / 0 / 0 | 0 attempts | 143579.0 / 187627 | 347218 | 0 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | create | 5 / 5 | 5 | 0 | 0.0% | 0.0% / 0.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | edit | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | guidance | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | unsupported | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **nvidia/nemotron-3-super-120b-a12b:** known prompt / completion / total / reasoning tokens: 224384 / 122834 / 347218 / 115881; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **nvidia/nemotron-3-super-120b-a12b / create-rich-dashboard** (create, failed): truncated: AI output reached the token limit before finishing. Return a smaller complete JSON definition within 8000 tokens.
- **nvidia/nemotron-3-super-120b-a12b / create-multistep-form** (create, failed): validation: The AI response was not valid JSON. Return exactly one complete JSON object without commentary or markdown.
- **nvidia/nemotron-3-super-120b-a12b / create-capacity-signup** (create, failed): validation: Record details and forms need dedicated non-tab pages

## Provenance

- Commit: `93f0291683bbcdf299ffd6276b2e9e7ccdc78496`
- Tracked dirty diff SHA-256: `86ead7e57ea915cf342e20c97be374e2cb48f5fe506678ba25554268982d5ea9`
- Frozen run fingerprint: `c01e7ac5414ff876fd66b2df6ff6eadbdd5774b39b6c22d8186db0416d66033f`
- Updated: 2026-10-08T22:48:29.830121Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-nemotron-instruction-schema-creation-low-checklist-v1, family: Nemotron, catalogUrl: https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b, reasoning: creation: low effort; no explicit reasoning budget; edit/guidance: thinking disabled, promptContract: nemotron-creation-checklist-v1, requestOverrides: {stream: false, chat_template_kwargs: {enable_thinking: false}}, creationRequestOverrides: {stream: false, reasoning_effort: low}, operationOverrides: {create: {stream: false, reasoning_effort: low}, unsupported: {stream: false, reasoning_effort: low}, edit: {stream: false, chat_template_kwargs: {enable_thinking: false}}, sequence: {stream: false, chat_template_kwargs: {enable_thinking: false}}, guidance: {stream: false, chat_template_kwargs: {enable_thinking: false}}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, … | https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b |
