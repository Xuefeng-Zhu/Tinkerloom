# AppNest Nemotron evaluation (nvidia)

Status: blocked. Benchmark: appnest-nemotron-v2. Planned operations per model: 36.

Execution: concurrency 4; global-dispatch pacing 4000 ms; operations within each model are sequential. Observed peak concurrent requests in the latest invocation: 3.

Pause reason: Requested per-invocation request cap reached..
Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | 0 / 36 | 1 | 0 | unknown | unknown / 0.0% | 0 / 36 / 0 / 0 | 0 attempts | unknown / unknown | 17808 | 0 |
| nvidia/nemotron-3-super-120b-a12b | 0 / 36 | 1 | 0 | unknown | unknown / 0.0% | 0 / 36 / 0 / 0 | 0 attempts | unknown / unknown | 17733 | 0 |
| nvidia/nemotron-3-ultra-550b-a55b | 1 / 36 | 1 | 1 | 100.0% | 100.0% / 2.8% | 0 / 35 / 0 / 0 | 0 attempts | 18171 / 18171 | 17682 | 0 |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | 0 / 36 | 1 | 0 | unknown | unknown / 0.0% | 0 / 36 / 0 / 0 | 1 attempts | unknown / unknown | unknown | 1 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | create | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b | create | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-super-120b-a12b | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b | create | 1 / 12 | 1 | 1 | 100.0% | 100.0% / 8.3% | 8.3% |
| nvidia/nemotron-3-ultra-550b-a55b | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-ultra-550b-a55b | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | edit | 0 / 12 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | guidance | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | unsupported | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **nvidia/nemotron-3.5-lightning-30b-a3b:** known prompt / completion / total / reasoning tokens: 16898 / 910 / 17808 / unknown; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.
- **nvidia/nemotron-3-super-120b-a12b:** known prompt / completion / total / reasoning tokens: 16898 / 835 / 17733 / 0; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.
- **nvidia/nemotron-3-ultra-550b-a55b:** known prompt / completion / total / reasoning tokens: 16898 / 784 / 17682 / unknown; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.
- **nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:** known prompt / completion / total / reasoning tokens: unknown / unknown / unknown / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {http_error: 1}.

## Provenance

- Commit: `7a4b402480fe6b16bc695d280e306a9722963b11`
- Tracked dirty diff SHA-256: `54a29d5e898c0aa4a1684d3a433acf7f101576c13f07a4a7e388e49f79b55b04`
- Frozen run fingerprint: `e27b66375d5be1ea191f83b36286c90c4bb0a681d481235532923bd1896fbc4a`
- Updated: 2026-10-08T08:36:38.192442Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3.5-lightning-30b-a3b |
| nvidia/nemotron-3-super-120b-a12b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b |
| nvidia/nemotron-3-ultra-550b-a55b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning |
