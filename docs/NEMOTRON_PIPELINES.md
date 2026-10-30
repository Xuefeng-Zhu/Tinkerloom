# Nemotron creation pipeline experiments

This is a summary of an opt-in AppNest study of synthetic app-definition creation. It does not establish that these experimental pipelines are implemented or enabled in Tinkerloom, and it is not a Nebius or live Tinkerloom acceptance result. See the [original AppNest pipeline study](../legacy_appnest/docs/NEMOTRON_PIPELINES.md) for its complete protocol and evidence references.

## Approaches compared

| Approach | Idea | Important boundary |
| --- | --- | --- |
| Efficient-creation control | Nemotron with a creation checklist and low reasoning effort | Evaluator profile; not a change to Tinkerloom's configured default |
| Scoped contract | Shorten the instructions and conservatively select relevant feature families | The full parser and original case assertions still apply |
| Semantic plan and compiler | Ask the model for a bounded plan and construct wiring server-side | Measures model plus compiler, not raw model output |
| Bounded repair | Request allowlisted changes to a rejected candidate | Strict final validation still applies; a patch is not guaranteed to be minimal |
| Cascade | Try Nemotron first, then use GLM in remaining attempts | A pass is a combined-model result, not a Nemotron-only pass |
| GLM control | Use GLM on the same cases | A separate comparator, not a Nemotron result |

The plan compiler did not choose authorization policies, invent fields or actions, or enable effects. The repair experiment bounded both the allowed changes and patch size. These restrictions were part of the AppNest study; their description here does not imply that Tinkerloom offers the same experimental modes.

## Observations

The pilot used six cases: five supported app requests and one unsupported request. Each pipeline correctly rejected the unsupported request. Reported passes allowed up to three attempts; operation time included attempted work, excluding pacing waits.

| Approach | Passed / 6 | First attempt / 6 | Attempts | Median operation seconds | Known tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Nemotron efficient-creation control | 3 | 2 | 13 | 78.6 | 297,216 |
| Scoped contract | 1 | 1 | 16 | 143.6 | 347,218 |
| Semantic plan and compiler | 2 | 2 | 14 | 47.7 | 117,764 |
| Bounded repair | 3 | 1 | 16 | 84.6 | 268,227; one usage result unknown |
| Nemotron then GLM cascade | 6 | 2 | 12 | 53.8 | 212,733; one usage result unknown |
| GLM control | 6 | 5 | 7 | 8.4 | 111,718 |

The scoped trial failed all five supported cases despite shorter requests. The semantic plan reduced request size and had a lower observed median, but its narrower grammar introduced validation failures. Bounded repairs recovered some cases while losing another success; matching the control's pass count did not mean the same cases passed. The cascade passed all six cases while using GLM for four operations. The GLM control passed all six with fewer attempts in this pilot.

These are individual trials on a small, deliberately difficult set. Some usage was unknown and costs were not reported; the results do not establish general model quality, pricing, or reliability. Request-byte reductions do not establish token savings. The experiments did not change the configured application model or default transport.

## Applying the lessons

Keep strict validation and authorization independent of model output. When comparing approaches, measure first-attempt and eventual passes, include failed attempts and unknown usage, and clearly identify the serving model. Treat offline fixtures, provider evaluations, application persistence, and device behavior as separate verification layers. Do not launch a live evaluation without explicit authorization and a usage budget.

See [Nemotron and AI generation](NEMOTRON.md) for the actual Tinkerloom provider configuration, and [Nemotron model evaluation](NEMOTRON_EVALUATION.md) for the broader AppNest study.
