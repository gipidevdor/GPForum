#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Collect existing deterministic gates and isolated database performance evidence."""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
DEADLINES = {"pr": 180, "main": 300, "deep": 600}


def write(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True, allow_nan=False) + "\n")
    temporary.replace(path)


def redact(text, env):
    # Parse structured stdout before redacting diagnostics: a test password
    # such as "postgres" is also a perfectly valid JSON key/version label.
    text = re.sub(r"(?i)(postgres(?:ql)?://)[^/@\s]+:[^/@\s]+@", r"\1[redacted]@", text)
    text = re.sub(r"(?i)(password\s*[=:]\s*)([^;\s]+)", r"\1[redacted]", text)
    for name, secret in env.items():
        if secret and re.search(r"PASSWORD|SECRET|TOKEN", name):
            text = text.replace(secret, "[redacted]")
    return text


def redact_values(value, env):
    if isinstance(value, dict):
        return {key: redact_values(item, env) for key, item in value.items()}
    if isinstance(value, list):
        return [redact_values(item, env) for item in value]
    return redact(value, env) if isinstance(value, str) else value


def execute(command, output, name, timeout=120, env=None):
    env = dict(os.environ if env is None else env)
    started = time.monotonic()
    timed_out = False
    try:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                stdout, stderr = process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate()
        code = process.returncode
    except OSError as error:
        stdout, stderr, code = "", str(error), 127
    elapsed = time.monotonic() - started
    diagnostic = output / "diagnostics" / (name + ".log")
    diagnostic.parent.mkdir(parents=True, exist_ok=True)
    diagnostic.write_text(redact(stdout + "\n" + stderr, env))
    try:
        payload = json.loads(stdout)
        if not isinstance(payload, dict):
            payload = None
        else:
            payload = redact_values(payload, env)
    except (ValueError, TypeError):
        payload = None
    return {"payload": payload, "exit_code": code, "duration_seconds": elapsed,
            "timed_out": timed_out, "diagnostic": str(diagnostic.relative_to(output))}


def numeric(values):
    return {key: value for key, value in values.items()
            if value is None or (isinstance(value, (int, float)) and not isinstance(value, bool))}


def plan_witness(endpoint):
    return {key: endpoint[key] for key in ("endpoint", "purpose", "sql_label", "summary", "violations", "warnings")
            if key in endpoint}


def run_state(result, success):
    return "skipped" if result.get("skipped") else "ok" if success else "failed"


def combined(states):
    return "failed" if "failed" in states else "skipped" if all(state == "skipped" for state in states) else "partial" if "skipped" in states else "ok"


def collect(output, mode, disposable=False, runner=execute, deadline=None):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    suites, database, outbox = [], [], []
    dsn = os.environ.get("GPFORUM_DATABASE_DSN")
    if dsn and not disposable:
        raise ValueError("--disposable-database is required: use an isolated migrated and seeded database")
    name = re.search(r"(?:^|;)dbname=([^;]+)", dsn.replace("dbi:Pg:", "")) if dsn else None
    if dsn and (not name or not (name[1].startswith("gpforum_perf_") or name[1] == "gpforum_test")):
        raise ValueError("--disposable-database requires a dedicated gpforum_perf_* or gpforum_test database")
    expires = time.monotonic() + (DEADLINES[mode] if deadline is None else deadline)
    command_runner = runner

    def runner(command, destination, name, timeout=120, env=None):
        remaining = expires - time.monotonic()
        if remaining <= 0.1:
            return {"payload": None, "exit_code": None, "skipped": True, "timed_out": False,
                    "duration_seconds": 0, "diagnostic": None, "reason": "Hot-path suite wall-clock deadline"}
        return command_runner(command, destination, name, timeout=min(timeout, remaining), env=env)

    repeats = 1 if mode == "pr" else 3
    metadata = json.loads((output / "metadata.json").read_text()) if (output / "metadata.json").exists() else {}
    if (output / "http-environment.json").exists():
        metadata.update(json.loads((output / "http-environment.json").read_text()))
    profile = metadata.get("dataset", {}).get("profile", "small" if mode == "pr" else "medium")
    if profile not in ("small", "medium", "hot-thread"):
        profile = "medium"  # Legacy plan CLI label; exact custom counts remain in run metadata.
    workers = "1" if mode == "pr" else "1,2" if mode == "main" else "1,2,4"
    messages = 1000 if mode == "pr" else 3000 if mode == "main" else 10000
    write(output / "hotpaths-environment.json", {"configuration": {"hotpaths": {
        "deadline_seconds": DEADLINES[mode] if deadline is None else deadline,
        "plan_repetitions": repeats, "plan_cli_profile_label": profile,
        "plans": ["readers", "functions"], "analyze": True,
        "outbox": {"messages": messages, "workers": [int(value) for value in workers.split(",")],
                   "repetitions": repeats, "batch_size": 100, "transport": "recording no-op", "database": "fresh owned"},
        "sql_service_comparison": {"enabled": mode == "deep", "read_iterations": 30,
                                   "write_iterations": 10, "warmup": 5, "proxy_delay_ms": 0.5},
        "profiling": "configured NYTProf deep only",
    }}})
    # The static index/OFFSET gate is reused without rerunning its own plan
    # subprocess. Plans below keep machine-readable timing and full evidence.
    static_env = dict(os.environ)
    static_env.pop("GPFORUM_DATABASE_DSN", None)
    static = runner(["script/gpforum-carton", "exec", "script/query-plan-check"], output,
                    "query-plan-static", timeout=60, env=static_env)
    suites.append({"suite": "query-plan-static", "status": run_state(static, static["exit_code"] == 0),
                   "reason": static.get("reason", "Required index and forbidden OFFSET checks"), "diagnostic": static["diagnostic"]})
    if not dsn:
        for name in ("query-budget", "database-plans", "outbox-postgres", "sql-functions", "profiling"):
            suites.append({"suite": name, "status": "skipped", "reason": "GPFORUM_DATABASE_DSN is absent"})
    else:
        budget = runner(["script/query-budget", "--check", "--json"], output, "query-budget", timeout=60)
        payload = budget["payload"]
        okay = budget["exit_code"] == 0 and payload and payload.get("status") == "ok"
        suites.append({"suite": "query-budget", "status": run_state(budget, okay),
                       "reason": budget.get("reason", "Catalog drift is deterministic; N+1 request counts remain blocking in ci.yml integration tier"),
                       "failure_kind": "deterministic" if payload and any(payload.get(key) for key in ("extra", "missing", "mismatched"))
                       else None if okay or budget.get("skipped") else "infrastructure_or_harness",
                       "diagnostic": budget["diagnostic"]})
        if payload:
            database.append({"scenario": "query-budget-catalog", "status": "ok" if okay else "failed",
                             "metrics": {}, "evidence": payload})
        for backend in ("readers", "functions"):
            states = []
            for repetition in range(1, repeats + 1):
                command = ["script/query-plan-evidence", "--check", "--json", "--analyze", "--profile", profile]
                if backend == "functions":
                    command.append("--functions")
                result = runner(command, output, f"query-plan-{backend}-{repetition}", timeout=150)
                payload = result["payload"]
                states.append(run_state(result, result["exit_code"] == 0 and payload and payload.get("status") == "ok"))
                if not payload:
                    continue
                for endpoint in payload.get("endpoints", []):
                    state = endpoint.get("status", "failed")
                    summary = endpoint.get("summary", {})
                    database.append({"scenario": "sql-plan-" + backend, "endpoint": endpoint.get("endpoint", "unknown"),
                                     "repetition": repetition, "status": "ok" if state == "ok" else "failed",
                                     "metrics": numeric({"sql_execution_ms": summary.get("actual_time_ms"),
                                                         "actual_rows": summary.get("actual_rows"),
                                                         "nested_statements": summary.get("nested_statements")}),
                                     "evidence": plan_witness(endpoint),
                                     "limitations": ["EXPLAIN instrumentation overhead; SQL time excludes HTTP and rendering"]})
            suites.append({"suite": "database-plans-" + backend,
                           "status": combined(states),
                           "skipped_repetitions": sum(state == "skipped" for state in states),
                           "reason": "Hot-path suite wall-clock deadline" if "skipped" in states
                           else "Nested stored-function plans require auto_explain LOAD; unavailable or unmeasured is never PASS",
                           "failure_kind": "deterministic" if any(row.get("evidence", {}).get("violations") for row in database
                                                                  if row["scenario"] == "sql-plan-" + backend)
                           else None if "failed" not in states else "infrastructure_or_harness"})
        result = runner(["script/gpforum-carton", "exec", "script/performance-outbox.pl", "--json",
                         "--messages", str(messages), "--workers", workers, "--repetitions", str(repeats)],
                        output, "outbox-postgres", timeout=300 if mode == "deep" else 150)
        payload = result["payload"]
        if payload:
            for row in payload.get("results", []):
                outbox.append({"scenario": "postgres-dispatch-noop", "workers": row["workers"],
                               "repetition": row["repetition"], "status": "ok" if row["status"] == "ok" else "failed",
                               "metrics": numeric({"messages_per_second": row.get("messages_per_second"),
                                                   "completed": row.get("delivered"), "duration_seconds": row.get("duration_seconds"),
                                                   "p50_ms": row.get("p50_batch_ms"), "p95_ms": row.get("p95_batch_ms"),
                                                   "p99_ms": row.get("p99_batch_ms"), "lost": row.get("lost"),
                                                   "duplicates": row.get("duplicates"), "acknowledged": row.get("acknowledged")}),
                               "configuration": {"messages": messages, "batch_size": 100, "transport": "no-op"},
                               "evidence": row,
                               "limitations": ["Actual PostgreSQL claim/renew/ack; no-op handler excludes real delivery cost; batch percentiles are not message latency"]})
        suites.append({"suite": "outbox-postgres", "status": run_state(result, result["exit_code"] == 0 and payload and payload.get("status") == "ok"),
                       "reason": result.get("reason", "Fresh owned database is dropped on completion or caught signals; synthetic delivery IDs verify losses and duplicates"),
                       "failure_kind": None if result.get("skipped") else "infrastructure_or_harness" if not payload or payload.get("error")
                       else "deterministic" if any(row["status"] != "ok" for row in outbox) else None,
                       "diagnostic": result["diagnostic"]})
        if mode == "deep":
            result = runner(["script/gpforum-carton", "exec", "script/bench-sql-functions", "--json",
                             "--read-iterations", "30", "--write-iterations", "10", "--warmup", "5", "--delay-ms", "0.5"],
                            output, "sql-functions", timeout=240)
            if result["payload"]:
                # The existing structured operation breakdown remains intact;
                # these are service/DBI timings, not pure SQL or HTTP timings.
                for operation, paths in result["payload"].get("operations", {}).items():
                    for path, cases in paths.items():
                        for connection in ("direct", "proxy"):
                            row = cases.get(connection)
                            if row:
                                database.append({"scenario": "sql-function-service-" + path + "-" + connection,
                                                 "endpoint": operation, "status": "ok" if result["exit_code"] == 0 else "failed",
                                                 "metrics": numeric({"p50_ms": row.get("median_ms"), "p95_ms": row.get("p95_ms"),
                                                                     "statements": row.get("statements"), "round_trips": row.get("round_trips"),
                                                                     "service_cpu_ms": row.get("cpu_ms")}),
                                                 "evidence_quality": "indicative",
                                                 "configuration": {"delay_ms": result["payload"].get("delay_ms"),
                                                                   "dataset": result["payload"].get("benchmark", {}).get("workload")},
                                                 "limitations": ["Service/DBI timings; one diagnostic sweep, internal iterations are not independent runner repetitions"]})
            suites.append({"suite": "sql-functions", "status": run_state(result, result["exit_code"] == 0 and result["payload"]),
                           "reason": result.get("reason", "Existing helper creates and drops its own 3000-post / 1500-thread database"),
                           "diagnostic": result["diagnostic"]})
            profile_path = output / "diagnostics" / "profile"
            profile_path.mkdir(parents=True, exist_ok=True)
            env = dict(os.environ, NYTPROF=f"file={profile_path.resolve()}/route-nytprof.out:addpid=1")
            probe = runner(["script/gpforum-carton", "exec", "perl", "-MDevel::NYTProf", "-e", "print qq{available\\n}"],
                           output, "nytprof-availability", timeout=30)
            if probe["exit_code"] == 0:
                profile_run = runner(["script/profile-nytprof", "--route", "/categories", "--configured",
                                      "--iterations", "10", "--warmup", "2", "--json"], output, "nytprof", timeout=120, env=env)
                binaries = list(profile_path.glob("*.out*"))
                suites.append({"suite": "profiling", "status": run_state(profile_run, profile_run["exit_code"] == 0 and binaries),
                               "reason": profile_run.get("reason", "Configured in-process request profile; binary files retained only in artifact diagnostics"),
                               "diagnostic": profile_run["diagnostic"]})
            else:
                suites.append({"suite": "profiling", "status": "skipped", "reason": probe.get("reason", "Devel::NYTProf is unavailable"),
                               "diagnostic": probe["diagnostic"]})
        else:
            for name in ("sql-functions", "profiling"):
                suites.append({"suite": name, "status": "skipped", "reason": "Reserved for bounded weekly/manual deep mode"})
    for kind, measurements in (("database", database), ("outbox", outbox)):
        if measurements:
            write(output / (kind + ".json"), {"schema_version": 1, "kind": kind,
                  "status": "ok" if all(row["status"] == "ok" for row in measurements) else "partial",
                  "measurements": measurements, "limitations": []})
    status = "failed" if any(row["status"] == "failed" for row in suites) else "partial" if any(row["status"] == "skipped" for row in suites) else "ok"
    states = {row.pop("suite"): row for row in suites}
    for kind, measurements in (("database", database), ("outbox", outbox)):
        related = [value for key, value in states.items() if
                   (key.startswith(("query-", "database-", "sql-functions")) if kind == "database" else key.startswith("outbox"))]
        required = [value for key, value in states.items() if
                    key.startswith(("query-", "database-")) or (mode == "deep" and key == "sql-functions")] if kind == "database" else related
        states[kind] = {"status": "failed" if any(row["status"] == "failed" for row in related)
                        else "partial" if measurements and any(row["status"] in ("partial", "skipped") for row in required)
                        else "ok" if measurements else "skipped",
                        "reason": "See individual gates and diagnostic artifacts; skipped suites never imply execution"}
    write(output / "hotpaths-status.json", states)
    return 1 if status == "failed" else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("pr", "main", "deep"), required=True)
    parser.add_argument("--disposable-database", action="store_true")
    parser.add_argument("--deadline", type=int, help="Total suite seconds (default PR 180, main 300, deep 600)")
    args = parser.parse_args()
    try:
        if args.deadline is not None and not 30 <= args.deadline <= 900:
            parser.error("--deadline must be 30..900 seconds")
        return collect(args.output, args.mode, args.disposable_database, deadline=args.deadline)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
