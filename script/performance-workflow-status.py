#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Record skipped/failed workflow steps even when dependency setup fails."""

import argparse
import importlib.util
import os
from pathlib import Path
import sys

SPEC = importlib.util.spec_from_file_location("evidence", Path(__file__).with_name("performance-evidence.py"))
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)


def statuses(environ):
    result = {}
    names = {"setup": "PERF_SETUP", "tools": "PERF_TOOLS", "databases": "PERF_DATABASES", "migrations": "PERF_MIGRATIONS",
             "http_workflow": "PERF_HTTP", "hotpaths_workflow": "PERF_HOTPATHS"}
    if environ.get("GITHUB_EVENT_NAME") == "pull_request":
        names.update(baseline_setup="PERF_BASE_SETUP", baseline_http="PERF_BASE_HTTP", baseline_hotpaths="PERF_BASE_HOTPATHS")
        if environ.get("PERF_BASE_REPORT"):
            names["baseline_report"] = "PERF_BASE_REPORT"
    for name, variable in names.items():
        outcome = environ.get(variable) or "skipped"
        state = "ok" if outcome == "success" else "failed" if outcome == "failure" else "skipped"
        result[name] = {"status": state, "reason": f"GitHub Actions step outcome: {outcome}"}
    result["pr_comment"] = {"status": "skipped", "reason": "Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled."}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        try:
            summary = evidence.read(args.output / "summary.json")
            if summary["status"] in ("failed", "skipped"):
                print(f"Performance collection: {summary['status']}; see Job Summary and artifacts.", file=sys.stderr)
                return 1
            return 0
        except (OSError, ValueError, KeyError):
            print("Performance report was not generated; collection did not pass.", file=sys.stderr)
            return 1
    if not (args.output / "metadata.json").exists():
        commit = os.environ.get("PERF_COMMIT") or os.environ.get("GITHUB_SHA")
        evidence.write(args.output / "metadata.json", evidence.initial(os.environ.get("PERF_MODE", "pr"), commit))
    evidence.write(args.output / "workflow-status.json", statuses(os.environ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
