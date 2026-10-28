# AppNest Nemotron evaluation (nvidia)

Status: completed. Benchmark: appnest-nemotron-v2. Planned operations per model: 8.

Execution: concurrency 1; serial-delay pacing 4000 ms; operations within each model are sequential.


Synthetic provider and definition benchmark; one trial per scenario. These results do not establish authenticated persistence, Flutter rendering, publication, device, or production behavior.

Observed correctness rates exclude operations without a model response. Planned pass rates include the full denominator. All retries contribute to latency and known token/cost sums.

| Model | Completed / planned | Attempts | Passed | First-pass observed | Eventual observed / planned | Skipped / pending / blocked / indeterminate | Availability failures | Median / p95 ms | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | 8 / 8 | 19 | 3 | 25.0% | 37.5% / 37.5% | 0 / 0 / 0 / 0 | 0 attempts | 25295.0 / 37483 | 361300 | 0 |

## Category results

| Model | Category | Completed / planned | Correctness scored | Passed | First-pass observed | Eventual observed / planned | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | create | 8 / 8 | 8 | 3 | 25.0% | 37.5% / 37.5% | 100.0% |
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

- **nvidia/nemotron-3-super-120b-a12b:** known prompt / completion / total / reasoning tokens: 339438 / 21862 / 361300 / 0; usage complete: true; reported cost USD: unknown (complete: false); availability-only outcomes: 0; availability kinds: {}.

## Failure examples

The checkpoint retains synthetic responses, definitions, and every attempt for offline replay. Up to three examples per model:

- **nvidia/nemotron-3-super-120b-a12b / create-calendar-category** (create, failed): validation: Choose an approved theme and icon
- **nvidia/nemotron-3-super-120b-a12b / create-calendar-appearance** (create, failed): validation: Choose an approved theme and icon
- **nvidia/nemotron-3-super-120b-a12b / create-rich-dashboard** (create, failed): validation: Page dashboardPage primaryActionId addActivity must reference a records.create.v1 action. Include addActivity in actionIds of a view on this page and set that view formPageId to its form page (unless the view is itself a form).

## Provenance

- Commit: `93f0291683bbcdf299ffd6276b2e9e7ccdc78496`
- Tracked dirty diff SHA-256: `f732a608cb02e94f7f52a763dd3f6be8ba26fb9ddb535dd914e6a320a83a92fd`
- Frozen run fingerprint: `ab0c586ef192ea482e35b0de7233a56d56c569a2a7e7b18cbf8d668740f6d045`
- Updated: 2026-10-08T15:08:50.373023Z.
- API base: https://integrate.api.nvidia.com/v1.

## Frozen route configuration

Provider routes and transport adaptations were frozen for the scored run. Profiles shape requests for each provider; local schema, semantic, unsupported-request, and repair checks remain authoritative. The report does not infer provider-side schema enforcement.

| Model | Endpoint availability / pricing | Supported parameters | Transport profile | Source |
| --- | --- | --- | --- | --- |
| nvidia/nemotron-3-super-120b-a12b | freeEndpoint: true; pricingVerified: false; account limits unknown | unknown | {profile: nvidia-instruction-schema-thinking-off-v1, family: Nemotron, catalogUrl: https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b, reasoning: thinking disabled, requestOverrides: {stream: false, chat_template_kwargs: {enable_thinking: false}}, responseContract: complete JSON schema supplied as instructions, generationDeadlineSeconds: 90, guidanceDeadlineSeconds: 20, generationMaxTokens: {initial: 8000, recognizedCreationTruncation: 12000}, guidanceMaxTokens: 2048, topP: model default; omitted, documentationUrls: [https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b/modelcard], parameterSources: {chat_template_kwargs.enable_thinking: https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b/modelcard, stream: https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b}, limitations: []} | https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b |
