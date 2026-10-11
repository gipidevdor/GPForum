#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
"""Append validated small evidence to main without rewriting application history.

The input artifact is data: no program, archive hook, profile or log from it is
executed or committed. Optimistic ordinary Git pushes make updates atomic and
reject concurrent changes; a conflict retries against the latest branch tip.
"""

import argparse
import base64
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("evidence", ROOT / "script/performance-evidence.py")
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)
BRANCH = "main"
FILES = ("metadata.json", "summary.json", "http.json", "database.json", "outbox.json", "reactor.json", "workers.json", "report.md")


def manifest(source, expected_commit=None, expected_run=None, expected_attempt=None):
    source = Path(source)
    if source.is_symlink():
        raise ValueError("Artifact directory is a symlink")
    evidence.validate(source)
    metadata = evidence.read(source / "metadata.json")
    for field, pattern in (("commit", r"[0-9a-f]{40}"), ("date", r"\d{4}-\d{2}-\d{2}"),
                           ("run_id", r"[A-Za-z0-9_-]{1,100}"), ("run_attempt", r"[1-9][0-9]{0,5}")):
        if not re.fullmatch(pattern, str(metadata[field])):
            raise ValueError(f"Unsafe publication {field}")
    for field, expected in (("commit", expected_commit), ("run_id", expected_run), ("run_attempt", expected_attempt)):
        if expected is not None and str(metadata[field]) != str(expected):
            raise ValueError(f"Artifact {field} does not match the triggering run")
    if metadata["mode"] not in ("main", "deep"):
        raise ValueError("Only main/deep evidence can enter persistent history")
    summary = evidence.read(source / "summary.json")
    for field in ("commit", "date", "run_id", "run_attempt", "mode"):
        if summary[field] != metadata[field]:
            raise ValueError("Metadata and summary provenance differ")
    payload = {}
    total = 0
    for name in FILES:
        path = source / name
        if not path.exists():
            continue
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 8_000_000:
            raise ValueError("Unsafe or excessive artifact file")
        if name == "report.md":
            # Generate display text with trusted code rather than trusting
            # artifact Markdown. JSON is schema-checked and secret-screened.
            data = evidence.report(metadata, summary).encode("utf-8")
        else:
            if name not in ("metadata.json", "summary.json"):
                provenance = evidence.read(path).get("provenance", {})
                for field in ("commit", "date"):
                    if provenance.get(field) != metadata[field]:
                        raise ValueError("Measurement provenance differs from metadata")
                for field in ("run_id", "run_attempt"):
                    if field in provenance and provenance[field] != metadata[field]:
                        raise ValueError("Measurement run differs from metadata")
            data = path.read_bytes()
        total += len(data)
        payload[name] = data
    if total > 30_000_000:
        raise ValueError("Evidence publication exceeds 30 MB")
    payload["report.md"] = evidence.report(metadata, summary).encode("utf-8")
    relative = Path("benchmarks/results") / metadata["date"] / metadata["commit"] / f"{metadata['run_id']}-{metadata['run_attempt']}"
    return relative, payload


def append_result(root, relative, payload):
    root = Path(root)
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Unsafe destination path")
    destination = root / relative
    for path in (destination, *destination.parents):
        if path == root.parent:
            break
        if path.is_symlink():
            raise ValueError("Results branch contains a symlink in the canonical path")
    if destination.exists():
        current = {path.name: path.read_bytes() for path in destination.iterdir() if path.is_file() and not path.is_symlink()}
        if current != payload:
            raise ValueError("Historical run already exists with different contents; refusing overwrite")
        return False
    destination.mkdir(parents=True)
    for name, data in payload.items():
        (destination / name).write_bytes(data)
    evidence.validate(destination)
    evidence.index(root)
    return True


def git(directory, *arguments, env=None, check=True):
    result = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *arguments], cwd=directory,
                            env=env, capture_output=True, text=True, timeout=45)
    if check and result.returncode:
        # Never echo subprocess headers, remote URLs or authentication details.
        raise RuntimeError(f"Git operation {arguments[0]} failed (exit {result.returncode}); inspect repository permissions/rules or network availability.")
    return result


def publish(source, remote, expected_commit=None, expected_run=None, expected_attempt=None, token=None, attempts=5):
    relative, payload = manifest(source, expected_commit, expected_run, expected_attempt)
    env = os.environ.copy()
    env.update(GIT_TERMINAL_PROMPT="0", GIT_LFS_SKIP_SMUDGE="1")
    if token:
        basic = base64.b64encode(("x-access-token:" + token).encode()).decode()
        env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader", GIT_CONFIG_VALUE_0="AUTHORIZATION: basic " + basic)
    for attempt in range(attempts):
        with tempfile.TemporaryDirectory(prefix="gpforum-performance-publish-") as directory:
            git(directory, "init", "--quiet", env=env)
            git(directory, "remote", "add", "origin", remote, env=env)
            exists = git(directory, "ls-remote", "--exit-code", "--heads", "origin", BRANCH, env=env, check=False)
            if exists.returncode not in (0, 2):
                raise RuntimeError("Cannot inspect results branch; publication is not confirmed")
            if exists.returncode == 0:
                git(directory, "fetch", "--quiet", "--no-tags", "--depth=1", "origin", BRANCH, env=env)
                git(directory, "checkout", "--quiet", "-b", BRANCH, "FETCH_HEAD", env=env)
            else:
                raise RuntimeError("Main branch is missing; refusing to initialize or replace application history")
            if not append_result(directory, relative, payload):
                return relative
            target = Path(directory) / "benchmarks"
            for name in ("README.md", "schema-v1.json"):
                if not (target / name).exists() and (ROOT / "benchmarks" / name).exists():
                    (target / name).write_bytes((ROOT / "benchmarks" / name).read_bytes())
            additions = [str(relative), "benchmarks/latest.json", "benchmarks/history.json"]
            additions.extend("benchmarks/" + name for name in ("README.md", "schema-v1.json") if (target / name).exists())
            git(directory, "add", "--", *additions, env=env)
            git(directory, "-c", "user.name=github-actions[bot]", "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                "commit", "--quiet", "-m", f"Record performance evidence {relative.name} [skip ci]", env=env)
            pushed = git(directory, "push", "--quiet", "origin", f"HEAD:refs/heads/{BRANCH}", env=env, check=False)
            if pushed.returncode == 0:
                return relative
            # An ordinary push rejects stale/non-fast-forward history. Start
            # from the new tip and reapply only this immutable result.
    raise RuntimeError("Publication failed after bounded retries; artifact remains available. Check branch rules and contents:write permission.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--expected-run", required=True)
    parser.add_argument("--expected-attempt", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
        raise ValueError("Invalid repository name")
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise ValueError("Missing job-scoped GITHUB_TOKEN")
    relative = publish(args.input, "https://github.com/" + args.repository + ".git",
                       args.expected_commit, args.expected_run, args.expected_attempt, token)
    url = "https://github.com/" + args.repository + "/tree/" + BRANCH + "/" + relative.as_posix()
    print("Published performance evidence: " + url)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as handle:
            handle.write(f"\n[Published immutable performance evidence]({url})\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as error:
        print("performance-publish: " + str(error), file=sys.stderr)
        sys.exit(1)
