# AppNest Nemotron evaluation (nvidia)

Status: completed. Benchmark: appnest-nemotron-v2. Planned operations per model: 36.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | 33 / 36 | 80 | 14 | 21.2% | 42.4% / 38.9% | 3 / 0 / 0 / 0 | 5 attempts | 75999 / 186471 | 1387255 | 5 |
| nvidia/nemotron-3-super-120b-a12b | 34 / 36 | 54 | 28 | 58.8% | 82.4% / 77.8% | 2 / 0 / 0 / 0 | 0 attempts | 2806.0 / 37183 | 950500 | 0 |
| nvidia/nemotron-3-ultra-550b-a55b | 35 / 36 | 68 | 24 | 46.9% | 75.0% / 66.7% | 1 / 0 / 0 / 0 | 21 attempts | 7557 / 107810 | 838007 | 21 |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | 32 / 36 | 86 | 6 | 23.5% | 35.3% / 16.7% | 4 / 0 / 0 / 0 | 66 attempts | 2306.0 / 35764 | 316328 | 66 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | create | 12 / 12 | 12 | 1 | 0.0% | 8.3% / 8.3% | 100.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | edit | 12 / 12 | 12 | 5 | 8.3% | 41.7% / 41.7% | 100.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | guidance | 4 / 4 | 4 | 4 | 75.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | unsupported | 4 / 4 | 4 | 3 | 75.0% | 75.0% / 75.0% | 100.0% |
| nvidia/nemotron-3.5-lightning-30b-a3b | sequence | 1 / 4 | 1 | 1 | 0.0% | 100.0% / 25.0% | 25.0% |
| nvidia/nemotron-3-super-120b-a12b | create | 12 / 12 | 12 | 6 | 16.7% | 50.0% / 50.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | edit | 12 / 12 | 12 | 12 | 75.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | guidance | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | unsupported | 4 / 4 | 4 | 4 | 100.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3-super-120b-a12b | sequence | 2 / 4 | 2 | 2 | 50.0% | 100.0% / 50.0% | 50.0% |
| nvidia/nemotron-3-ultra-550b-a55b | create | 12 / 12 | 11 | 7 | 18.2% | 63.6% / 58.3% | 100.0% |
| nvidia/nemotron-3-ultra-550b-a55b | edit | 12 / 12 | 11 | 7 | 36.4% | 63.6% / 58.3% | 100.0% |
| nvidia/nemotron-3-ultra-550b-a55b | guidance | 4 / 4 | 3 | 3 | 100.0% | 100.0% / 75.0% | 100.0% |
| nvidia/nemotron-3-ultra-550b-a55b | unsupported | 4 / 4 | 4 | 4 | 75.0% | 100.0% / 100.0% | 100.0% |
| nvidia/nemotron-3-ultra-550b-a55b | sequence | 3 / 4 | 3 | 3 | 100.0% | 100.0% / 75.0% | 75.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create | 12 / 12 | 6 | 0 | 0.0% | 0.0% / 0.0% | 100.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | edit | 12 / 12 | 7 | 4 | 28.6% | 57.1% / 33.3% | 100.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | guidance | 4 / 4 | 3 | 1 | 33.3% | 33.3% / 25.0% | 100.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | unsupported | 4 / 4 | 1 | 1 | 100.0% | 100.0% / 25.0% | 100.0% |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | sequence | 0 / 4 | 0 | 0 | unknown | unknown / 0.0% | 0.0% |

## Recommendations

- **create:** No winner: complete comparable create correctness coverage is required for every selected model.
- **edit:** No winner: complete comparable edit correctness coverage is required for every selected model.

Recommendations are exploratory. Correctness ranks first, then first-attempt success, median latency, and known total tokens; unknown usage never wins a tie. The application model is unchanged.

## Usage and availability

NVIDIA free developer endpoint, account limits unknown. The trial API is expected to be free; unit pricing and account quota are unverified. Provider-reported cost remains unknown when omitted. Partial sums are labeled below.

- **nvidia/nemotron-3.5-lightning-30b-a3b:** known prompt / completion / total / reasoning tokens: 1324923 / 62332 / 1387255 / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {timeout: 5}.
- **nvidia/nemotron-3-super-120b-a12b:** known prompt / completion / total / reasoning tokens: 920225 / 30275 / 950500 / 0; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.
- **nvidia/nemotron-3-ultra-550b-a55b:** known prompt / completion / total / reasoning tokens: 816477 / 21530 / 838007 / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 3; availability kinds: {http_error: 21}.
- **nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:** known prompt / completion / total / reasoning tokens: 311089 / 5239 / 316328 / unknown; usage complete: false; reported cost USD: unknown (complete: false); availability-only outcomes: 15; availability kinds: {http_error: 66}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **nvidia/nemotron-3.5-lightning-30b-a3b / create-notes-fields** (create, failed): validation: list options: unknown properties controls
- **nvidia/nemotron-3.5-lightning-30b-a3b / create-notes-appearance** (create, failed): timeout: The AI provider did not finish within the bounded response deadline. Try again later.
- **nvidia/nemotron-3.5-lightning-30b-a3b / create-reminders-timing** (create, failed): validation: Include one owner inbox reminder rule for open tasks.
- **nvidia/nemotron-3-super-120b-a12b / create-notes-fields** (create, failed): validation: Missing required capabilities: views.interactive.v1
- **nvidia/nemotron-3-super-120b-a12b / create-calendar-category** (create, failed): validation: Choose an approved theme and icon
- **nvidia/nemotron-3-super-120b-a12b / create-calendar-appearance** (create, failed): validation: Choose an approved theme and icon
- **nvidia/nemotron-3-ultra-550b-a55b / create-reminders-timing** (create, failed): http_error HTTP 503: AI provider could not complete the request (HTTP 503).
- **nvidia/nemotron-3-ultra-550b-a55b / create-reminders-name** (create, failed): validation: Missing required capabilities: views.interactive.v1
- **nvidia/nemotron-3-ultra-550b-a55b / create-rich-dashboard** (create, failed): validation: Choose an approved theme and icon
- **nvidia/nemotron-3-nano-omni-30b-a3b-reasoning / create-notes-fields** (create, failed): http_error HTTP 503: AI provider could not complete the request (HTTP 503).
- **nvidia/nemotron-3-nano-omni-30b-a3b-reasoning / create-notes-appearance** (create, failed): validation: Unsupported field type
- **nvidia/nemotron-3-nano-omni-30b-a3b-reasoning / create-reminders-timing** (create, failed): validation: AppSpec: unknown properties unsupported

## Provenance

- Commit: `7a4b402480fe6b16bc695d280e306a9722963b11`
- Tracked dirty diff SHA-256: `6b45352e00ef8c72b979c8c97cff64770033a8efc5e2e081e86e6fe61399b6d6`
- Frozen run fingerprint: `2bdf5764a25f152759f936a945d50cfbbc6c7d23e51000b56aae7fc64a32bbb1`
- Updated: 2026-10-08T08:25:25.001971Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3.5-lightning-30b-a3b |
| nvidia/nemotron-3-super-120b-a12b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b |
| nvidia/nemotron-3-ultra-550b-a55b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, reasoning: thinking disabled, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20} | https://build.nvidia.com/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning |
