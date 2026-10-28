# Nemotron creation pipeline pilot

This opt-in experiment tests changes to the creation pipeline while leaving the
configured application, strict AppSpec parser and historical benchmark assertions
unchanged. Results measure synthetic definition quality, provider usage and
total measured attempt time per operation. They do not establish Flutter rendering, authenticated
persistence, publication, device behavior or production readiness.

The [pilot protocol](evidence/nemotron-pipelines/2026-10-08/plan.json) was recorded
before provider calls. Three difficult existing creation cases, two fresh transfer
requests and one unsupported request are evaluated once under each pipeline.
Fresh efficient-creation Nemotron and GLM 5.3 controls use the same requests.
There is no independent repetition or statistical reliability claim.

## Experiments

| Pipeline | Change | Validation |
| --- | --- | --- |
| `scoped` | Shorter system instructions and conservative family selection in the instruction schema | Full original parser and request assertions |
| `plan` | Model emits a versioned semantic plan; server constructs IDs, action bindings, routes and capability declarations | Strict plan bounds, strict final AppSpec, original request assertions |
| `repair` | Initial full definition; eligible retries emit bounded changes to its rejected graph | Allowlisted paths/values, strict final AppSpec, original request assertions |
| `cascade` | Nemotron first; remaining original attempt slots use GLM | Unchanged full-definition scorer; actual serving model recorded per attempt |

All Nemotron variants use the previously measured `efficient-creation` transport
profile: low reasoning effort, temperature zero, no explicit reasoning budget.
The plan/repair grammars replace the generic complete-AppSpec checklist only when
their own response protocol is active. Edits and guidance retain existing behavior.

The scoped contract keeps every rich record component branch for record requests;
it does not guess individual component types from keywords. It can omit disjoint
utility/device families and narrows explicitly collection-free utility requests.
Ambiguous envelopes retain the complete contract. Family selection still depends
on recognized wording, so uncommon mixed utility synonyms remain a limitation
before any wider promotion.

The plan compiler never chooses a policy, grants privileges, invents fields,
workflow states, reminder conditions or operations. These remain explicit model
declarations. It builds wiring and derives capabilities from the resulting strict
graph. This is a combined model-and-compiler score, not raw Nemotron AppSpec output.

Bounded repairs allow at most 24 changes and 32 KiB per patch. Changes may set,
remove or append schema-allowed values; they cannot replace the entire definition
or its root record/action/view/rule arrays. Malformed initial JSON keeps full
generation. If a patch itself is malformed or invalid, its raw response is retained
and the next attempt falls back to full generation because there is no eligible
AppSpec repair base. Unsupported-only replies remain strict passthrough responses.

The cascade makes one provider call per evaluator attempt, with at most three
calls total per operation. Its first GLM call receives the original request and
diagnostic, without the Nemotron rejected graph. A subsequent GLM repair can use
the preceding GLM response. Persisted serving-model metadata determines this
behavior after checkpoint resume. Cascade trials run serially to preserve pacing
for the actual models. A cascade pass is not counted as a Nemotron-only pass.

## Bounds and evidence

Every generation retains the existing 90-second deadline and 8,000 completion
token limit; only recognized creation truncation permits 12,000 tokens on retry.
All retries count toward latency and known usage. Reported operation time sums attempt durations; queue/pacing intervals are excluded. Requests start at least four
seconds apart within each run; only the two independent control models overlap.
Credential, quota, HTTP 202 and nonzero reported-cost guards remain in place.
NVIDIA advertises free endpoints but does not report a numerical trial allowance
or verified token price through this interface; missing usage/cost stays unknown.

The [evidence directory](evidence/nemotron-pipelines/2026-10-08/) contains a frozen
source archive, hashes, catalog checks, checkpoints, raw and derived responses,
per-attempt serving models, replay checks and an independent bookkeeping audit.
The two transfer requests have dedicated tests that reject hidden features and
incomplete forms even when the definition passes ordinary structural validation.

## Reproduction

For an offline description, replace `--live` with `--describe`. An ignored
server-side NVIDIA key is required only for live requests.

```sh
CI=true dart run scripts/nemotron_eval.dart --live --provider=nvidia \
  --models=nvidia/nemotron-3-super-120b-a12b \
  --nemotron-profile=efficient-creation --creation-pipeline=scoped \
  --cases=create-rich-dashboard,create-multistep-form,create-capacity-signup,create-transfer-reading,create-transfer-team,unsupported-executable \
  --output=output/nemotron-pipelines/scoped.json
```

Select `plan`, `repair` or `cascade` for the other experiments. Cascade additionally
checks GLM availability/access and requires concurrency one. Omit
`--creation-pipeline` for unchanged model-only controls. `--replay` rederives
accepted pipeline candidates from the saved raw response and then runs the same
strict scorer, comparing the result with the saved candidate.

## Results

All planned trials completed. Every row uses the same six cases: five supported
app requests and one unsupported request. Every pipeline correctly rejected the
unsupported request. Passes below allow up to three attempts. Times include
successful and failed operations and all their attempts, excluding pacing waits.

| Pipeline | Passed / 6 | First attempt / 6 | API attempts | Median operation seconds | p95 seconds | Known total tokens | Missing usage attempts |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Nemotron efficient-creation control | 3 | 2 | 13 | 78.6 | 141.8 | 297,216 | 0 |
| Scoped contract | 1 | 1 | 16 | 143.6 | 187.6 | 347,218 | 0 |
| Compact plan and compiler | 2 | 2 | 14 | 47.7 | 55.5 | 117,764 | 0 |
| Bounded repairs | 3 | 1 | 16 | 84.6 | 190.5 | 268,227 | 1 |
| Nemotron then GLM fallback | 6 | 2 | 12 | 53.8 | 202.3 | 212,733 | 1 |
| GLM 5.3 control | 6 | 5 | 7 | 8.4 | 19.8 | 111,718 | 0 |

Shortening the initial supported-creation requests by 26.3–26.4% in bytes did not
help the scoped trial. It failed all five supported requests and spent many
completion tokens on reasoning before producing a complete response. These byte
reductions measure authored request bodies, not provider token savings.

The compact plan reduced initial request bytes by 68.3–68.6% and had a lower
observed median operation time, but passed fewer cases than the Nemotron control. Capacity signup
passed on its first attempt where the control failed. Dashboard, photo journal,
reading and team requests each failed all three attempts. An independent
[rejected-plan audit](evidence/nemotron-pipelines/2026-10-08/plan-failure-audit.json)
reproduced all 12 recorded errors from the unmodified raw responses. Five plans
put details components on ordinary pages, two supplied forbidden boolean
checklist values, and five violated other explicit plan constraints. This audit
found no compiler defect in these outputs; it records only the first error per
attempt, and the experimental plan grammar is narrower than full AppSpec.

Bounded repairs recovered the dashboard and team requests on their third attempts
but lost the photo-journal success from the control, leaving the same 3/6 overall
score. The photo journal retained a missing editable visible title through both
repairs. Capacity signup omitted reachable capacity controls and then exhausted
its final completion budget. Reading never reached patch mode: truncation and a
90-second timeout preceded a full definition with forbidden workflow values on a
boolean checklist. That timeout has unknown usage; the known token sum is
incomplete. The [repair audit](evidence/nemotron-pipelines/2026-10-08/repair-failure-audit.json)
reconstructed all five returned patches and verified all six repair bases. The
successful dashboard patch used all 24 allowed changes, while team needed one
control removal. Bounded patches did not guarantee a minimal change.

The cascade passed every case, using GLM for four operations after Nemotron
failed. It made six Nemotron calls and six GLM calls. Capacity signup needed the
last allowed GLM attempt after a 90-second timeout; this operation took 202.3
seconds of measured attempt time. Its timed-out usage is unknown. GLM alone also
passed every case, with fewer attempts and a much lower observed median in its
fresh control. A cascade pass measures both models and is not Nemotron parity.

For this pilot, direct GLM is the strongest choice for creation. None of the
Nemotron-only experiments exceeded its fresh control. The plan/compiler remains
a candidate for further work because it reduced request size and passed capacity
signup, but its narrower grammar introduced new rejection opportunities. These
are single trials on a deliberately difficult subset; model/provider variation
and the earlier concurrent controls prevent a general latency or reliability
claim. The configured application remains unchanged; these options are available
only through the explicit evaluation flag.

Validation passed 416 focused tests, strict workspace analysis and selected-source
format checks. [Offline replay](evidence/nemotron-pipelines/2026-10-08/replay.json)
rederived all 21 accepted results through the frozen compiler/parser and unchanged
request assertions. The [independent audit](evidence/nemotron-pipelines/2026-10-08/audit.json)
verified all 78 attempts, serving-model routing, run fingerprints, raw/derived
hashes, patch assemblies, pacing, concurrency, summaries, 35 unchanged frozen
source files and five unchanged pre-existing work files. Known usage totals
1,354,876 tokens across 76 attempts; two timeout attempts remain unknown. Cost
was unreported throughout. [Checksums](evidence/nemotron-pipelines/2026-10-08/SHA256SUMS)
cover the saved evidence. These checks establish synthetic definition acceptance,
not application runtime acceptance.
