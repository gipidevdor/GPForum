#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Failure/skip/baseline/publication evidence contracts, without a server."""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("evidence", ROOT / "script/performance-evidence.py")
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_outbox_support_is_triggered_and_baseline_fingerprinted(self):
        metadata = evidence.initial("main", "a" * 40)
        workflow = (ROOT / ".github/workflows/performance.yml").read_text()
        for path in ("t/lib/GPForum/Test/PostgresHarness.pm", "t/lib/GPForum/Test/OutboxTransport.pm"):
            with self.subTest(path=path):
                self.assertIn("- '" + path + "'", workflow)
                self.assertEqual(metadata["configuration"]["harness_sha256"][path],
                                 hashlib.sha256((ROOT / path).read_bytes()).hexdigest())
                changed = copy.deepcopy(metadata)
                changed["configuration"]["harness_sha256"][path] = "0" * 64
                self.assertNotEqual(evidence.compatible_signature(metadata), evidence.compatible_signature(changed))

    def run_data(self, name, rps=100, status="ok", count=3):
        output = self.root / name
        metadata = evidence.initial("pr", ("a" if name == "base" else "b") * 40)
        metadata["versions"] = {"perl": "5.40", "mojolicious": "9.49", "postgres": "16"}
        metadata["dataset"] = {"profile": "small", "threads": 12, "posts": 96}
        evidence.write(output / "metadata.json", metadata)
        rows = [{"scenario": "health-live", "endpoint": "/health/live", "generator": "wrk", "reactor": "Mojo::Reactor::Poll",
                 "workers": 2, "concurrency": 10, "repetition": i + 1, "status": status,
                 "metrics": {"requests_per_second": rps + i, "p50_ms": 1, "p95_ms": 5, "p99_ms": 9,
                             "completed": 200, "http_errors": 0 if status == "ok" else 20, "transport_errors": 0, "duration_seconds": 2,
                             "cpu_percent": None, "rss_bytes": 12345678}} for i in range(count)]
        evidence.write(output / "http.json", {"schema_version": 1, "kind": "http", "status": status, "measurements": rows, "limitations": []})
        for kind in ("database", "outbox"):
            evidence.write(output / (kind + ".json"), {"schema_version": 1, "kind": kind, "status": "ok", "measurements": [{"scenario": "check", "status": "ok", "metrics": {"statements": 2}}], "limitations": []})
        return output

    def test_success_report_and_provenance(self):
        output = self.run_data("success")
        result = evidence.finalize(output)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["measurements"][0]["comparison"]["classification"], "not-comparable")
        self.assertTrue(evidence.validate(output))
        self.assertIn("Mojo::Reactor::Poll", (output / "report.md").read_text())
        self.assertEqual(evidence.read(output / "http.json")["provenance"]["commit"], "b" * 40)

    def test_failure_is_saved_not_passed(self):
        result = evidence.finalize(self.run_data("failure", status="failed"))
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["measurements"][0]["metrics"], {})

    def test_worker_comparison_report_and_complete_provenance(self):
        output = self.run_data("workers")
        payload = evidence.read(output / "http.json")
        scaled = copy.deepcopy(payload["measurements"])
        for row in scaled:
            row["workers"] = 4
            row["metrics"]["requests_per_second"] *= 2
        payload["measurements"].extend(scaled)
        evidence.write(output / "http.json", payload)
        evidence.finalize(output)
        workers = evidence.read(output / "workers.json")
        self.assertEqual(workers["status"], "ok")
        self.assertEqual(len(workers["differences"]), 1)
        self.assertEqual(workers["differences"][0]["comparison"]["classification"], "improvement")
        self.assertEqual(workers["provenance"]["run_id"], evidence.read(output / "metadata.json")["run_id"])
        self.assertEqual(evidence.read(output / "reactor.json")["status"], "partial")
        self.assertIn("workers=4", (output / "report.md").read_text())

    def test_empty_skip_produces_no_measurement_files(self):
        output = self.root / "skip"
        evidence.write(output / "metadata.json", evidence.initial("pr"))
        evidence.write(output / "suite-status.json", {"http": {"status": "skipped", "reason": "wrk unavailable"}})
        result = evidence.finalize(output)
        self.assertEqual(result["status"], "skipped")
        self.assertFalse((output / "http.json").exists())
        self.assertFalse((output / "reactor.json").exists())
        self.assertIn("wrk unavailable", (output / "report.md").read_text())

    def test_confirmed_regression_repeated(self):
        base = self.run_data("base")
        evidence.finalize(base)
        result = evidence.finalize(self.run_data("current", rps=70), base)
        comparison = result["measurements"][0]["comparison"]
        self.assertEqual(comparison["classification"], "confirmed-regression")
        self.assertAlmostEqual(comparison["deltas_pct"]["requests_per_second"], -29.703, places=3)
        self.assertEqual(result["status"], "ok", "advisory timing does not fail the job")

    def test_single_run_never_confirms(self):
        base = self.run_data("base")
        evidence.finalize(base)
        result = evidence.finalize(self.run_data("current", rps=40, count=1), base)
        self.assertEqual(result["measurements"][0]["comparison"]["classification"], "possible-regression")

    def test_noise_robust_stable_and_improved(self):
        base = self.run_data("base")
        evidence.finalize(base)
        stable = evidence.finalize(self.run_data("stable", rps=103), base)
        self.assertEqual(stable["measurements"][0]["comparison"]["classification"], "stable")
        improved = evidence.finalize(self.run_data("improved", rps=140), base)
        self.assertEqual(improved["measurements"][0]["comparison"]["classification"], "improvement")

    def test_incompatible_runner_rejects_baseline(self):
        base = self.run_data("base")
        evidence.finalize(base)
        current = self.run_data("current", rps=40)
        metadata = evidence.read(current / "metadata.json")
        metadata["runner"]["cpu_count"] = 333
        evidence.write(current / "metadata.json", metadata)
        result = evidence.finalize(current, base)
        self.assertEqual(result["measurements"][0]["comparison"]["classification"], "not-comparable")

    def test_malformed_nonfinite_and_sensitive_data_rejected(self):
        output = self.run_data("success")
        evidence.finalize(output)
        payload = evidence.read(output / "http.json")
        for corrupt in ("negative", "secret", "missing"):
            changed = copy.deepcopy(payload)
            if corrupt == "negative":
                changed["measurements"][0]["metrics"]["p95_ms"] = -1
            elif corrupt == "secret":
                changed["password"] = "oops"
            else:
                del changed["measurements"][0]["status"]
            evidence.write(output / "http.json", changed)
            with self.assertRaises(ValueError):
                evidence.validate(output)
        (output / "http.json").write_text('{"v": NaN}')
        with self.assertRaises(ValueError):
            evidence.validate(output)

    def test_malformed_benchmark_preserves_other_results(self):
        output = self.run_data("success")
        (output / "database.json").write_text('{"password":"test-value", BROKEN}')
        result = evidence.finalize(output)
        self.assertEqual(result["status"], "failed")
        self.assertFalse((output / "database.json").exists())
        self.assertTrue((output / "http.json").exists())
        self.assertIn("infrastructure_or_harness", json.dumps(result))
        diagnostic = (output / "diagnostics/database-invalid.log").read_text()
        self.assertNotIn("test-value", diagnostic)
        self.assertTrue(evidence.validate(output))

    def test_history_immutable_repeated_commit_partial_not_latest(self):
        # Copy two independently recorded runs to the publisher's canonical paths.
        for attempt in ("1", "2"):
            output = self.root / "benchmarks/results/2026-10-11" / ("b" * 40) / ("77-" + attempt)
            source = self.run_data("run" + attempt)
            # Construct here without depending on directory copy helpers.
            output.mkdir(parents=True)
            for file in source.glob("*.json"):
                (output / file.name).write_bytes(file.read_bytes())
            metadata = evidence.read(output / "metadata.json")
            metadata.update(run_id="77", run_attempt=attempt)
            evidence.write(output / "metadata.json", metadata)
            evidence.finalize(output)
        historical = list((self.root / "benchmarks/results").glob("**/*.json"))
        before = {str(p): p.read_bytes() for p in historical}
        evidence.index(self.root)
        self.assertEqual(len(evidence.read(self.root / "benchmarks/history.json")["runs"]), 2)
        self.assertEqual(evidence.read(self.root / "benchmarks/latest.json")["run"]["run_attempt"], "2")
        evidence.index(self.root)
        self.assertEqual(before, {str(p): p.read_bytes() for p in historical})

        partial = self.run_data("partial")
        evidence.write(partial / "workflow-status.json", {"http": {"status": "partial", "reason": "suite deadline"}})
        evidence.finalize(partial)
        destination = self.root / "benchmarks/results/2026-10-11" / ("b" * 40) / "78-1"
        destination.parent.mkdir(parents=True, exist_ok=True)
        partial.rename(destination)
        evidence.index(self.root)
        self.assertEqual(evidence.read(self.root / "benchmarks/latest.json")["run"]["run_id"], "77")
        self.assertEqual(len(evidence.read(self.root / "benchmarks/history.json")["runs"]), 3)


if __name__ == "__main__":
    unittest.main()
