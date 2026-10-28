#!/usr/bin/env python3
"""Read-only, standard-library bookkeeping audit for the Nemotron tuning trial.

Defaults to evidence beside this script. Optional --archive and --root support
working output directories and another checkout. Refuses running/in-flight raw
checkpoints. Emits audit.json only after every check passes. No provider calls,
credentials, server startup, or content rescoring; use Dart --replay to rescore.
"""

import argparse
import collections
import datetime as dt
import hashlib
import io
import json
import math
import pathlib
import statistics
import subprocess
import sys
import tarfile


CATEGORIES = ("create", "edit", "guidance", "unsupported", "sequence")
SUPPORTED_PROFILES = {"baseline", "bounded-reasoning", "contract-reasoning", "contract-only", "efficient-creation", "publisher-creation"}
AVAILABILITY = {
    "http_error", "timeout", "transport_error", "quota", "quota_exhausted",
    "rate_limit", "unavailable", "interrupted", "provider_error", "auth_error",
    "configuration_error",
}
SCORABLE = {
    "received", "validation", "truncated", "completion_stopped", "content_missing",
    "output_json", "output_shape", "output_size", "guidance_completion",
}
MANIFEST_KEYS = (
    "benchmarkVersion", "provider", "nemotronProfile", "benchmarkLabel",
    "modelFamilies", "apiBase", "models", "scenarios", "source", "maxAttempts",
    "execution", "transportProfiles",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def same(actual, expected, label):
    require(actual == expected, f"Mismatch: {label}")


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) \
        and math.isfinite(value) and value >= 0 else None


def first(*values):
    return next((v for v in values if v is not None), None)


def ratio(n, d):
    return n / d if d else None


def category(row):
    return "sequence" if row.get("sequenceSourceId") is not None else row["operation"]


def timestamp(value):
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "Timestamp lacks timezone")
    return parsed


def usage(attempts):
    sums, known, missing = {}, collections.Counter(), 0
    keys = ("promptTokens", "completionTokens", "totalTokens", "reasoningTokens", "costReportedUsd")
    for attempt in attempts:
        value = attempt.get("usage") or {}
        details = first(value.get("completion_tokens_details"), value.get("completionTokensDetails")) or {}
        metrics = {
            "promptTokens": first(value.get("prompt_tokens"), value.get("promptTokens")),
            "completionTokens": first(value.get("completion_tokens"), value.get("completionTokens")),
            "totalTokens": first(value.get("total_tokens"), value.get("totalTokens")),
            "reasoningTokens": first(value.get("reasoning_tokens"), value.get("reasoningTokens"),
                                     details.get("reasoning_tokens"), details.get("reasoningTokens")),
            "costReportedUsd": value.get("cost"),
        }
        missing += all(number(metrics[k]) is None for k in keys if k != "costReportedUsd")
        for key, raw in metrics.items():
            valid = number(raw)
            if valid is not None:
                sums[key] = sums.get(key, 0) + valid
                known[key] += 1
    count = len(attempts)
    return {
        **{k: sums.get(k) for k in keys}, "knownAttempts": dict(known),
        "attemptCount": count, "missingUsageAttempts": missing,
        "complete": bool(count) and all(known[k] == count for k in keys[:3]),
        "reasoningComplete": bool(count) and known["reasoningTokens"] == count,
        "costComplete": bool(count) and known["costReportedUsd"] == count,
    }


def scored(row):
    return row["status"] == "passed" or any(
        a["kind"] not in AVAILABILITY and (a["kind"] in SCORABLE or a.get("success") is True)
        for a in row["attempts"])


def aggregate(rows, planned):
    completed = [r for r in rows if r["status"] in {"passed", "failed"}]
    checked = [r for r in completed if scored(r)]
    attempts = [a for r in rows for a in r["attempts"]]
    states = collections.Counter(r["status"] for r in rows)
    passed = states["passed"]
    first_pass = sum(bool(r["attempts"]) and r["attempts"][0].get("success") is True for r in checked)
    available = [a for a in attempts if a["kind"] in AVAILABILITY]
    latency = sorted(v for r in completed if (v := number(r.get("totalMs"))) is not None)
    return {
        "planned": planned, "attempted": sum(bool(r["attempts"]) for r in rows),
        "completed": len(completed), "passed": passed, "failed": len(completed) - passed,
        "correctnessCompleted": len(checked), "correctnessFailed": len(checked) - passed,
        "firstAttemptPassed": first_pass, "skipped": states["skipped"],
        "pending": states["pending"] + max(0, planned - len(rows)), "inFlight": states["in_flight"],
        "indeterminate": states["indeterminate"], "blocked": states["blocked"],
        "availabilityFailureAttempts": len(available),
        "availabilityFailureKinds": dict(collections.Counter(a["kind"] for a in available)),
        "availabilityOnlyFailures": sum(not scored(r) for r in completed),
        "attemptCount": len(attempts), "completionCoverage": ratio(len(completed), planned),
        "resolvedCoverage": ratio(len(completed) + states["skipped"], planned),
        "correctnessCoverage": ratio(len(checked), planned),
        "firstAttemptPassRateObserved": ratio(first_pass, len(checked)),
        "firstAttemptPassRatePlanned": ratio(first_pass, planned),
        "eventualPassRateObserved": ratio(passed, len(checked)),
        "eventualPassRatePlanned": ratio(passed, planned),
        "latencyMs": {
            "sampleCount": len(latency), "median": statistics.median(latency) if latency else None,
            "p95": latency[math.ceil(len(latency) * .95) - 1] if latency else None,
            "quantileMethod": "median midpoint; p95 nearest rank",
        }, "usage": usage(attempts),
    }


def timing(checkpoint):
    starts, events, per_model, deviations = [], [], collections.defaultdict(list), []
    for row in checkpoint["operations"]:
        for a in row["attempts"]:
            start, end = timestamp(a["dispatchedAt"]), timestamp(a["completedAt"])
            require(end >= start, "Attempt timestamp reversed")
            starts.append(start)
            events.extend(((start, 1), (end, -1)))
            per_model[row["model"]].append((start, end))
            deviations.append(abs((end - start).total_seconds() * 1000 - a["elapsedMs"]))
    active = peak = 0
    for _, change in sorted(events, key=lambda e: (e[0], e[1])):
        active += change
        peak = max(peak, active)
    require(active == 0, "Unbalanced request timing")
    for intervals in per_model.values():
        intervals.sort()
        require(all(b[0] >= a[1] for a, b in zip(intervals, intervals[1:])), "Per-model request overlap")
    starts.sort()
    minimum = min(((b - a).total_seconds() * 1000 for a, b in zip(starts, starts[1:])), default=None)
    execution = checkpoint["execution"]
    require(peak <= execution["concurrency"], "Client request concurrency exceeded manifest")
    require(minimum is None or minimum >= execution["requestIntervalMs"], "Global request spacing below manifest")
    observed = checkpoint.get("executionObserved")
    if observed is not None:
        same(observed["requestsDispatchedThisInvocation"], len(starts), "recorded dispatch count")
        same(observed["peakConcurrentRequestsThisInvocation"], peak, "recorded client concurrency peak")
    require(not starts or timestamp(checkpoint["createdAt"]) <= starts[0], "Dispatch predates checkpoint")
    last = max((e[0] for e in events), default=None)
    require(last is None or last <= timestamp(checkpoint["updatedAt"]), "Completion follows checkpoint timestamp")
    return {
        "attemptsWithTimestamps": len(starts), "clientPeakConcurrent": peak,
        "perModelOverlapCount": 0, "minimumGlobalStartGapMs": minimum,
        "maxTimestampVersusElapsedDifferenceMs": max(deviations, default=None),
        "firstDispatchAt": starts[0].isoformat() if starts else None,
        "lastCompletionAt": last.isoformat() if last else None,
        "recordedExecutionObserved": observed,
        "remoteWorkAfterClientTimeoutKnown": False,
    }


def audit_checkpoint(checkpoint, summary, label):
    require(checkpoint["status"] in {"completed", "blocked", "incomplete"}, f"{label} is not terminal")
    models, scenarios, rows = checkpoint["models"], checkpoint["scenarios"], checkpoint["operations"]
    same(len(models), len(set(models)), f"{label} distinct models")
    same(len(scenarios), len({s["id"] for s in scenarios}), f"{label} distinct cases")
    identity = lambda r: (r["model"], r["case"], r["operation"], r.get("sequenceSourceId"))
    expected = [(m, s["id"], s["operation"], s.get("sequenceSourceId")) for s in scenarios for m in models]
    same(list(map(identity, rows)), expected, f"{label} operation coverage and order")
    for row in rows:
        require(row["status"] in {"passed", "failed", "skipped", "pending", "blocked", "indeterminate"}, f"{label} unresolved claim")
        require("inFlightAttempt" not in row, f"{label} unresolved in-flight marker")
        attempts = row["attempts"]
        require(len(attempts) <= checkpoint["maxAttempts"], "Attempt cap exceeded")
        same([a["number"] for a in attempts], list(range(1, len(attempts) + 1)), "Attempt numbering")
        same(row["totalMs"], sum(a["elapsedMs"] for a in attempts), "Operation elapsed sum")
        require(not any(a.get("success") is True for a in attempts[:-1]), "Dispatch after success")
        if row["status"] == "passed":
            require(attempts and attempts[-1].get("success") is True, "Pass lacks successful final attempt")
    if checkpoint["status"] == "completed":
        require(all(r["status"] in {"passed", "failed", "skipped"} for r in rows), "Completed checkpoint has pending work")
    manifest = {k: checkpoint[k] for k in MANIFEST_KEYS}
    source = checkpoint["source"]
    manifest["source"] = {k: source[k] for k in ("commit", "contractSourceSha256")}
    same(digest(compact(manifest)), checkpoint["runFingerprint"], f"{label} run fingerprint")
    same(digest(compact({"files": source["files"], "dartVersion": source["dartVersion"]})),
         source["contractSourceSha256"], f"{label} source manifest hash")
    planned = {c: sum(category(s) == c for s in scenarios) for c in CATEGORIES}
    same(summary["plannedCategories"], planned, f"{label} planned categories")
    same(summary["plannedPerModel"], len(scenarios), f"{label} planned cases")
    for k in MANIFEST_KEYS + ("status", "createdAt", "updatedAt", "runFingerprint", "catalog", "executionObserved"):
        if k in summary and k != "models":
            same(summary[k], checkpoint.get(k), f"{label} summary {k}")
    same(list(summary["models"]), models, f"{label} summary models")
    independent = {}
    for model in models:
        model_rows = [r for r in rows if r["model"] == model]
        independent[model] = {
            **aggregate(model_rows, len(scenarios)),
            "categories": {c: aggregate([r for r in model_rows if category(r) == c], planned[c]) for c in CATEGORIES},
        }
        same(independent[model], summary["models"][model], f"{label} independently recomputed summary {model}")
    return {"status": checkpoint["status"], "models": independent, "timing": timing(checkpoint),
            "plannedCategories": planned, "runFingerprintVerified": checkpoint["runFingerprint"]}


def verify_source(root, source, archive, read, read_bytes):
    files = source["files"]
    require(bool(files), "Empty frozen source manifest")
    same(read(archive / "source-files.json"), files, "source snapshot hash manifest")
    explicit = {"scripts/nemotron_eval.dart", "pubspec.yaml", "pubspec.lock", "appnest_server/pubspec.yaml", "packages/appnest_spec/pubspec.yaml"}
    prefixes = ("appnest_server/lib/src/modules/builder/", "appnest_server/lib/src/evaluation/", "packages/appnest_spec/lib/")
    tar_raw = read_bytes(archive / "source.tar.gz")
    snapshot = {}
    with tarfile.open(fileobj=io.BytesIO(tar_raw), mode="r:gz") as tar:
        for member in tar.getmembers():
            name = member.name
            require(member.isfile() and not member.issym() and not member.islnk(), "Snapshot has a nonregular source entry")
            require(name not in snapshot and name in files, "Snapshot has duplicate or unexpected source path")
            require(name in explicit or name.startswith(prefixes) and name.endswith(".dart"), "Unexpected source path")
            require(not pathlib.PurePosixPath(name).is_absolute() and ".." not in pathlib.PurePosixPath(name).parts,
                    "Snapshot source path escapes root")
            require(0 <= member.size <= 32 * 1024 * 1024, "Snapshot source file exceeds limit")
            data = tar.extractfile(member).read()
            same(digest(data), files[name], f"snapshot source bytes {name}")
            snapshot[name] = data
    same(set(snapshot), set(files), "exact snapshot source file set")
    prompt = snapshot["appnest_server/lib/src/modules/builder/nemotron_prompt.dart"]
    declaration_start = prompt.index(b"const nemotronCreationChecklist =")
    declaration_end = prompt.index(b";\n", declaration_start) + 1
    checklist = prompt[declaration_start:declaration_end]
    current_matches = sum((root / name).is_file() and digest((root / name).read_bytes()) == expected
                          for name, expected in files.items())
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
    return {
        "matchedSnapshotFiles": len(files), "sourceTarSha256": digest(tar_raw),
        "recordedCommit": source["commit"], "currentCommit": head,
        "headMatchesRecordedCommit": head == source["commit"],
        "contractSourceSha256": source["contractSourceSha256"],
        "creationChecklistDeclarationSha256": digest(checklist),
        "creationChecklistDeclarationBytes": len(checklist),
        "checklistDigestScope": "From const nemotronCreationChecklist through its final semicolon; excludes comments and trailing newline.",
        "currentFilesMatchingSnapshot": current_matches, "currentSourceBytesMatch": current_matches == len(files),
        "limit": "Snapshot bytes, including dirty source, are authoritative. Current source may differ between rounds; commit alone does not recreate the snapshot.",
    }


def selection(plan, checkpoints, audits, baseline):
    target = plan["targetModel"]
    gate = plan["candidateGate"]
    candidates = []
    for profile in plan["screeningProfiles"]:
        checkpoint, result = checkpoints[profile], audits[profile]["models"][target]
        same(checkpoint["models"], [target], f"{profile} screening model")
        same(checkpoint["nemotronProfile"], profile, f"{profile} profile")
        same([s["id"] for s in checkpoint["scenarios"]], plan["screeningCases"], f"{profile} screen cases")
        rows = {r["case"]: r for r in checkpoint["operations"]}
        improvements = {
            "eventualPasses": result["passed"] > baseline["passed"],
            "firstAttemptPasses": result["firstAttemptPassed"] > baseline["firstAttemptPassed"],
            "fewerAttempts": result["attemptCount"] < baseline["attemptCount"],
        }
        checks = {
            "complete": checkpoint["status"] == "completed" and result["completed"] == gate["plannedCases"],
            "minimumPasses": result["passed"] >= gate["minEventualPasses"],
            "availabilityFailuresWithinGate": result["availabilityOnlyFailures"] <= gate["availabilityOnlyFailuresAllowed"],
            "regressionCasesPass": all(rows[c]["status"] == "passed" for c in gate["regressionCasesMustPass"]),
            "improvedBaseline": any(improvements[k] for k in gate["mustImproveBaselineOnAtLeastOne"]),
            "eventualNonregression": not gate["eventualPassesMustNotRegressBaseline"] or result["passed"] >= baseline["passed"],
        }
        candidates.append({"profile": profile, "eligible": profile != "baseline" and all(checks.values()),
                           "checks": checks, "improvements": improvements,
                           "passed": result["passed"], "firstAttemptPassed": result["firstAttemptPassed"],
                           "attemptCount": result["attemptCount"], "medianMs": result["latencyMs"]["median"]})
    eligible = sorted((c for c in candidates if c["eligible"]),
                      key=lambda c: (-c["passed"], -c["firstAttemptPassed"], c["attemptCount"], c["medianMs"]))
    return {"candidates": candidates, "selectedProfile": eligible[0]["profile"] if eligible else None}


def verify_profile(checkpoint, plan, label):
    profile_id = checkpoint["nemotronProfile"]
    profile = checkpoint["transportProfiles"][plan["targetModel"]]
    off = {"stream": False, "chat_template_kwargs": {"enable_thinking": False}}
    if profile_id in {"baseline", "contract-only", "efficient-creation", "publisher-creation"}:
        same(profile["requestOverrides"], off, f"{label} thinking-off transport")
    elif profile_id in {"bounded-reasoning", "contract-reasoning"}:
        same(profile["requestOverrides"], {"stream": False, "reasoning_effort": "low", "reasoning_budget": plan["limits"]["reasoningTokens"]},
             f"{label} bounded reasoning transport")
    if profile_id in {"contract-only", "efficient-creation", "publisher-creation"}:
        creation = off if profile_id == "contract-only" else {"stream": False, "reasoning_effort": "low"}
        if profile_id == "publisher-creation":
            creation = {**creation, "temperature": 1.0, "top_p": .95}
        same(profile["creationRequestOverrides"], creation, f"{label} creation transport")
        same(profile["operationOverrides"], {"create": creation, "unsupported": creation,
                                             "edit": off, "sequence": off, "guidance": off},
             f"{label} creation-only reasoning and baseline edit/guidance")
    same(profile.get("promptContract"), "nemotron-creation-checklist-v1"
         if profile_id in {"contract-reasoning", "contract-only", "efficient-creation", "publisher-creation"} else None,
         f"{label} creation contract identity")


def audit_round(archive, root, read, read_bytes):
    plan = read(archive / "plan.json")
    profiles = plan["screeningProfiles"]
    require(profiles and len(profiles) == len(set(profiles)) and set(profiles) <= SUPPORTED_PROFILES,
            "Invalid registered profiles")
    checkpoints, audits = {}, {}
    for label in profiles:
        checkpoint = read(archive / f"{label}.json")
        checkpoints[label] = checkpoint
        audits[label] = audit_checkpoint(checkpoint, read(archive / f"{label}.json.summary.json"), label)
    reference = checkpoints[profiles[0]]
    if "baseline" in checkpoints:
        baseline_checkpoint = checkpoints["baseline"]
        baseline_audit = audits["baseline"]
        baseline_receipt = {"reusedFromEarlierRound": False}
    else:
        baseline_reference = plan.get("archiveBaselineCheckpoint", plan.get("baselineCheckpoint"))
        require(isinstance(baseline_reference, str), "Missing archive baseline reference")
        baseline_path = (archive / baseline_reference).resolve()
        require(baseline_path.is_relative_to(root) and baseline_path.name == "baseline.json", "Unsafe baseline reference")
        baseline_checkpoint = read(baseline_path)
        baseline_audit = audit_checkpoint(baseline_checkpoint, read(pathlib.Path(str(baseline_path) + ".summary.json")), "reused baseline")
        require(timestamp(baseline_checkpoint["updatedAt"]) <= timestamp(plan["recordedAt"]), "Reused baseline does not predate adaptive plan")
        baseline_receipt = {"reusedFromEarlierRound": True, "path": baseline_reference,
                            "runFingerprint": baseline_checkpoint["runFingerprint"],
                            "sourceContractSha256": baseline_checkpoint["source"]["contractSourceSha256"]}
    baseline = baseline_audit["models"][plan["targetModel"]]
    require(timestamp(plan["recordedAt"]) <= timestamp(reference["createdAt"]), "Plan recorded after round began")
    for before, after in zip(profiles, profiles[1:]):
        require(timestamp(checkpoints[before]["updatedAt"]) <= timestamp(checkpoints[after]["createdAt"]), "Screening invocations overlap")
    gate = selection(plan, checkpoints, audits, baseline)
    historical_comparison = None
    if (archive / "full.json").exists():
        full = read(archive / "full.json")
        require(gate["selectedProfile"] is not None, "Full phase has no eligible selected profile")
        same(full["nemotronProfile"], gate["selectedProfile"], "full selected profile")
        same(full["models"], [plan["targetModel"], plan["controlModel"]], "full model IDs and order")
        same(len(full["scenarios"]), 36, "full case coverage")
        same(full["execution"]["concurrency"], 2, "registered full concurrency")
        require(timestamp(checkpoints[profiles[-1]]["updatedAt"]) <= timestamp(full["createdAt"]), "Full phase predates screening completion")
        checkpoints["full"] = full
        audits["full"] = audit_checkpoint(full, read(archive / "full.json.summary.json"), "full")
        full_cases = {s["id"]: s for s in full["scenarios"]}
        same([full_cases[s["id"]] for s in baseline_checkpoint["scenarios"]], baseline_checkpoint["scenarios"], "screen/full scenario bytes")
        historical_path = root / "docs/evidence/nvidia-free-models/2026-10-08/checkpoint.json"
        historical_bytes = read_bytes(historical_path)
        historical = json.loads(historical_bytes)
        same(full["scenarios"], historical["scenarios"], "all 36 original scenario definitions and order")
        same(full["transportProfiles"][plan["controlModel"]], historical["transportProfiles"][plan["controlModel"]], "unchanged GLM control profile")
        historical_comparison = {"sha256": digest(historical_bytes), "matchedCases": 36, "glmControlProfileUnchanged": True}
    for label, checkpoint in checkpoints.items():
        for k in ("commit", "contractSourceSha256", "files", "dartVersion"):
            same(checkpoint["source"][k], reference["source"][k], f"{label} within-round source {k}")
        same(checkpoint["maxAttempts"], plan["limits"]["maxAttemptsPerCase"], f"{label} attempt limit")
        same(checkpoint["execution"]["requestIntervalMs"], plan["limits"]["globalRequestStartIntervalSeconds"] * 1000, f"{label} pacing limit")
        if label != "full":
            same(checkpoint["scenarios"], baseline_checkpoint["scenarios"], f"{label} original screening scenarios")
            same(checkpoint["execution"]["concurrency"], 1, f"{label} serial screening")
        verify_profile(checkpoint, plan, label)
        cap = plan["limits"]["fullMaxDispatches" if label == "full" else "screeningMaxDispatchesPerProfile"]
        require(sum(len(r["attempts"]) for r in checkpoint["operations"]) <= cap, f"{label} request cap")
        for profile in checkpoint["transportProfiles"].values():
            same(profile["generationDeadlineSeconds"], plan["limits"]["generationSeconds"], "generation deadline")
            same(profile["guidanceDeadlineSeconds"], plan["limits"]["guidanceSeconds"], "guidance deadline")
            same(profile["generationMaxTokens"], {"initial": plan["limits"]["initialGenerationTokens"], "recognizedCreationTruncation": plan["limits"]["recognizedTruncationTokens"]}, "generation token limits")
    source = verify_source(root, reference["source"], archive, read, read_bytes)
    requests = read(archive / "request-hashes.json")
    for model in (plan["targetModel"], plan["controlModel"]):
        same(set(requests[model]), set(plan["screeningCases"]), "baseline/GLM eight initial request hash cases")
        require(all(isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v)
                    for v in requests[model].values()), "Invalid request SHA256 receipt")
    legacy = None
    before_path, after_path = (archive / "legacy-request-hashes-before.json",
                               archive / "legacy-request-hashes-after.json")
    if before_path.exists() or after_path.exists():
        before, after = read(before_path), read(after_path)
        same(before, after, "all recorded legacy initial/repair request hashes")
        historical = read(root / "docs/evidence/nvidia-free-models/2026-10-08/checkpoint.json")
        metadata_before_path = pathlib.Path(str(before_path) + ".profiles.json")
        metadata_after_path = pathlib.Path(str(after_path) + ".profiles.json")
        metadata = None
        if metadata_before_path.exists() or metadata_after_path.exists():
            metadata_before, metadata_after = read(metadata_before_path), read(metadata_after_path)
            same(metadata_before, metadata_after, "all recorded legacy profile metadata hashes")
            baseline_models = (
                "nvidia/nemotron-3.5-lightning-30b-a3b", "nvidia/nemotron-3-super-120b-a12b",
                "nvidia/nemotron-3-ultra-550b-a55b", "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
                "moonshotai/kimi-k3", "z-ai/glm-5.3", "deepseek-ai/deepseek-v4.1-flash",
                "z-ai/glm-5.3-flash", "google/gemma-4-31b-it", "poolside/laguna-xs-2.1",
            )
            controls = ("nvidia/nemotron-3-super-120b-a12b", "nvidia/nemotron-3-ultra-550b-a55b",
                        "z-ai/glm-5.3", "z-ai/glm-5.3-flash")
            configurations = {f"baseline/{m}" for m in baseline_models} | {
                f"{p}/{m}" for p in ("bounded-reasoning", "contract-reasoning", "contract-only", "efficient-creation")
                for m in controls}
            same(set(metadata_before), configurations, "26 legacy profile/model metadata identities")
            require(all(isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v)
                        for v in metadata_before.values()), "Invalid profile metadata SHA256 receipt")
            metadata = {"matchedRecordedMetadataHashes": len(metadata_before), "models": len(baseline_models),
                        "profileModelCombinations": len(configurations)}
        else:
            configurations = {
                f"{p}/{m}" for p in ("baseline", "bounded-reasoning", "contract-reasoning")
                for m in ("nvidia/nemotron-3-super-120b-a12b", "nvidia/nemotron-3-ultra-550b-a55b", plan["controlModel"])}
        expected = {
            f"{configuration}/{s['id']}/{stage}" for configuration in configurations
            for s in historical["scenarios"] for stage in ("initial", "repair")
        }
        same(set(before), expected, "legacy initial/repair request receipt identities")
        require(all(isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v)
                    for v in before.values()), "Invalid legacy request SHA256 receipt")
        for model, cases in requests.items():
            for case, value in cases.items():
                same(before[f"baseline/{model}/{case}/initial"], value, "initial request/legacy receipt consistency")
        legacy = {"matchedRecordedRequestHashes": len(before), "cases": len(historical["scenarios"]),
                  "profileModelCombinations": len(configurations), "profileMetadata": metadata, "initialAndRepair": True,
                  "limit": "Recorded request hash equality only; this Python helper does not reconstruct Dart payloads."}
    result = {
        "source": source, "baselineReference": baseline_receipt, "legacyRequestReceipts": legacy,
        "screeningSelection": gate, "phases": audits, "historicalScenarioComparison": historical_comparison,
        "selectionExposure": {"screenedCases": len(baseline_checkpoint["scenarios"]),
                              "additionalFullCases": 36 - len(baseline_checkpoint["scenarios"]) if "full" in checkpoints else None,
                              "fullIsIndependentOfSelection": False if "full" in checkpoints else None},
        "wholeCheckoutDirtyDiffSnapshots": {k: c["source"]["dirtyTrackedSha256"] for k, c in checkpoints.items()},
        "createdAt": reference["createdAt"], "updatedAt": checkpoints[list(checkpoints)[-1]]["updatedAt"],
    }
    return result, reference["source"]["files"], requests, plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent)
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[4])
    args = parser.parse_args()
    archive, root = args.archive.resolve(), args.root.resolve()
    raw = {}

    def read_bytes(path):
        path = path.resolve()
        require(path.is_relative_to(root), "Audit input leaves repository")
        raw[str(path.relative_to(root))] = path.read_bytes()
        return raw[str(path.relative_to(root))]

    def read(path):
        return json.loads(read_bytes(path))

    directories = [archive] if (archive / "plan.json").exists() else sorted(
        p for p in archive.iterdir() if p.is_dir() and (p / "plan.json").exists())
    require(bool(directories), "No archived round plans found")
    rounds, sources, requests, plans = {}, {}, {}, {}
    for directory in directories:
        name = directory.name
        rounds[name], sources[name], requests[name], plans[name] = audit_round(directory, root, read, read_bytes)
    full_count = sum("full" in r["phases"] for r in rounds.values())
    require(full_count <= 1, "More than one full benchmark across this task")
    all_rows = [row for directory in directories for profile in rounds[directory.name]["phases"]
                for row in read(directory / f"{profile}.json")["operations"]]
    global_counts = aggregate(all_rows, len(all_rows))
    totals = {key: global_counts[key] for key in (
        "planned", "completed", "passed", "failed", "firstAttemptPassed", "attemptCount",
        "availabilityFailureAttempts", "availabilityOnlyFailures", "usage")}
    trial_timing = timing({
        "operations": all_rows, "execution": {"concurrency": 2 if full_count else 1, "requestIntervalMs": 4000},
        "createdAt": min((r["createdAt"] for r in rounds.values()), key=timestamp),
        "updatedAt": max((r["updatedAt"] for r in rounds.values()), key=timestamp),
    })
    replay = None
    if (archive / "replay.json").exists():
        receipt = read(archive / "replay.json")
        same(receipt["providerCalls"], 0, "replay recorded provider call count")
        expected_replays = {f"{name}/{profile}.json" for name, r in rounds.items() for profile in r["phases"]}
        same({r["path"] for r in receipt["checkpoints"]}, expected_replays, "replay receipt checkpoint coverage")
        accepted = 0
        for row in receipt["checkpoints"]:
            path = (archive / row["path"]).resolve()
            require(path.is_relative_to(archive), "Replay checkpoint path leaves archive")
            checkpoint_raw = read_bytes(path)
            checkpoint = json.loads(checkpoint_raw)
            same(digest(checkpoint_raw), row["sha256"], "replay checkpoint bytes")
            count = sum(r["status"] == "passed" for r in checkpoint["operations"])
            same(row["acceptedResponsesReplayed"], count, "replay accepted response count")
            same(row["exitCode"], 0, "recorded offline replay exit code")
            accepted += count
        replay = {"recordedAcceptedResponsesReplayed": accepted, "checkpoints": len(receipt["checkpoints"]),
                  "scope": receipt["scoringScope"],
                  "limit": "Binds operator-recorded Dart replay receipt to raw checkpoint bytes/counts; Python does not execute Dart or independently rescore content."}
    cross_round = []
    mutable = {"appnest_server/lib/src/evaluation/nvidia_model_profiles.dart", "appnest_server/lib/src/modules/builder/provider.dart",
               "appnest_server/lib/src/modules/builder/nemotron_prompt.dart", "scripts/nemotron_eval.dart"}
    for before, after in zip(list(rounds), list(rounds)[1:]):
        require(timestamp(rounds[before]["updatedAt"]) <= timestamp(plans[after]["recordedAt"]), "Adaptive round plan predates prior round completion")
        same(plans[before]["screeningCases"], plans[after]["screeningCases"], "cross-round scenario IDs")
        same(plans[before]["candidateGate"], plans[after]["candidateGate"], "unchanged adaptive selection gate")
        same(set(sources[before]), set(sources[after]), "cross-round source file sets")
        changed = [name for name in sources[before] if sources[before][name] != sources[after][name]]
        require(set(changed) <= mutable, "Scorer/scenarios/other frozen source changed across rounds")
        if plans[after].get("round", 1) >= 3:
            same(sources[before]["appnest_server/lib/src/modules/builder/nemotron_prompt.dart"],
                 sources[after]["appnest_server/lib/src/modules/builder/nemotron_prompt.dart"],
                 "third-round whole prompt helper remains unchanged")
        same(rounds[before]["source"]["creationChecklistDeclarationSha256"],
             rounds[after]["source"]["creationChecklistDeclarationSha256"], "unchanged creation checklist declaration bytes")
        same(requests[before], requests[after], "recorded baseline and GLM initial request body hashes")
        cross_round.append({"before": before, "after": after, "changedTransportFiles": changed,
                            "unchangedScorerAndScenarioFiles": len(sources[before]) - len(changed),
                            "creationChecklistDeclarationUnchanged": True,
                            "recordedInitialRequestHashesEqual": True,
                            "requestHashLimit": "Compares recorded SHA256 receipts; standard-library auditor does not reconstruct Dart request bodies."})
    result = {
        "schemaVersion": 2, "auditPassed": True, "networkCallsMade": False,
        "auditHelperSha256": digest(pathlib.Path(__file__).read_bytes()),
        "inputsSha256": {k: digest(v) for k, v in raw.items()}, "rounds": rounds,
        "crossRoundComparisons": cross_round, "fullBenchmarkCount": full_count, "offlineReplayReceipt": replay,
        "totals": totals, "trialTiming": trial_timing,
        "allArchivedOperationsCompleted": global_counts["completed"] == global_counts["planned"],
        "selectedProfileByRound": {name: r["screeningSelection"]["selectedProfile"] for name, r in rounds.items()},
        "limitations": [
            "Independent bookkeeping and snapshot provenance only; model content needs offline Dart replay.",
            "Adaptive exploratory tuning across eight selected creation cases; 28 full cases, if run, are additional to screening.",
            "Reused baseline across source snapshots and time windows is not a simultaneous randomized causal control.",
            "Task times sum attempts and local validation, exclude dispatch waiting, and do not isolate provider inference speed.",
            "No statistical or universal parity claim, or app rendering, persistence, device, deployment, pricing or quota verification.",
            "Remote work after client timeouts is unknown; missing usage and cost remain unknown.",
            "Exact source snapshot bytes are verified independently of current checkout and whole-checkout dirty diffs.",
        ],
    }
    output = archive / "audit.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Independent audit passed: {len(rounds)} archived round(s), {full_count} full benchmark(s); wrote {output}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print(f"Audit failed; no new audit.json written: {error}", file=sys.stderr)
        raise SystemExit(1)
