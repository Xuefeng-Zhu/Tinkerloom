# AppNest Nemotron evaluation (nvidia)

Status: completed. Benchmark: appnest-nemotron-v2. Planned operations per model: 8.

Execution: concurrency 1; serial-delay pacing 4000 ms; operations within each model are sequential.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | 8 / 8 | 16 | 6 | 25.0% | 75.0% / 75.0% | 0 / 0 / 0 / 0 | 0 attempts | 89130.0 / 117621 | 340477 | 0 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | create | 8 / 8 | 8 | 6 | 25.0% | 75.0% / 75.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | edit | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | guidance | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | unsupported | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **nvidia/nemotron-3-super-120b-a12b:** known prompt / completion / total / reasoning tokens: 287019 / 53458 / 340477 / 37134; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **nvidia/nemotron-3-super-120b-a12b / create-calendar-category** (create, failed): validation: Missing required capabilities: records.create.v1, records.patch.v1
- **nvidia/nemotron-3-super-120b-a12b / create-rich-dashboard** (create, failed): validation: Boolean checklists need a record patch action

## Provenance

- Commit: `93f0291683bbcdf299ffd6276b2e9e7ccdc78496`
- Tracked dirty diff SHA-256: `4adb7027cb3089ad6f8a98b1ff593471a7dca22632b6c5a52c0accdc2efcc80b`
- Frozen run fingerprint: `ac65e484994caa4c2295a7ab991a1613211abfb17d6ec73e9c2dbb32b30627cd`
- Updated: 2026-10-08T16:16:01.420036Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-nemotron-instruction-schema-publisher-creation-low-checklist-v1, family: Nemotron, catalogUrl: https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b, reasoning: creation: low effort; no explicit reasoning budget; edit/guidance: thinking disabled, promptContract: nemotron-creation-checklist-v1, requestOverrides: {stream: false, chat_template_kwargs: {enable_thinking: false}}, creationRequestOverrides: {stream: false, reasoning_effort: low, temperature: 1.0, top_p: 0.95}, operationOverrides: {create: {stream: false, reasoning_effort: low, temperature: 1.0, top_p: 0.95}, unsupported: {stream: false, reasoning_effort: low, temperature: 1.0, top_p: 0.95}, edit: {stream: false, chat_template_kwargs: {enable_thinking: false}}, sequence: {stream: false, chat_template_kwargs: {enable_thinking: false}}, guidance: {stream: false, chat_template_kwargs: {enable_thinking: false}}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, g… | https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b |
