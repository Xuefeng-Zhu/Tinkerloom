# AppNest NVIDIA model evaluation (nvidia)

Status: blocked. Benchmark: appnest-nemotron-v2. Planned operations per model: 36.

Execution: concurrency 3; global-dispatch pacing 4000 ms; operations within each model are sequential. Observed peak concurrent requests in the latest invocation: 3.

Pause reason: rate_limit (HTTP 429); resume explicitly after availability changes..
Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| moonshotai/kimi-k3 | 24 / 36 | 65 | 7 | 62.5% | 87.5% / 19.4% | 0 / 11 / 1 / 0 | 56 attempts | 270010.5 / 270026 | 147494 | 56 |
| z-ai/glm-5.3 | 36 / 36 | 41 | 35 | 88.9% | 97.2% / 97.2% | 0 / 0 / 0 / 0 | 1 attempts | 2718.5 / 17506 | 598251 | 1 |
| deepseek-ai/deepseek-v4.1-flash | 20 / 36 | 62 | 0 | unknown | unknown / 0.0% | 0 / 16 / 0 / 0 | 62 attempts | 270035.5 / 270051 | unknown | 62 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| moonshotai/kimi-k3 | create | 12 / 12 | 8 | 7 | 62.5% | 87.5% / 58.3% | 100.0% |
| moonshotai/kimi-k3 | edit | 12 / 12 | 0 | 0 | unknown | unknown / 0.0% | 100.0% |
| moonshotai/kimi-k3 | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| moonshotai/kimi-k3 | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| moonshotai/kimi-k3 | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| z-ai/glm-5.3 | create | 12 / 12 | 12 | 11 | 66.7% | 91.7% / 91.7% | 100.0% |
| z-ai/glm-5.3 | edit | 12 / 12 | 12 | 12 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | guidance | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | unsupported | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| z-ai/glm-5.3 | sequence | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| deepseek-ai/deepseek-v4.1-flash | create | 12 / 12 | 0 | 0 | unknown | unknown / 0.0% | 100.0% |
| deepseek-ai/deepseek-v4.1-flash | edit | 8 / 12 | 0 | 0 | unknown | unknown / 0.0% | 66.7% |
| deepseek-ai/deepseek-v4.1-flash | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| deepseek-ai/deepseek-v4.1-flash | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| deepseek-ai/deepseek-v4.1-flash | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **moonshotai/kimi-k3:** known prompt / completion / total / reasoning tokens: 142446 / 5048 / 147494 / 313; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 16; availability kinds: {timeout: 55, rate_limit: 1}.
- **z-ai/glm-5.3:** known prompt / completion / total / reasoning tokens: 586683 / 11568 / 598251 / 2163; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 1}.
- **deepseek-ai/deepseek-v4.1-flash:** known prompt / completion / total / reasoning tokens: unknown / unknown / unknown / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 20; availability kinds: {timeout: 62}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **moonshotai/kimi-k3 / create-reminders-name** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **moonshotai/kimi-k3 / create-rich-dashboard** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **moonshotai/kimi-k3 / create-multistep-form** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **z-ai/glm-5.3 / create-multistep-form** (create, failed): validation: Expose private image upload, timestamp, multiline caption, rating and favorite controls.
- **deepseek-ai/deepseek-v4.1-flash / create-notes-fields** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **deepseek-ai/deepseek-v4.1-flash / create-notes-appearance** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **deepseek-ai/deepseek-v4.1-flash / create-reminders-timing** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.

## Provenance

- Commit: `7a4b402480fe6b16bc695d280e306a9722963b11`
- Tracked dirty diff SHA-256: `594138a88d13ccd1e5d676105dea59e827ec315bdc44b3ebf889d00c346f2e60`
- Frozen run fingerprint: `e7cd449878d1973a1e973cee86dcaa68dd2030325283fb0006b8c085121bb84a`
- Updated: 2026-10-08T10:22:38.092014Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| moonshotai/kimi-k3 | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-kimi-k3-instruction-schema-low-v1, family: Kimi, catalogUrl: https://build.nvidia.com/moonshotai/kimi-k3, reasoning: always enabled; low effort requested, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3, https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer, temperature: https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer, reasoning_effort: https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer}, limitations: [Bounded AppNest feasibility profile; thinking cannot be disabled., Temp… | https://build.nvidia.com/moonshotai/kimi-k3 |
| z-ai/glm-5.3 | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-glm-5.3-instruction-schema-low-v1, family: GLM, catalogUrl: https://build.nvidia.com/z-ai/glm-5-3, reasoning: enabled; low effort requested; previous thinking cleared, requestOverrides: {stream: false, temperature: 0, reasoning_effort: low, chat_template_kwargs: {clear_thinking: true}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, https://recipes.vllm.ai/zai-org/GLM-5.3], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, temperature: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer, reasoning_effort: https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3, reasoning_effort.locat… | https://build.nvidia.com/z-ai/glm-5-3 |
| deepseek-ai/deepseek-v4.1-flash | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-deepseek-v4.1-flash-instruction-schema-default-v1, family: DeepSeek, catalogUrl: https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash, reasoning: model default; no documented NVIDIA HTTP override sent, requestOverrides: {stream: false, temperature: 0}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer, https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash/modelcard], parameterSources: {stream: https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer, temperature: https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer}, limitations: [Bounded AppNest feasibility profile; source-model numeric reasoning controls are not assumed to be … | https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash |
