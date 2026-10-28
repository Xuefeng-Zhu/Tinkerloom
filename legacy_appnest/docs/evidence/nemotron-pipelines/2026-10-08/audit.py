#!/usr/bin/env python3
"""Independent, read-only bookkeeping audit of the creation-pipeline pilot.

Standard library only; no credentials, inference, Dart execution, or servers.
Prints JSON to stdout. Missing/running files are reported as partial by default;
--require-complete requires the five planned checkpoints to be completed.
Strict semantic acceptance and deterministic plan compilation must additionally
be replayed by the frozen Dart evaluator. This script never upgrades a score.
"""

import argparse
import collections
import datetime as dt
import hashlib
import io
import json
import math
import pathlib
import re
import statistics
import sys
import tarfile


RUN_FILES = {
    "controls": "controls.json",
    "scoped": "scoped.json",
    "plan": "plan-pipeline.json",
    "repair": "repair.json",
    "cascade": "cascade.json",
}
MANIFEST_KEYS = (
    "benchmarkVersion", "provider", "nemotronProfile", "creationPipeline",
    "benchmarkLabel", "modelFamilies", "apiBase", "models", "scenarios",
    "source", "maxAttempts", "execution", "transportProfiles",
)
AVAILABILITY = {
    "http_error", "timeout", "transport_error", "quota", "quota_exhausted",
    "rate_limit", "unavailable", "interrupted", "provider_error", "auth_error",
    "configuration_error",
}
SCORABLE = {
    "received", "validation", "truncated", "completion_stopped",
    "content_missing", "output_json", "output_shape", "output_size",
    "guidance_completion", "pipeline_validation",
}
STATES = {
    "passed", "failed", "skipped", "pending", "blocked", "in_flight",
    "indeterminate",
}
UNRELATED_RECEIPT = pathlib.Path(
    "/private/tmp/appnest-pipeline-unrelated-hashes.json"
)
# Retain the pre-trial receipt for reproducibility after temporary-file cleanup.
UNRELATED_HASHES = {
    "appnest_flutter/lib/features/builder/builder_screen.dart":
        "540045c51fce22926d1c87a5767bea0490db18c2b1df4b9626da04244236e3e6",
    "appnest_flutter/test/builder_creation_test.dart":
        "7fde1900979d14d5006253e44658e617733445a315111b54ac1f418d3c9a0a8e",
    "appnest_server/lib/src/modules/builder/builder.dart":
        "520ba357c52158fb4279e8ece468ec06b12470a588a9371b6d504a789c60de4f",
    "appnest_server/test/integration/generation_context_test.dart":
        "c335886bab6e6cfd16f0db58cd9ba1cb1dbcc634bbcf056def3ef85be232dff9",
    "docs/CREATION_FLOW.md":
        "281515c9d19bd3b1735036e173b41c8ed74af0fb1bb4e2807856820a6a7602c4",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def same(actual, expected, label):
    require(actual == expected, "Mismatch: " + label)


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def timestamp(value):
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "Timestamp lacks timezone")
    return parsed


def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) \
        and math.isfinite(value) and value >= 0 else None


def sha(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def usage(attempts):
    sums, known, missing = {}, collections.Counter(), 0
    for attempt in attempts:
        value = attempt.get("usage") or {}
        require(isinstance(value, dict), "Usage is not an object")
        details = value.get("completion_tokens_details") or \
            value.get("completionTokensDetails") or {}
        metrics = {
            "promptTokens": value.get("prompt_tokens", value.get("promptTokens")),
            "completionTokens": value.get("completion_tokens", value.get("completionTokens")),
            "totalTokens": value.get("total_tokens", value.get("totalTokens")),
            "reasoningTokens": value.get("reasoning_tokens", value.get(
                "reasoningTokens", details.get("reasoning_tokens", details.get("reasoningTokens")))),
            "costReportedUsd": value.get("cost"),
        }
        missing += all(number(metrics[key]) is None for key in (
            "promptTokens", "completionTokens", "totalTokens", "reasoningTokens"))
        for key, raw in metrics.items():
            if number(raw) is not None:
                sums[key] = sums.get(key, 0) + raw
                known[key] += 1
    keys = ("promptTokens", "completionTokens", "totalTokens", "reasoningTokens", "costReportedUsd")
    count = len(attempts)
    return {
        **{key: sums.get(key) for key in keys},
        "knownAttempts": dict(known), "attemptCount": count,
        "missingUsageAttempts": missing,
        "complete": bool(count) and all(known[key] == count for key in keys[:3]),
        "reasoningComplete": bool(count) and known["reasoningTokens"] == count,
        "costComplete": bool(count) and known["costReportedUsd"] == count,
    }


def scored(row):
    return row["status"] == "passed" or any(
        attempt["kind"] not in AVAILABILITY and
        (attempt["kind"] in SCORABLE or attempt.get("success") is True)
        for attempt in row["attempts"])


def aggregate(rows):
    attempts = [attempt for row in rows for attempt in row["attempts"]]
    completed = [row for row in rows if row["status"] in {"passed", "failed"}]
    correctness = [row for row in completed if scored(row)]
    latency = sorted(row["totalMs"] for row in completed)
    states = collections.Counter(row["status"] for row in rows)
    return {
        "planned": len(rows), "completed": len(completed),
        "passed": states["passed"], "failed": states["failed"],
        "correctnessScored": len(correctness),
        "availabilityOnlyFailures": sum(not scored(row) for row in completed),
        "firstAttemptPassed": sum(bool(row["attempts"]) and
            row["attempts"][0].get("success") is True for row in rows),
        "attemptCount": len(attempts),
        "retryCount": sum(max(0, len(row["attempts"]) - 1) for row in rows),
        "states": dict(states),
        "attemptFailureKinds": dict(collections.Counter(
            attempt["kind"] for attempt in attempts if not attempt.get("success"))),
        "availabilityFailureAttempts": sum(attempt["kind"] in AVAILABILITY for attempt in attempts),
        "operationLatencyMs": {
            "sampleCount": len(latency),
            "median": statistics.median(latency) if latency else None,
            "p95": latency[math.ceil(len(latency) * .95) - 1] if latency else None,
            "quantileMethod": "median midpoint; p95 nearest rank",
            "scope": "Completed operation attempt durations; excludes inter-request pacing sleeps",
        },
        "usage": usage(attempts),
        "cases": [{
            "case": row["case"], "status": row["status"],
            "firstAttemptPassed": bool(row["attempts"]) and row["attempts"][0].get("success") is True,
            "attempts": len(row["attempts"]),
            "retries": max(0, len(row["attempts"]) - 1),
            "operationMs": row["totalMs"],
            "lastDiagnostic": row["attempts"][-1].get("diagnostic") if row["attempts"] else None,
        } for row in rows],
    }


def verify_source(archive, root):
    files = read(archive / "source-files.json")
    require(isinstance(files, dict) and bool(files), "Empty frozen source manifest")
    require(all(sha(value) for value in files.values()), "Invalid source digest")
    raw = (archive / "source.tar.gz").read_bytes()
    found = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tar:
        for member in tar.getmembers():
            name = member.name
            path = pathlib.PurePosixPath(name)
            require(member.isfile() and not member.issym() and not member.islnk(),
                    "Snapshot contains nonregular source entry")
            require(name not in found and name in files, "Unexpected/duplicate snapshot entry")
            require(not path.is_absolute() and ".." not in path.parts,
                    "Snapshot path escapes root")
            require(0 <= member.size <= 32 * 1024 * 1024, "Oversized source entry")
            content = tar.extractfile(member).read()
            same(digest(content), files[name], "snapshot source bytes " + name)
            found[name] = content
    same(set(found), set(files), "exact snapshot source file set")
    for name, expected in files.items():
        same(digest((root / name).read_bytes()), expected, "current frozen source " + name)
    if UNRELATED_RECEIPT.exists():
        same(read(UNRELATED_RECEIPT), UNRELATED_HASHES, "temporary pre-existing-file receipt")
    for name, expected in UNRELATED_HASHES.items():
        same(digest((root / name).read_bytes()), expected, "unrelated pre-existing file " + name)
    return files, {
        "sourceTarSha256": digest(raw), "matchedSnapshotFiles": len(found),
        "currentFrozenFilesMatching": len(files), "unrelatedFilesUnchanged": len(UNRELATED_HASHES),
        "unrelatedReceipt": str(UNRELATED_RECEIPT),
        "unrelatedReceiptEmbeddedForReproducibility": True,
    }


def response_object(raw):
    text = raw.strip()
    fenced = re.fullmatch(r"```json\s*\r?\n([\s\S]*?)\r?\n```", text, flags=re.I)
    if fenced and "```" not in fenced.group(1):
        text = fenced.group(1)
    result = json.loads(text)
    require(isinstance(result, dict), "Expected raw JSON object")
    return result


def apply_patch(base, changes):
    """Only replay authored path operations; semantic validation stays in Dart."""
    candidate = json.loads(json.dumps(base))
    for change in changes:
        path = change["path"]
        parent = candidate
        for key in path[:-1]:
            parent = parent[key]
        key, op = path[-1], change["op"]
        if op == "set":
            parent[key] = change["value"]
        elif op == "remove":
            if isinstance(parent, list):
                del parent[key]
            else:
                parent.pop(key)
        elif op == "append":
            parent[key].append(change["value"])
        else:
            raise ValueError("Unknown authored patch operation")
    return candidate


def pipeline_evidence(row, pipeline, target, fallback):
    counts = collections.Counter()
    patch_bases = []
    for index, attempt in enumerate(row["attempts"]):
        evidence = attempt.get("pipelineEvidence")
        if pipeline is None:
            require(evidence is None, "Control unexpectedly contains pipeline evidence")
            continue
        require(isinstance(evidence, dict), "Experimental attempt lacks pipeline evidence")
        counts["attemptsWithEvidence"] += 1
        same(evidence["pipeline"], pipeline, "attempt pipeline identity")
        same(evidence["version"], "appnest-creation-pipeline-v1", "pipeline metadata version")
        same(evidence["maxTotalCallsPerOperation"], 3, "pipeline call cap")
        same(evidence["syntheticEvaluationOnly"], True, "synthetic-only evidence")
        same(evidence["strictScorerUnchanged"], True, "strict-scoring evidence")
        expected_model = fallback if pipeline == "cascade" and index else target
        same(evidence["servedByModel"], expected_model, "actual route identity")
        require(sha(evidence.get("requestSha256")), "Missing/invalid pipeline request hash")
        require(number(evidence.get("requestBytes")) is not None and evidence["requestBytes"] > 0,
                "Missing/invalid request byte count")
        protocol = evidence.get("responseProtocol")
        allowed = {"creationPlanVersion:1"} if pipeline == "plan" else \
            {"AppSpec", "boundedCreationChanges"} if pipeline == "repair" else {"AppSpec"}
        require(protocol in allowed, "Unexpected response protocol")
        raw = attempt.get("providerResponse", attempt.get("syntheticResponse"))
        derived = attempt.get("syntheticResponse")
        if attempt.get("success"):
            require(isinstance(attempt.get("providerResponse"), str),
                    "Successful pipeline attempt lacks saved raw provider response")
            require(sha(evidence.get("rawResponseSha256")) and
                    sha(evidence.get("derivedResponseSha256")),
                    "Successful pipeline attempt lacks response hashes")
        if isinstance(raw, str):
            counts["rawResponsesPresent"] += 1
        if "rawResponseSha256" in evidence:
            require(isinstance(raw, str), "Raw hash has no saved raw response")
            same(digest(raw.encode("utf-8")), evidence["rawResponseSha256"], "raw provider hash")
            counts["rawHashesVerified"] += 1
        if "derivedResponseSha256" in evidence:
            require(isinstance(derived, str), "Derived hash has no saved response")
            same(digest(derived.encode("utf-8")), evidence["derivedResponseSha256"], "derived response hash")
            counts["derivedHashesVerified"] += 1
        if protocol == "AppSpec" and attempt.get("providerResponse") is not None:
            same(raw, derived, "identity pipeline response")
        if "repairBase" in evidence:
            require(pipeline == "repair" and protocol == "boundedCreationChanges" and index > 0,
                    "Unexpected repair base")
            base = evidence["repairBase"]
            require(isinstance(base, dict), "Repair base is not an object")
            same(base, response_object(row["attempts"][index - 1]["syntheticResponse"]),
                 "repair base equals preceding rejected complete candidate")
            base_hash = digest(compact(base))
            if "repairBaseSha256" in evidence:
                same(evidence["repairBaseSha256"], base_hash, "repair base hash")
            patch_bases.append({"case": row["case"], "attempt": index + 1,
                                "sha256": base_hash, "bytes": len(compact(base))})
            if "derivedResponseSha256" in evidence:
                output = response_object(raw)
                if "unsupported" in output:
                    same(set(output), {"unsupported"}, "unsupported repair shape")
                    same(raw, derived, "unsupported repair passthrough")
                else:
                    same(apply_patch(base, output["changes"]), response_object(derived),
                         "independently assembled bounded patch")
                    counts["patchAssembliesVerified"] += 1
    return counts, patch_bases


def timing(checkpoint, pipeline, target, fallback):
    intervals = []
    actual = collections.defaultdict(list)
    for row in checkpoint["operations"]:
        for index, attempt in enumerate(row["attempts"]):
            start, end = timestamp(attempt["dispatchedAt"]), timestamp(attempt["completedAt"])
            require(end >= start, "Attempt timestamps reversed")
            model = fallback if pipeline == "cascade" and index else row["model"]
            actual[model].append((start, end))
            intervals.append((start, end, model))
    starts = sorted(start for start, _, _ in intervals)
    gap = min(((b - a).total_seconds() * 1000 for a, b in zip(starts, starts[1:])), default=None)
    require(gap is None or gap >= checkpoint["execution"]["requestIntervalMs"],
            "Global request-start spacing below frozen limit")
    peak, active = 0, 0
    events = [(start, 1) for start, _, _ in intervals] + [(end, -1) for _, end, _ in intervals]
    for _, change in sorted(events, key=lambda event: (event[0], event[1])):
        active += change
        peak = max(peak, active)
    require(active == 0 and peak <= checkpoint["execution"]["concurrency"],
            "Client concurrency exceeded frozen limit")
    for model, values in actual.items():
        values.sort()
        require(all(after[0] >= before[1] for before, after in zip(values, values[1:])),
                "Actual serving-model overlap: " + model)
    if intervals:
        require(timestamp(checkpoint["createdAt"]) <= min(starts), "Dispatch predates checkpoint")
        require(max(end for _, end, _ in intervals) <= timestamp(checkpoint["updatedAt"]),
                "Completion follows checkpoint update")
    observed = checkpoint.get("executionObserved")
    if checkpoint["status"] == "completed" and observed:
        same(observed["requestsDispatchedThisInvocation"], len(intervals), "observed dispatch count")
        same(observed["peakConcurrentRequestsThisInvocation"], peak, "observed peak concurrency")
    return {"completedAttempts": len(intervals), "minimumGlobalStartGapMs": gap,
            "clientPeakConcurrent": peak, "actualModelOverlapCount": 0}, intervals


def audit_run(label, checkpoint, plan, files, reference, require_complete):
    pipeline = None if label == "controls" else label
    target, fallback = plan["targetModel"], plan["controlAndFallbackModel"]
    models = [target, fallback] if pipeline is None else [target]
    same(checkpoint["models"], models, label + " models")
    same([scenario["id"] for scenario in checkpoint["scenarios"]], plan["cases"], label + " cases")
    same(checkpoint["provider"], "nvidia", "provider")
    same(checkpoint["apiBase"], "https://integrate.api.nvidia.com/v1", "API base")
    same(checkpoint["nemotronProfile"], plan["nemotronTransportProfile"], "transport recipe")
    same(checkpoint["maxAttempts"], plan["maxAttemptsPerOperation"], "attempt cap")
    same(checkpoint["execution"]["requestIntervalMs"], plan["requestIntervalMs"], "pacing")
    same(checkpoint["execution"]["perModelSequential"], True, "per-model sequential")
    same(checkpoint["execution"]["concurrency"], 2 if pipeline is None else 1, "planned concurrency")
    same(checkpoint["freeOnly"], True, "free-only route")
    same(checkpoint["connectedAppVerified"], False, "acceptance evidence boundary")
    require(timestamp(plan["createdAt"]) <= timestamp(checkpoint["createdAt"]), "Pilot plan recorded after dispatch")
    metadata = checkpoint.get("creationPipeline")
    if pipeline is None:
        require(metadata is None, "Model-only controls contain a pipeline")
    else:
        same(metadata["pipeline"], pipeline, "registered pipeline identity")
    source = checkpoint["source"]
    same(source["files"], files, label + " frozen source files")
    same(digest(compact({"files": files, "dartVersion": source["dartVersion"]})),
         source["contractSourceSha256"], label + " source digest")
    if reference is not None:
        same(checkpoint["scenarios"], reference["scenarios"], label + " exact scenario definitions")
        for key in ("commit", "contractSourceSha256", "dartVersion", "files"):
            same(source[key], reference["source"][key], label + " exact contract source " + key)
        same(checkpoint["transportProfiles"][target], reference["transportProfiles"][target],
             label + " unchanged target sampling/limits profile")
    for profile in checkpoint["transportProfiles"].values():
        same(profile["generationDeadlineSeconds"], plan["generationDeadlineSeconds"], "generation deadline")
        same(profile["generationMaxTokens"], {"initial": 8000, "recognizedCreationTruncation": 12000},
             "generation token limits")
    manifest = {key: checkpoint[key] for key in MANIFEST_KEYS if key in checkpoint}
    manifest["source"] = {key: source[key] for key in ("commit", "contractSourceSha256")}
    same(digest(compact(manifest)), checkpoint["runFingerprint"], label + " run fingerprint")
    rows = checkpoint["operations"]
    expected = [(model, scenario["id"], scenario["operation"]) for scenario in checkpoint["scenarios"]
                for model in models]
    same([(row["model"], row["case"], row["operation"]) for row in rows], expected,
         label + " exact planned operation set/order")
    evidence_counts, patch_bases = collections.Counter(), []
    for row in rows:
        require(row["status"] in STATES, "Unknown operation state")
        attempts = row["attempts"]
        require(isinstance(attempts, list) and len(attempts) <= 3, "Attempt cap exceeded")
        same([attempt["number"] for attempt in attempts], list(range(1, len(attempts) + 1)), "attempt numbering")
        require(all(number(attempt.get("elapsedMs")) is not None for attempt in attempts), "Invalid elapsed time")
        same(row["totalMs"], sum(attempt["elapsedMs"] for attempt in attempts), "operation elapsed sum")
        require(not any(attempt.get("success") is True for attempt in attempts[:-1]), "Dispatch after success")
        if row["status"] == "passed":
            require(attempts and attempts[-1].get("success") is True, "Pass lacks final successful attempt")
            require(isinstance(attempts[-1].get("syntheticResponse"), str), "Pass lacks saved response")
            if row["operation"] == "create":
                require(isinstance(row.get("candidate"), dict), "Creation pass lacks candidate")
        if row["status"] == "failed":
            require(attempts and not attempts[-1].get("success"), "Failure has invalid final attempt")
        if require_complete:
            require(row["status"] in {"passed", "failed"} and "inFlightAttempt" not in row,
                    "Unresolved operation in final audit")
        counts, bases = pipeline_evidence(row, pipeline, target, fallback)
        evidence_counts.update(counts)
        patch_bases.extend(bases)
    if require_complete:
        same(checkpoint["status"], "completed", label + " completed checkpoint")
    timing_result, intervals = timing(checkpoint, pipeline, target, fallback)
    models_result = {model: aggregate([row for row in rows if row["model"] == model]) for model in models}
    serving = collections.defaultdict(list)
    for row in rows:
        for index, attempt in enumerate(row["attempts"]):
            actual = fallback if pipeline == "cascade" and index else row["model"]
            serving[actual].append(attempt)
    return {
        "status": checkpoint["status"], "checkpoint": RUN_FILES[label],
        "runFingerprintVerified": checkpoint["runFingerprint"],
        "modelsOrPipeline": models_result,
        "actualServingAttempts": {model: {"attempts": len(attempts), "usage": usage(attempts)}
                                  for model, attempts in serving.items()},
        "pipelineEvidence": dict(evidence_counts), "repairBaseHashesVerified": patch_bases,
        "timing": timing_result,
    }, intervals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent)
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[4])
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    archive, root = args.archive.resolve(), args.root.resolve()
    plan_path = archive / "pilotplan.json"
    if not plan_path.exists():
        plan_path = archive / "plan.json"
    plan = read(plan_path)
    same(len(plan["cases"]), 6, "six planned pilot cases")
    same(len(set(plan["cases"])), 6, "unique pilot cases")
    same(plan["profiles"], ["control-efficient-creation", "control-glm-5.3", "scoped", "plan", "repair", "cascade"],
         "registered pilot profiles")
    files, source_result = verify_source(archive, root)
    results, pending, all_intervals = {}, [], []
    reference = read(archive / RUN_FILES["controls"]) if (archive / RUN_FILES["controls"]).exists() else None
    for label, filename in RUN_FILES.items():
        path = archive / filename
        if not path.exists():
            pending.append(filename)
            continue
        checkpoint = read(path)
        result, intervals = audit_run(label, checkpoint, plan, files, reference, args.require_complete)
        if args.require_complete:
            summary = read(pathlib.Path(str(path) + ".summary.json"))
            same(summary["runFingerprint"], checkpoint["runFingerprint"], label + " summary fingerprint")
            same(summary["status"], checkpoint["status"], label + " summary status")
            for model, independent in result["modelsOrPipeline"].items():
                reported = summary["models"][model]
                for key in ("planned", "completed", "passed", "firstAttemptPassed", "attemptCount",
                            "availabilityOnlyFailures", "availabilityFailureAttempts", "usage"):
                    same(reported[key], independent[key], label + " independently recomputed " + model + " " + key)
                for key in ("sampleCount", "median", "p95"):
                    same(reported["latencyMs"][key], independent["operationLatencyMs"][key],
                         label + " independently recomputed latency " + key)
            result["summaryBookkeepingVerified"] = True
        results[label] = result
        all_intervals.extend(intervals)
        if checkpoint["status"] != "completed":
            pending.append(filename + ":" + checkpoint["status"])
    if args.require_complete:
        require(not pending, "Missing or unfinished checkpoints: " + ", ".join(pending))
        same(len(results), 5, "all planned checkpoint files")
    by_model = collections.defaultdict(list)
    for start, end, model in all_intervals:
        by_model[model].append((start, end))
    for model, intervals in by_model.items():
        intervals.sort()
        require(all(after[0] >= before[1] for before, after in zip(intervals, intervals[1:])),
                "Actual model overlap across pilot runs: " + model)
    output = {
        "schemaVersion": 1, "audit": "independent-python-creation-pipeline-bookkeeping-v1",
        "status": "complete" if not pending else "partial", "requireComplete": args.require_complete,
        "protocolPlan": plan_path.name, "protocolPlanSha256": digest(plan_path.read_bytes()),
        "expectedCheckpointFiles": RUN_FILES, "pendingOrMissing": pending,
        "source": source_result, "runs": results,
        "actualModelOverlapAcrossRuns": 0,
        "limitations": [
            "Bookkeeping, source bytes, manifest fingerprints, raw/derived hashes and patch assembly only.",
            "Strict AppSpec/request assertions and plan compilation require separate frozen Dart offline replay.",
            "servedByModel identifies the configured API route; provider-internal execution is not independently observed.",
            "Missing usage/cost remains unknown. Operation latency sums attempt durations and excludes pacing sleeps.",
            "A partial audit ignores live in-flight calls whose completion records do not yet exist.",
        ],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError, tarfile.TarError) as error:
        print(json.dumps({"status": "failed", "error": str(error)}, indent=2), file=sys.stderr)
        sys.exit(1)
