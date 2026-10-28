# NVIDIA free-model evaluation: blocked evidence receipt

[Evaluation guide](../../../FREE_MODEL_EVALUATION.md) · [Primary report](checkpoint.json.md)

This preserves the NVIDIA Kimi K3, GLM 5.3 and DeepSeek V4.1 Flash run stopped
by HTTP 429. It is a **blocked, incomplete run**, not a completed 108-operation
comparison. The process drained to zero in-flight requests and exited with the
expected guard status 3. No resume was attempted after the rate-limit block;
numerical account quota and reset time remain unknown.

## Frozen identity and primary outcomes

- Checkpoint updated: `2026-10-08T10:22:38.092014Z`; status: `blocked`.
- Benchmark: `appnest-nemotron-v2`; 36 identical scenarios per model.
- Source commit: `7a4b402480fe6b16bc695d280e306a9722963b11`.
- Contract source SHA-256: `f647ad486340c43ddb4d2da5fbb6f4f143ec2b54cec04bc79a47bc3a182c6822`.
- Run fingerprint: `e7cd449878d1973a1e973cee86dcaa68dd2030325283fb0006b8c085121bb84a`.
- Checkpoint SHA-256: `9f83e60ae88fe28d3e30da0102deb4ea69dadcd973ae8bafb638ee34c9f3f771`.
- Execution: client concurrency 3, one active client invocation per model,
  global dispatch starts at least four seconds apart.
- Planned: 108 operations. Terminal: 80, comprising 42 passes and 38 failures.
  Separately, one operation is blocked and 27 are pending; none are skipped,
  in flight or indeterminate. Recorded attempts: 168.

All three primary artifacts and nine final offline diagnostic/helper files are
**exact byte copies** from `output/nvidia-free-model-eval/`. The
[SHA256SUMS](SHA256SUMS) manifest covers those 12 preserved files. This README
is a separate audit receipt. The source checkpoint did not change during
copying or offline diagnostics. Historical Nemotron serial and smoke evidence
was preserved independently.

## Independent read-only audit

The archival audit checked all 108 unique model/case pairs, the three-attempt
bound, every per-model and per-category count, first-attempt and eventual
passes, availability-only classification, cumulative token sums, median and
nearest-rank p95. Saved summary and checkpoint timestamps agree. The 36 scenario
definitions exactly match the historical NVIDIA Nemotron serial checkpoint.

All **28 frozen source-file hashes matched**. Recomputing the source contract
hash and run fingerprint from the frozen manifest also matched. All three
post-hoc diagnostic JSON files identify the same final checkpoint hash, status,
timestamp and run fingerprint, record matching source hashes, and state that
primary scores were unchanged and no provider calls were made.

A UTC timestamp sweep of all 168 attempts found **three peak active client
invocations**, no overlapping client requests within one model queue and a
minimum dispatch gap of **4.010608 seconds**. All client invocations had settled.
These are client scheduling observations. Timed-out remote work, eventual
provider completion, cancellation and cost remain unknown.

There were 49 attempts with numeric token usage, totaling 745,745 known tokens,
and 119 attempts with unknown usage. No attempt reported cost. Unknown usage
or cost is not zero. Of 38 failed operations, 36 were availability-only;
DeepSeek supplied no completion, so its output quality could not be scored.
No categorical creation or editing winner is supported by the incomplete
comparable response coverage.

## Publication source scope

The isolated publication excludes an unrelated pre-existing change to
`appnest_server/lib/src/modules/builder/builder.dart` that was present in the
scored working tree and recorded in its 28-file manifest. **27 of those 28
source files match the published checkout**. The benchmark, provider, scenarios
and validation code is unchanged. The earlier 28-file integrity checks above
describe the original scored snapshot at archival time, rather than asserting
that this narrower publication reproduces every source hash. Saved checkpoints,
diagnostics, helpers and checksums remain immutable.

Primary offline `--replay` below reads the archived accepted responses and
candidates; it needs neither credentials nor files under the working `output/`
directory. The stricter diagnostic helpers verify every original source hash
and can intentionally reject this publication. Restore the **original scored
source snapshot**, including its recorded `builder.dart`, before rerunning
those helpers. Copying the checkpoint alone does not satisfy that requirement.

### Fresh isolated-publication validation

The narrower publication checkout separately passed workspace
`dart --suppress-analytics analyze --fatal-infos` with no issues, formatting
checks on 16 authored Dart files with zero changes, the same 287 focused tests
listed below, and archived primary `--replay` for all 42 accepted results.
The initial sandboxed test invocation stopped on a build-hook telemetry/cache
permission error before running tests; the permitted rerun passed all 287.
These fresh publication checks made no live provider requests, did not alter
historical scores or artifacts, and establish no new runtime acceptance.

## Offline replay and implementation verification

Offline primary replay exited 0 and checked **all 42 accepted synthetic
results** without changing the checkpoint. From the repository root:

```sh
dart --suppress-analytics run scripts/nemotron_eval.dart --replay \
  --provider=nvidia \
  --models=moonshotai/kimi-k3,z-ai/glm-5.3,deepseek-ai/deepseek-v4.1-flash \
  --concurrency=3 \
  --output=docs/evidence/nvidia-free-models/2026-10-08/checkpoint.json
```

Separately, before live dispatch the final source passed **287 focused tests**
with this command from `appnest_server`:

```sh
dart --suppress-analytics test test/nemotron_*_test.dart test/nvidia_model_extension_test.dart test/provider_test.dart test/generation_requirements_test.dart test/generation_repair_bindings_test.dart test/generation_quality_test.dart
```

Workspace analysis from the repository root was clean:

```sh
dart --suppress-analytics analyze --fatal-infos
```

Formatting of eight touched authored Dart files made zero changes before live
dispatch. The frozen source-file hashes remained unchanged through the blocked
run. The three post-hoc diagnostic helpers each exited 0 and passed analysis
and formatting checks; their final Markdown/JSON pairs were then archived.

After restoring that original scored source in a separate disposable checkout,
the Kimi/GLM detailed helpers also need a working checkpoint copy. With no
existing working checkpoint, run from the repository root:

```sh
mkdir -p output/nvidia-free-model-eval
cp docs/evidence/nvidia-free-models/2026-10-08/checkpoint.json output/nvidia-free-model-eval/checkpoint.json
dart --packages=.dart_tool/package_config.json docs/evidence/nvidia-free-models/2026-10-08/offline_kimi_reminder_diagnostic.dart
dart --packages=.dart_tool/package_config.json docs/evidence/nvidia-free-models/2026-10-08/offline_glm_multistep_diagnostic.dart
```

The helpers write separate working diagnostic outputs. The compiler helper
accepts an explicit checkpoint and output prefix. Keep archived files immutable;
this is original-snapshot diagnostic reproduction, not a clean-publication
source-equivalence or live-provider claim.

To verify preserved bytes, from this evidence directory run:

```sh
shasum -a 256 -c SHA256SUMS
```

Publication whitespace checks preserve the original extra EOF blank line in
each detailed assertion Markdown report. The remaining staged files pass the
default check, and all files pass with only `blank-at-eof` disabled. The two
archived reports and their declared hashes remain unchanged.

This evidence establishes synthetic provider, schema/assertion, offline replay
and implementation-test behavior. It does not establish renderer execution,
authenticated asset upload or persistence, reminder delivery, publication,
physical-device behavior or production acceptance. The GLM upload-control and
Kimi reminder-optionality diagnoses remain separate from primary scores.
