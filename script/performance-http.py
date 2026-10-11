#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Bounded real Hypnotoad evidence; reuse GPForum's seeder and Mojo generator.

Only run live against a disposable gpforum_perf_* (or CI gpforum_test) database.
Only anonymous GETs are generated. Raw logs stay in output/
diagnostics for artifact retention; the publication tool selects only JSON/MD.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import resource
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_VERSION = 1
SCENARIOS = {
    "health_live": "/health/live",
    "home": "/",
    "categories": "/categories",
    "category": "/c/018f1001-0001-7000-8000-000000000001",
    "thread": "/t/018f1004-0001-7000-8000-000000000001",
    "search": "/search?q=performance",
    "cache_hit": "/categories",
    "cache_miss": "/categories",
}
DEFAULTS = {
    "pr": {"duration": 2, "deadline": 240, "concurrency": [1, 10]},
    "main": {"duration": 2, "deadline": 600, "concurrency": [1, 10, 50, 100]},
    "deep": {"duration": 3, "deadline": 1200, "concurrency": [1, 10, 50, 100, 250, 500]},
}
PG_SETTINGS = ["shared_buffers", "work_mem", "effective_cache_size",
               "max_connections", "random_page_cost", "jit",
               "synchronous_commit", "effective_io_concurrency"]


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def sanitize(text):
    text = str(text)
    # First redact credential structures. A fixture secret such as 'postgres'
    # is also a substring of the URI scheme; replacing known secrets first
    # would hide the scheme from the URI matcher and expose its password.
    text = re.sub(r"(?i)(password\s*=\s*)[^;\s]+", r"\1[redacted]", text)
    text = re.sub(r"(?i)(postgres(?:ql)?://)[^/@\s]+:[^/@\s]+@", r"\1[redacted]@", text)
    for key, value in os.environ.items():
        if value and len(value) >= 4 and re.search(r"PASSWORD|SECRET|TOKEN", key):
            text = text.replace(value, "[redacted]")
    return text


def run_command(command, timeout, log=None, env=None, accepted_codes=(0,)):
    """Deadline, bounded output, no shell expansion and process-group cleanup."""
    process = subprocess.Popen([str(x) for x in command], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=max(0.1, timeout))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            output, _ = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
        if log:
            Path(log).write_text(sanitize(output[-200000:]))
        raise RuntimeError("command exceeded its deadline")
    if log:
        Path(log).write_text(sanitize(output[-200000:]))
    if process.returncode not in accepted_codes:
        raise RuntimeError(f"command failed (exit {process.returncode}): {sanitize(output[-1200:])}")
    # Structured stdout is parsed immediately by each caller. Redacting it
    # before JSON decoding corrupts innocent keys when a secret equals e.g.
    # the CI fixture password 'postgres'. Only logs/errors are emitted raw.
    return output


def parse_wrk(output):
    matches = re.findall(r"^GPFORUM_WRK (\{[^\n]+\})$", output, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("wrk did not return one complete metrics record")
    result = json.loads(matches[0])
    for key in ("completed", "http_errors", "transport_errors", "duration_seconds",
                "requests_per_second", "p50_ms", "p95_ms", "p99_ms"):
        value = result.get(key)
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            raise ValueError(f"invalid wrk metric {key}")
    if result["duration_seconds"] <= 0 or result["completed"] <= 0:
        raise ValueError("wrk completed no requests")
    return result


def wrk_version(diagnostics=None):
    # The CLI prints usage and exits 1 even for a successful version query.
    log = Path(diagnostics) / "wrk-version.log" if diagnostics else None
    output = run_command(["wrk", "--version"], 5, log=log, accepted_codes=(0, 1))
    match = re.search(r"^wrk [0-9]+(?:\.[0-9]+)+[^\n]*", output, re.MULTILINE)
    if match:
        return match[0]
    if not re.search(r"^wrk(?:[ \t]|$)", output, re.MULTILINE):
        raise ValueError("wrk did not identify itself in its version output")
    # Distribution builds can omit the upstream git-derived version banner.
    # Query the installed package, rather than assigning an assumed release.
    if shutil.which("dpkg-query"):
        package_log = Path(diagnostics) / "wrk-package-version.log" if diagnostics else None
        try:
            package = run_command(["dpkg-query", "--show", "--showformat=${Version}", "wrk"],
                                  5, log=package_log).strip()
            if re.fullmatch(r"[0-9][A-Za-z0-9.+:~_-]*", package):
                return f"wrk (distribution package {package}; CLI upstream unspecified)"
        except (OSError, RuntimeError, subprocess.SubprocessError):
            pass
    # The recognizable tool can still measure; this string explicitly records
    # that its release was not verified. The runner adds a binary fingerprint.
    return "wrk (CLI upstream version unspecified; distribution package unavailable)"


def parse_mojo(output):
    report = json.loads(output)
    if "completed" not in report:
        raise ValueError("Mojo generator returned no measurements")
    codes = report.get("status_codes", {})
    result = {
        "completed": int(report["completed"]),
        "http_errors": sum(int(count) for code, count in codes.items()
                           if code.isdigit() and not 200 <= int(code) < 400),
        "transport_errors": int(codes.get("error", 0)),
        "duration_seconds": float(report["wall_seconds"]),
        "requests_per_second": float(report["req_per_sec"]),
        "p50_ms": float(report["p50_ms"]),
        "p95_ms": float(report["p95_ms"]),
        "p99_ms": float(report["p99_ms"]),
        "concurrency_effective": int(report["peak_inflight"]),
    }
    if result["completed"] <= 0 or result["duration_seconds"] <= 0:
        raise ValueError("Mojo completed no requests")
    if any(not math.isfinite(value) or value < 0 for value in result.values()):
        raise ValueError("invalid Mojo metric")
    return result


def plan(mode, concurrency=None, cpu_count=None):
    """Base endpoints at low load; targeted high load avoids a Cartesian sweep."""
    cpu_count = cpu_count or os.cpu_count() or 1
    levels = concurrency or DEFAULTS[mode]["concurrency"]
    cells = []
    for scenario in SCENARIOS:
        for concurrent in levels:
            if concurrent > 50 and scenario not in ("health_live", "thread", "search", "cache_hit"):
                continue
            cells.append({"scenario": scenario, "endpoint": SCENARIOS[scenario],
                          "workers": 2, "concurrency": concurrent,
                          "cache_mode": "miss" if scenario == "cache_miss" else "normal"})
    if mode != "pr":
        worker_counts = [4] + ([8] if mode == "deep" and cpu_count >= 4 else [])
        for workers in worker_counts:
            for scenario in ("thread", "search", "cache_hit"):
                # This is a worker comparison at identical concurrency, not
                # an assumption that every vCPU deserves another worker.
                worker_levels = (50, 250) if mode == "deep" else (50, 100)
                for concurrent in [x for x in levels if x in worker_levels]:
                    cells.append({"scenario": scenario, "endpoint": SCENARIOS[scenario],
                                  "workers": workers, "concurrency": concurrent,
                                  "cache_mode": "normal"})
    return cells


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def process_snapshot(master):
    """Sum live manager+workers RSS; CPU ps average is explicitly indicative."""
    try:
        result = subprocess.run(["ps", "-axo", "pid=,ppid=,pcpu=,rss="],
                                capture_output=True, text=True, timeout=2, check=True)
        rows = [line.split() for line in result.stdout.splitlines()]
        members = [row for row in rows if len(row) == 4 and
                   (int(row[0]) == master or int(row[1]) == master)]
        children = [int(row[0]) for row in members if int(row[1]) == master]
        return {"cpu_percent": sum(float(row[2]) for row in members),
                "rss_bytes": sum(int(row[3]) * 1024 for row in members),
                "workers_actual": len(children), "worker_pids": children}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"cpu_percent": None, "rss_bytes": None,
                "workers_actual": None, "worker_pids": []}


def linux_cpu_ticks(master):
    if platform.system() != "Linux":
        return None
    try:
        rows = process_snapshot(master)
        ticks = {}
        for pid in [master] + rows["worker_pids"]:
            # comm may contain spaces/parens; fields after its last ')' start
            # with state, whose index zero precedes utime at index 11.
            fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            ticks[pid] = int(fields[11]) + int(fields[12])
        return ticks
    except (OSError, ValueError, IndexError):
        return None


def resources_between(before, after, duration, snapshot):
    cpu = snapshot["cpu_percent"]
    source = "ps lifetime average; indicative"
    if before is not None and after is not None and before.keys() == after.keys() and duration > 0:
        cpu = 100 * (sum(after.values()) - sum(before.values())) / os.sysconf("SC_CLK_TCK") / duration
        source = "Linux /proc manager+workers CPU time delta / generator wall duration"
    return {"cpu_percent": round(cpu, 3) if cpu is not None else None,
            "rss_bytes": snapshot["rss_bytes"]}, source


def probe_url(url, timeout=3):
    request = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        # Consume so rendering/send failures are visible, but cap the body.
        response.read(2 * 1024 * 1024)
        if response.status != 200:
            raise RuntimeError(f"endpoint returned HTTP {response.status}")
        return response.geturl(), response.headers.get("X-GPForum-Cache")


class Server:
    def __init__(self, output, reactor, workers, cache_mode, index, deadline):
        self.directory = output / "diagnostics" / f"server-{index}"
        self.directory.mkdir(parents=True)
        self.port = free_port()
        self.base = f"http://127.0.0.1:{self.port}"
        self.log_path = self.directory / "hypnotoad.log"
        self.env = dict(os.environ)
        self.env.pop("LIBEV_FLAGS", None)
        self.env.update({
            "MOJO_REACTOR": f"Mojo::Reactor::{reactor}",
            "GPFORUM_LOG_LEVEL": "fatal", "GPFORUM_WEB_PROCESSES": str(workers),
            "GPFORUM_RUNTIME_WORKER_POLICY": "configured",
            "GPFORUM_RUNTIME_LISTEN": self.base,
            "GPFORUM_RUNTIME_PID_FILE": str(self.directory / "hypnotoad.pid"),
            "GPFORUM_RUNTIME_BACKLOG": "1024", "GPFORUM_RUNTIME_CLIENTS": "2048",
            "GPFORUM_RUNTIME_REQUESTS": "100000000",
            "GPFORUM_RUNTIME_GRACEFUL_TIMEOUT": "3",
            "GPFORUM_FORUM_READ_RATE_LIMIT": "100000000",
            "GPFORUM_GLIFISTORE_URL": "", "GPFORUM_LOCAL_CACHE_MAX_ENTRIES": "4096",
            "GPFORUM_CATEGORY_CACHE_TTL_SECONDS": "3600",
            "GPFORUM_PERFORMANCE_CACHE_MODE": cache_mode,
            "GPFORUM_PERFORMANCE_TELEMETRY_DIR": str(self.directory),
        })
        if reactor == "EV" and platform.system() == "Linux":
            self.env["LIBEV_FLAGS"] = "4"
        self.log = self.log_path.open("w")
        self.process = subprocess.Popen(
            [str(ROOT / "script/gpforum-carton"), "exec", "hypnotoad", "-f",
             str(ROOT / "benchmarks/hypnotoad-app.pl")], cwd=ROOT, env=self.env,
            stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
        self.workers = workers
        self.reactor = f"Mojo::Reactor::{reactor}"
        self.deadline = min(deadline, time.monotonic() + 30)
        try:
            while time.monotonic() < self.deadline:
                if self.process.poll() is not None:
                    raise RuntimeError("Hypnotoad exited during startup")
                try:
                    probe_url(self.base + "/health/live", timeout=1)
                    break
                except (OSError, urllib.error.URLError):
                    time.sleep(0.1)
            else:
                raise RuntimeError("Hypnotoad did not become live in 30 seconds")
            self.master = int((self.directory / "hypnotoad.pid").read_text().strip())
            # A live first worker does not prove every configured worker has
            # forked and selected its backend. New short health connections
            # distribute bounded warming across all serving processes.
            while time.monotonic() < self.deadline:
                probe_url(self.base + "/health/live", timeout=1)
                try:
                    self.telemetry()
                    break
                except RuntimeError:
                    time.sleep(0.01)
            else:
                raise RuntimeError("all configured workers did not produce serving reactor telemetry before startup deadline")
        except BaseException:
            self.close()
            raise

    def telemetry(self):
        actual = process_snapshot(self.master)
        telemetry = []
        for pid in actual["worker_pids"]:
            path = self.directory / f"worker-{pid}.json"
            if path.exists():
                telemetry.append(json.loads(path.read_text()))
        if not telemetry or any(row["reactor"] != self.reactor for row in telemetry):
            raise RuntimeError(f"requested {self.reactor} did not match serving worker reactor")
        if len(telemetry) != len(actual["worker_pids"]) or {row["pid"] for row in telemetry} != set(actual["worker_pids"]):
            raise RuntimeError("some serving workers have not produced actual reactor telemetry")
        if self.reactor == "Mojo::Reactor::EV" and platform.system() == "Linux" and any(row["ev_backend"] != 4 for row in telemetry):
            raise RuntimeError("serving EV worker did not select Linux epoll backend")
        if actual["workers_actual"] != self.workers:
            raise RuntimeError("serving worker count changed during measurement")
        return telemetry

    def close(self):
        if self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
                self.process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(self.process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.process.wait(timeout=3)
        self.log.close()
        # Process logs can contain DBI connection errors; redact before upload.
        self.log_path.write_text(sanitize(self.log_path.read_text(errors="replace")[-200000:]))


def probe_reactor(reactor, diagnostics, timeout):
    env = dict(os.environ, MOJO_REACTOR=f"Mojo::Reactor::{reactor}")
    if reactor == "EV" and platform.system() == "Linux":
        env["LIBEV_FLAGS"] = "4"
    output = run_command(["script/gpforum-carton", "exec", "perl", "-MMojo::IOLoop", "-e",
                          "my $class=ref Mojo::IOLoop->singleton->reactor; print $class; print ':' . EV::backend() if $class eq 'Mojo::Reactor::EV'"], timeout,
                         diagnostics / f"probe-{reactor}.log", env)
    expected = f"Mojo::Reactor::{reactor}" + (":4" if reactor == "EV" and platform.system() == "Linux" else "")
    return output.strip() == expected


def prepare_dataset(mode, diagnostics, timeout):
    deadline = time.monotonic() + timeout
    if mode == "pr":
        options = ["--profile", "small"]
    elif mode == "main":
        options = ["--users", "25", "--categories", "8", "--threads", "240", "--posts-per-thread", "20"]
    else:
        options = ["--users", "40", "--categories", "4", "--threads", "600", "--posts-per-thread", "120"]
    result = json.loads(run_command(["script/seed-performance-data", "--json", *options],
                                    deadline - time.monotonic(), diagnostics / "seed.log"))
    run_command(["script/query-budget", "--sync"], min(deadline - time.monotonic(), 30), diagnostics / "query-budget-sync.log")
    script = r'''
use GPForum::Config; use GPForum::Schema; use JSON::MaybeXS qw(encode_json);
my $schema = GPForum::Schema->connect_from_config(GPForum::Config->from_environment);
my $db = $schema->storage->dbh; $db->do('ANALYZE');
my %settings; for my $name (@ARGV) { $settings{$name} = $db->selectrow_array('SELECT current_setting(?)',undef,$name); }
print encode_json({postgres => $db->selectrow_array('SHOW server_version'), database_settings => \%settings});
'''
    pg = json.loads(run_command(["script/gpforum-carton", "exec", "perl", "-Ilib", "-e", script, *PG_SETTINGS],
                               min(deadline - time.monotonic(), 60), diagnostics / "postgres-metadata.log"))
    dataset = {"profile": result["profile"], "counts": result["dataset"],
               "seed_version": "SeedDataset-v1", "mode": mode,
               "implementation_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in (ROOT / "lib/GPForum/Benchmark/SeedDataset.pm", ROOT / "lib/GPForum/Command/PerformanceSeed.pm")}}
    dataset["signature"] = hashlib.sha256(json.dumps(dataset, sort_keys=True).encode()).hexdigest()
    return dataset, pg


def wrk_measure(server, cell, args, log, deadline):
    canonical, _ = probe_url(server.base + cell["endpoint"])
    expected = "miss" if cell["cache_mode"] == "miss" else "hit" if cell["scenario"] == "cache_hit" else None
    # New connections distribute warming over worker-local caches. Only hit
    # assertions need every response to be a hit; the expiry runtime misses.
    warmed = 0
    for _ in range(100):
        if time.monotonic() + args.duration + 8 > deadline:
            raise RuntimeError("suite deadline during cache warmup")
        _, state = probe_url(canonical)
        warmed = warmed + 1 if not expected or state == expected else 0
        if warmed >= max(8, server.workers * 4):
            break
    if expected and warmed < max(8, server.workers * 4):
        raise RuntimeError(f"cache policy {expected} could not be verified")
    telemetry_before = server.telemetry()
    before = linux_cpu_ticks(server.master)
    started = time.monotonic()
    output = run_command(["wrk", "--latency", "-t", str(min(2, cell["concurrency"])),
                          "-c", str(cell["concurrency"]), "-d", f"{args.duration}s",
                          "--timeout", "3s", "-s", ROOT / "benchmarks/wrk-metrics.lua", canonical],
                         min(args.duration + 8, deadline - started), log)
    elapsed = time.monotonic() - started
    after = linux_cpu_ticks(server.master)
    snapshot = process_snapshot(server.master)
    metrics = parse_wrk(output)
    metrics["concurrency_effective"] = None  # wrk exposes configured connections, not observed in-flight peak.
    resources, resource_source = resources_between(before, after, elapsed, snapshot)
    metrics.update(resources)
    validation_error = None
    cache_after = None
    try:
        _, cache_after = probe_url(canonical)
        server.telemetry()
        if expected and cache_after != expected:
            validation_error = f"cache policy changed after measurement ({cache_after})"
    except (OSError, ValueError, RuntimeError, urllib.error.URLError) as error:
        validation_error = sanitize(error)
    return metrics, {"canonical_endpoint": urllib.parse.urlsplit(canonical).path +
                    ("?" + urllib.parse.urlsplit(canonical).query if urllib.parse.urlsplit(canonical).query else ""),
                    "cache_observed": cache_after, "workers_actual": snapshot["workers_actual"],
                    "worker_telemetry": telemetry_before, "cpu_source": resource_source,
                    "rss_source": "ps manager+workers resident memory at end; not peak",
                    "validation_error": validation_error,
                    "generator_wall_seconds": round(elapsed, 6)}


def mojo_measure(server, cell, args, log, deadline):
    canonical, _ = probe_url(server.base + cell["endpoint"])
    expected = "miss" if cell["cache_mode"] == "miss" else "hit" if cell["scenario"] == "cache_hit" else None
    for _ in range(server.workers * 8):
        _, observed = probe_url(canonical)
    if expected and observed != expected:
        raise RuntimeError(f"cache policy {expected} could not be verified")
    split = urllib.parse.urlsplit(canonical)
    route = split.path + ("?" + split.query if split.query else "")
    before = linux_cpu_ticks(server.master)
    started = time.monotonic()
    output = run_command(["script/stress-load", "--profile", "smoke", "--json", "--base-url", server.base,
                          "--route", route, "--concurrency", str(cell["concurrency"]),
                          "--requests-per-client", str(max(10, math.ceil(100 / cell["concurrency"]))), "--request-timeout", "3"],
                         min(20, deadline - started), log,
                         dict(os.environ, MOJO_REACTOR="Mojo::Reactor::Poll"))
    elapsed = time.monotonic() - started
    metrics = parse_mojo(output)
    snapshot = process_snapshot(server.master)
    resources, source = resources_between(before, linux_cpu_ticks(server.master), elapsed, snapshot)
    metrics.update(resources)
    return metrics, {"workers_actual": snapshot["workers_actual"], "cpu_source": source,
                    "rss_source": "ps manager+workers resident memory at end; not peak",
                    "worker_telemetry": server.telemetry(), "canonical_endpoint": route,
                    "capacity_class": "indicative fixed-request Mojo comparison; not sustained capacity"}


def suite_status(output, status, reason, skips):
    path = output / "suite-status.json"
    statuses = json.loads(path.read_text()) if path.exists() else {}
    statuses["http"] = {"status": status, "reason": reason, "skipped": skips}
    write_json(path, statuses)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=DEFAULTS, default="pr")
    parser.add_argument("--duration", type=int)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--deadline", type=int)
    parser.add_argument("--concurrency", help="comma-separated progressive levels; maximum 500 by default")
    parser.add_argument("--allow-1000", action="store_true")
    parser.add_argument("--disposable-database", action="store_true")
    parser.add_argument("--generator", choices=("auto", "wrk", "mojo"), default="auto")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    args.duration = DEFAULTS[args.mode]["duration"] if args.duration is None else args.duration
    args.deadline = DEFAULTS[args.mode]["deadline"] if args.deadline is None else args.deadline
    if not 1 <= args.duration <= 30 or not 1 <= args.repetitions <= 5 or not 30 <= args.deadline <= 1800:
        parser.error("duration 1..30, repetitions 1..5 and deadline 30..1800 required")
    levels = None
    if args.concurrency:
        try:
            levels = sorted(set(int(item) for item in args.concurrency.split(",")))
        except ValueError:
            parser.error("invalid concurrency list")
        if not levels or any(item < 1 or item > (1000 if args.allow_1000 else 500) for item in levels):
            parser.error("concurrency must be 1..500 (1000 requires --allow-1000)")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    cells = plan(args.mode, levels)
    skips = [{"scenario": "authenticated", "reason": "read-only anonymous suite; safe durable auth fixture unavailable"}]
    skips.append({"scenario": "full_cartesian_matrix", "reason": "bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit"})
    if args.mode != "deep":
        skips.append({"scenario": "concurrency_250_500", "reason": "bounded PR/main modes; use deep sweep"})
    if args.mode == "pr":
        skips.append({"scenario": "workers_4_8", "reason": "PR smoke fixes two workers; worker scaling runs on main/deep"})
    elif args.mode == "main":
        skips.append({"scenario": "workers_8", "reason": "eight-worker sweep reserved for capable deep runners"})
    if args.mode == "deep" and (os.cpu_count() or 1) < 4:
        skips.append({"scenario": "workers_8", "reason": "runner has fewer than four CPUs"})
    if not args.allow_1000:
        skips.append({"scenario": "concurrency_1000", "reason": "requires explicit --allow-1000 and capable runner"})
    elif any(cell["concurrency"] == 1000 for cell in cells):
        memory = os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE") if platform.system() == "Linux" else 0
        soft_limit = resource.getrlimit(resource.RLIMIT_NOFILE)[0]
        if (os.cpu_count() or 1) < 4 or memory < 8 * 1024**3 or soft_limit < 4096:
            cells = [cell for cell in cells if cell["concurrency"] != 1000]
            skips.append({"scenario": "concurrency_1000", "reason": "requires Linux >=4 CPUs, 8GiB memory, 4096 file descriptors"})
    if args.dry_run:
        suite_status(args.output, "skipped", "dry-run; no measurements executed", skips +
                     [{"scenario": "http_plan", "reason": "dry-run", "plan": cells}])
        print(json.dumps({"status": "skipped", "plan": cells}))
        return 0
    dsn = os.environ.get("GPFORUM_DATABASE_DSN", "")
    name = re.search(r"(?:^|;)dbname=([^;]+)", dsn.replace("dbi:Pg:", ""))
    if not args.disposable_database or not name or not (name[1].startswith("gpforum_perf_") or name[1] == "gpforum_test"):
        suite_status(args.output, "failed", "requires --disposable-database and dedicated gpforum_perf_* / gpforum_test DB", skips)
        return 2
    deadline = time.monotonic() + args.deadline
    diagnostics = args.output / "diagnostics"
    diagnostics.mkdir(exist_ok=True)
    measurements = []
    failures = []
    wrk_available = bool(shutil.which("wrk"))
    generator = "wrk" if args.generator == "auto" and wrk_available else "mojo" if args.generator == "auto" else args.generator
    if generator == "wrk" and not wrk_available:
        suite_status(args.output, "failed", "independent wrk generator unavailable", skips)
        return 1
    if generator != "wrk":
        skips.append({"scenario": "independent_wrk", "reason": "wrk unavailable or explicitly disabled; Mojo evidence indicative"})
    try:
        dataset, pg = prepare_dataset(args.mode, diagnostics, deadline - time.monotonic())
        versions = json.loads(run_command(["script/gpforum-carton", "exec", "perl", "-MMojolicious", "-MJSON::MaybeXS=encode_json", "-e",
                    "print encode_json({perl => \"$^V\", mojolicious => $Mojolicious::VERSION, ev => eval {require EV; \"$EV::VERSION\"}})"], 10))
        versions["postgres"] = pg["postgres"]
        versions["wrk"] = None
        environment = {
            "versions": versions, "dataset": dataset,
            "configuration": {"http_duration_seconds": args.duration,
                "http_repetitions": args.repetitions, "http_concurrency": levels or DEFAULTS[args.mode]["concurrency"],
                "cache": "local-only; 4096 entries; SSR TTL 3600s; miss harness TTL -1s",
                "cache_miss_policy": "SSR store expires immediately; category model cache remains warm",
                "read_rate_limit": 100000000, "database_settings": pg["database_settings"],
                "backlog": 1024, "clients_per_worker": 2048,
                "mojo_requests": "at least 100 total; at least 10 per client"}}
        # Preserve completed seed/PG/runtime evidence even if a generator probe
        # fails: database/outbox suites still need accurate dataset provenance.
        write_json(args.output / "http-environment.json", environment)
        if wrk_available:
            try:
                versions["wrk"] = wrk_version(diagnostics)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                if generator == "wrk":
                    raise
                skips.append({"scenario": "wrk_version", "reason": "unused optional wrk probe failed: " + sanitize(error)})
            if versions["wrk"] and "CLI upstream" in versions["wrk"]:
                skips.append({"scenario": "wrk_upstream_version", "reason": versions["wrk"]})
                binary = Path(shutil.which("wrk"))
                if binary.is_file():
                    environment["configuration"]["wrk_binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
                elif generator == "wrk":
                    raise RuntimeError("cannot fingerprint wrk with unspecified upstream version")
            environment["configuration"]["wrk_upstream_version_verified"] = bool(versions["wrk"] and re.match(r"^wrk [0-9]+(?:\.[0-9]+)+", versions["wrk"]))
            write_json(args.output / "http-environment.json", environment)
        reactors = ["Poll"]
        if args.mode == "pr":
            skips.append({"scenario": "reactor_EV", "reason": "PR smoke fixes Poll; Linux main/deep compare optional EV"})
        elif platform.system() != "Linux":
            skips.append({"scenario": "reactor_EV", "reason": "comparison is Linux-only; EV stays optional on other platforms"})
        else:
            try:
                ev_available = probe_reactor("EV", diagnostics, 10)
                ev_reason = "EV unavailable or actual reactor/backend cannot be selected"
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                ev_available = False
                ev_reason = "optional EV probe unavailable: " + sanitize(error)
            if ev_available:
                reactors.append("EV")
            else:
                skips.append({"scenario": "reactor_EV", "reason": ev_reason})
        server_index = 0
        saturation = {}
        for repetition in range(1, args.repetitions + 1):
            reactor_order = reactors if repetition % 2 else list(reversed(reactors))
            for reactor in reactor_order:
                groups = sorted(set((cell["workers"], cell["cache_mode"]) for cell in cells))
                if repetition % 2 == 0:
                    groups.reverse()
                for workers, cache_mode in groups:
                    group = [cell for cell in cells if (cell["workers"], cell["cache_mode"]) == (workers, cache_mode)]
                    if deadline - time.monotonic() < args.duration + 12:
                        skips.extend({**cell, "reactor": f"Mojo::Reactor::{reactor}", "repetition": repetition,
                                      "reason": "suite wall-clock deadline"} for cell in group)
                        continue
                    server_index += 1
                    server = None
                    try:
                        server = Server(args.output, reactor, workers, cache_mode, server_index, deadline)
                        for index, cell in enumerate(group):
                            stop_key = (cell["scenario"], reactor, workers)
                            if cell["concurrency"] > saturation.get(stop_key, math.inf) or deadline - time.monotonic() < args.duration + 8:
                                skips.append({**cell, "reactor": server.reactor, "repetition": repetition,
                                              "reason": "stopped after errors/saturation or suite deadline"})
                                continue
                            measurement = {**cell, "generator": generator, "reactor": server.reactor,
                                           "repetition": repetition, "status": "ok",
                                           "evidence_quality": "indicative" if generator == "mojo" else "measured-comparative"}
                            try:
                                runner = wrk_measure if generator == "wrk" else mojo_measure
                                metrics, details = runner(server, cell, args, diagnostics / f"measure-{server_index}-{index}.log", deadline)
                                measurement.update({"metrics": metrics, **details})
                                total = metrics["completed"] + metrics["transport_errors"]
                                errors = metrics["http_errors"] + metrics["transport_errors"]
                                if errors:
                                    measurement["status"] = "failed"
                                    measurement["failure_kind"] = "http_or_transport_errors"
                                    failures.append(f"{cell['scenario']} {reactor}/{workers}/{cell['concurrency']} returned errors")
                                if details.get("validation_error"):
                                    measurement["status"] = "failed"
                                    measurement["failure_kind"] = "infrastructure_or_harness"
                                    failures.append(details["validation_error"])
                                if errors > max(1, total * .01) or metrics["p95_ms"] > 2000:
                                    saturation[stop_key] = min(cell["concurrency"], saturation.get(stop_key, math.inf))
                                measurements.append(measurement)
                                write_json(args.output / "http.json", {"schema_version": 1, "kind": "http",
                                    "status": "partial", "measurements": measurements, "limitations": []})
                                print(f"http {cell['scenario']} {reactor} workers={workers} c={cell['concurrency']} rep={repetition} {measurement['status']} rps={metrics['requests_per_second']:.2f}", flush=True)
                            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, urllib.error.URLError) as error:
                                reason = sanitize(error)
                                failures.append(reason)
                                skips.append({**measurement, "status": "failed", "reason": reason,
                                              "failure_kind": "infrastructure_or_harness"})
                        # Keep the original Mojo generator at one representative
                        # health and heavy endpoint, separate from sustained wrk.
                        if generator == "wrk" and reactor == "Poll" and workers == 2 and cache_mode == "normal":
                            for scenario in ("health_live", "thread"):
                                if deadline - time.monotonic() < 22:
                                    skips.append({"scenario": f"mojo_{scenario}", "reason": "suite deadline"})
                                    continue
                                cell = {"scenario": scenario, "endpoint": SCENARIOS[scenario], "workers": 2,
                                        "concurrency": 10, "cache_mode": "normal"}
                                metrics, details = mojo_measure(server, cell, args, diagnostics / f"mojo-{server_index}-{scenario}.log", deadline)
                                measurements.append({**cell, "generator": "mojo", "reactor": server.reactor,
                                    "repetition": repetition, "status": "failed" if metrics["http_errors"] + metrics["transport_errors"] else "ok",
                                    "evidence_quality": "indicative",
                                    "metrics": metrics, **details})
                                if metrics["http_errors"] + metrics["transport_errors"]:
                                    failures.append(f"Mojo comparison {scenario} returned errors")
                    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, urllib.error.URLError) as error:
                        reason = sanitize(error)
                        failures.append(reason)
                        skips.extend({**cell, "reactor": f"Mojo::Reactor::{reactor}", "repetition": repetition,
                                      "status": "failed", "reason": reason, "failure_kind": "infrastructure_or_harness"} for cell in group)
                    finally:
                        if server:
                            server.close()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        failures.append(sanitize(error))
    status = "failed" if not measurements else "partial" if failures or any("deadline" in skip["reason"] for skip in skips) else "ok"
    limitations = ["Shared runner and load generator share the host; values are comparative evidence, not production capacity.",
        "wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.",
        "RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.",
        "Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.",
        "Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database."]
    if generator != "wrk":
        limitations.append("Independent generator unavailable: fixed-request Mojo rows are indicative, not measured sustained capacity.")
    if measurements:
        write_json(args.output / "http.json", {"schema_version": 1, "kind": "http", "status": status,
            "measurements": measurements, "limitations": limitations})
    suite_status(args.output, status, "; ".join(failures[:5]) or "completed planned HTTP measurements", skips)
    return 1 if failures or not measurements else 0


if __name__ == "__main__":
    sys.exit(main())
