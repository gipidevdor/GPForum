# The 1.0 Baseline: What Changed and the Proof

[ADR 0150](../adr/0150-the-schema-starts-from-a-1-0-baseline.md) replaced the
106 migrations of the 0.x chain (001 to 135) with 24 files numbered 1000 to
1023. This is the proof that nothing the code, the tests or the operators use
changed, and the list of everything that did.

Measured on 2026-10-22 on the development laptop (Apple arm64, PostgreSQL
18.6 from Homebrew, Perl 5.44), on a private cluster with the default
durability settings. "The chain" is the tree just before the baseline; "the
baseline" is the tree with it.

## How it was compared

[`script/schema-fingerprint`](../../script/schema-fingerprint) prints a
database's schema as one sorted line per fact: schemas with their owner and
grants; every relation with its kind, persistence, row security, replica
identity, partition key, options and grants; every column by its position
among the live ones, with its type, nullability, identity, generation,
collation, storage, compression, statistics target, options, default and
grants; every constraint and index with its definition and validity;
triggers, sequences, extended statistics, policies, types, comments, default
privileges and per-database settings; and every function's identity, result,
kind, language, volatility, parallel safety, strictness, security,
leakproofness, cost, rows, settings, owner, arguments with their defaults,
grants, and the MD5 of its body. Month partitions are counted under their
parent.

Two databases were built on the same cluster, each by `gpforum migrate
--apply` (so each with its partition window and synced query budgets): one
from the chain, one from the baseline. Their fingerprints were compared with
`comm -3`, and every line that differs was put in one of the categories below
by a script that reads the owner's decisions; a line in none fails it. The
functions whose result changed are compared after putting the table back for
the row type: the lines must then be identical.

## The result

Every line that differs is in one of these, and no other line differs
([every line, with its category](evidence/migration-baseline-1.0-fingerprint-difference.txt)):

| | Facts only in the chain | Facts only in the baseline | What |
| --- | ---: | ---: | --- |
| R1 | 178 | 0 | 89 uncalled functions (their contract and body lines) |
| R2 | 259 + 17 + 3 | 0 | 14 tables (relation, columns, constraints), their indexes, the shard trigger and its function |
| R3 | 6 | 0 | 6 empty schemas |
| R4 | 17 | 4 | `migration_safety` (its relation, columns and constraints) folds into two columns and a check of `schema_versions` |
| R5 | 152 + 77 | 313 + 152 + 77 | 28 row types (relation, type and 257 columns); 152 contracts that return them; 77 bodies that name their columns |
| R6 | 22 | 22 | 22 labels (two of them, `ops_realtime_poll_v1` and `_v2`, also return a row type) |
| R7 | 0 | 74 | 74 table comments |

The rows a fresh database holds are the same in both, apart from the
migration ledger itself (24 rows instead of 106, with `applied_by` and
`execution_ms`) and the 5 rows of the dropped `database_role_contracts`: the
25 query budgets and the 9 partition registry rows are identical.

One difference is below what the catalogue's definitions show: nine columns
the chain added to a table that already existed (`attachments.scan_attempts`,
`automod_settings.review_first_posts` and `review_flagged`,
`dead_letters.failure_type`, `outbox_messages.attempt_count` and
`next_attempt_at`, `users.bio`, `preferred_locale` and `preferred_theme`) are
fast defaults in a chain database (`pg_attribute.atthasmissing`): a row
written before the column was added reads its value from the catalogue. In a
baseline database every column was there from the first row, and none is.
What a query reads is the same.

## Behaviour

- **Unit suite**: 457 files, 17,355 tests, pass.
- **Integration tier** on PostgreSQL 18 (`t/integration`, Unix socket): 128
  files, 11,574 tests, pass, but for one test that fails as often on the
  chain. `postgres-first-post-review.t` reads two posts held in the same
  second in the order `created_at DESC, review_id DESC`; the time the code
  passes and the UUIDv7 ids `GPForum::Infrastructure::Id` draws both carry
  whole seconds, so the two tie at random. Run six times in turn on each
  tree, it failed twice on each. The function it reads has the same body in
  the chain and in the baseline.
- **Results of the hot calls**: the thirteen calls timed below answered the
  same rows from a chain database and a baseline database seeded alike
  (`medium`).
- **The staging drill** (`gpforum staging-drill --seed-profile medium`): fresh
  migrate 24 of 24 with nothing to do on a second run, upgrade path 1022 to
  1023, dump and restore with 120 threads and 25 members: pass
  ([its report](evidence/migration-baseline-1.0-staging-drill.json)).
- **A 0.x database** is refused by `migrate --apply` and `--check` (exit 1,
  nothing applied), and its data moves into a 1.0 database with the dump and
  restore of [docs/ops/upgrade.md](../ops/upgrade.md#from-a-forum-built-before-10):
  on a `medium` seed with log rows, all 6,334 rows of the plain tables and
  every row of the three partitioned logs arrived identical.

## Query plans

`gpforum query-plan-evidence --check --functions --profile medium`, on a
chain and a baseline database seeded alike, judged all 20 endpoints `ok` on
both ([chain](evidence/migration-baseline-1.0-plans-chain.json),
[baseline](evidence/migration-baseline-1.0-plans-baseline.json)). Endpoint by
endpoint the two reports are the same: the same root node, the same
estimated and actual rows, cost and shared buffers hit for every statement,
the nested ones included, and the same warnings.

## Speed

Each call below is one `pgbench` script (`-M prepared`, one client, five
seconds a round) calling the entry point the code calls, with the ids of the
`medium` seed, alternated between the two databases. The figure is the
median latency of the rounds, with their range; `pgbench` prints a
microsecond, so 0.001 ms is its resolution.

| Call | Rounds | Chain, ms | Baseline, ms | Change |
| --- | ---: | ---: | ---: | ---: |
| Session validate | 3 | 0.041 (0.041–0.041) | 0.042 (0.041–0.042) | +2.4% |
| Resolve viewer | 3 | 0.057 (0.056–0.059) | 0.057 (0.056–0.057) | +0.0% |
| Thread page head | 3 | 0.054 (0.053–0.076) | 0.054 (0.053–0.056) | +0.0% |
| Thread page posts (26) | 3 | 0.112 (0.111–0.113) | 0.113 (0.112–0.113) | +0.9% |
| Thread page reads (likes, reactions, replies) | 3 | 0.109 (0.108–0.112) | 0.109 (0.109–0.109) | +0.0% |
| Category list | 3 | 0.248 (0.247–0.253) | 0.251 (0.247–0.256) | +1.2% |
| Category threads, signed in | 3 | 0.420 (0.418–0.422) | 0.420 (0.420–0.427) | +0.0% |
| Latest threads | 3 | 0.539 (0.533–0.559) | 0.547 (0.533–0.552) | +1.5% |
| Ranked search | 3 | 3.108 (3.088–3.148) | 3.156 (3.102–3.229) | +1.5% |
| Notification inbox | 3 | 1.654 (1.630–1.681) | 1.638 (1.614–1.676) | -1.0% |
| Unread badge | 3 | 1.527 (1.525–1.542) | 1.529 (1.522–1.538) | +0.1% |
| Member by id | 5 | 0.034 (0.033–0.034) | 0.029 (0.029–0.029) | -14.7% |
| Admin category list | 5 | 0.040 (0.040–0.041) | 0.039 (0.039–0.039) | -2.5% |

Every change but one is inside the range the same database spans from round
to round. Member by id is faster on the baseline in every round. Part of it
is the fast defaults above: rewriting `users` in a copy of the chain
database (`VACUUM FULL`, which writes every row whole) took it from 0.035 to
0.033 ms, against the baseline's 0.029. The rest was not isolated, and the
baseline claims no speed of its own: its function bodies are the chain's
(R5 names the same columns `*` stood for).

`script/bench-render --iterations 200 --warmup 30`, five runs a side,
alternated, each run building its own database from its tree's migrations
and seed. The figure is the median, over the runs, of each run's median and
95th percentile request time; the range is that of the runs' medians.

| Page | Chain p50, ms | Baseline p50, ms | Chain p95, ms | Baseline p95, ms |
| --- | ---: | ---: | ---: | ---: |
| Thread, member | 9.47 (8.85–14.02) | 9.47 (8.88–11.81) | 10.24 | 10.84 |
| Thread, guest | 5.49 (4.52–7.87) | 4.80 (4.52–7.79) | 8.20 | 5.43 |
| Categories | 3.55 (3.36–5.88) | 3.55 (3.38–5.71) | 4.08 | 4.13 |
| Category | 5.02 (4.83–7.48) | 5.11 (4.87–8.57) | 5.96 | 5.63 |
| Home | 6.35 (5.84–8.68) | 6.25 (5.83–8.71) | 7.04 | 6.81 |
| Search | 8.71 (6.98–10.31) | 8.78 (7.60–10.93) | 9.32 | 9.53 |

The runs of one tree spread wider than the two trees differ: no page is
slower beyond that spread, and none is claimed faster.

## Every difference

### R1: the functions nothing calls

No function the catalogue calls reaches them, through any body: 87 versions
kept for a previous release's workers and the two helpers they used
(`core_notification_event_type_v1`, `core_notification_type_default_v1`).

`admin_permission_allowed_v2`, `community_list_bookmarks_v1`, `community_list_bookmarks_v2`, `community_list_feed_v1`, `community_list_feed_v2`, `community_list_mentions_v1`, `community_list_mentions_v2`, `core_notification_event_type_v1`, `core_notification_type_default_v1`, `forum_create_reply_v1`, `forum_create_reply_v2`, `forum_list_categories_v1`, `forum_list_categories_v2`, `forum_resolve_viewer_v2`, `forum_resolve_viewer_v4`, `forum_thread_page_posts_scoped_v2`, `forum_thread_page_posts_v2`, `forum_thread_page_reads_v1`, `forum_thread_page_reads_v2`, `forum_write_command_v1`, `forum_write_command_v2`, `identity_update_user_v1`, `identity_update_user_v2`, `moderation_automod_record_v1`, `moderation_automod_record_v2`, `moderation_automod_rules_v2`, `moderation_review_mine_v1`, `moderation_review_mine_v2`, `moderation_target_update_v1`, `moderation_target_update_v2`, `moderation_target_v1`, `moderation_target_v2`, `notification_delivery_plan_v1`, `notification_delivery_plan_v2`, `notification_digest_due_v1`, `notification_digest_due_v2`, `notification_digest_items_v1`, `notification_digest_items_v2`, `notification_digest_plan_v2`, `notification_digest_record_v2`, `notification_list_inbox_v1`, `notification_list_inbox_v2`, `notification_list_inbox_v3`, `notification_list_inbox_v4`, `notification_set_type_preferences_v1`, `notification_set_type_preferences_v2`, `notification_type_preferences_v1`, `notification_type_preferences_v2`, `notification_unread_count_v1`, `notification_unread_count_v2`, `notification_unread_count_v3`, `notification_unread_count_v4`, `notification_unsubscribe_v1`, `notification_unsubscribe_v2`, `portability_export_parts_v10`, `portability_export_parts_v12`, `portability_export_parts_v14`, `portability_export_parts_v16`, `portability_export_parts_v18`, `portability_export_parts_v2`, `portability_export_parts_v20`, `portability_export_parts_v4`, `portability_export_parts_v6`, `portability_export_parts_v8`, `privacy_revoke_user_v10`, `privacy_revoke_user_v12`, `privacy_revoke_user_v14`, `privacy_revoke_user_v16`, `privacy_revoke_user_v18`, `privacy_revoke_user_v2`, `privacy_revoke_user_v20`, `privacy_revoke_user_v4`, `privacy_revoke_user_v6`, `privacy_revoke_user_v8`, `privacy_update_v2`, `search_autocomplete_v1`, `search_autocomplete_v2`, `search_autocomplete_v3`, `search_autocomplete_v4`, `search_autocomplete_v5`, `search_autocomplete_v6`, `search_ranked_v1`, `search_ranked_v2`, `search_ranked_v3`, `search_ranked_v4`, `search_ranked_v5`, `search_ranked_v6`, `search_ranked_v7`, `search_ranked_v8`

### R2: the tables nothing reads

No function of `api`, no store and no command reads or writes them; `t/05`
read their CREATE statements from the 0.x files and nothing else did.
`category_stats` was written by the performance seed and read by nothing; the
seed no longer writes it. `thread_counter_shards` carried a trigger that moved
the previous release's writes into `thread_counters` (ADR 0119); no release
came before.

`admin_role_audit_projection`, `aggregate_stream_versions`,
`audit_checkpoints`, `category_stats`, `database_role_contracts`,
`effective_permissions`, `idempotency_keys`, `permission_grants`,
`permission_revocations`, `posts_archive`, `role_binding_events`,
`thread_counter_shards` (with `thread_counter_shards_into_counters()`),
`view_count_deltas`, `visibility_events`.

### R3: the empty schemas

`app`, `security`, `audit`, `search`, `jobs`, `analytics`: created by the
first blueprint, never used.

### R4: the migration ledger

`schema_versions` gains `applied_by text NOT NULL DEFAULT current_user` and
`execution_ms integer CHECK (execution_ms >= 0)`. `migration_safety` repeated
its version and checksum beside `requires_lock`, `reversible` and
`rollback_sql_hash`, which the runner always wrote false, false and empty; it
is gone, and the runner writes one row per migration, in the migration's own
transaction.

### R5: the row types

Each type is the table's columns at 1.0, by name, type and order (checked
column by column: 28 types, 257 columns, none missing or extra).

| Type | The table it was |
| --- | --- |
| `api.admin_announcement_v1` | `public.site_announcements` |
| `api.admin_audit_entry_v1` | `public.audit_log` |
| `api.admin_permission_v1` | `public.permissions` |
| `api.admin_role_binding_v1` | `public.role_bindings` |
| `api.admin_role_permission_v1` | `public.role_permissions` |
| `api.admin_role_v1` | `public.roles` |
| `api.attachment_file_v1` | `public.attachments` |
| `api.attachment_link_v1` | `public.attachment_links` |
| `api.attachment_variant_v1` | `public.attachment_variants` |
| `api.community_bookmark_v1` | `public.bookmarks` |
| `api.forum_category_v1` | `public.categories` |
| `api.forum_post_v1` | `public.posts` |
| `api.forum_read_state_v1` | `public.thread_read_state` |
| `api.forum_space_v1` | `public.spaces` |
| `api.forum_thread_v1` | `public.threads` |
| `api.identity_credential_v1` | `public.credentials` |
| `api.identity_session_v1` | `public.sessions` |
| `api.identity_token_v1` | `public.identity_tokens` |
| `api.identity_trust_snapshot_v1` | `public.trust_score_snapshots` |
| `api.identity_user_v1` | `public.users` |
| `api.moderation_action_v1` | `public.moderation_actions` |
| `api.moderation_report_v1` | `public.reports` |
| `api.moderation_suspension_v1` | `public.suspensions` |
| `api.notification_preference_v1` | `public.notification_preferences` |
| `api.notification_subscription_v1` | `public.subscriptions` |
| `api.ops_partition_v1` | `public.partition_registry` |
| `api.ops_query_budget_v1` | `public.endpoint_query_budgets` |
| `api.outbox_message_v1` | `public.outbox_messages` |

The 152 functions that return one (and `ops_realtime_poll_v1`, `_v2`, under
R6): their contracts differ only in the type.

`admin_announcement_by_id_v1`, `admin_announcement_by_id_v2`, `admin_audit_page_v1`, `admin_audit_page_v2`, `admin_audit_recent_v1`, `admin_audit_recent_v2`, `admin_category_by_id_v1`, `admin_category_by_id_v2`, `admin_first_live_space_v1`, `admin_first_live_space_v2`, `admin_insert_announcement_v1`, `admin_insert_announcement_v2`, `admin_insert_binding_v1`, `admin_insert_binding_v2`, `admin_insert_category_v1`, `admin_insert_category_v2`, `admin_insert_permission_v1`, `admin_insert_permission_v2`, `admin_insert_role_permission_v1`, `admin_insert_role_permission_v2`, `admin_insert_role_v1`, `admin_insert_role_v2`, `admin_insert_space_v1`, `admin_insert_space_v2`, `admin_list_announcements_v1`, `admin_list_announcements_v2`, `admin_list_categories_v1`, `admin_list_categories_v2`, `admin_list_permissions_v1`, `admin_list_permissions_v2`, `admin_list_roles_v1`, `admin_list_roles_v2`, `admin_live_category_by_slug_v1`, `admin_live_category_by_slug_v2`, `admin_lock_binding_v1`, `admin_lock_binding_v2`, `admin_lookup_audit_v1`, `admin_lookup_audit_v2`, `admin_lookup_binding_v1`, `admin_lookup_binding_v2`, `admin_lookup_permission_v1`, `admin_lookup_permission_v2`, `admin_lookup_role_permission_v1`, `admin_lookup_role_permission_v2`, `admin_lookup_role_v1`, `admin_lookup_role_v2`, `admin_permissions_for_role_v1`, `admin_permissions_for_role_v2`, `admin_retire_announcement_v1`, `admin_retire_announcement_v2`, `admin_revoke_binding_v1`, `admin_revoke_binding_v2`, `admin_roles_for_user_v1`, `admin_roles_for_user_v2`, `admin_space_by_id_v1`, `admin_space_by_id_v2`, `admin_space_by_slug_v1`, `admin_space_by_slug_v2`, `admin_update_category_v1`, `admin_update_category_v2`, `attachment_find_v1`, `attachment_find_v2`, `attachment_insert_v1`, `attachment_insert_v2`, `attachment_link_insert_v1`, `attachment_link_insert_v2`, `attachment_links_v1`, `attachment_links_v2`, `attachment_orphans_v1`, `attachment_orphans_v2`, `attachment_source_post_v1`, `attachment_source_post_v2`, `attachment_source_thread_v1`, `attachment_source_thread_v2`, `attachment_update_v1`, `attachment_update_v2`, `attachment_variant_insert_v1`, `attachment_variant_insert_v2`, `attachment_variants_v1`, `attachment_variants_v2`, `community_find_bookmark_v1`, `community_find_bookmark_v2`, `forum_active_announcements_v1`, `forum_active_announcements_v2`, `forum_find_post_v1`, `forum_find_post_v2`, `forum_read_state_v1`, `forum_read_state_v2`, `identity_active_password_v1`, `identity_active_password_v2`, `identity_credential_by_id_v1`, `identity_credential_by_id_v2`, `identity_hold_password_v1`, `identity_hold_password_v2`, `identity_insert_credential_v1`, `identity_insert_credential_v2`, `identity_insert_token_v1`, `identity_insert_token_v2`, `identity_insert_user_v1`, `identity_insert_user_v2`, `identity_lock_passwords_v1`, `identity_lock_passwords_v2`, `identity_profile_trust_v1`, `identity_profile_trust_v2`, `identity_rotate_token_v1`, `identity_rotate_token_v2`, `identity_token_by_id_v1`, `identity_token_by_id_v2`, `identity_unused_token_v1`, `identity_unused_token_v2`, `identity_update_user_v3`, `identity_update_user_v4`, `identity_user_by_id_v1`, `identity_user_by_id_v2`, `identity_user_by_identifier_v1`, `identity_user_by_identifier_v2`, `moderation_action_find_v1`, `moderation_action_find_v2`, `moderation_action_insert_v1`, `moderation_action_insert_v2`, `moderation_action_list_v1`, `moderation_action_list_v2`, `moderation_action_update_v1`, `moderation_action_update_v2`, `moderation_report_find_v1`, `moderation_report_find_v2`, `moderation_report_insert_v1`, `moderation_report_insert_v2`, `moderation_report_queue_v1`, `moderation_report_queue_v2`, `moderation_report_update_v1`, `moderation_report_update_v2`, `moderation_suspension_find_v1`, `moderation_suspension_find_v2`, `moderation_suspension_insert_v1`, `moderation_suspension_insert_v2`, `moderation_suspension_list_v1`, `moderation_suspension_list_v2`, `moderation_suspension_update_v1`, `moderation_suspension_update_v2`, `notification_find_subscription_v1`, `notification_find_subscription_v2`, `notification_list_preferences_v1`, `notification_list_preferences_v2`, `ops_partition_registry_v1`, `ops_partition_registry_v2`, `ops_query_budget_list_v1`, `ops_query_budget_list_v2`, `outbox_claim_ready_v1`, `outbox_claim_ready_v2`, `session_lookup_v1`, `session_lookup_v2`

The 77 bodies that name the type's columns where they read `SELECT *`,
`alias.*` or `RETURNING *` -- each projection checked to read the table the
function returns, and every change read:

`admin_announcement_by_id_v1`, `admin_audit_page_v1`, `admin_audit_recent_v1`, `admin_category_by_id_v1`, `admin_first_live_space_v1`, `admin_insert_announcement_v1`, `admin_insert_binding_v1`, `admin_insert_category_v1`, `admin_insert_permission_v1`, `admin_insert_role_permission_v1`, `admin_insert_role_v1`, `admin_insert_space_v1`, `admin_list_announcements_v1`, `admin_list_categories_v1`, `admin_list_permissions_v1`, `admin_list_roles_v1`, `admin_live_category_by_slug_v1`, `admin_lock_binding_v1`, `admin_lookup_audit_v1`, `admin_lookup_binding_v1`, `admin_lookup_permission_v1`, `admin_lookup_role_permission_v1`, `admin_lookup_role_v1`, `admin_permissions_for_role_v1`, `admin_retire_announcement_v1`, `admin_revoke_binding_v1`, `admin_roles_for_user_v1`, `admin_space_by_id_v1`, `admin_space_by_slug_v1`, `admin_update_category_v1`, `attachment_find_v1`, `attachment_insert_v1`, `attachment_link_insert_v1`, `attachment_links_v1`, `attachment_orphans_v1`, `attachment_source_post_v1`, `attachment_source_thread_v1`, `attachment_update_v1`, `attachment_variant_insert_v1`, `attachment_variants_v1`, `community_find_bookmark_v1`, `forum_active_announcements_v1`, `forum_find_post_v1`, `forum_read_state_v1`, `identity_active_password_v1`, `identity_credential_by_id_v1`, `identity_hold_password_v1`, `identity_insert_credential_v1`, `identity_insert_token_v1`, `identity_insert_user_v1`, `identity_lock_passwords_v1`, `identity_profile_trust_v1`, `identity_rotate_token_v1`, `identity_token_by_id_v1`, `identity_unused_token_v1`, `identity_update_user_v3`, `identity_user_by_id_v1`, `identity_user_by_identifier_v1`, `moderation_action_find_v1`, `moderation_action_insert_v1`, `moderation_action_list_v1`, `moderation_action_update_v1`, `moderation_report_find_v1`, `moderation_report_insert_v1`, `moderation_report_queue_v1`, `moderation_report_update_v1`, `moderation_suspension_find_v1`, `moderation_suspension_insert_v1`, `moderation_suspension_list_v1`, `moderation_suspension_update_v1`, `notification_find_subscription_v1`, `notification_list_preferences_v1`, `ops_partition_registry_v1`, `ops_query_budget_list_v1`, `ops_realtime_poll_v1`, `outbox_claim_ready_v1`, `session_lookup_v1`

### R6: the labels

| Functions | Was | Is | Why |
| --- | --- | --- | --- |
| `ops_realtime_poll_v1`, `_v2`, `ops_realtime_settled_v1`, `_v2` | `STABLE` | `VOLATILE` | They read `clock_timestamp()`, which is volatile |
| `forum_next_position_v1`, `_v2`, `portability_export_parts_v1`, `privacy_review_v1`, `_v2` | `VOLATILE` | `STABLE` | Reads: they write nothing and call nothing that does |
| `core_command_existing_v1`, `core_community_like_answer_v1`, `core_community_like_event_v1`, `core_community_message_event_v1`, `core_community_message_row_valid_v1`, `core_community_reaction_answer_v1`, `core_community_reaction_event_v1`, `core_identity_recovery_hashes_valid_v1`, `core_notification_digest_period_v1`, `core_notification_event_type_v2`, `core_notification_type_default_v2`, `core_session_digest_equals_v1`, `core_transport_payload_v1` | `IMMUTABLE` | `IMMUTABLE PARALLEL SAFE` | Pure functions of their arguments, used inside other functions' statements |

The audit that found them followed every body through the functions it
calls, for writes, locks and volatile built-ins; no other label disagrees
with its body.

### R7: the comments

Each of the 74 tables carries a `COMMENT ON TABLE`, the first sentence of the
comment above it in its file.


## What did not change, on purpose

- **No index was added or dropped.** No index is a prefix of another with the
  same predicate; dropping one without a production workload to show it
  unused would trade a measured plan for a guess.
- **No storage parameter, statistics target or collation changed.** The
  `fillfactor` set on the four tables updated in place, and the
  `autovacuum_analyze_threshold` measured for spaces and categories, stay:
  nothing measured since asks for other values, and the plan gate passes on
  every endpoint without extended statistics.
- **No function body changed beyond R5**, so every plan the plan gate judged
  is the plan it judges now.

## Doing it again

On an empty cluster, with the chain's tree checked out in one directory and
the baseline's in another:

```sh
createdb chain && GPFORUM_DATABASE_DSN='dbi:Pg:dbname=chain;host=/tmp' bin/gpforum migrate --apply  # in the chain's tree
createdb baseline && GPFORUM_DATABASE_DSN='dbi:Pg:dbname=baseline;host=/tmp' bin/gpforum migrate --apply  # in the baseline's tree
script/schema-fingerprint chain > chain.fp
script/schema-fingerprint baseline > baseline.fp
LC_ALL=C comm -3 chain.fp baseline.fp
```

The same comparison holds any later migration to account: two databases
that should be the same print nothing.
