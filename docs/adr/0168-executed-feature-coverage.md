# ADR 0168: Executed feature coverage

## Status

Accepted (2026-11-02).

## Context

ADR 0167 connects operations to their GUI entrances. Its static source guard
cannot prove that a form submits the right command or that the database
changes. The first complete instrumented integration run left 39 operations
unobserved. A legacy test helper also sent unchecked checkboxes, including the
new media continuation, which a browser would omit.

## Decision

Keep navigation wiring, functional behavior and performance measurements as
separate forms of evidence. Add an explicit feature manifest and a strict
`script/test-features` gate. Every registered route belongs to exactly one
feature family and has an expected HTTP outcome; each family declares named
behavioral postconditions in identified tests. The complete integration
directory always runs, alongside the manifest's unit witnesses.

An opt-in test-only probe records successful non-TODO assertions when their
description contains the declared literal witness. The report requires all
witnesses from their declared files, all expected HTTP outcomes and a passing
whole test run. Missing, skipped, failed or TODO witnesses cannot satisfy the
gate. Newly registered, stale and duplicate routes fail it. A mapped route
without a request requirement also fails. Probe unit tests deliberately
exercise false-positive cases and preserve normal failing TAP behavior.

The probe is never loaded by production entry points. Evidence contains test,
feature, assertion and operation names/statuses; request bodies, database bind
values and uploaded bytes are not captured. This extends no production schema
and changes no SQL catalogue contract.

New GUI integration tests derive requests from rendered forms, preserving
native control selection, CSRF and command IDs. They verify database state
rather than relying on redirects. Extend the real integration service tests
with native forms for outbox commands and actual OpenID linking, login and
unlinking; inject controlled transport responses into the production service
with signed claims. Cover every packaged provider with a named executable case.

Exercise an actual 100 MiB multipart file against PostgreSQL, verifying its
stored byte count, chunk completeness and SHA-256, access before review,
approval and bounded range reads. Prerecorded audio gets a native upload,
review, retrieval and player-rendering case. These container fixtures establish
storage and presentation contracts, not browser decoding or playback quality.

The default runner ignores caller database settings and uses temporary
clusters. An explicit `--configured` option supports CI's disposable database
service and refuses to run without a selected database. CI retains the normal
integration gate and also runs the feature verdict, publishing its report.

## Consequences

Coverage now means the manifest's executed behavior and HTTP contracts. A new
operation needs a feature assignment, expected response and meaningful result
assertion. No percentage is inferred from source mentions or successful query
execution. Functional coverage is not line/branch coverage or a promise that
all possible inputs, live providers or devices have been tested.

The current inventory is 39 feature families, 223 operations and 157 mandatory
behavioral criteria. The GUI map documents the exact command and test surfaces.
All additional databases and large files are disposable; no LAN preview is
restarted.
