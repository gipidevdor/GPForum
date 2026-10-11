#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Versioned continuous performance evidence, using only Python's standard library."""

import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parent.parent
KINDS = ("http", "database", "outbox", "reactor", "workers")
STATES = ("ok", "partial", "failed", "skipped")
KEYS = ("scenario", "endpoint", "generator", "reactor", "workers", "concurrency", "cache_mode")
LOWER_BETTER = {"p50_ms", "p95_ms", "p99_ms", "sql_execution_ms", "statements", "round_trips"}
HIGHER_BETTER = {"requests_per_second", "messages_per_second"}
HARNESS_FILES = ("script/performance-evidence.py", "script/performance-http.py", "script/performance-hotpaths.py",
                 "script/performance-outbox.pl", "benchmarks/hypnotoad-app.pl", "benchmarks/wrk-metrics.lua",
                 "t/lib/GPForum/Test/PostgresHarness.pm", "t/lib/GPForum/Test/OutboxTransport.pm")


def read(path):
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def command(args):
    try:
        return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.DEVNULL, timeout=10).strip()
    except (OSError, subprocess.SubprocessError):
        return None


def initial(mode, commit=None):
    now = dt.datetime.now(dt.timezone.utc)
    cpu_model = platform.processor() or platform.machine()
    mem = None
    if Path("/proc/cpuinfo").exists():
        match = re.search(r"model name\s*:\s*(.+)", Path("/proc/cpuinfo").read_text())
        if match:
            cpu_model = match[1]
        match = re.search(r"MemTotal:\s*(\d+)", Path("/proc/meminfo").read_text())
        if match:
            mem = int(match[1]) * 1024
    elif platform.system() == "Darwin":
        cpu_model = command(["sysctl", "-n", "machdep.cpu.brand_string"]) or cpu_model
        memory = command(["sysctl", "-n", "hw.memsize"])
        mem = int(memory) if memory and memory.isdigit() else None
    return {
        "schema_version": 1, "kind": "metadata", "commit": commit or command(["git", "rev-parse", "HEAD"]) or "0" * 40,
        "date": now.date().isoformat(), "timestamp": now.isoformat(), "mode": mode,
        "run_id": os.environ.get("GITHUB_RUN_ID", "local-" + uuid.uuid4().hex),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "dirty": bool(command(["git", "status", "--porcelain", "--untracked-files=no"])),
        "working_tree_diff_sha256": hashlib.sha256((command(["git", "diff", "HEAD", "--", "lib", "templates", "assets", "migrations", "cpanfile", "cpanfile.snapshot", "deploy"]) or "").encode()).hexdigest(),
        "runner": {"os": platform.system(), "arch": platform.machine(), "cpu_count": os.cpu_count(),
                   "cpu_model": cpu_model, "memory_bytes": mem, "kernel": platform.release(),
                   "name": os.environ.get("RUNNER_NAME", "local"), "label": os.environ.get("GPFORUM_PERF_RUNNER", "local"),
                   "image": os.environ.get("ImageOS", platform.system()), "image_version": os.environ.get("ImageVersion")},
        "versions": {}, "dataset": {}, "configuration": {"harness_sha256": {
            name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in HARNESS_FILES if (ROOT / name).exists()}},
        "artifact_url": os.environ.get("GPFORUM_PERF_ARTIFACT_URL", ""),
        "history_url": "https://github.com/" + os.environ.get("GITHUB_REPOSITORY", "gpicchiarelli/GPForum") + "/tree/main/benchmarks/results",
        "run_url": (os.environ.get("GITHUB_SERVER_URL", "https://github.com") + "/" + os.environ.get("GITHUB_REPOSITORY", "gpicchiarelli/GPForum") + "/actions/runs/" + os.environ["GITHUB_RUN_ID"]) if os.environ.get("GITHUB_RUN_ID") else "",
        "limitations": ["Shared runners and a colocated load generator give comparative CI evidence, not production capacity."],
    }


def compatible_signature(metadata):
    runner = metadata.get("runner", {})
    value = {
        "runner": {k: runner.get(k) for k in ("os", "arch", "label", "image", "cpu_count", "cpu_model")},
        "memory_gib": round((runner.get("memory_bytes") or 0) / 1024 ** 3),
        "versions": metadata.get("versions", {}), "dataset": metadata.get("dataset", {}),
        "configuration": metadata.get("configuration", {}), "mode": metadata["mode"], "schema_version": 1,
    }
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def key(row):
    return tuple(str(row.get(k, "")) for k in KEYS)


def aggregate(measurements, kind):
    groups = {}
    for row in measurements:
        groups.setdefault(key(row), []).append(row)
    results = []
    for group, rows in groups.items():
        good = [r for r in rows if r["status"] == "ok"]
        metrics, spread, samples = {}, {}, {}
        names = sorted({k for r in good for k, v in r.get("metrics", {}).items() if isinstance(v, (int, float)) and not isinstance(v, bool)})
        for name in names:
            values = [r["metrics"][name] for r in good if isinstance(r.get("metrics", {}).get(name), (int, float))]
            center = statistics.median(values)
            metrics[name] = center
            spread[name] = statistics.median(abs(x - center) for x in values)
            samples[name] = values
        result = {k: rows[0][k] for k in KEYS if k in rows[0]}
        result.update(kind=kind, status="ok" if len(good) == len(rows) else "failed", repetitions=len(good),
                      attempted=len(rows), metrics=metrics, mad=spread, samples=samples,
                      evidence_quality="measured-comparative" if len(good) >= 3 else "indicative")
        if any(r.get("evidence_quality") == "indicative" for r in rows):
            result["evidence_quality"] = "indicative"
        results.append(result)
    return results


def compare(current, baseline):
    result = {"classification": "not-comparable", "deltas_pct": {}, "reason": "No matching valid baseline scenario."}
    if not baseline or current["status"] != "ok" or baseline.get("status") != "ok":
        return result
    changes = []
    improvements = []
    for name, value in current["metrics"].items():
        old = baseline.get("metrics", {}).get(name)
        if old is None or old <= 0:
            continue
        delta = 100 * (value / old - 1)
        result["deltas_pct"][name] = round(delta, 3)
        if name not in LOWER_BETTER | HIGHER_BETTER:
            continue
        detrimental = -delta if name in HIGHER_BETTER else delta
        noise = max(current.get("mad", {}).get(name, 0) / max(value, 1e-12), baseline.get("mad", {}).get(name, 0) / old) * 300
        threshold = max(10, noise)
        if detrimental > threshold:
            a = current.get("samples", {}).get(name, [])
            b = baseline.get("samples", {}).get(name, [])
            separated = bool(a and b) and (max(a) < min(b) if name in HIGHER_BETTER else min(a) > max(b))
            confirmed = len(a) >= 3 and len(b) >= 3 and separated and detrimental >= max(15, threshold)
            changes.append("confirmed-regression" if confirmed else "possible-regression")
        elif detrimental < -threshold:
            improvements.append(name)
    if not result["deltas_pct"]:
        return result
    result["classification"] = ("confirmed-regression" if "confirmed-regression" in changes else "possible-regression" if changes else "improvement" if improvements else "stable")
    result["reason"] = "Median comparison; tolerance >=10% and 3x relative MAD; confirmation needs >=3 repeats, >=15% change and separated sample ranges. Timing classifications are advisory."
    if min(current.get("repetitions", 0), baseline.get("repetitions", 0)) < 3 and result["classification"] in ("stable", "improvement"):
        result.update(classification="not-comparable", reason="Fewer than three repetitions; deltas are indicative only.")
    return result


def configuration_differences(rows, field):
    differences = []
    for row in rows:
        peers = [r for r in rows if all(r.get(k) == row.get(k) for k in KEYS if k != field)]
        if field == "workers":
            peers.sort(key=lambda r: r[field])
        else:
            peers.sort(key=lambda r: (r[field] != "Mojo::Reactor::Poll", r[field]))
        peer = peers[0]
        if row[field] != peer[field]:
            differences.append({k: row[k] for k in KEYS if k in row} | {
                "value": row[field], "baseline_value": peer[field], "comparison": compare(row, peer)})
    return differences


def schema_validate(value, schema, definitions=None, path="$", top=None):
    """Validate the explicit JSON Schema subset used in schema-v1.json; fail on unknown keywords."""
    top = top or schema
    permitted = {"$schema", "$id", "$defs", "$ref", "title", "description", "type", "required", "properties", "additionalProperties", "items", "minItems", "enum", "const", "anyOf", "minimum", "pattern", "maxLength"}
    unknown = set(schema) - permitted
    if unknown:
        raise ValueError(f"unsupported schema keywords: {unknown}")
    if "$ref" in schema:
        reference = top
        for part in schema["$ref"].removeprefix("#/").split("/"):
            reference = reference[part]
        return schema_validate(value, reference, path=path, top=top)
    if "anyOf" in schema:
        for branch in schema["anyOf"]:
            try:
                schema_validate(value, branch, path=path, top=top)
                return
            except ValueError:
                pass
        raise ValueError(f"{path}: no schema variant matches")
    types = schema.get("type", [])
    if isinstance(types, str):
        types = [types]
    checks = {"object": isinstance(value, dict), "array": isinstance(value, list), "string": isinstance(value, str),
              "integer": isinstance(value, int) and not isinstance(value, bool), "number": isinstance(value, (int, float)) and not isinstance(value, bool),
              "boolean": isinstance(value, bool), "null": value is None}
    if types and not any(checks[t] for t in types):
        raise ValueError(f"{path}: expected {types}")
    if "enum" in schema and value not in schema["enum"] or "const" in schema and value != schema["const"]:
        raise ValueError(f"{path}: invalid value")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if not math.isfinite(value) or "minimum" in schema and value < schema["minimum"]:
            raise ValueError(f"{path}: invalid number")
    if isinstance(value, str):
        if "pattern" in schema and not re.search(schema["pattern"], value):
            raise ValueError(f"{path}: invalid string")
        if len(value) > schema.get("maxLength", 1_000_000):
            raise ValueError(f"{path}: excessive string")
    if isinstance(value, dict):
        missing = set(schema.get("required", [])) - set(value)
        if missing:
            raise ValueError(f"{path}: missing {sorted(missing)}")
        props = schema.get("properties", {})
        for name, item in value.items():
            rule = props.get(name, schema.get("additionalProperties", True))
            if rule is False:
                raise ValueError(f"{path}: unexpected {name}")
            if isinstance(rule, dict):
                schema_validate(item, rule, path=f"{path}.{name}", top=top)
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise ValueError(f"{path}: insufficient items")
        for index, item in enumerate(value):
            schema_validate(item, schema.get("items", {}), path=f"{path}[{index}]", top=top)


def secrets(value):
    if isinstance(value, dict):
        for name, item in value.items():
            if re.search(r"^(?:.*_)?(?:password|passwd|secret|token|credential|authorization|cookie)$", name, re.I) and item not in (None, "[redacted]"):
                raise ValueError("Sensitive field in performance evidence")
            secrets(item)
    elif isinstance(value, list):
        for item in value:
            secrets(item)
    elif isinstance(value, str):
        if re.search(r"BEGIN (?:RSA |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|(?:password|passwd)=(?!\[redacted\](?:[;\s]|$))([^;\s]+)|postgres(?:ql)?://[^/@\s]+:[^/@\s]+@", value, re.I):
            raise ValueError("Sensitive value in performance evidence")


def redact_text(raw):
    raw = re.sub(r"(?i)(postgres(?:ql)?://)[^/@\s]+:[^/@\s]+@", r"\1[redacted]@", raw)
    for name, value in os.environ.items():
        if len(value) >= 4 and re.search(r"PASSWORD|SECRET|TOKEN", name):
            raw = raw.replace(value, "[redacted]")
    raw = re.sub(r'(?i)("(?:password|passwd|secret|token|authorization)"\s*:\s*)"[^"\n]*"', r'\1"[redacted]"', raw)
    raw = re.sub(r"(?i)((?:password|passwd)=)[^;\s]+", r"\1[redacted]", raw)
    raw = re.sub(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}", "[redacted]", raw)
    return raw[:200000]


def validate(output, schema_path=None):
    schema = read(schema_path or ROOT / "benchmarks/schema-v1.json")
    for name in ("metadata", "summary", *KINDS):
        path = Path(output) / (name + ".json")
        if not path.exists():
            if name in ("metadata", "summary"):
                raise ValueError(f"Missing {name}.json")
            continue
        if path.is_symlink() or path.stat().st_size > 8_000_000:
            raise ValueError("Unsafe evidence file")
        value = read(path)
        schema_validate(value, schema)
        secrets(value)
        if name in KINDS and value["kind"] != name:
            raise ValueError("Evidence kind does not match filename")
        if name in KINDS and not value.get("measurements"):
            raise ValueError("Measurement files require real observations")
        if name == "http":
            required_metrics = {"requests_per_second", "completed", "http_errors", "transport_errors", "p50_ms", "p95_ms", "p99_ms", "duration_seconds"}
            for row in value["measurements"]:
                if not set(KEYS[:6]) <= set(row) or "repetition" not in row:
                    raise ValueError("HTTP measurement is missing its scenario configuration")
                if not required_metrics <= set(row["metrics"]):
                    raise ValueError("HTTP measurement is missing required metrics")
                if row["metrics"]["duration_seconds"] <= 0:
                    raise ValueError("HTTP measurement duration must be positive")
    metadata, summary = read(Path(output) / "metadata.json"), read(Path(output) / "summary.json")
    for name in ("commit", "date", "run_id", "run_attempt"):
        if metadata[name] != summary[name]:
            raise ValueError(f"Summary metadata mismatch: {name}")
    return True


def merge_environment(metadata, output):
    for name in ("http-environment.json", "hotpaths-environment.json"):
        path = output / name
        if path.exists():
            extra = read(path)
            for field in ("versions", "dataset", "configuration", "runner"):
                metadata[field].update(extra.get(field, {}))
            metadata["limitations"].extend(extra.get("limitations", []))
    metadata["comparison_signature"] = compatible_signature(metadata)


def status_records(output):
    records = {}
    for name in ("suite-status.json", "hotpaths-status.json", "workflow-status.json"):
        path = output / name
        if not path.exists():
            continue
        data = read(path)
        if isinstance(data, dict):
            records.update(data)
        else:
            for row in data:
                records[row["scenario"]] = row
    return records


def choose_baseline(root, metadata):
    candidates = []
    for path in Path(root).glob("**/summary.json"):
        try:
            summary = read(path)
            if summary.get("status") == "ok" and summary.get("comparison_signature") == metadata["comparison_signature"] and summary["commit"] != metadata["commit"]:
                candidates.append((summary["timestamp"], path.parent))
        except (OSError, ValueError, KeyError):
            continue
    return max(candidates, default=(None, None))[1]


def finalize(output, baseline=None, baseline_root=None):
    output = Path(output)
    metadata = read(output / "metadata.json")
    merge_environment(metadata, output)
    write(output / "metadata.json", metadata)
    suites = status_records(output)
    measurements = []
    limitations = list(metadata["limitations"])
    for kind in ("http", "database", "outbox"):
        path = output / (kind + ".json")
        if path.exists():
            try:
                payload = read(path)
                schema_validate(payload, read(ROOT / "benchmarks/schema-v1.json"))
                secrets(payload)
                rows = payload.get("measurements", [])
                if not rows or payload.get("kind") != kind:
                    raise ValueError(f"{kind} has no valid observations")
            except (ValueError, OSError, KeyError) as error:
                suites[kind] = {"status": "failed", "failure_kind": "infrastructure_or_harness", "reason": "Invalid measurement payload: " + str(error)}
                diagnostic = output / "diagnostics" / (kind + "-invalid.log")
                diagnostic.parent.mkdir(parents=True, exist_ok=True)
                diagnostic.write_text("Payload rejected by secret screening.\n" if "Sensitive" in str(error) else redact_text(path.read_text(errors="replace")), encoding="utf-8")
                path.unlink()
                continue
            measurements.extend(aggregate(rows, kind))
            suites.setdefault(kind, {"status": payload["status"]})
            limitations.extend(payload.get("limitations", []))
            # Provenance on every persisted data envelope, not only the index.
            payload["provenance"] = {k: metadata[k] for k in ("commit", "date", "timestamp", "run_id", "run_attempt", "runner", "versions", "dataset", "configuration")}
            write(path, payload)
        else:
            suites.setdefault(kind, {"status": "skipped", "reason": "No measurement data was produced."})
    baseline = Path(baseline) if baseline else choose_baseline(baseline_root, metadata) if baseline_root else None
    prior, baseline_reason = None, "No baseline available."
    if baseline:
        try:
            validate(baseline)
            prior = read(baseline / "summary.json")
            if prior.get("status") in ("failed", "skipped"):
                prior, baseline_reason = None, "Baseline failed or did not execute benchmarks."
            elif prior.get("comparison_signature") != metadata["comparison_signature"]:
                prior, baseline_reason = None, "Runner, dataset, configuration, mode or tool versions differ."
            else:
                baseline_reason = "Compatible baseline."
        except (ValueError, OSError):
            baseline_reason = "Baseline invalid or incomplete."
    old = {(r["kind"], key(r)): r for r in prior.get("measurements", [])} if prior else {}
    for row in measurements:
        row["comparison"] = compare(row, old.get((row["kind"], key(row))))
        if not prior:
            row["comparison"]["reason"] = baseline_reason
    failed = any(r.get("status") in ("failed", "fail") for r in suites.values()) or any(r["status"] != "ok" for r in measurements)
    incomplete = any(r.get("status") in ("partial", "skipped") for name, r in suites.items() if name in ("http", "database", "outbox"))
    status = "failed" if failed else "partial" if incomplete and measurements else "ok" if measurements else "skipped"
    summary = {k: metadata[k] for k in ("commit", "date", "timestamp", "run_id", "run_attempt", "mode", "comparison_signature")}
    summary.update(schema_version=1, kind="summary", status=status, runner=metadata["runner"], dataset=metadata["dataset"],
                   configuration=metadata["configuration"], suites=suites, measurements=measurements,
                   baseline={"path": str(baseline) if baseline else None, "commit": prior["commit"] if prior else None, "reason": baseline_reason},
                   limitations=list(dict.fromkeys(limitations)))
    write(output / "summary.json", summary)
    for kind, field in (("reactor", "reactor"), ("workers", "workers")):
        rows = [r for r in measurements if r["kind"] == "http" and field in r]
        if not rows:
            continue
        differences = configuration_differences(rows, field)
        derived_status = "failed" if any(r["status"] != "ok" for r in rows) else "ok" if differences else "partial"
        write(output / (kind + ".json"), {"schema_version": 1, "kind": kind, "status": derived_status, "measurements": rows, "differences": differences,
             "provenance": {k: metadata[k] for k in ("commit", "date", "timestamp", "run_id", "run_attempt", "runner", "versions", "dataset", "configuration")},
             "limitations": [] if differences else [f"Only one {field} configuration measured; comparison not executed."]})
    (output / "report.md").write_text(report(metadata, summary), encoding="utf-8")
    validate(output)
    return summary


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ").replace("<", "&lt;")[:500]


def number(value):
    return "—" if value is None else f"{value:.3f}"


def report(metadata, summary):
    runner = metadata["runner"]
    lines = ["# GPForum continuous performance evidence", "", f"Commit: `{metadata['commit']}` · mode: **{metadata['mode']}** · status: **{summary['status']}**",
             f"Run: {metadata['run_id']} / attempt {metadata['run_attempt']} · {metadata['timestamp']}", "",
             f"Runner: {cell(runner.get('label'))}, {cell(runner.get('os'))}/{cell(runner.get('arch'))}, {runner.get('cpu_count')} CPUs, {cell(runner.get('cpu_model'))}.",
             "", "Versions: " + cell(json.dumps(metadata["versions"], sort_keys=True)), "",
             "Dataset: " + cell(json.dumps(metadata["dataset"], sort_keys=True)), "", f"Baseline: {cell(summary['baseline']['reason'])} {summary['baseline'].get('commit') or ''}", "",
             "Values below are medians of repetitions; SQL times remain separate from HTTP time. Timing comparisons are advisory.", "",
             "| Scenario | Generator / reactor / workers / concurrency | Repeats | Status | req/s or msg/s | p50 ms | p95 ms | p99 ms | CPU % / RSS MiB | Comparison |",
             "| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |"]
    if metadata.get("dirty"):
        lines.insert(5, "Working tree contains tracked changes; this local run is not evidence of a clean commit. Relevant diff SHA-256: `" + metadata["working_tree_diff_sha256"] + "`.")
    for row in summary["measurements"]:
        m = row["metrics"]
        settings = " / ".join(cell(row.get(k, "—")) for k in ("generator", "reactor", "workers", "concurrency"))
        rss = m.get("rss_bytes")
        lines.append(f"| {cell(row['kind'] + ':' + row['scenario'])} | {settings} | {row['repetitions']} | {row['status']} ({row['evidence_quality']}) | {number(m.get('requests_per_second', m.get('messages_per_second')))} | {number(m.get('p50_ms'))} | {number(m.get('p95_ms', m.get('sql_execution_ms')))} | {number(m.get('p99_ms'))} | {number(m.get('cpu_percent'))} / {number(rss / 1024 ** 2 if rss is not None else None)} | {row['comparison']['classification']} |")
    lines.extend(["", "## Baseline changes", "", "| Scenario | Classification | Percentage changes |", "| --- | --- | --- |"])
    for row in summary["measurements"]:
        comparison = row["comparison"]
        if comparison["deltas_pct"]:
            lines.append(f"| {cell(row['scenario'])} | {comparison['classification']} | {cell(', '.join(f'{k}: {v:+.1f}%' for k, v in comparison['deltas_pct'].items()))} |")
    lines.extend(["", "## Reactor and worker configuration changes", "",
                  "These compare configurations within this run; they are not commit regressions.", "",
                  "| Scenario | Configuration | Compared with | Concurrency | Classification | Percentage changes |",
                  "| --- | --- | --- | ---: | --- | --- |"])
    for field in ("reactor", "workers"):
        rows = [r for r in summary["measurements"] if r["kind"] == "http" and field in r]
        for difference in configuration_differences(rows, field):
            comparison = difference["comparison"]
            deltas = ', '.join(f'{k}: {v:+.1f}%' for k, v in comparison['deltas_pct'].items())
            lines.append(f"| {cell(difference['scenario'])} | {field}={cell(difference['value'])} | {cell(difference['baseline_value'])} | {difference.get('concurrency', '—')} | {comparison['classification']} | {cell(deltas)} |")
    lines.extend(["", "## Suite status and skipped tests", ""])
    for name, state in summary["suites"].items():
        lines.append(f"- {cell(name)}: **{cell(state.get('status'))}** — {cell(state.get('reason', ''))}")
        for skip in state.get("skipped", []):
            lines.append("  - " + cell(json.dumps(skip, sort_keys=True)))
    lines.extend(["", "## Limits", ""] + ["- " + cell(x) for x in summary["limitations"]])
    lines.extend(["", f"[Persistent history]({metadata['history_url']})"])
    if metadata.get("artifact_url"):
        lines.append(f"[Artifacts]({metadata['artifact_url']})")
    elif metadata.get("run_url"):
        lines.append(f"[Run and artifacts]({metadata['run_url']})")
    return "\n".join(lines) + "\n"


def index(root):
    root = Path(root)
    rows = []
    for path in sorted((root / "benchmarks/results").glob("**/summary.json")):
        validate(path.parent)
        summary = read(path)
        entry = {k: summary[k] for k in ("commit", "date", "timestamp", "run_id", "run_attempt", "mode", "status", "comparison_signature")}
        entry["path"] = str(path.parent.relative_to(root))
        entry["metrics"] = [{k: r[k] for k in ("kind", "scenario", "metrics", "comparison", "status")} for r in summary["measurements"]]
        rows.append(entry)
    rows.sort(key=lambda r: (r["timestamp"], r["run_id"], r["run_attempt"]))
    write(root / "benchmarks/history.json", {"schema_version": 1, "kind": "history", "runs": rows})
    valid = [row for row in rows if row["status"] == "ok"]
    write(root / "benchmarks/latest.json", {"schema_version": 1, "kind": "latest", "run": valid[-1] if valid else None})
    schema = read(ROOT / "benchmarks/schema-v1.json")
    for name in ("history", "latest"):
        schema_validate(read(root / f"benchmarks/{name}.json"), schema)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    init = sub.add_parser("init")
    init.add_argument("--output", type=Path, required=True)
    init.add_argument("--mode", choices=("pr", "main", "deep"), required=True)
    init.add_argument("--commit")
    finish = sub.add_parser("finalize", aliases=["finalise"])
    finish.add_argument("--output", type=Path, required=True)
    finish.add_argument("--baseline", type=Path)
    finish.add_argument("--baseline-root", type=Path)
    check = sub.add_parser("validate")
    check.add_argument("--output", type=Path, required=True)
    check.add_argument("--schema", type=Path)
    listing = sub.add_parser("index")
    listing.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "init":
        if (args.output / "metadata.json").exists():
            raise ValueError("Evidence run already initialized; use a distinct directory")
        metadata = initial(args.mode, args.commit)
        schema_validate(metadata, read(ROOT / "benchmarks/schema-v1.json"))
        write(args.output / "metadata.json", metadata)
    elif args.action in ("finalize", "finalise"):
        summary = finalize(args.output, args.baseline, args.baseline_root)
        print(f"performance evidence: {summary['status']}, {len(summary['measurements'])} scenarios")
    elif args.action == "validate":
        validate(args.output, args.schema)
        print("Performance evidence schema valid")
    elif args.action == "index":
        index(args.root)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError) as error:
        print(f"performance-evidence: {error}", file=sys.stderr)
        sys.exit(1)
