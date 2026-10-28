#!/usr/bin/env python3
"""Independently reconcile the archived, synthetic NVIDIA candidate trial.

Run from any directory after both archived checkpoints are terminal, or after
an administrative interrupt documented in operational-stop.json:
    python3 /path/to/AppNest/docs/evidence/nvidia-model-candidates/2026-10-08/audit.py

Uses only Python's standard library. Reads evidence, the 29 named source files,
and git HEAD; never reads credentials, invokes providers, or starts a server.
An interrupted raw checkpoint remains running/in_flight in the evidence; a
receipt must record process exit and bind the preserved bytes by SHA-256.
Writes audit.json only after every check succeeds. This checks bookkeeping and
provenance, not model-response scoring (use the Dart offline replay for that).
"""

import collections
import datetime as dt
import hashlib
import json
import math
import pathlib
import statistics
import subprocess
import sys


CATEGORIES = ("create", "edit", "guidance", "unsupported", "sequence")
AVAILABILITY = {
    "http_error", "timeout", "transport_error", "quota", "quota_exhausted",
    "rate_limit", "unavailable", "interrupted", "provider_error", "auth_error",
    "configuration_error",
}
SCORABLE = {
    "received", "validation", "truncated", "completion_stopped",
    "content_missing", "output_json", "output_shape", "output_size",
    "guidance_completion",
}
STATUSES = {"passed", "failed", "skipped", "pending", "blocked", "indeterminate"}
STOP_HTTP = {202, 401, 402, 403, 429}
MANIFEST_KEYS = (
    "benchmarkVersion", "provider", "benchmarkLabel", "modelFamilies",
    "apiBase", "models", "scenarios", "source", "maxAttempts", "execution",
    "transportProfiles",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def same(actual, expected, label):
    require(actual == expected, f"Mismatch: {label}")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def compact(value):
    # Dart jsonEncode preserves insertion order, emits UTF-8, and has no spaces.
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def number(value):
    return value if (isinstance(value, (int, float)) and not isinstance(value, bool)
                     and math.isfinite(value) and value >= 0) else None


def first(*values):
    return next((v for v in values if v is not None), None)


def ratio(numerator, denominator):
    return numerator / denominator if denominator else None


def category(row):
    return "sequence" if row.get("sequenceSourceId") is not None else row["operation"]


def usage(attempts):
    sums, known = {}, collections.Counter()
    missing = 0
    for attempt in attempts:
        value = attempt.get("usage") or {}
        details = first(value.get("completion_tokens_details"),
                        value.get("completionTokensDetails")) or {}
        metrics = {
            "promptTokens": first(value.get("prompt_tokens"), value.get("promptTokens")),
            "completionTokens": first(value.get("completion_tokens"), value.get("completionTokens")),
            "totalTokens": first(value.get("total_tokens"), value.get("totalTokens")),
            "reasoningTokens": first(value.get("reasoning_tokens"), value.get("reasoningTokens"),
                                     details.get("reasoning_tokens"), details.get("reasoningTokens")),
            "costReportedUsd": value.get("cost"),
        }
        if all(number(v) is None for k, v in metrics.items() if k != "costReportedUsd"):
            missing += 1
        for key, raw in metrics.items():
            valid = number(raw)
            if valid is not None:
                sums[key] = sums.get(key, 0) + valid
                known[key] += 1
    count = len(attempts)
    return {
        **{key: sums.get(key) for key in (
            "promptTokens", "completionTokens", "totalTokens", "reasoningTokens", "costReportedUsd")},
        "knownAttempts": dict(known), "attemptCount": count,
        "missingUsageAttempts": missing,
        "complete": bool(count) and all(known[k] == count for k in (
            "promptTokens", "completionTokens", "totalTokens")),
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
            "sampleCount": len(latency),
            "median": statistics.median(latency) if latency else None,
            "p95": latency[math.ceil(len(latency) * .95) - 1] if latency else None,
            "quantileMethod": "median midpoint; p95 nearest rank",
        },
        "usage": usage(attempts),
    }


def timestamp(value):
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "Timestamp must include timezone")
    return parsed


def timing(checkpoint, interrupted=False):
    starts, events, per_model = [], [], collections.defaultdict(list)
    elapsed = []
    for row in checkpoint["operations"]:
        for attempt in row["attempts"]:
            start, end = timestamp(attempt["dispatchedAt"]), timestamp(attempt["completedAt"])
            require(end >= start, "Attempt timestamp reversed")
            identity = (row["case"], attempt["number"])
            per_model[row["model"]].append((start, end, identity))
            starts.append(start)
            events.extend(((start, 1), (end, -1)))
            elapsed.append(abs((end - start).total_seconds() * 1000 - attempt["elapsedMs"]))
    starts.sort()
    active = peak = 0
    # Completions precede new starts at equal timestamps.
    for _, change in sorted(events, key=lambda e: (e[0], e[1])):
        active += change
        peak = max(peak, active)
    require(active == 0, "Unbalanced attempt timing")
    overlaps = []
    for model, intervals in per_model.items():
        intervals.sort()
        for previous, current in zip(intervals, intervals[1:]):
            if current[0] < previous[1]:
                overlaps.append({"model": model, "previous": previous[2], "next": current[2]})
    gaps = [(right - left).total_seconds() * 1000 for left, right in zip(starts, starts[1:])]
    minimum_gap = min(gaps) if gaps else None
    execution = checkpoint["execution"]
    require(peak <= execution["concurrency"], "Client request concurrency exceeded manifest")
    require(not overlaps, "Overlapping client requests within a model")
    require(minimum_gap is None or minimum_gap >= execution["requestIntervalMs"],
            "Global dispatch spacing fell below manifest")
    observed = checkpoint["executionObserved"]
    unfinished = sum(r["status"] == "in_flight" for r in checkpoint["operations"])
    if interrupted:
        # The durable marker precedes dispatch. Its start timestamp is not saved.
        # executionObserved is updated at completion, so can lag later markers.
        require(len(starts) <= observed["requestsDispatchedThisInvocation"] <= len(starts) + unfinished,
                "Recorded request count is outside completed/claimed bounds")
        require(peak <= observed["peakConcurrentRequestsThisInvocation"] <= execution["concurrency"],
                "Recorded concurrency peak is outside known/allowed bounds")
    else:
        same(observed["requestsDispatchedThisInvocation"], len(starts), "recorded request count")
        same(observed["peakConcurrentRequestsThisInvocation"], peak, "recorded client concurrency peak")
    return {
        "attemptsWithTimestamps": len(starts), "clientPeakConcurrent": peak,
        "perModelOverlapCount": len(overlaps), "minimumGlobalStartGapMs": minimum_gap,
        "maxTimestampVersusElapsedDifferenceMs": max(elapsed) if elapsed else None,
        "wallClockMs": (max(e[0] for e in events) - min(starts)).total_seconds() * 1000 if starts else None,
        "timingCoverage": "completed attempts only; unfinished claims have no saved dispatch timestamp" if unfinished else "all attempts",
        "unfinishedClaimsWithUnknownDispatchTiming": unfinished,
        "unfinishedMarkersEstablishRemoteDispatch": False if unfinished else None,
        "recordedExecutionObserved": observed,
        "remoteWorkAfterClientTimeoutKnown": False,
    }


def audit_checkpoint(checkpoint, summary, label, interrupted=False):
    allowed_statuses = {"completed", "blocked", "incomplete"} | ({"running"} if interrupted else set())
    require(checkpoint["status"] in allowed_statuses,
            f"{label} checkpoint is not terminal; audit.json will not be written")
    models, scenarios, rows = checkpoint["models"], checkpoint["scenarios"], checkpoint["operations"]
    same(len(models), len(set(models)), f"{label} distinct model IDs")
    same(len(scenarios), len({s["id"] for s in scenarios}), f"{label} distinct cases")
    expected_rows = [(m, s["id"], s["operation"], s.get("sequenceSourceId")) for s in scenarios for m in models]
    same([(r["model"], r["case"], r["operation"], r.get("sequenceSourceId")) for r in rows],
         expected_rows, f"{label} model-case operation coverage/order")
    for row in rows:
        require(row["status"] in STATUSES | ({"in_flight"} if interrupted else set()),
                f"{label} unresolved in-flight/unknown status")
        if interrupted and row["status"] == "in_flight":
            same(row.get("inFlightAttempt"), len(row["attempts"]) + 1, f"{label} unfinished claim identity")
            require(row["inFlightAttempt"] <= checkpoint["maxAttempts"], "Unfinished attempt exceeds cap")
        else:
            require("inFlightAttempt" not in row, f"{label} stale in-flight claim")
        require(len(row["attempts"]) <= checkpoint["maxAttempts"], "Attempt cap exceeded")
        same([a["number"] for a in row["attempts"]], list(range(1, len(row["attempts"]) + 1)),
             "Attempt numbering")
        same(row["totalMs"], sum(a["elapsedMs"] for a in row["attempts"]), "Attempt elapsed sum")
        if row["status"] == "passed":
            require(row["attempts"] and row["attempts"][-1].get("success") is True,
                    "Passed operation lacks final successful attempt")
    if checkpoint["status"] == "completed":
        require(all(r["status"] in {"passed", "failed", "skipped"} for r in rows),
                "Completed checkpoint has unresolved operations")
    manifest = {key: checkpoint[key] for key in MANIFEST_KEYS}
    source = checkpoint["source"]
    manifest["source"] = {key: source[key] for key in ("commit", "contractSourceSha256")}
    same(digest(compact(manifest)), checkpoint["runFingerprint"], f"{label} run fingerprint")
    same(digest(compact({"files": source["files"], "dartVersion": source["dartVersion"]})),
         source["contractSourceSha256"], f"{label} frozen source manifest hash")
    planned = {key: sum(category(s) == key for s in scenarios) for key in CATEGORIES}
    same(summary["plannedCategories"], planned, f"{label} planned category counts")
    same(summary["plannedPerModel"], len(scenarios), f"{label} planned case count")
    for key in MANIFEST_KEYS + ("status", "createdAt", "updatedAt", "runFingerprint", "catalog", "executionObserved"):
        if key in summary and key != "models":
            same(summary[key], checkpoint[key], f"{label} summary {key}")
    same(list(summary["models"]), models, f"{label} summary model IDs/order")
    independent = {}
    for model in models:
        model_rows = [r for r in rows if r["model"] == model]
        independent[model] = {
            **aggregate(model_rows, len(scenarios)),
            "categories": {c: aggregate([r for r in model_rows if category(r) == c], planned[c]) for c in CATEGORIES},
        }
        same(independent[model], summary["models"][model], f"{label} aggregate {model}")
    return {
        "status": checkpoint["status"], "operationStatuses": dict(collections.Counter(r["status"] for r in rows)),
        "runFingerprintVerified": checkpoint["runFingerprint"], "plannedCategories": planned,
        "models": independent, "timing": timing(checkpoint, interrupted=interrupted),
        "administrativelyInterrupted": interrupted,
        "unfinishedClaimsAtStop": [
            {"model": r["model"], "case": r["case"], "attemptNumber": r["inFlightAttempt"],
             "outcome": "unknown; durable marker does not prove dispatch or cancellation"}
            for r in rows if r["status"] == "in_flight"
        ],
    }


def verify_gate(smoke, gate, plan, smoke_bytes):
    same(digest(smoke_bytes), gate["smokeCheckpointSha256"], "smoke gate checkpoint hash")
    same(smoke["status"], "completed", "smoke completed before eligibility gate")
    same(plan["models"], smoke["models"], "smoke planned models")
    same(plan["smokeCases"], [s["id"] for s in smoke["scenarios"]], "smoke planned cases")
    same(plan["smokeOperations"], len(smoke["operations"]), "smoke planned operation count")
    same(plan["source"], smoke["source"], "plan frozen source")
    same(plan["smokeSourceFingerprint"], smoke["runFingerprint"], "plan smoke fingerprint")
    same(plan["execution"], smoke["execution"], "plan execution settings")
    results = []
    for model in smoke["models"]:
        rows = [r for r in smoke["operations"] if r["model"] == model]
        attempts = [a for r in rows for a in r["attempts"]]
        responses = [r["case"] for r in rows if any(
            a["kind"] in {"received", "validation"} and isinstance(a.get("syntheticResponse"), str)
            and a["syntheticResponse"].strip() for a in r["attempts"])]
        results.append({
            "model": model, "eligible": len(responses) == len(rows), "respondedCases": responses,
            "passed": sum(r["status"] == "passed" for r in rows), "attempts": len(attempts),
            "attemptKinds": dict(collections.Counter(a["kind"] for a in attempts)),
            "httpStatuses": dict(collections.Counter(str(a["httpStatus"]) for a in attempts if "httpStatus" in a)),
        })
    same(gate["results"], results, "independent smoke response eligibility")
    eligible = [r["model"] for r in results if r["eligible"]]
    same(gate["eligibleModels"], eligible, "gate eligible model IDs")
    same(gate["excludedModels"], [r["model"] for r in results if not r["eligible"]], "gate excluded model IDs")
    global_stop = smoke.get("billingGuardTripped") is True or any(
        a.get("httpStatus") in STOP_HTTP for r in smoke["operations"] for a in r["attempts"])
    same(gate["globalStopTripped"], global_stop, "global stop gate")
    require(not global_stop, "Full benchmark should not follow tripped smoke stop gate")
    same(gate["smokeStatus"], smoke["status"], "gate smoke status")
    return {"eligibleModels": eligible, "excludedModels": gate["excludedModels"], "globalStopTripped": global_stop}


def verify_source(root, source):
    files = source["files"]
    same(len(files), 29, "number of frozen source files")
    explicit = {"scripts/nemotron_eval.dart", "pubspec.yaml", "pubspec.lock", "appnest_server/pubspec.yaml",
                "packages/appnest_spec/pubspec.yaml"}
    prefixes = ("appnest_server/lib/src/modules/builder/", "appnest_server/lib/src/evaluation/", "packages/appnest_spec/lib/")
    for name, expected in files.items():
        require(name in explicit or (name.startswith(prefixes) and name.endswith(".dart")), "Unexpected source path")
        path = (root / name).resolve()
        require(path.is_relative_to(root), "Source path leaves checkout")
        same(digest(path.read_bytes()), expected, f"current checkout source {name}")
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True,
                          capture_output=True, text=True).stdout.strip()
    return {"matchedCurrentFiles": len(files), "recordedSourceCommit": source["commit"],
            "currentCheckoutCommit": head, "headMatchesRecordedCommit": head == source["commit"],
            "currentSourceBytesMatch": True,
            "limit": "Source bytes are checked, including dirty source from the scored run. This does not assert a clean commit or re-create the recorded whole-checkout dirty diff."}


def verify_operational_stop(receipt, checkpoint, checkpoint_bytes):
    same(receipt["schemaVersion"], 1, "operational stop receipt version")
    same(receipt["action"], "administrative_interrupt", "operational stop action")
    same(receipt["checkpointSha256"], digest(checkpoint_bytes), "operational stop checkpoint bytes")
    same(receipt["processExitVerified"], True, "operator-recorded process exit")
    require(isinstance(receipt["pid"], int) and not isinstance(receipt["pid"], bool) and receipt["pid"] > 0,
            "Operational stop requires a positive process ID")
    require(receipt["signal"] in {"SIGINT", "SIGTERM"}, "Unexpected administrative stop signal")
    require(isinstance(receipt["exitCode"], int) and not isinstance(receipt["exitCode"], bool),
            "Operational stop requires recorded exit code")
    for key in ("reason", "processExitEvidence"):
        require(isinstance(receipt[key], str) and receipt[key].strip(), f"Operational stop requires {key}")
    same(receipt["rawCheckpointStatus"], checkpoint["status"], "stop receipt raw checkpoint status")
    same(receipt["unknownInFlightAtStop"], [
        {key: row[key] for key in ("model", "case", "operation", "inFlightAttempt")}
        for row in checkpoint["operations"] if row["status"] == "in_flight"
    ], "stop receipt unfinished claims")
    for key in ("checkpointMutatedForStop", "remoteCancellationVerified", "resumeAttempted"):
        same(receipt[key], False, f"stop receipt {key}")
    require(timestamp(checkpoint["updatedAt"]) <= timestamp(receipt["processExitVerifiedAt"])
            and timestamp(receipt["signalSentAt"]) <= timestamp(receipt["processExitVerifiedAt"])
            <= timestamp(receipt["recordedAt"]), "Operational stop timestamps are inconsistent")
    return {
        "receiptVerified": True, "action": receipt["action"], "reason": receipt["reason"],
        "pid": receipt["pid"], "signal": receipt["signal"], "exitCode": receipt["exitCode"],
        "processExitVerifiedAt": receipt["processExitVerifiedAt"],
        "processExitEvidenceBasis": "Recorded operator receipt; this helper does not independently inspect process state.",
        "rawCheckpointStatusPreserved": checkpoint["status"],
        "remoteRequestsCancelled": "unknown",
    }


def main():
    archive = pathlib.Path(__file__).resolve().parent
    root = archive.parents[3]
    inputs = ("smoke.json", "smoke.json.summary.json", "full.json", "full.json.summary.json", "smoke-gate.json", "plan.json")
    raw = {name: (archive / name).read_bytes() for name in inputs}
    data = {name: json.loads(value) for name, value in raw.items()}
    smoke, full = data["smoke.json"], data["full.json"]
    stop = None
    stop_path = archive / "operational-stop.json"
    if stop_path.exists():
        raw[stop_path.name] = stop_path.read_bytes()
        stop = verify_operational_stop(json.loads(raw[stop_path.name]), full, raw["full.json"])
    # Refuse to emit an audit for a live checkpoint, even if other checks pass.
    for label, checkpoint in (("smoke", smoke), ("full", full)):
        interrupted = label == "full" and stop is not None
        require(checkpoint["status"] in {"completed", "blocked", "incomplete"} | ({"running"} if interrupted else set()),
                f"{label} is still running without a verified administrative stop receipt")
        require(interrupted or all(r["status"] != "in_flight" for r in checkpoint["operations"]),
                f"{label} still has in-flight work without a verified administrative stop receipt")
    gate = verify_gate(smoke, data["smoke-gate.json"], data["plan.json"], raw["smoke.json"])
    same(full["models"], gate["eligibleModels"], "full eligibility model IDs/order")
    # Documentation edits can change the whole-checkout dirty-diff receipt;
    # commit, Dart version and every contract-source byte must stay identical.
    for key in ("commit", "contractSourceSha256", "files", "dartVersion"):
        same(full["source"][key], smoke["source"][key], f"smoke/full frozen source {key}")
    same(full["execution"], smoke["execution"], "smoke/full execution settings")
    same(len(full["scenarios"]), data["plan.json"]["fullCasesPerEligibleModel"], "full case count")
    same(len(full["operations"]), data["smoke-gate.json"]["fullOperations"], "full operation count")
    same(len(full["operations"]) * full["maxAttempts"], data["smoke-gate.json"]["fullMaxRequests"], "full request cap")
    same(data["smoke-gate.json"]["sourceFileHashesMatched"], len(full["source"]["files"]), "gate source hash count")
    require(timestamp(data["smoke-gate.json"]["recordedAt"]) <= timestamp(full["createdAt"]), "Full trial predates eligibility gate")
    historical_path = root / "docs/evidence/nvidia-free-models/2026-10-08/checkpoint.json"
    historical_bytes = historical_path.read_bytes()
    historical = json.loads(historical_bytes)
    same(full["scenarios"], historical["scenarios"], "all 36 historical scenario definitions/order")
    source = verify_source(root, full["source"])
    audit = {
        "schemaVersion": 1, "auditPassed": True, "networkCallsMade": False,
        "auditHelperSha256": digest(pathlib.Path(__file__).read_bytes()),
        "inputsSha256": {name: digest(value) for name, value in raw.items()},
        "historicalScenarioComparison": {"matched": True, "cases": len(full["scenarios"]),
                                         "checkpointSha256": digest(historical_bytes)},
        "source": source, "smokeGate": gate,
        "wholeCheckoutDirtyDiffSnapshots": {
            "smoke": smoke["source"]["dirtyTrackedSha256"],
            "full": full["source"]["dirtyTrackedSha256"],
            "equal": smoke["source"]["dirtyTrackedSha256"] == full["source"]["dirtyTrackedSha256"],
            "note": "Whole-checkout dirty diffs can include documentation outside the frozen contract. Frozen source files, commit, Dart version and contract hash were checked separately.",
        },
        "operationalStop": stop,
        "smoke": audit_checkpoint(smoke, data["smoke.json.summary.json"], "smoke"),
        "full": audit_checkpoint(full, data["full.json.summary.json"], "full", interrupted=stop is not None),
        "limitations": [
            "Independent Python bookkeeping audit; does not independently re-score model content.",
            "Single exploratory trial. Provider queues and remote work after client timeouts are unknown.",
            "No authenticated persistence, Flutter rendering, device, publication, or production verification.",
            "Free endpoint advertising and access metadata do not verify unit pricing or numerical quota.",
            "Administrative interruption preserves the raw in-flight markers. Unfinished outcomes and their dispatch times are unknown, and remote cancellation is not established.",
        ],
    }
    output = archive / "audit.json"
    output.write_text(json.dumps(audit, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Independent audit passed: smoke {len(smoke['operations'])} archived operation rows; "
          f"full {len(full['operations'])} planned rows, raw status {full['status']}, "
          f"administrative interrupt {stop is not None}; 29 source files; wrote {output.name}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Audit failed; no new audit.json written: {error}", file=sys.stderr)
        raise SystemExit(1)
