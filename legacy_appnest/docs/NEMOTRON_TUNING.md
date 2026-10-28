# Nemotron contract tuning

[Documentation index](README.md) · [Evaluation CLI](NEMOTRON_EVALUATION.md) ·
[GLM, Kimi and DeepSeek comparison](FREE_MODEL_EVALUATION.md) ·
[GLM Flash, Gemma and Laguna comparison](NVIDIA_MODEL_COMPARISON.md)

## Experiment — 2026-10-08 UTC

This experiment targets `nvidia/nemotron-3-super-120b-a12b`, selected for its
12/12 eventual fixed-baseline edits and absence of service failures in the earlier
AppNest run. It compares opt-in alternatives against the existing thinking-off
profile, then admits at most one candidate across all rounds to the original
36-case benchmark against a contemporaneous `z-ai/glm-5.3` control. The configured
application's model and default transport remain unchanged.

**Tuning improved several strict creation checks, but no candidate met the
gate for a full comparison.** `efficient-creation` tied the highest eventual
result and led those tied candidates on first-try passes: 6/8 versus baseline's 3/8, with 5/8 first-try
passes versus 2/8, and 14 attempts versus 19. Its median operation time increased
from 25.295 to 52.1915 seconds, and token usage includes one unknown attempt.
The publisher-sampling candidate also passed 6/8, with only 2/8 first-try passes,
16 attempts and a median of 89.130 seconds.

No 36-case full benchmark or new GLM control was launched. GLM's earlier 36/36
result belongs to a [separate historical comparison](NVIDIA_MODEL_COMPARISON.md),
not a contemporaneous control for this tuning screen. **GLM parity has not been
demonstrated.** The acceptance gate remains seven of eight passes with the two
regression cases preserved; the failed profiles and protocol amendment remain
visible below.

| Screening profile | Eventual passes | First-attempt passes | Attempts | Median / p95 operation time | Known total tokens | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| [Baseline, thinking off](evidence/nemotron-tuning/2026-10-08/phase1/baseline.json) | 3/8 | 2/8 | 19 | 25.295 / 37.483 s | 361,300 | Reference |
| [Bounded reasoning](evidence/nemotron-tuning/2026-10-08/phase1/bounded-reasoning.json) | 5/8 | 1/8 | 19 | 75.100 / 122.430 s | 406,396 | Excluded |
| [Contract emphasis plus bounded reasoning](evidence/nemotron-tuning/2026-10-08/phase1/contract-reasoning.json) | 5/8 | 3/8 | 18 | 69.412 / 103.499 s | 373,021 | Excluded |

Bounded reasoning fixed both calendar cases and the rich dashboard after
repairs, while the previously passing reminder case regressed. It missed both
the seven-pass minimum and the requirement to preserve the reminder/focus
regression cases. It also reduced first-attempt acceptance and increased
operation time. This is evidence of a tradeoff within these eight cases, not a
uniform benefit from enabling reasoning. Adding contract emphasis restored the
reminder case and raised first-attempt passes to 3/8, but the dashboard, multistep
photo form and capacity cases still failed. It remained below the seven-pass
minimum.

The remaining contract-candidate failures were concrete definition issues:
unsupported properties on a boolean checklist control; missing requested photo
form controls and a boolean favorite field; and a conditional reminder where
the capacity request required an unconditional reminder to active claimants.
The capacity view's correct schema type is `capacity`; renderer widget names
are not schema alternatives. These remained failures under the unchanged
validator and request assertions.

All 56 round-one attempts reported token usage, totaling 1,140,717 tokens.
Bounded reasoning reported 18,984 reasoning tokens, the contract candidate
18,057, and baseline zero. No availability failures occurred. Actual cost was
not reported. [Round-one archived checkpoints](evidence/nemotron-tuning/2026-10-08/phase1/plan.json)
and the [independent audit](evidence/nemotron-tuning/2026-10-08/audit.json) preserve
the terminal results.

The bounded profile's calendar-appearance first response contained prose before
the JSON and failed the JSON-only contract. It reported 1,023 reasoning tokens
against the requested 1,024 budget, 5,363 completion tokens below the 8,000 limit,
and 62.085 seconds below the deadline. Multistep and reminder responses also
failed the JSON-only contract before later repairs. A budget-boundary interaction
is a hypothesis, not an established cause. Those responses were rejected rather
than stripped or credited. Separately, the dashboard first attempt reached the
8,000-token limit; its second attempt passed using the existing recognized
truncation retry allowance.

## Second round — completed without an eligible candidate

The second-round plan was recorded after the first round completed and before
its new provider calls. It reuses the same eight cases, acceptance gate,
selection order, limits and earlier baseline. Its two candidates separate
checklist emphasis from hard-budget reasoning behavior:

| Profile | Creation | Edits and guidance |
| --- | --- | --- |
| `contract-only` | Existing thinking-off request plus the creation checklist | Existing thinking-off request |
| `efficient-creation` | Checklist plus low reasoning effort, with no explicit `reasoning_budget` | Entire original thinking-off request |

| Screening profile | Eventual passes | First-attempt passes | Attempts | Median / p95 operation time | Known total tokens | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| [Contract only](evidence/nemotron-tuning/2026-10-08/phase2/contract-only.json) | 5/8 | 2/8 | 19 | 28.9745 / 45.677 s | 366,420 | Excluded |
| [Efficient creation](evidence/nemotron-tuning/2026-10-08/phase2/efficient-creation.json) | 6/8 | 5/8 | 14 | 52.1915 / 255.089 s | 283,441; one attempt unknown | Excluded |

The checklist-only candidate passed both calendar cases that baseline failed. It
retained reminder and focus passes, but dashboard routing, requested photo form
controls and the capacity reminder still failed after all three attempts. It
missed the seven-pass gate. Its 19 attempts all reported usage, including zero
reasoning tokens; no availability failure occurred and cost was not reported.
This improved eventual checks at less time than either first-round reasoning
candidate, while preserving the same remaining three complex-case failures as
the contract-and-budget candidate.

Efficient creation passed the photo form on its first attempt and raised
first-attempt acceptance to 5/8. Dashboard and capacity still failed after three
attempts each; it missed the same seven-pass gate. The dashboard emitted an
unsupported form control, then hit the 8,000-token limit, then produced an
invalid workflow. Capacity omitted a capability, hit the token limit, and timed
out on its last attempt. Those are two scored failures with one availability
failure attempt, rather than an availability-only failed case.

Usage was known for 13 of its 14 attempts: 283,441 known total tokens, including
44,890 reasoning tokens. The timeout's usage is unknown, so the recorded sum
cannot establish a lower complete token requirement than baseline. Actual cost
remains unknown. No second-round candidate qualified for a full run.

Here the authored creation path also includes unsupported ideas, which must
still return the existing unsupported-only response. Sequence operations use
the edit path and retain baseline transport. The same opt-in implementation
supports Ultra with medium effort, but this live tuning trial targets Super;
Ultra improvements are not measured here.

These are adaptive follow-up candidates, not part of the initial round's
preregistered profile list. Baseline reuse across time windows and frozen source
snapshots is not a simultaneous randomized causal control. Recorded baseline and
GLM initial-request hashes, unchanged scenario/scorer files and per-round source
snapshots support comparison while preserving that limitation.

## Third round — protocol amendment, completed

The second-round plan described its two candidates as the final variants. That
stopping protocol was **extended after both failed**, when a primary-source
review identified an untested published recommendation: Super's model card uses
temperature 1.0 and `top_p: 0.95`, while every earlier trial used temperature 0
and omitted `top_p`. The [model card](https://build.nvidia.com/nvidia/nemotron-3-super-120b-a12b/modelcard)
is the basis for testing this parameter gap; greedy decoding as the cause of the
failures remains unproven.

A separate [third-round plan](evidence/nemotron-tuning/2026-10-08/phase3/plan.json)
was recorded at **15:57:35 UTC**, before its source
changes and provider calls. It adds one `publisher-creation` candidate: the
unchanged checklist, low effort, no explicit reasoning budget, and the published
sampling values on the authored creation path, including unsupported ideas.
Edits, sequences, guidance, baseline and GLM retain their original payloads.
The same eight cases, acceptance gate and ordering apply, with at most one full
36-case candidate-versus-GLM run across the entire task. Original plans and
failed results remain preserved. This additional adaptation increases selection
exposure and is not a previously registered independent confirmation.

| Screening profile | Eventual passes | First-attempt passes | Attempts | Median / p95 operation time | Known total tokens | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| [Publisher creation](evidence/nemotron-tuning/2026-10-08/phase3/publisher-creation.json) | 6/8 | 2/8 | 16 | 89.130 / 117.621 s | 340,477 | Excluded |

Calendar-category and rich-dashboard cases failed after all three attempts. The
last calendar response still omitted create/patch capability declarations; the
dashboard's boolean checklist lacked a record-patch action. Notes, photo form,
capacity and reminder cases passed after two attempts each, while calendar
appearance and focus passed on their first attempts. All 16 attempts reported
usage, including 37,134 reasoning tokens, with no availability failures and
unreported cost.

This candidate passed capacity where efficient creation failed, but failed the
calendar-category case that efficient creation passed. It tied eventual passes
with fewer first-try successes, more attempts and higher median time. The
published sampling values did not establish a uniform benefit under these
bounds. No candidate met the unchanged seven-pass gate, and no full comparison
was launched. Temperature 1.0 also introduces sampling variation; one trial
cannot establish a reproducible gain or regression.

## Profiles and fixed bounds

| Profile | Nemotron change | Creation prompt |
| --- | --- | --- |
| `baseline` | Existing `enable_thinking: false` | Existing full AppSpec contract |
| `bounded-reasoning` | `reasoning_effort: low`, `reasoning_budget: 1024` | Existing full AppSpec contract |
| `contract-reasoning` | Same bounded reasoning | Existing contract plus a compact creation-only checklist |

The first-round experimental reasoning requests use documented NVIDIA
parameters. The 1,024-token budget is this trial's choice, not a publisher recommendation, and
shares the existing completion budget with final JSON. No redundant thinking
toggle is sent. The planned GLM control retained its existing low-effort request
and `clear_thinking: true`; it was not called because no candidate qualified.

The checklist emphasizes existing grammar, supported icons, component and
control bindings, requested features, capability declarations, page routing and
repair completeness. It has no benchmark IDs or fixture content, introduces no
templates, and does not alter output after generation. It applies only to
Nemotron creation messages; semantic edits and guidance keep their existing
prompts. Validation and strict scoring remain unchanged.

All profiles use nonstreaming requests, a 90-second generation
deadline, a 20-second guidance deadline, and at most three attempts per case.
Generation requests in the first two rounds use temperature 0 and omit `top_p`.
Guidance preserves its baseline request, which omits temperature and `top_p`.
The third-round candidate changes those values only on the authored creation
path; edits and sequences retain generation temperature 0 with `top_p` omitted.
Generation allows 8,000 tokens initially and 12,000 after recognized creation
truncation; guidance allows 2,048. Global request starts remain at least four
seconds apart, with one active request per model. Screening runs sequentially
with concurrency 1; the full phase uses concurrency 2.

The live evaluator must verify public free-endpoint advertising and authenticated
model access before dispatch. Auth, quota, nonzero reported cost and existing
HTTP 202 guards stop or block the evaluator. No automatic resume, credit purchase
or paid fallback is part of the protocol. Numeric quota, reset times and actual
cost remain unknown unless the provider explicitly reports them.

## Registered selection

Round one screened eight creation cases in three fresh checkpoints, in order:
`baseline`, `bounded-reasoning`, `contract-reasoning`.
Round two screened `contract-only`, then `efficient-creation`, in fresh checkpoints
using the same cases and the first-round baseline reference.
The amended third round screened one `publisher-creation` profile against that
same baseline and those same cases.

- Notes fields and search/filter bindings
- Calendar category and calendar appearance
- Rich dashboard
- Multistep form
- Capacity signup
- Reminder name
- Focus clock

A candidate must complete all eight, pass at least seven, have no
availability-only failed case, and pass the reminder and focus regression
cases. Eventual passes must not regress against baseline. At least one of
eventual passes, first-attempt passes or total attempts must improve. Eligible
candidates are ordered by eventual passes, first-attempt passes, fewest attempts
and then lowest median operation time. No qualifying candidate means no full
phase.

At most one qualifying selected profile across all rounds receives a fresh
36-case run alongside GLM: 12 creations,
12 fixed-baseline edits, four guidance, four unsupported requests and four
sequences using each model's own accepted creation. The full run repeats the
eight screened creation cases and adds 28 other cases. It is therefore an
adaptive exploratory comparison, not an independent holdout evaluation. A
complete category result is necessary before discussing parity within these
checks; one trial cannot establish statistical reliability or a universal model
ranking.

## Evidence and interpretation

Before second-round live calls, workspace analysis found no issues and 350
focused evaluator/provider/generation tests passed. Offline construction
receipts preserve all 648 initial/repair request hashes across the 36 original
cases, three legacy profiles and Super, Ultra and GLM. The 16 earlier baseline
and GLM initial hashes for these eight creation cases also match. The sequence
receipt uses each declared fixture baseline, rather than an actual model-created
definition. These are offline request checks, not additional provider results.

Before third-round live calls, workspace analysis again found no issues,
formatting made zero changes, and 162 focused tests passed, including nine new
publisher-profile tests. Expanded offline receipts preserved all 1,872 request
hashes and 26 profile-metadata hashes across the five existing modes and all
supported model combinations. The complete creation-prompt helper remained
byte-identical to the second-round snapshot. These checks preserve earlier
profiles and scorer behavior while the new profile changes creation sampling.

Offline Dart replay also rescored all 30 accepted responses across the six
terminal checkpoints, reproduced their saved accepted
candidates exactly, and exited successfully for each checkpoint. The
[replay receipt](evidence/nemotron-tuning/2026-10-08/replay.json) binds those counts
to the raw checkpoint hashes. This CLI replays accepted responses; failed
attempts were not rescored by that replay.

Round-one evidence retains its plan, each terminal raw checkpoint and generated
summary, exact source snapshot, source-file manifest and recorded initial-request
hash receipts. Rounds two and three retain separate plans, source snapshots and
terminal results; earlier source and raw checkpoints are
not overwritten. A read-only standard-library audit independently
recomputes outcomes, first-attempt counts, attempts, category coverage, median and
p95 operation times, known/missing token
usage, selection and fingerprints. It also verifies every recorded source file
against its round's tar snapshot without extracting or executing its contents.
Separate checks verify scenario consistency, client pacing and absence of
per-model overlap. It refuses
running checkpoints and unresolved in-flight claims.

The final audit reconciled all **48 completed operations and 105 attempts**
across the six profiles and three rounds. There were 30 eventual passes and 18
scored failures, with no availability-only failed case. The single timeout was
the last efficient-creation capacity attempt. Usage was known for 104/105
attempts: **2,131,055 known total tokens**, including **119,065 known reasoning
tokens**; one timeout's usage and all costs remain unknown. Each round's 30-file
source snapshot passed. Cross-round changes were limited to four request-adaptation
files, then three, with the scorer, scenario definitions and checklist
declaration preserved. Every request lane was serial and client starts met the
four-second minimum.

Run the read-only bookkeeping and source-snapshot audit from the repository
root without credentials or provider calls:

```sh
python3 docs/evidence/nemotron-tuning/2026-10-08/audit.py
```

Operation time includes failed attempts, repairs and local validation and
excludes dispatch waiting. It is not isolated inference speed. Missing usage
and cost remain unknown. Provider work after a client timeout cannot be inferred
from local request timestamps.

The source receipts record commit `93f0291` plus each round's exact dirty source bytes,
including the pre-existing builder fix. Checking out that commit alone does not
reconstruct the evaluated code. Whole-checkout dirty-diff hashes can differ
because of documentation changes. Each round's source contract must remain
identical across its profiles and any full run; transport source may change
between the separately registered rounds. Scenario, scoring and other frozen
source files must remain unchanged across rounds. Snapshot verification does
not require the current checkout to retain the first round's transport files.

Synthetic saved-response checks and replay establish definition and patch
validation only. They do not establish Flutter rendering, authenticated
persistence, notification delivery, uploads, physical-device behavior or
production acceptance.
