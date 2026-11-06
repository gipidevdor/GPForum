# ADR 0156: The Audit Chain Is One Chain Per Aggregate, Linked at Commit

## Status

Accepted (2026-10-24). Supersedes ADR 0114 (proposed, never implemented).
Amends ADR 0020 (the chain is built in PostgreSQL, from the stored form),
ADR 0116 (a caller's audit id is locked on its own) and ADR 0126, section 2
(one named exception to "a shipped version never changes").

## Date

2026-10-24

## Context

Every audit row linked to "the newest row" of one chain for the whole forum,
chosen by `ORDER BY created_at DESC, audit_id DESC` -- both values the
caller's -- under `pg_advisory_xact_lock(2026060210)`, which every audited
write held from its audit insert to its COMMIT
(`api.core_append_audit_v1`, `api.core_shared_append_audit_v1`,
`api.core_record_audit_v1`, `api.ops_record_audit_v1`). Checked against the
code on 2026-10-23:

- **The tip was not the last row.** Two writers take the lock in turn, but
  their `created_at` was stamped in Perl before either waited: the second to
  insert can carry the earlier time, link to the first, and sort below it.
  The third writer then links to the first again, and the second is a leaf
  no row ever points to. The caller's time is right to keep (ADR 0116: a
  replay carries its command's time), and wrong to order by.
- **Every audited write waited for every other.** Replies, reports, logins
  (`Identity::SecurityAudit`) and rate-limit blocks all took the one lock,
  so write throughput was bounded by one audit-to-commit interval however
  many cores or writers there were, and a transaction that stalled after
  its audit stalled them all (ADR 0111 named it the forum's real
  serialisation point).
- **A stored row did not verify.** `record_hash` covered the caller's input
  -- `created_at` as `2026-10-03T10:22:14Z`, metadata as a Perl hash -- while
  the row came back with the time in the session's zone and the metadata as
  jsonb text; only the record kept in memory verified.

ADR 0114 proposed to link rows after commit, from a background linker, into
a second table with its own epochs, anchors and restore procedure. It was
not implemented. It rejected synchronous chains over tip rows that every
audit would update and over a clock, and per-actor chains that rate
limiting and the system jobs would share.

## Decision

1. **A row belongs to the chain of its target.** `chain_key` is
   `target_type:target_id` (`:` for a row with no target), and
   `chain_position` its place in that chain, dense from 1. `previous_hash`
   is the `record_hash` at the position before. The order is the stored
   one and no clock is involved, so the caller's time cannot fork it.
2. **The lock is the aggregate's.** The insert takes
   `pg_advisory_xact_lock(2026102401, hashtext(chain_key))`, reads the tip
   by position through `idx_audit_log_chain_key_position`, and inserts.
   Writers of different aggregates do not wait for each other; writers of
   one aggregate wait on its lock, which a reply's own thread row lock
   already made them do. No tip row is updated: the tip is the last row of
   the table itself.
3. **The hash covers the stored form.** `record_hash` is the SHA-256 of the
   canonical JSON of `action`, `actor_id`, `audit_id`, `correlation_id`,
   `created_at` in UTC with microseconds
   (`to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`),
   `metadata` as jsonb, `previous_hash`, `schema_version` as a number,
   `target_id` and `target_type` (`api.core_audit_digest_v1`).
   `GPForum::Infrastructure::AuditRecord` hashes the same form, so a row
   read back verifies as the record did. A `previous_hash` the caller sends
   is not the link; the chain decides it.
4. **A caller's audit id is locked on its own**,
   `pg_advisory_xact_lock(2026100311, hashtext(audit_id))`, before the
   lookup across the partitions (ADR 0116 amended): two writers of one id
   cannot both miss each other, and an id the recorder mints is neither
   locked nor looked up.
5. **Verification is a function.** `api.ops_audit_chain_verify_v2(chain_key)`
   walks one chain by position and answers each flaw with its position and
   audit id: a position that does not follow the one before, a
   `previous_hash` that is not the hash of the row before, a `record_hash`
   that is not the row's own. `EventRecorder::verify_audit_chain` calls it. A
   month partition that retention dropped reads as a gap; a `gpforum
   audit-chain verify` command and the console's view are follow-ups.
6. **Rows written before migration 1035 are left as they are.** Their
   `chain_key` and `chain_position` are NULL and their old links stand; an
   aggregate's chain starts at position 1 with the first row written after
   the migration. Nothing is rewritten.
7. **The four functions are replaced in place.** A chain discipline must
   change for every writer at once, the previous release's workers included:
   two disciplines side by side link to different tips and fork the chain,
   and the old one keeps the forum-wide lock. Migration 1035 writes `CREATE
   OR REPLACE` for `core_append_audit_v1`, `core_shared_append_audit_v1`,
   `core_record_audit_v1` and `ops_record_audit_v1`, signatures and result
   types unchanged, so the previous release's entry point
   (`ops_record_audit_v2`) runs the new discipline from the migration on.
   `t/641` holds every other function to ADR 0126, section 2, and names
   these four in `%REPLACED_IN_PLACE`; nothing else may be replaced.

## Consequences

- No audited write waits for a write to another aggregate. Verified in
  `t/integration/postgres-audit-chain.t`: with one thread's audit open in a
  transaction, an audit of a post commits at once and a second audit of the
  same thread hits `lock_timeout`; the old lock is not in `pg_locks`.
- The chain cannot fork: three audits of one thread stamped June, January
  and March take positions 1, 2, 3 and each links to the one before.
- Every row verifies from the table, in any session time zone, and the
  verifier finds a changed row, a missing row and a broken link.
- A reply to a thread audits the post, a report audits the report, a login
  audits the user: contention between audited writes is what their targets
  already imposed. Rows with no target share one chain, `:`; today those are
  system actions.
- A per-aggregate chain says in what order one aggregate was acted on, not
  the forum: the console's timeline stays by `created_at`. Tamper evidence
  against someone who can rewrite a whole chain consistently still needs an
  anchor kept outside the database (THREAT_MODEL), as before.
- Two kinds of row coexist until the months before 1035 are retired:
  legacy rows, verifiable one by one as the old record and in the old order,
  and chained rows. Retention that drops a month of chained rows leaves a
  gap the verifier reports; a later decision may seal a month before it is
  dropped.
- The request path gains one advisory lock on a hash and one index read, and
  loses the forum-wide lock and the tip read across every partition.
- Rollback: the previous bodies are in migration 1011 and 1022; restoring
  them restores the forum-wide discipline, and the two columns stay unused.
  The migration adds two nullable columns (a catalog change) and one partial
  index that no existing row enters, built under the parent's `SHARE` lock
  for the time of an empty scan.

## Related Decisions and Implementation

- ADR 0114 (superseded), ADR 0020, ADR 0111 (follow-up closed), ADR 0116,
  ADR 0126 section 2, ADR 0127 (the verify entry point is a boundary).
- `migrations/1035_audit_chain_per_aggregate.sql`;
  `lib/GPForum/Infrastructure/AuditRecord.pm` (`canonical_time`,
  `chain_key`, the stored-form `record_hash`),
  `lib/GPForum/Infrastructure/EventRecorder.pm` (`verify_audit_chain`; its
  resultset path, kept for the doubles and the differential tests under ADR
  0126 section 8, writes the same chain: the aggregate's lock, the tip by
  position, the id's own lock),
  `lib/GPForum/Schema/Result/AuditLog.pm`,
  `lib/GPForum/Service/Admin/AuditReview.pm` (the viewer reads the entry's
  columns on both paths),
  `lib/GPForum/Infrastructure/SqlFunctionCatalogue.pm`
  (`ops_audit_chain_verify`).
- `t/integration/postgres-audit-chain.t`, `t/116-infrastructure-audit-record.t`,
  `t/316-log-ids-across-partitions.t`, `t/641-sql-function-migrations.t`,
  `t/integration/postgres-sql-function-reply.t`.
- `docs/THREAT_MODEL.md`, `docs/audit/failure-modes.md` FM-010,
  `docs/QUALITY_PROGRAM.md` 1.3, `migrations/README.md`.
