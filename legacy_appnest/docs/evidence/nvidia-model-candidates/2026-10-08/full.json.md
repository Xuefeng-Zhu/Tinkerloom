# AppNest NVIDIA model evaluation (nvidia)

Status: running. Benchmark: appnest-nemotron-v2. Planned operations per model: 36.

Execution: concurrency 4; global-dispatch pacing 4000 ms; operations within each model are sequential. Observed peak concurrent requests in the latest invocation: 3.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z-ai/glm-5.3-flash | 36 / 36 | 41 | 36 | 86.1% | 100.0% / 100.0% | 0 / 0 / 0 / 0 | 1 attempts | 15744.0 / 129744 | 602012 | 1 |
| google/gemma-4-31b-it | 4 / 36 | 12 | 0 | unknown | unknown / 0.0% | 0 / 31 / 0 / 0 | 12 attempts | 270013.0 / 270032 | unknown | 12 |
| z-ai/glm-5.3 | 36 / 36 | 43 | 36 | 80.6% | 100.0% / 100.0% | 0 / 0 / 0 / 0 | 1 attempts | 5944.0 / 43787 | 631492 | 1 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| z-ai/glm-5.3-flash | create | 12 / 12 | 12 | 12 | 66.7% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | edit | 12 / 12 | 12 | 12 | 91.7% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | guidance | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | unsupported | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3-flash | sequence | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| google/gemma-4-31b-it | create | 4 / 12 | 0 | 0 | unknown | unknown / 0.0% | 33.3% |
| google/gemma-4-31b-it | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| google/gemma-4-31b-it | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| google/gemma-4-31b-it | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| google/gemma-4-31b-it | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| z-ai/glm-5.3 | create | 12 / 12 | 12 | 12 | 50.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | edit | 12 / 12 | 12 | 12 | 91.7% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | guidance | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | unsupported | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | sequence | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **z-ai/glm-5.3-flash:** known prompt / completion / total / reasoning tokens: 589192 / 12820 / 602012 / 1928; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 1}.
- **google/gemma-4-31b-it:** known prompt / completion / total / reasoning tokens: unknown / unknown / unknown / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 4; availability kinds: {timeout: 12}.
- **z-ai/glm-5.3:** known prompt / completion / total / reasoning tokens: 619037 / 12455 / 631492 / 2277; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 1}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **google/gemma-4-31b-it / create-notes-fields** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **google/gemma-4-31b-it / create-notes-appearance** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **google/gemma-4-31b-it / create-reminders-timing** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.

## Provenance

- Commit: `93f0291683bbcdf299ffd6276b2e9e7ccdc78496`
- Tracked dirty diff SHA-256: `b62070abcfb2509649cba8b801856c0f98a1c749b0cefa71320b7252e260433c`
- Frozen run fingerprint: `512fbe9da3770a8b2b86c6987be7616dc967a2890047e7698d6d1b5a05784135`
- Updated: 2026-10-08T14:44:34.704263Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| z-ai/glm-5.3-flash | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-glm-5.3-flash-instruction-schema-low-v1, family: GLM, catalogUrl: https://build.nvidia.com/z-ai/glm-5-3-flash, reasoning: always enabled; low effort requested; previous thinking cleared, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low, chat_template_kwargs: {clear_thinking: true}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash, https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer, https://recipes.vllm.ai/zai-org/GLM-5.3-Flash], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer, temperature: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer, reasoning_effort: https://docs.api.nvidia.com/n… | https://build.nvidia.com/z-ai/glm-5-3-flash |
| google/gemma-4-31b-it | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-gemma-4-31b-it-instruction-schema-thinking-off-v1, family: Gemma, catalogUrl: https://build.nvidia.com/google/gemma-4-31b-it, reasoning: thinking disabled, requestOverrides: {stream: false, temperature: 0, chat_template_kwargs: {enable_thinking: false}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer, https://build.nvidia.com/google/gemma-4-31b-it/modelcard], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer, temperature: https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer, chat_template_kwargs.enable_thinking: https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer}, limitations: [Bounded AppNest f… | https://build.nvidia.com/google/gemma-4-31b-it |
| z-ai/glm-5.3 | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-glm-5.3-instruction-schema-low-v1, family: GLM, catalogUrl: https://build.nvidia.com/z-ai/glm-5-3, reasoning: enabled; low effort requested; previous thinking cleared, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low, chat_template_kwargs: {clear_thinking: true}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, https://recipes.vllm.ai/zai-org/GLM-5.3], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, temperature: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, reasoning_effort: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, reasoning_effort.locat… | https://build.nvidia.com/z-ai/glm-5-3 |
