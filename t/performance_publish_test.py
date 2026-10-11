#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Immutable, bounded, data-only publication using local Git remotes."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "script" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


publisher = load("publisher", "performance-publish.py")
workflow = load("workflow", "performance-workflow-status.py")
evidence = publisher.evidence


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.remote = self.root / "remote.git"
        subprocess.run(["git", "init", "--quiet", "--bare", str(self.remote)], check=True)
        checkout = self.root / "application"
        checkout.mkdir()
        subprocess.run(["git", "init", "--quiet", "--initial-branch", "main"], cwd=checkout, check=True)
        (checkout / "application.pl").write_text("# application source must be preserved\n")
        subprocess.run(["git", "add", "application.pl"], cwd=checkout, check=True)
        subprocess.run(["git", "-c", "user.name=Test Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Initial application"], cwd=checkout, check=True)
        subprocess.run(["git", "push", "--quiet", str(self.remote), "main"], cwd=checkout, check=True)

    def tearDown(self):
        self.temporary.cleanup()

    def sample(self, run="77", attempt="1"):
        source = self.root / (run + "-" + attempt)
        metadata = evidence.initial("main", "a" * 40)
        metadata.update(run_id=run, run_attempt=attempt)
        evidence.write(source / "metadata.json", metadata)
        evidence.write(source / "workflow-status.json", {"http": {"status": "skipped", "reason": "Infrastructure test fixture"}})
        evidence.finalize(source)
        return source

    def clone(self):
        destination = self.root / "results"
        subprocess.run(["git", "clone", "--quiet", "--branch", publisher.BRANCH, str(self.remote), str(destination)], check=True)
        return destination

    def test_first_publish_repeat_attempt_and_data_allowlist(self):
        first = self.sample()
        (first / "diagnostics").mkdir()
        (first / "diagnostics/secret.log").write_text("never publish raw logs")
        (first / "danger.py").write_text("raise Exception('must never run')")
        (first / "report.md").write_text("<script>untrusted markup</script>")
        relative = publisher.publish(first, str(self.remote), "a" * 40, "77", "1")
        publisher.publish(first, str(self.remote), "a" * 40, "77", "1")
        publisher.publish(self.sample(attempt="2"), str(self.remote))
        clone = self.clone()
        self.assertTrue((clone / relative / "summary.json").exists())
        self.assertNotIn("untrusted markup", (clone / relative / "report.md").read_text())
        self.assertFalse((clone / relative / "diagnostics").exists())
        self.assertFalse((clone / relative / "danger.py").exists())
        history = evidence.read(clone / "benchmarks/history.json")
        self.assertEqual(len(history["runs"]), 2)
        self.assertIsNone(evidence.read(clone / "benchmarks/latest.json")["run"])
        self.assertEqual((clone / "application.pl").read_text(), "# application source must be preserved\n")
        commits = subprocess.check_output(["git", "log", "--format=%s"], cwd=clone, text=True)
        self.assertIn("Initial application", commits)

    def test_historical_overwrite_rejected(self):
        source = self.sample()
        publisher.publish(source, str(self.remote))
        metadata = evidence.read(source / "metadata.json")
        metadata["limitations"].append("changed contents")
        evidence.write(source / "metadata.json", metadata)
        evidence.finalize(source)
        with self.assertRaisesRegex(ValueError, "refusing overwrite"):
            publisher.publish(source, str(self.remote))

    def test_provenance_path_and_symlink_rejected(self):
        source = self.sample()
        with self.assertRaisesRegex(ValueError, "triggering run"):
            publisher.manifest(source, "b" * 40)
        metadata = evidence.read(source / "metadata.json")
        metadata["run_id"] = "../escape"
        evidence.write(source / "metadata.json", metadata)
        with self.assertRaises(ValueError):
            publisher.manifest(source)
        source = self.sample(run="88")
        (source / "report.md").unlink()
        (source / "report.md").symlink_to(source / "metadata.json")
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            publisher.manifest(source)

    def test_pr_cannot_publish_and_tokens_not_in_git_config(self):
        source = self.sample()
        metadata = evidence.read(source / "metadata.json")
        metadata["mode"] = "pr"
        evidence.write(source / "metadata.json", metadata)
        evidence.finalize(source)
        with self.assertRaisesRegex(ValueError, "main/deep"):
            publisher.manifest(source)
        token = "fixture-token-for-environment-only"
        publisher.publish(self.sample(run="88"), str(self.remote), token=token)
        clone = self.clone()
        self.assertNotIn(token, (clone / ".git/config").read_text())
        self.assertNotIn("AUTHORIZATION", (clone / ".git/config").read_text())

    def test_measurement_provenance_cannot_disagree_with_run(self):
        source = self.sample()
        evidence.write(source / "http.json", {"schema_version": 1, "kind": "http", "status": "ok", "measurements": [{"scenario": "health_live", "endpoint": "/health/live", "generator": "wrk", "reactor": "Mojo::Reactor::Poll", "workers": 2, "concurrency": 1, "repetition": 1, "status": "ok", "metrics": {"requests_per_second": 100, "completed": 200, "http_errors": 0, "transport_errors": 0, "duration_seconds": 2, "p50_ms": 1, "p95_ms": 2, "p99_ms": 3}}], "limitations": []})
        evidence.finalize(source)
        data = evidence.read(source / "http.json")
        data["provenance"]["commit"] = "b" * 40
        evidence.write(source / "http.json", data)
        with self.assertRaisesRegex(ValueError, "Measurement provenance"):
            publisher.manifest(source)

    def test_push_conflict_retries_without_force(self):
        source = self.sample()
        original = publisher.git
        pushes = []

        def transient(directory, *arguments, **kwargs):
            if arguments[0] == "push":
                pushes.append(arguments)
                if len(pushes) == 1:
                    return subprocess.CompletedProcess(arguments, 1, "", "simulated concurrent push")
            return original(directory, *arguments, **kwargs)

        with patch.object(publisher, "git", side_effect=transient):
            publisher.publish(source, str(self.remote))
        self.assertEqual(len(pushes), 2)
        self.assertFalse(any("--force" in arguments for arguments in pushes))

    def test_actual_concurrent_push_preserves_each_run(self):
        first = self.sample(run="60")
        relative = publisher.publish(first, str(self.remote))
        source = self.sample(run="61")
        competitor = self.sample(run="62")
        original = publisher.git
        raced = False

        def concurrent(directory, *arguments, **kwargs):
            nonlocal raced
            if arguments[0] == "push" and not raced:
                raced = True
                publisher.publish(competitor, str(self.remote))
            return original(directory, *arguments, **kwargs)

        with patch.object(publisher, "git", side_effect=concurrent):
            publisher.publish(source, str(self.remote))
        clone = self.clone()
        self.assertEqual(len(evidence.read(clone / "benchmarks/history.json")["runs"]), 3)
        _, expected = publisher.manifest(first)
        self.assertEqual({p.name: p.read_bytes() for p in (clone / relative).iterdir()}, expected)

    def test_destination_symlink_cannot_escape_results_tree(self):
        source = self.sample()
        relative, payload = publisher.manifest(source)
        checkout = self.root / "checkout"
        checkout.mkdir()
        (checkout / "benchmarks").symlink_to(source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            publisher.append_result(checkout, relative, payload)

    def test_failed_push_is_bounded_and_artifact_preserved(self):
        source = self.sample()
        original = publisher.git
        pushes = []

        def rejected(directory, *arguments, **kwargs):
            if arguments[0] == "push":
                pushes.append(arguments)
                return subprocess.CompletedProcess(arguments, 1, "", "branch policy denied")
            return original(directory, *arguments, **kwargs)

        with patch.object(publisher, "git", side_effect=rejected):
            with self.assertRaisesRegex(RuntimeError, "bounded retries"):
                publisher.publish(source, str(self.remote), attempts=3)
        self.assertEqual(len(pushes), 3)
        self.assertTrue((source / "summary.json").exists())

    def test_missing_main_branch_cannot_create_an_orphan(self):
        remote = self.root / "empty.git"
        subprocess.run(["git", "init", "--quiet", "--bare", str(remote)], check=True)
        with self.assertRaisesRegex(RuntimeError, "refusing to initialize"):
            publisher.publish(self.sample(), str(remote))
        refs = subprocess.check_output(["git", "show-ref"], cwd=remote, text=True) if subprocess.run(["git", "show-ref"], cwd=remote, capture_output=True).returncode == 0 else ""
        self.assertEqual(refs, "")

    def test_setup_failure_and_absent_benchmarks_are_explicit(self):
        values = workflow.statuses({"PERF_CONTRACTS": "failure", "PERF_SETUP": "failure", "PERF_TOOLS": "skipped", "GITHUB_EVENT_NAME": "pull_request"})
        self.assertEqual(values["contracts"]["status"], "failed")
        self.assertEqual(values["contracts"]["failure_kind"], "infrastructure_or_harness")
        self.assertEqual(values["setup"]["status"], "failed")
        self.assertEqual(values["http_workflow"]["status"], "skipped")
        self.assertEqual(values["baseline_http"]["status"], "skipped")
        self.assertEqual(values["pr_comment"]["status"], "skipped")

    def test_workflow_security_no_publication_loop(self):
        text = (ROOT / ".github/workflows/performance.yml").read_text()
        benchmark, publish = text.split("  publish:\n", 1)
        self.assertNotIn("contents: write", benchmark)
        self.assertNotIn("pull_request_target", text)
        self.assertNotIn("workflow_run:", text)
        self.assertIn("github.event_name != 'pull_request' && github.ref == 'refs/heads/main'", publish)
        self.assertIn("persist-credentials: false", benchmark)
        self.assertIn("branches: [main]", text)
        self.assertNotIn("'benchmarks/**'", text)
        self.assertNotIn("'benchmarks/results/**'", text)
        self.assertNotIn("'benchmarks/latest.json'", text)
        self.assertNotIn("'benchmarks/history.json'", text)
        self.assertIn("retention-days: 14", text)


if __name__ == "__main__":
    unittest.main()
