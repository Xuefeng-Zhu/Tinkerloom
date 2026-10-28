# AppNest NVIDIA model evaluation (nvidia)

Status: completed. Benchmark: appnest-nemotron-v2. Planned operations per model: 3.

Execution: concurrency 4; global-dispatch pacing 4000 ms; operations within each model are sequential. Observed peak concurrent requests in the latest invocation: 4.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z-ai/glm-5.3-flash | 3 / 3 | 5 | 3 | 66.7% | 100.0% / 100.0% | 0 / 0 / 0 / 0 | 2 attempts | 24133 / 192078 | 33454 | 2 |
| google/gemma-4-31b-it | 3 / 3 | 4 | 3 | 66.7% | 100.0% / 100.0% | 0 / 0 / 0 / 0 | 1 attempts | 32664 / 114659 | 36697 | 1 |
| poolside/laguna-xs-2.1 | 3 / 3 | 9 | 0 | unknown | unknown / 0.0% | 0 / 0 / 0 / 0 | 9 attempts | 1934 / 180858 | unknown | 9 |
| z-ai/glm-5.3 | 3 / 3 | 3 | 3 | 100.0% | 100.0% / 100.0% | 0 / 0 / 0 / 0 | 0 attempts | 2855 / 10017 | 33418 | 0 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| z-ai/glm-5.3-flash | create | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | edit | 1 / 1 | 1 | 1 | 0.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | guidance | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | unsupported | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| z-ai/glm-5.3-flash | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| google/gemma-4-31b-it | create | 1 / 1 | 1 | 1 | 0.0% | 100.0% / 100.0% | 100.0% |
| google/gemma-4-31b-it | edit | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| google/gemma-4-31b-it | guidance | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| google/gemma-4-31b-it | unsupported | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| google/gemma-4-31b-it | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| poolside/laguna-xs-2.1 | create | 1 / 1 | 0 | 0 | unknown | unknown / 0.0% | 100.0% |
| poolside/laguna-xs-2.1 | edit | 1 / 1 | 0 | 0 | unknown | unknown / 0.0% | 100.0% |
| poolside/laguna-xs-2.1 | guidance | 1 / 1 | 0 | 0 | unknown | unknown / 0.0% | 100.0% |
| poolside/laguna-xs-2.1 | unsupported | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| poolside/laguna-xs-2.1 | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| z-ai/glm-5.3 | create | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | edit | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | guidance | 1 / 1 | 1 | 1 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | unsupported | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |
| z-ai/glm-5.3 | sequence | 0 / 0 | 0 | 0 | unknown | unknown / unknown | unknown |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **z-ai/glm-5.3-flash:** known prompt / completion / total / reasoning tokens: 32816 / 638 / 33454 / 43; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 2}.
- **google/gemma-4-31b-it:** known prompt / completion / total / reasoning tokens: 35569 / 1128 / 36697 / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 1}.
- **poolside/laguna-xs-2.1:** known prompt / completion / total / reasoning tokens: unknown / unknown / unknown / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 3; availability kinds: {timeout: 2, http_error: 7}.
- **z-ai/glm-5.3:** known prompt / completion / total / reasoning tokens: 32800 / 618 / 33418 / 24; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **poolside/laguna-xs-2.1 / create-notes-fields** (create, failed): http_error HTTP 503: AI provider could not complete the request (HTTP 503).
- **poolside/laguna-xs-2.1 / edit-notes-fields** (edit, failed): http_error HTTP 503: AI provider could not complete the request (HTTP 503).
- **poolside/laguna-xs-2.1 / guidance-ambiguous-organize** (guidance, failed): http_error HTTP 503: Nemotron guidance request failed.

## Provenance

- Commit: `93f0291683bbcdf299ffd6276b2e9e7ccdc78496`
- Tracked dirty diff SHA-256: `ad104563e37844fb31ddfc77900de81ee892838dd7a782cf0f79b77dac43e083`
- Frozen run fingerprint: `c7dd349e9bd578409da856422b17ee3a3e746bdfe72ef5cf717b9c1ec6bbe6c4`
- Updated: 2026-10-08T14:24:37.495185Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| z-ai/glm-5.3-flash | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-glm-5.3-flash-instruction-schema-low-v1, family: GLM, catalogUrl: https://build.nvidia.com/z-ai/glm-5-3-flash, reasoning: always enabled; low effort requested; previous thinking cleared, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low, chat_template_kwargs: {clear_thinking: true}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash, https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer, https://recipes.vllm.ai/zai-org/GLM-5.3-Flash], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer, temperature: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer, reasoning_effort: https://docs.api.nvidia.com/n… | https://build.nvidia.com/z-ai/glm-5-3-flash |
| google/gemma-4-31b-it | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-gemma-4-31b-it-instruction-schema-thinking-off-v1, family: Gemma, catalogUrl: https://build.nvidia.com/google/gemma-4-31b-it, reasoning: thinking disabled, requestOverrides: {stream: false, temperature: 0, chat_template_kwargs: {enable_thinking: false}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer, https://build.nvidia.com/google/gemma-4-31b-it/modelcard], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer, temperature: https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer, chat_template_kwargs.enable_thinking: https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer}, limitations: [Bounded AppNest f… | https://build.nvidia.com/google/gemma-4-31b-it |
| poolside/laguna-xs-2.1 | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-laguna-xs-2.1-instruction-schema-default-v1, family: Laguna, catalogUrl: https://build.nvidia.com/poolside/laguna-xs-2.1, reasoning: model default; no documented NVIDIA HTTP override sent, requestOverrides: {stream: false, temperature: 0}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1-infer, https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1-infer, temperature: https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1-infer}, limitations: [Bounded AppNest feasibility profile; optional source-model thinking is not assumed to expose an NVIDIA HTTP parameter., Temperatur… | https://build.nvidia.com/poolside/laguna-xs-2.1 |
| z-ai/glm-5.3 | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-glm-5.3-instruction-schema-low-v1, family: GLM, catalogUrl: https://build.nvidia.com/z-ai/glm-5-3, reasoning: enabled; low effort requested; previous thinking cleared, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low, chat_template_kwargs: {clear_thinking: true}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, https://recipes.vllm.ai/zai-org/GLM-5.3], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, temperature: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, reasoning_effort: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, reasoning_effort.locat… | https://build.nvidia.com/z-ai/glm-5-3 |
