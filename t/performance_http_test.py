#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Parser, bounds and failure tests, without a database or sockets."""
import importlib.util
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("performance_http", Path(__file__).resolve().parents[1] / "script/performance-http.py")
http = importlib.util.module_from_spec(spec)
spec.loader.exec_module(http)


class HttpEvidenceTests(unittest.TestCase):
    def test_wrk_uses_actual_duration_and_all_percentiles(self):
        record = {"completed": 100, "http_errors": 2, "transport_errors": 1,
                  "duration_seconds": 2.001, "requests_per_second": 49.975,
                  "p50_ms": 1.01, "p95_ms": 3.02, "p99_ms": 8.03}
        self.assertEqual(http.parse_wrk("noise\nGPFORUM_WRK " + json.dumps(record) + "\n"), record)

    def test_missing_duplicate_invalid_or_empty_measurements_rejected(self):
        for output in ("", "GPFORUM_WRK {}\n", "GPFORUM_WRK {}\nGPFORUM_WRK {}\n"):
            with self.assertRaises(ValueError):
                http.parse_wrk(output)
        record = {"completed": 0, "http_errors": 0, "transport_errors": 0,
                  "duration_seconds": 1, "requests_per_second": 0,
                  "p50_ms": 0, "p95_ms": 0, "p99_ms": 0}
        with self.assertRaises(ValueError):
            http.parse_wrk("GPFORUM_WRK " + json.dumps(record))

    def test_mojo_separates_http_and_transport_and_real_concurrency(self):
        record = {"completed": 100, "wall_seconds": "1.000", "req_per_sec": "100.000",
                  "p50_ms": "1.0", "p95_ms": "2.0", "p99_ms": "3.0", "peak_inflight": 10,
                  "status_codes": {"200": 96, "503": 3, "error": 1}}
        metrics = http.parse_mojo(json.dumps(record))
        self.assertEqual((metrics["http_errors"], metrics["transport_errors"], metrics["concurrency_effective"]), (3, 1, 10))

    def test_targeted_plan_and_worker_cap(self):
        pr = http.plan("pr", cpu_count=2)
        self.assertEqual(len(pr), 16)
        self.assertEqual({row["workers"] for row in pr}, {2})
        self.assertEqual({row["concurrency"] for row in pr}, {1, 10})
        deep = http.plan("deep", cpu_count=2)
        self.assertNotIn(8, {row["workers"] for row in deep})
        self.assertFalse(any(row["scenario"] == "home" and row["concurrency"] > 50 for row in deep))
        deep8 = http.plan("deep", cpu_count=4)
        self.assertIn(8, {row["workers"] for row in deep8})

    def test_telemetry_requires_every_live_worker_and_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            server = http.Server.__new__(http.Server)
            server.directory = Path(directory)
            server.master = 100
            server.workers = 2
            server.reactor = "Mojo::Reactor::Poll"
            snapshot = {"workers_actual": 2, "worker_pids": [101, 102]}
            http.write_json(server.directory / "worker-101.json", {"pid": 101, "reactor": server.reactor, "ev_backend": None})
            with patch.object(http, "process_snapshot", return_value=snapshot):
                with self.assertRaisesRegex(RuntimeError, "some serving workers"):
                    server.telemetry()
                http.write_json(server.directory / "worker-102.json", {"pid": 102, "reactor": server.reactor, "ev_backend": None})
                self.assertEqual(len(server.telemetry()), 2)
                http.write_json(server.directory / "worker-102.json", {"pid": 102, "reactor": "Mojo::Reactor::EV", "ev_backend": 4})
                with self.assertRaisesRegex(RuntimeError, "did not match"):
                    server.telemetry()

    def test_dry_run_creates_only_explicit_skip_state(self):
        with tempfile.TemporaryDirectory() as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(http.main(["--output", directory, "--dry-run"]), 0)
            state = json.loads((Path(directory) / "suite-status.json").read_text())
            self.assertEqual(state["http"]["status"], "skipped")
            self.assertFalse((Path(directory) / "http.json").exists())

    def test_refuses_persistent_application_database(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum"}):
            result = http.main(["--output", directory, "--disposable-database"])
            self.assertEqual(result, 2)
            self.assertFalse((Path(directory) / "http.json").exists())
            self.assertEqual(json.loads((Path(directory) / "suite-status.json").read_text())["http"]["status"], "failed")

    def test_failed_preparation_has_no_fake_data_and_preserves_other_suites(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}), patch.object(http, "prepare_dataset", side_effect=RuntimeError("database unavailable")):
            http.write_json(Path(directory) / "suite-status.json", {"database": {"status": "ok"}})
            result = http.main(["--output", directory, "--disposable-database", "--generator", "mojo"])
            self.assertEqual(result, 1)
            state = json.loads((Path(directory) / "suite-status.json").read_text())
            self.assertEqual(state["database"]["status"], "ok")
            self.assertEqual(state["http"]["status"], "failed")
            self.assertIn("database unavailable", state["http"]["reason"])
            self.assertFalse((Path(directory) / "http.json").exists())

    def test_metrics_do_not_record_passwords(self):
        with patch.dict(os.environ, {"GPFORUM_DATABASE_PASSWORD": "canary-password"}):
            self.assertNotIn("canary-password", http.sanitize("DBI password=canary-password; URI postgresql://user:otherpassword@localhost"))
            self.assertNotIn("otherpassword", http.sanitize("URI postgresql://user:otherpassword@localhost"))

    def test_ci_password_substring_cannot_hide_uri_credentials(self):
        with patch.dict(os.environ, {"GPFORUM_DATABASE_PASSWORD": "canary-password", "PGPASSWORD": "postgres"}):
            for scheme in ("postgres://", "postgresql://"):
                sanitized = http.sanitize(f"DBI password=canary-password; URI {scheme}user:otherpassword@localhost")
                self.assertNotIn("canary-password", sanitized)
                self.assertNotIn("otherpassword", sanitized)
                self.assertNotIn("user:", sanitized)

    def test_fixture_password_does_not_corrupt_structured_json_keys(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_PASSWORD": "postgres"}):
            log = Path(directory) / "metadata.log"
            output = http.run_command(["python3", "-c", "print('{\"postgres\":\"16.4\"}')"], 2, log)
            self.assertEqual(json.loads(output)["postgres"], "16.4")
            self.assertNotIn("postgres", log.read_text())

    def test_command_deadline_kills_children(self):
        with self.assertRaisesRegex(RuntimeError, "deadline"):
            http.run_command(["python3", "-c", "import time; time.sleep(5)"], .05)

    def test_tool_version_can_explicitly_accept_documented_exit_one(self):
        output = http.run_command(["python3", "-c", "print('tool 1.0'); raise SystemExit(1)"], 2, accepted_codes=(0, 1))
        self.assertEqual(output.strip(), "tool 1.0")
        with self.assertRaisesRegex(RuntimeError, "exit 1"):
            http.run_command(["python3", "-c", "raise SystemExit(1)"], 2)
        with patch.object(http, "run_command", return_value="wrk 4.2.0 [kqueue]\nUsage: wrk"):
            self.assertEqual(http.wrk_version(), "wrk 4.2.0 [kqueue]")
        with patch.object(http, "run_command", return_value="Usage: wrk"), self.assertRaises(ValueError):
            http.wrk_version()

    def test_ubuntu_wrk_banner_uses_actual_distribution_package(self):
        with patch.object(http, "run_command", side_effect=["wrk  Copyright (C) 2012 Will Glozer\nUsage: wrk <options> <url>", "4.1.0-5build2"]), patch.object(http.shutil, "which", return_value="/usr/bin/dpkg-query"):
            self.assertEqual(http.wrk_version(), "wrk (distribution package 4.1.0-5build2; CLI upstream unspecified)")

    def test_wrk_version_logs_banner_and_does_not_invent_an_upstream_release(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(http, "run_command", return_value="wrk unspecified Copyright (C) 2012 Will Glozer") as command, patch.object(http.shutil, "which", return_value=None):
            self.assertEqual(http.wrk_version(directory), "wrk (CLI upstream version unspecified; distribution package unavailable)")
            self.assertEqual(command.call_args.kwargs["log"], Path(directory) / "wrk-version.log")
        with patch.object(http, "run_command", return_value="another-tool 4.2.0"), self.assertRaises(ValueError):
            http.wrk_version()

    def test_dataset_provenance_survives_unidentifiable_primary_wrk(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}), patch.object(http, "prepare_dataset", return_value=({"signature": "known-seed", "counts": {"posts": 4800}}, {"postgres": "16.4", "database_settings": {"work_mem": "4MB"}})), patch.object(http, "run_command", return_value='{"perl":"v5.40","mojolicious":"9.49"}'), patch.object(http.shutil, "which", return_value="/fake/wrk"), patch.object(http, "wrk_version", side_effect=ValueError("unidentifiable wrk")):
            result = http.main(["--output", directory, "--disposable-database", "--generator", "wrk"])
            self.assertEqual(result, 1)
            environment = json.loads((Path(directory) / "http-environment.json").read_text())
            self.assertEqual(environment["dataset"]["counts"]["posts"], 4800)
            self.assertEqual(environment["versions"]["postgres"], "16.4")
            self.assertEqual(environment["versions"]["perl"], "v5.40")
            self.assertIsNone(environment["versions"]["wrk"])
            self.assertFalse((Path(directory) / "http.json").exists())

    def test_default_reactor_probe_cleans_only_its_environment_and_records_selection(self):
        runtime = {"perl": "v5.40", "mojolicious": "9.49", "ev": "4.33",
                   "default_reactor": "Mojo::Reactor::EV", "default_ev_backend": 4}
        inherited = {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test",
                     "MOJO_REACTOR": "Mojo::Reactor::Poll", "LIBEV_FLAGS": "2",
                     "GPFORUM_TEST_ENV_PRESERVED": "runtime-probe"}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, inherited), patch.object(http, "prepare_dataset", return_value=({"signature": "known-seed"}, {"postgres": "16.4", "database_settings": {}})), patch.object(http, "run_command", return_value=json.dumps(runtime)) as command, patch.object(http.shutil, "which", return_value="/fake/wrk"), patch.object(http, "wrk_version", side_effect=ValueError("unidentifiable wrk")):
            self.assertEqual(http.main(["--output", directory, "--disposable-database", "--generator", "wrk"]), 1)
            probe_env = command.call_args.kwargs["env"]
            self.assertNotIn("MOJO_REACTOR", probe_env)
            self.assertNotIn("LIBEV_FLAGS", probe_env)
            self.assertEqual(probe_env["GPFORUM_TEST_ENV_PRESERVED"], "runtime-probe")
            self.assertEqual(os.environ["MOJO_REACTOR"], "Mojo::Reactor::Poll")
            self.assertEqual(os.environ["LIBEV_FLAGS"], "2")
            environment = json.loads((Path(directory) / "http-environment.json").read_text())
            self.assertEqual(environment["configuration"]["default_reactor"], "Mojo::Reactor::EV")
            self.assertEqual(environment["configuration"]["default_ev_backend"], 4)
            self.assertNotIn("default_reactor", environment["versions"])
            self.assertNotIn("default_ev_backend", environment["versions"])
            self.assertEqual(environment["versions"]["perl"], "v5.40")
            self.assertEqual(environment["versions"]["ev"], "4.33")

    def test_explicit_mojo_ignores_unusable_optional_wrk_probe(self):
        class FakeServer:
            def __init__(self, output, reactor, workers, cache_mode, index, deadline):
                self.reactor = "Mojo::Reactor::" + reactor
            def close(self):
                pass
        metrics = {"completed": 100, "http_errors": 0, "transport_errors": 0,
                   "duration_seconds": 1, "requests_per_second": 100,
                   "p50_ms": 1, "p95_ms": 2, "p99_ms": 3,
                   "cpu_percent": None, "rss_bytes": None, "concurrency_effective": 10}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}), patch.object(http, "prepare_dataset", return_value=({"signature": "known-seed"}, {"postgres": "16.4", "database_settings": {}})), patch.object(http, "run_command", return_value='{"perl":"v5.40","mojolicious":"9.49"}'), patch.object(http.shutil, "which", return_value="/fake/wrk"), patch.object(http, "wrk_version", side_effect=ValueError("unidentifiable optional wrk")), patch.object(http, "Server", FakeServer), patch.object(http, "mojo_measure", return_value=(metrics, {"workers_actual": 2})), contextlib.redirect_stdout(io.StringIO()):
            result = http.main(["--output", directory, "--disposable-database", "--generator", "mojo", "--concurrency", "10"])
            self.assertEqual(result, 0)
            self.assertEqual(len(json.loads((Path(directory) / "http.json").read_text())["measurements"]), 24)
            state = json.loads((Path(directory) / "suite-status.json").read_text())
            self.assertTrue(any("unused optional wrk" in row["reason"] for row in state["http"]["skipped"]))

    def test_distribution_version_fallback_fingerprints_installed_binary(self):
        class FakeServer:
            def __init__(self, output, reactor, workers, cache_mode, index, deadline):
                self.reactor = "Mojo::Reactor::" + reactor
            def close(self):
                pass
        metrics = {"completed": 100, "http_errors": 0, "transport_errors": 0,
                   "duration_seconds": 1, "requests_per_second": 100,
                   "p50_ms": 1, "p95_ms": 2, "p99_ms": 3,
                   "cpu_percent": None, "rss_bytes": None, "concurrency_effective": 10}
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "wrk"
            binary.write_bytes(b"simulated distribution executable")
            with patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}), patch.object(http, "prepare_dataset", return_value=({"signature": "known-seed"}, {"postgres": "16.4", "database_settings": {}})), patch.object(http, "run_command", return_value='{"perl":"v5.40","mojolicious":"9.49"}'), patch.object(http.shutil, "which", return_value=str(binary)), patch.object(http, "wrk_version", return_value="wrk (distribution package 4.1.0-5build2; CLI upstream unspecified)"), patch.object(http, "Server", FakeServer), patch.object(http, "mojo_measure", return_value=(metrics, {"workers_actual": 2})), contextlib.redirect_stdout(io.StringIO()):
                result = http.main(["--output", directory, "--disposable-database", "--generator", "mojo", "--concurrency", "10"])
            self.assertEqual(result, 0)
            environment = json.loads((Path(directory) / "http-environment.json").read_text())
            self.assertEqual(environment["configuration"]["wrk_binary_sha256"], hashlib.sha256(binary.read_bytes()).hexdigest())
            self.assertFalse(environment["configuration"]["wrk_upstream_version_verified"])

    def test_numeric_overrides_are_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            for option, value in (("--duration", "0"), ("--duration", "31"), ("--repetitions", "6"), ("--deadline", "1801"), ("--concurrency", "1000")):
                with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                    http.main(["--output", directory, "--dry-run", option, value])

    def test_real_data_survives_one_failed_cell(self):
        class FakeServer:
            def __init__(self, output, reactor, workers, cache_mode, index, deadline):
                self.reactor = "Mojo::Reactor::" + reactor
            def close(self):
                pass

        metrics = {"completed": 100, "http_errors": 0, "transport_errors": 0,
                   "duration_seconds": 1, "requests_per_second": 100,
                   "p50_ms": 1, "p95_ms": 2, "p99_ms": 3,
                   "cpu_percent": None, "rss_bytes": None, "concurrency_effective": 10}
        calls = 0
        def measure(*args):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise RuntimeError("one endpoint unavailable")
            return dict(metrics), {"workers_actual": 2}

        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}), patch.object(http, "prepare_dataset", return_value=({"signature": "test"}, {"postgres": "16.4", "database_settings": {}})), patch.object(http, "run_command", return_value='{"perl":"v5.40","mojolicious":"9.49"}'), patch.object(http.shutil, "which", return_value=None), patch.object(http, "Server", FakeServer), patch.object(http, "mojo_measure", side_effect=measure), contextlib.redirect_stdout(io.StringIO()):
            result = http.main(["--output", directory, "--disposable-database", "--generator", "mojo", "--concurrency", "10"])
            self.assertEqual(result, 1)
            data = json.loads((Path(directory) / "http.json").read_text())
            self.assertEqual(data["status"], "partial")
            self.assertEqual(len(data["measurements"]), 23)
            self.assertTrue(all(row["evidence_quality"] == "indicative" for row in data["measurements"]))
            state = json.loads((Path(directory) / "suite-status.json").read_text())
            self.assertTrue(any(row.get("status") == "failed" for row in state["http"]["skipped"]))

    def test_failed_optional_ev_probe_keeps_poll_measurements(self):
        class FakeServer:
            def __init__(self, output, reactor, workers, cache_mode, index, deadline):
                self.reactor = "Mojo::Reactor::" + reactor
            def close(self):
                pass
        metrics = {"completed": 100, "http_errors": 0, "transport_errors": 0,
                   "duration_seconds": 1, "requests_per_second": 100,
                   "p50_ms": 1, "p95_ms": 2, "p99_ms": 3,
                   "cpu_percent": None, "rss_bytes": None, "concurrency_effective": 10}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}), patch.object(http, "prepare_dataset", return_value=({"signature": "test"}, {"postgres": "16.4", "database_settings": {}})), patch.object(http, "run_command", return_value='{"perl":"v5.40","mojolicious":"9.49"}'), patch.object(http.shutil, "which", return_value=None), patch.object(http.platform, "system", return_value="Linux"), patch.object(http, "probe_reactor", side_effect=RuntimeError("EV unavailable")), patch.object(http, "Server", FakeServer), patch.object(http, "mojo_measure", return_value=(metrics, {"workers_actual": 2})), contextlib.redirect_stdout(io.StringIO()):
            result = http.main(["--output", directory, "--mode", "main", "--disposable-database", "--generator", "mojo", "--concurrency", "10"])
            self.assertEqual(result, 0)
            data = json.loads((Path(directory) / "http.json").read_text())
            self.assertEqual(data["status"], "ok")
            self.assertEqual(len(data["measurements"]), 24)
            self.assertEqual({row["reactor"] for row in data["measurements"]}, {"Mojo::Reactor::Poll"})
            state = json.loads((Path(directory) / "suite-status.json").read_text())
            self.assertTrue(any("EV unavailable" in row["reason"] for row in state["http"]["skipped"]))


if __name__ == "__main__":
    unittest.main()
