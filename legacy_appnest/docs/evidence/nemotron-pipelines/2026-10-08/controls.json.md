# AppNest NVIDIA model evaluation (nvidia)


Status: completed. Benchmark: appnest-nemotron-v2. Planned operations per model: 6.

Execution: concurrency 2; global-dispatch pacing 4000 ms; operations within each model are sequential. Observed peak concurrent requests in the latest invocation: 2.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | 6 / 6 | 13 | 3 | 33.3% | 50.0% / 50.0% | 0 / 0 / 0 / 0 | 0 attempts | 78576.0 / 141828 | 297216 | 0 |
| z-ai/glm-5.3 | 6 / 6 | 7 | 6 | 83.3% | 100.0% / 100.0% | 0 / 0 / 0 / 0 | 0 attempts | 8426.5 / 19766 | 111718 | 0 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | create | 5 / 5 | 5 | 2 | 20.0% | 40.0% / 40.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | edit | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | guidance | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| nvidia/nemotron-3-super-120b-a12b | unsupported | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| z-ai/glm-5.3 | create | 5 / 5 | 5 | 5 | 80.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | edit | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| z-ai/glm-5.3 | guidance | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| z-ai/glm-5.3 | unsupported | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |

## Recommendations

- **create:** z-ai/glm-5.3 leads the complete create comparison (5/5 eventual, 4/5 first attempt).
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **nvidia/nemotron-3-super-120b-a12b:** known prompt / completion / total / reasoning tokens: 231890 / 65326 / 297216 / 54848; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.
- **z-ai/glm-5.3:** known prompt / completion / total / reasoning tokens: 106772 / 4946 / 111718 / 1157; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **nvidia/nemotron-3-super-120b-a12b / create-rich-dashboard** (create, failed): validation: Boolean checklists need a record patch action
- **nvidia/nemotron-3-super-120b-a12b / create-capacity-signup** (create, failed): validation: Reminder condition needs a valid choice value
- **nvidia/nemotron-3-super-120b-a12b / create-transfer-reading** (create, failed): validation: Boolean checklists need a record patch action

## Provenance

- Commit: `93f0291683bbcdf299ffd6276b2e9e7ccdc78496`
- Tracked dirty diff SHA-256: `86ead7e57ea915cf342e20c97be374e2cb48f5fe506678ba25554268982d5ea9`
- Frozen run fingerprint: `7a2880e1a66c0a3a248e13e665da9ebb863ffc37bb2a5ad6d9f948d2e6b42fc1`
- Updated: 2026-10-08T22:34:06.593207Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-nemotron-instruction-schema-creation-low-checklist-v1, family: Nemotron, catalogUrl: https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b, reasoning: creation: low effort; no explicit reasoning budget; edit/guidance: thinking disabled, promptContract: nemotron-creation-checklist-v1, requestOverrides: {stream: false, chat_template_kwargs: {enable_thinking: false}}, creationRequestOverrides: {stream: false, reasoning_effort: low}, operationOverrides: {create: {stream: false, reasoning_effort: low}, unsupported: {stream: false, reasoning_effort: low}, edit: {stream: false, chat_template_kwargs: {enable_thinking: false}}, sequence: {stream: false, chat_template_kwargs: {enable_thinking: false}}, guidance: {stream: false, chat_template_kwargs: {enable_thinking: false}}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, … | https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b |
| z-ai/glm-5.3 | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-glm-5.3-instruction-schema-low-v1, family: GLM, catalogUrl: https://build.nvidia.com/z-ai/glm-5-3, reasoning: enabled; low effort requested; previous thinking cleared, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low, chat_template_kwargs: {clear_thinking: true}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, https://recipes.vllm.ai/zai-org/GLM-5.3], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, temperature: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, reasoning_effort: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, reasoning_effort.locat… | https://build.nvidia.com/z-ai/glm-5-3 |
