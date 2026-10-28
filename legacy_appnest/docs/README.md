# Documentation index

Use the setup and contract guides for current behavior. Evidence pages describe a particular dated checkout or environment; their test counts and local IDs are snapshots.

## Start here

| Goal | Read |
| --- | --- |
| Understand the product and run it | [Project README](../README.md), then [local development](DEVELOPMENT.md) |
| Configure AI or diagnose generation | [AI setup](AI_SETUP.md), then [creation flow](CREATION_FLOW.md) |
| Demonstrate shared data and reminders | [Demo guide](DEMO.md) |
| Understand trust, data, and module boundaries | [Architecture](../ARCHITECTURE.md), [implementation decisions](IMPLEMENTATION.md), [Serverpod feature map](SERVERPOD_FEATURE_MAP.md) |
| Assess acceptance and remaining work | [Requirements](REQUIREMENTS.md), [verification records](VERIFICATION.md), [architecture review](ARCHITECTURE_REVIEW.md), [security limits](SECURITY.md) |
| Change platform source safely | [Development workflow](DEVELOPMENT.md#changing-the-platform), [agent instructions](../AGENTS.md) |

## Feature contracts

| Guide | Covers |
| --- | --- |
| [Creation flow](CREATION_FLOW.md) | Describe-first creation, optional clarification, generation, and publication |
| [Customization](CUSTOMIZATION.md) | Appearance/content/layout/behavior editing and local clock/timer behavior |
| [Mini-apps](MINI_APPS.md) | Pages, navigation, Daily Planner, queries, summaries, and reminders |
| [Rich components](RICH_COMPONENTS.md) | Data views, charts, forms, checklists, workflow boards, and private images |
| [Appearance](APPEARANCE.md) | Style tokens, responsive composition, and compatible visual changes |
| [Visual editing](VISUAL_EDITING.md) | Preview selection, inspector edits, draft queues, and conflict handling |
| [Mobile features](MOBILE_FEATURES.md) | Device-local consent, supported native operations, lifecycle, and platform limits |

## Dated evidence and investigations

Begin with [verification records](VERIFICATION.md) for the scope of each check. A screenshot using synthetic preview data does not establish backend persistence. A provider adapter test does not establish live model quality. A native build does not establish physical-device behavior.

| Record | Evidence type |
| --- | --- |
| [Architecture review](ARCHITECTURE_REVIEW.md) | 2026-10-07 source review, selected passing suites, and focused defect reproductions |
| [Fresh AI creation](AI_CREATION_CHECK.md) | Historical authenticated browser creation/publication and semantic edits |
| [Customization AI evaluation](CUSTOMIZATION_AI_CHECK.md) | Historical targeted provider creation/edit batches with explicit baselines |
| [Nemotron model evaluation](NEMOTRON_EVALUATION.md) | Reproducible free-route model comparison, scoring and checkpoint recovery |
| [Nemotron contract tuning](NEMOTRON_TUNING.md) | Opt-in creation checklist and reasoning trials with frozen source, unchanged scoring and GLM comparison gates |
| [Nemotron creation pipelines](NEMOTRON_PIPELINES.md) | Opt-in scoped prompts, deterministic plan compilation, bounded repairs and GLM fallback pilot |
| [Kimi, GLM and DeepSeek evaluation](FREE_MODEL_EVALUATION.md) | Blocked 108-operation NVIDIA comparison, seven-model category observations and archived evidence |
| [GLM Flash, Gemma and Laguna comparison](NVIDIA_MODEL_COMPARISON.md) | 2026-10-08 NVIDIA smoke and partial full phase: Flash and GLM passed 36/36 each; Gemma interrupted after timeouts, Laguna unavailable |
| [GLM Flash live application check](GLM_FLASH_LIVE_CHECK.md) | Dated local browser, authenticated publication and record persistence check, with failed edit evidence |
| [Generation failure investigation](GENERATION_FAILURE_CHECK.md) | A dated failure, subsequent changes, and bounded verification |
| [Rich components live check](RICH_COMPONENTS_LIVE_CHECK.md) | Historical local RPC/browser media, forms, queries, and persistence |
| [Phone Toolkit AI check](IPHONE_AI_CHECK.md) | Historical generation/browser behavior; distinct from native-device acceptance |
| [Serverpod feedback](SERVERPOD_FEEDBACK.md) | Framework-owned observations and reproduction recipes for the reviewed release |

## Keeping these pages accurate

- Put setup commands in [DEVELOPMENT.md](DEVELOPMENT.md) and operator AI configuration in [AI_SETUP.md](AI_SETUP.md); link to them from feature pages.
- Change the relevant feature contract when its source behavior changes. Keep [architecture](../ARCHITECTURE.md) focused on boundaries and invariants.
- Record validation with date, source revision or checkout description, commands, evidence layer, and remaining gaps. Preserve older results as history instead of presenting them as current acceptance.
- Treat the [architecture review](ARCHITECTURE_REVIEW.md) as an observation snapshot. Mark a finding resolved only with an implementation reference and relevant fresh evidence.
- Use repository-relative links. Link to source symbols or stable code anchors when useful; avoid machine-specific paths and temporary files as the only evidence.
- Keep credentials, private records, database directories, and raw private logs out of documentation and committed evidence.

[Back to the project README](../README.md)
