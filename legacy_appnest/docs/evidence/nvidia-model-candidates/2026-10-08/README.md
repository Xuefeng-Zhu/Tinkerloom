# NVIDIA candidate evaluation receipt — 2026-10-08 UTC

[Comparison guide](../../../NVIDIA_MODEL_COMPARISON.md)

This archive preserves a completed response smoke and a **partially completed
full invocation**. GLM 5.3 Flash and the GLM 5.3 control each completed all 36
cases successfully. Gemma's full lane was stopped after 12 consecutive timeouts;
Laguna had already been excluded by the smoke gate because it returned no output.

## Preserved phases

| Phase | Results | Attempts and coverage |
| --- | --- | --- |
| Smoke | 9 passed, 3 availability-only failures | All 12 operations resolved; 21 completed attempts |
| Full invocation | 72 passed, 4 availability-only failures | 76 of 108 operations terminal; 96 completed attempts, one additional unfinished claim, 31 pending operations |

Smoke finished at `2026-10-08T14:24:37.495185Z`. GLM Flash, Gemma and GLM each
passed all three smoke cases; Flash needed five attempts, Gemma four and GLM
three. Laguna returned two timeouts and seven HTTP 503s over nine attempts.
Its output quality is unmeasured.

The raw full checkpoint was last saved at `2026-10-08T14:44:34.704263Z`.
GLM Flash passed 31/36 on the first attempt and 36/36 eventually over 41 attempts.
GLM passed 29/36 on the first attempt and 36/36 eventually over 43 attempts.
Both passed all 12 creations, 12 fixed edits, four guidance cases, four unsupported
requests and four creation-to-edit sequences.

The separate [operational stop receipt](operational-stop.json) records a stopping
decision added during the trial after Gemma remained unavailable. It was not part
of the original [smoke eligibility rule](plan.json). The evaluator's exact PID,
launch time, command and working directory were checked before SIGINT; process
exit was verified, and the tool session returned exit 130. No resume followed.
The raw full checkpoint deliberately retains `status: running` and one durable
`in_flight` marker for Gemma's first `create-calendar-category` attempt. That
request's remote outcome and cancellation remain unknown. The archived report's
raw status does not mean a local evaluator is still running.

## Integrity and verification

Checkpoint, summary and report files are exact byte copies from
`output/nvidia-free-models-2026-10-08-round2/`. The checkpoints were not rewritten
to mark the administrative stop. [SHA256SUMS](SHA256SUMS) covers the nine protocol,
gate, checkpoint, summary, report and stop files, plus the independent audit
helper and its JSON result. This README is a separate receipt.

The scored source was commit `93f0291683bbcdf299ffd6276b2e9e7ccdc78496` plus the
working-tree changes identified in the manifests, including the pre-existing
`builder.dart` edit. Both phases have the same 29 frozen source-file hashes,
Dart version and source contract hash. Whole-checkout dirty-diff receipts differ
because documentation changed between phases; those are not the frozen contract.
Restoring the clean commit alone does not recreate the evaluated source.

The standard-library [audit helper](audit.py) independently reconciled all model
and category counts, first-attempt passes, known/missing usage, cumulative attempt
durations, midpoint medians and nearest-rank p95. It verified the smoke gate,
operational stop receipt, source hashes, source/run fingerprints and all 36
scenario definitions against the earlier benchmark. See [audit.json](audit.json).

Timestamp checks found peaks of four overlapping client invocations in the smoke
and three in the full phase, no per-model overlap, and minimum dispatch gaps of
4.010267 and 4.012059 seconds respectively. Full timing checks use completed
attempts; the unfinished claim is reported separately. Client timing does not
establish provider-side concurrency, inference time or cancellation.

Known usage was 103,569 tokens from nine of 21 completed smoke attempts, and
1,233,504 tokens from 82 of 96 completed full attempts. Usage for the remaining
completed attempts and the unfinished claim is unknown. No cost was reported;
actual cost, numerical account quota and reset times remain unknown.

Before live dispatch, workspace analysis and formatting passed, and all 315
focused evaluator/provider/generation tests passed. Offline replay subsequently
validated all nine accepted smoke results and all 72 accepted full results.
These checks establish synthetic provider, definition and bookkeeping behavior;
they do not establish Flutter rendering, authenticated persistence, upload,
reminder, physical-device or production acceptance.

## Offline reproduction

From the repository root, replay the accepted results without credentials:

```sh
dart --suppress-analytics run scripts/nemotron_eval.dart --replay \
  --provider=nvidia \
  --models=z-ai/glm-5.3-flash,google/gemma-4-31b-it,poolside/laguna-xs-2.1,z-ai/glm-5.3 \
  --cases=create-notes-fields,edit-notes-fields,guidance-ambiguous-organize \
  --concurrency=4 \
  --output=docs/evidence/nvidia-model-candidates/2026-10-08/smoke.json

dart --suppress-analytics run scripts/nemotron_eval.dart --replay \
  --provider=nvidia \
  --models=z-ai/glm-5.3-flash,google/gemma-4-31b-it,z-ai/glm-5.3 \
  --concurrency=4 \
  --output=docs/evidence/nvidia-model-candidates/2026-10-08/full.json

python3 docs/evidence/nvidia-model-candidates/2026-10-08/audit.py
```

The audit requires the original source-file bytes and reports whether the current
checkout commit matches the recorded source commit; replay uses the archived
accepted responses and current validation code. After source changes,
restore the evaluated snapshot to reproduce the strict provenance audit. Preserve
the archived files; use a fresh output path for any new live trial.

From this evidence directory, verify the preserved artifact bytes with:

```sh
shasum -a 256 -c SHA256SUMS
```
