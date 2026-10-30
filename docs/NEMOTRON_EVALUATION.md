# Nemotron model evaluation

This summary carries forward a synthetic AppNest evaluation as background for working with Nemotron. It does **not** measure the current Tinkerloom implementation, its Flutter client or Appwrite deployment, and it is not evidence of a Nebius integration. The [original AppNest study](../legacy_appnest/docs/NEMOTRON_EVALUATION.md) preserves the full protocol, evidence references, and qualifications. Provider behavior and availability can change.

## Evaluation design

The study evaluated app-definition creation, edits against fixed definitions, idea guidance, unsupported requests, and follow-up edits using synthetic cases. Four Nemotron model routes used the NVIDIA developer API with thinking disabled. Each result was scored against a strict parser and request-specific assertions. Follow-up edits depended on that model having produced an accepted creation, so some were skipped. The serial comparison ran one call at a time and allowed bounded attempts for an operation.

A passed synthetic result means the candidate met the study's validation and case assertions. It does not prove a rendered Flutter experience, authenticated record persistence, publication, device behavior, or production readiness. A provider call failing before a usable response is an availability failure, not a correctness result.

## Results

The study resolved 144 planned operations: 72 passed, 62 failed and 10 dependent sequence edits were skipped, over 288 attempts. Each result below is **first-attempt passes → eventual passes**, with the planned case count in the column heading.

| Model | Creation /12 | Fixed edits /12 | Guidance /4 | Unsupported /4 | Follow-up edits /4 |
| --- | --- | --- | --- | --- | --- |
| Lightning | 0 → 1 | 1 → 5 | 3 → 4 | 3 → 3 | 0 → 1; 3 skipped |
| Super | 2 → 6 | 9 → 12 | 4 → 4 | 4 → 4 | 1 → 2; 2 skipped |
| Ultra | 2 → 7 | 4 → 7 | 3 → 3 | 3 → 4 | 3 → 3; 1 skipped |
| Nano Omni | 0 → 0 | 2 → 4 | 1 → 1 | 1 → 1 | 0 → 0; 4 skipped |

Super had the strongest observed fixed-baseline edit result in this study. Ultra produced the most strict creation passes, but provider failures prevented comparable response coverage, so the study did not name a definitive creation or editing winner. Lightning had five timeout attempts; Ultra and Nano Omni had 21 and 66 HTTP 503 attempts respectively. Quick failures are not evidence of fast usable generation.

Common failures included invalid JSON, unsupported properties or controls, missing requested features, and edits that changed unrelated behavior. A separate offline diagnostic passed the same saved responses through a capability compiler and accepted one additional Ultra creation. That post-hoc result does not change the original strict score.

Known usage totaled 3,492,090 tokens across 196 attempts; usage for the remaining 92 attempts was unknown. The provider did not report cost, so actual cost remains unknown. These are single-trial observations on the study cases, not a universal model ranking, reliability guarantee, or current pricing statement.

A separate bounded parallel smoke used a four-request cap and observed at most three overlapping calls. One response passed, two failed validation and one returned HTTP 503. It tested scheduling and pacing, not a full parallel quality comparison or a measured speedup.

## Contract and reasoning tuning

A separate AppNest screening compared creation-contract and reasoning profiles for the Super model on eight cases. The thinking-off baseline passed 3/8 eventually and 2/8 on the first attempt. The `efficient-creation` candidate passed 6/8 eventually and 5/8 on the first attempt, but its median operation time rose from 25.295 to 52.1915 seconds and one usage result was unknown. The publisher-sampling candidate also passed 6/8 eventually, with 2/8 first-attempt passes. None met the predefined seven-pass gate, so no candidate advanced to a full benchmark; parity with GLM was not demonstrated. These are evaluator-only profiles and did not change the application default. The [original tuning study](../legacy_appnest/docs/NEMOTRON_TUNING.md) contains the full profiles, failure analysis, and evidence references.

## Using these findings

Use the failures to design representative cases and retain strict validation. Compare first-attempt results with eventual results, include failed and skipped cases, distinguish provider availability from correctness, and report unknown usage honestly. Any new evaluation needs its own explicit authorization, usage limits, and evidence; normal Tinkerloom tests are offline. Tinkerloom does not ship the original AppNest evaluation CLI.

For configured provider behavior, see [Nemotron and AI generation](NEMOTRON.md). The related [creation pipeline study](NEMOTRON_PIPELINES.md) evaluates alternatives and should not be mistaken for a Tinkerloom production feature.
