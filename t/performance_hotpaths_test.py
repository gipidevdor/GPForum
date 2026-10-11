# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("hotpaths", Path(__file__).resolve().parents[1] / "script/performance-hotpaths.py")
hotpaths = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hotpaths)


class HotpathsTest(unittest.TestCase):
    def fixture_runner(self, failures=()):
        def run(command, output, name, **kwargs):
            payload = None
            code = 1 if any(name.startswith(prefix) for prefix in failures) else 0
            if name == "query-budget":
                payload = {"status": "ok" if code == 0 else "fail", "missing": []}
            if name.startswith("query-plan-") and name != "query-plan-static":
                payload = {"status": "ok" if code == 0 else "fail", "endpoints": [
                    {"endpoint": "home", "status": "ok" if code == 0 else "fail", "sql_label": "threads_public_activity",
                     "summary": {"actual_time_ms": 0.2, "actual_rows": 25}, "violations": [], "warnings": [], "plan": "bulky"}]}
            if name == "outbox-postgres":
                payload = {"status": "ok" if code == 0 else "fail", "results": [
                    {"workers": 1, "repetition": 1, "status": "ok" if code == 0 else "fail",
                     "messages_per_second": 2000, "duration_seconds": 0.5, "delivered": 1000,
                     "lost": 0, "duplicates": 0, "acknowledged": 1000}]}
            if name == "sql-functions":
                payload = {"operations": {"search": {"function": {"direct": {"median_ms": 1, "p95_ms": 2,
                                                                                "statements": 1, "round_trips": 1}}}}}
            return {"payload": payload, "exit_code": code, "duration_seconds": 0.1,
                    "timed_out": False, "diagnostic": "diagnostics/" + name + ".log"}
        return run

    def test_missing_database_is_explicit_skip(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            self.assertEqual(hotpaths.collect(directory, "pr", runner=self.fixture_runner()), 0)
            status = json.loads((Path(directory) / "hotpaths-status.json").read_text())
            self.assertEqual(status["database"]["status"], "skipped")
            self.assertTrue(any(row["status"] == "skipped" for row in status.values()))
            self.assertFalse((Path(directory) / "database.json").exists())
            self.assertFalse((Path(directory) / "outbox.json").exists())

    def test_disposable_guard(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}):
            with self.assertRaisesRegex(ValueError, "disposable-database"):
                hotpaths.collect(directory, "pr", runner=self.fixture_runner())

    def test_suite_deadline_skips_remaining_commands(self):
        def never(*args, **kwargs):
            self.fail("A command executed after the suite deadline")
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}):
            self.assertEqual(hotpaths.collect(directory, "deep", True, never, deadline=0), 0)
            status = json.loads((Path(directory) / "hotpaths-status.json").read_text())
            self.assertTrue(all(row["status"] == "skipped" for row in status.values()))
            self.assertEqual(status["database-plans-functions"]["skipped_repetitions"], 3)
            self.assertFalse((Path(directory) / "database.json").exists())
            self.assertFalse((Path(directory) / "outbox.json").exists())

    def test_application_database_name_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum"}):
            with self.assertRaisesRegex(ValueError, "dedicated gpforum_perf"):
                hotpaths.collect(directory, "pr", True, self.fixture_runner())

    def test_success_normalizes_and_excludes_full_plans(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}):
            self.assertEqual(hotpaths.collect(directory, "main", True, self.fixture_runner()), 0)
            payload = json.loads((Path(directory) / "database.json").read_text())
            self.assertEqual(payload["status"], "ok")
            plans = [row for row in payload["measurements"] if row["scenario"].startswith("sql-plan")]
            self.assertEqual(len(plans), 6)
            self.assertEqual(plans[0]["metrics"]["sql_execution_ms"], 0.2)
            self.assertNotIn("plan", plans[0]["evidence"])
            self.assertEqual(json.loads((Path(directory) / "outbox.json").read_text())["measurements"][0]["metrics"]["lost"], 0)

    def test_failure_preserves_partial_data(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}):
            self.assertEqual(hotpaths.collect(directory, "pr", True, self.fixture_runner(("query-plan-functions",))), 1)
            payload = json.loads((Path(directory) / "database.json").read_text())
            self.assertEqual(payload["status"], "partial")
            self.assertTrue(any(row["status"] == "failed" for row in payload["measurements"]))
            self.assertTrue((Path(directory) / "outbox.json").exists())

    def test_deep_unavailable_profiler_is_not_pass(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"GPFORUM_DATABASE_DSN": "dbi:Pg:dbname=gpforum_perf_test"}):
            self.assertEqual(hotpaths.collect(directory, "deep", True, self.fixture_runner(("nytprof-availability",))), 0)
            status = json.loads((Path(directory) / "hotpaths-status.json").read_text())
            self.assertEqual(status["profiling"]["status"], "skipped")
            payload = json.loads((Path(directory) / "database.json").read_text())
            self.assertTrue(any(row["scenario"] == "sql-function-service-function-direct" for row in payload["measurements"]))

    def test_subprocess_parses_before_diagnostic_redaction(self):
        with tempfile.TemporaryDirectory() as directory:
            result = hotpaths.execute(["python3", "-c", 'print(\'{"postgres": "18", "status": "ok", "error": "password=postgres"}\')'],
                                      Path(directory), "redaction", env=dict(os.environ, GPFORUM_DATABASE_PASSWORD="postgres"))
            self.assertEqual(result["payload"]["postgres"], "18")
            self.assertNotIn("postgres", result["payload"]["error"])
            self.assertNotIn("postgres", (Path(directory) / result["diagnostic"]).read_text())

    def test_timeout_has_diagnostic_and_no_invented_data(self):
        with tempfile.TemporaryDirectory() as directory:
            result = hotpaths.execute(["python3", "-c", "import time; time.sleep(5)"], Path(directory), "timeout", timeout=0.01)
            self.assertTrue(result["timed_out"])
            self.assertIsNone(result["payload"])
            self.assertNotEqual(result["exit_code"], 0)


if __name__ == "__main__":
    unittest.main()
