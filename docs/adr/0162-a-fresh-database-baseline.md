# ADR 0162: A Fresh Database Baseline

## Status

Accepted (2026-11-01). The owner explicitly chose an empty database: cleanliness,
optimality and ergonomics, rather than preserving the accumulated migration
history or upgrading its databases.

Amends ADR 0150's file layout and ADR 0126/0127's retained compatibility
boundaries. The audit exception in ADR 0156 is historical: the new baseline
creates each final audit function once, without `CREATE OR REPLACE`.

## Context

The 1.0 baseline and subsequent changes had grown to 66 files and 32,555 SQL
lines. Tables were created, altered, stripped of unused columns and reindexed
across several files. A freshly installed database also received 154 function
definitions that no current catalogue call or trigger could reach.

## Decision

Replace that chain with 26 files numbered 2000–2025. Create every table in its
final shape, keep its constraints/comments/indexes together, place cross-table
foreign keys after the tables, and group function implementations by domain.
Declare dependencies before SQL bodies that use them. Keep the current typed
API signatures, settings, privileges, function bodies, triggers and seed policy.
Remove the 154 unreachable definitions and the tests' legacy allowlists.

The existing SQL API version names remain stable. Renaming working contracts
would add code churn without reducing installed SQL. Implementations and typed
owner-rights boundaries are both required: the latter keep the restricted
runtime role from accessing tables directly.

The migration runner rejects recorded versions below 2000 as an earlier
baseline, before applying anything. Start from an empty database; there is no
automatic conversion, data-copy procedure or rolling upgrade from the old chain.
Later migrations are append-only and checksummed as usual.

## Verification

Build the former chain and the baseline on the same disposable PostgreSQL 18
cluster. Remove exactly the unreachable functions from a clone of the former,
then compare `script/schema-fingerprint` outputs. They must be identical,
including function bodies and grants, indexes, predicates, triggers, defaults,
constraints, row types and partition setup. Check seeds separately because their
creation timestamps and the migration ledger naturally differ.

Run the static migration contract, live catalogue/security contracts and forum
integration tests; update the canonical schema snapshot. The comparison and
validation are recorded in
[the baseline evidence](../architecture/migration-baseline-2026-11.md).
