# Database migrations

Start with an **empty database** and run `gpforum migrate`. The baseline is
26 files, numbered **2000–2025**, that create the current schema directly.
It replaces the earlier migration chains; databases recording versions below
2000 are refused with instructions to create an empty database. No data import
or in-place upgrade from those chains is part of this baseline.

See [ADR 0162](../docs/adr/0162-a-fresh-database-baseline.md) and the
[schema comparison](../docs/architecture/migration-baseline-2026-11.md).

## Find a definition

| Files | Contents |
| --- | --- |
| `2000_foundation.sql` | Extensions, the Italian search configuration, closed `api` schema, migration ledger, partition registry and query budgets. |
| `2001_identity.sql`–`2010_privacy.sql` | Tables by domain, in their final shape. Primary/unique/check constraints, comments and indexes stay beside their table. The two singleton settings rows are initialized here. |
| `2011_relations.sql` | Foreign keys, after all referenced tables exist. Circular references remain deferred where the application needs them. |
| `2012_api_core.sql` | Composite result types and shared functions. |
| `2013_api_session.sql`–`2024_api_privacy.sql` | Implementations grouped by domain. Operations includes outbox, partitions and workers; admin includes plugin settings; privacy includes portability. |
| `2018_api_access.sql` | Shared access composition that needs the earlier admin/moderation implementations. |
| `2022_api_notification.sql` | Notification functions, then the thread-page composition that depends on them. |
| `2025_api_entry_points.sql` | Typed `SECURITY DEFINER` boundaries and the table triggers, once their dependencies exist. |
| `2026_identity_token_owner.sql` | Owner lookup for consistent credential/token lock ordering during account recovery. |
| `2027_attachment_write_limits.sql` | Locked author writes and serialized per-owner upload allowances. |
| `2028_public_cache_revocation.sql` | Committed public-content revocation epoch and its typed configuration read boundary. |
| `2029_follow_feed_private_replies.sql` | Current private-reply visibility rules for followed-member feeds. |
| `2030_attachment_owner_retained_index.sql` | Concurrent covering index for attachment quota accounting, including retained soft-deleted files. |
| `2031_network_integrations.sql`–`2032_oidc_account_links.sql` | Discord delivery, moderated syndication, expanded administrator settings and explicit OIDC account links. |
| `2033_navigation_context.sql`–`2038_moderation_transfer_title_index.sql` | Navigation, member profiles, upload pagination and indexed moderation thread selection. |
| `2039_hot_table_autovacuum.sql` | Earlier vacuum/analyze eligibility for frequently updated forum, search, outbox and session tables. |
| `2040_hybrid_search.sql` | pgvector, an invalidated embedding projection and typed semantic search/indexing boundaries. See the [hybrid search prerequisites](../docs/ops/hybrid-search.md). |
| `2041_moderation_transfer_picker_work.sql` | Resolve picker membership/read grants once per statement, preserving the previous boundary for rolling workers. |

Within the 2000–2025 baseline, every table and function is created once. No version is retained solely for
older workers; there are no data backfills, temporary indexes or add/drop-column
steps. Shared implementations remain only when current callers reach them. Existing
API version suffixes remain the contracts named by
`GPForum::Infrastructure::SqlFunctionCatalogue`; they do not imply that earlier
versions are installed.

Function bodies are validated when created. Dependencies are ordered explicitly;
`check_function_bodies` is never disabled. Each function revokes PUBLIC execution
beside its own declaration. SQL-language boundaries forward to invoker
implementations; implementations do not call privileged boundaries.

Monthly partitions are created by `gpforum migrate` and maintained by the daily
timer. Only permanent default partitions belong in these files. The same command
syncs query budgets; neither generated month names nor generated budgets belong
in the baseline.

## Make a later change

- Add a file after the highest number already present. Once this baseline
  has been installed, its files are immutable: the runner verifies checksums.
- Use one transaction (`BEGIN;` / `COMMIT;`) and set a local `lock_timeout`.
- Give each table a `COMMENT ON TABLE`. Keep names used to identify constraint
  violations stable.
- Follow ADR 0126 and 0127: versioned functions, pinned `search_path` and plan
  mode, honest volatility, typed results, no dynamic SQL, PUBLIC execution
  revoked, and owner rights only at typed catalogue boundaries.
- Future rolling upgrades may retain the preceding API version temporarily;
  remove it with a later contract migration once no worker calls it. This
  fresh baseline retains none. `t/641` and the live catalogue test reject
  unreachable functions.
- On an existing populated database, use `CREATE INDEX CONCURRENTLY` in a
  separate file starting with `-- gpforum:no-transaction`; make each statement
  safe to repeat. The initial empty-database baseline uses ordinary indexes.

## Check it

`gpforum migrate --plan` lists the work, `gpforum migrate` applies it, and
`gpforum migrate --check` verifies the installed schema. A second application
has no pending files. Use `script/schema-fingerprint` to compare database
contracts and `script/schema-snapshot` for the reviewed schema in
`etc/schema/postgresql-18.sql`.

## Web Push

`2042_web_push.sql` adds encrypted per-device consent, an independent bounded
delivery outbox, versioned notification APIs, transactional session/account
revocation hooks and consent metadata in account exports. Re-provision runtime
API grants after migration. [Deployment and key handling](../docs/ops/web-push.md).

## Passkeys

`2043_passkeys.sql` connects WebAuthn credentials to member accounts, opaque
user handles, single-use challenges and existing credential revocation.
Refresh runtime API grants and restart the application after deployment.
[Account and login flows](../docs/passkeys-registration.md).

## Native community commands

`2044_native_community_targets.sql` combines the existing bookmark removal and
subscription mute/revocation stores with their command log in one atomic call.
Apply the migration and refresh runtime API grants before restarting the new
application code. Existing target-store functions and command-log semantics are
retained; a failed store or command-log close rolls back the complete command.

## Handler claim owner and suspension rank

`2050_event_claim_owner.sql` gives each worker handler claim a token: only the
run that holds the claim releases it on failure, so a worker whose lease ran
out cannot free the claim another worker took over. `ops_event_claim_v2` stays
for workers from the preceding release. `2051_suspension_rank.sql` adds the
check of whom an actor may suspend: staff only by an administrator, never
oneself. Refresh runtime API grants and restart the web service and workers.

## Review follow-ups

`2052_review_followups.sql` makes "mark all read" mark what the badge counts,
direct-message notifications included, in one statement; deletes completed
handler claims once a dead-letter replay can no longer need them (the
dead-letter retention and a week), and `2053_event_claim_completed_index.sql`
builds their completion-time index concurrently;
and has erasure remove the account's OIDC links and passkey handles with its
credentials. The versions these replace are dropped. Refresh runtime API
grants and restart the web service and workers.
