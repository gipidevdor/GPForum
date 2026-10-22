# Database migrations

SQL files form an append-only history. Directory names organize that history; only the numeric filename prefix determines execution order.

## Layout

| Directory | Versions | Purpose |
| --- | --- | --- |
| [001-schema/](001-schema/) | 001–051 | Tables, constraints, indexes, preferences and partition foundations. |
| [002-function-api/](002-function-api/) | 052–099 | API schema, implementations and runtime privilege boundaries. |
| [003-evolution/](003-evolution/) | 100 onward | Subsequent optimizations and product features, in global version order. |

## Rules

- Keep applied SQL files byte-for-byte unchanged: the runner checks their SHA-256 against `schema_versions`.
- Keep existing version prefixes and basenames. Gaps (071–098 and 120) are historical; do not renumber or fill them.
- Add new work to `003-evolution/` with a globally unique version greater than every existing version. Coordinate version allocation across concurrent branches.
- Each change is a new migration. Keep released API signatures and return contracts compatible with workers from the previous release.
- Preserve the existing transaction markers and the `gpforum:no-transaction` protocol for concurrent indexes.
- Write a migration as one transaction, `BEGIN;` on its first line and `COMMIT;` on its last, or as a `gpforum:no-transaction` file of statements safe to repeat. The runner writes the `schema_versions` row before that `COMMIT`, so a migration and its record commit together; it refuses a new file of several transactions (ADR 0126, amended 2026-10-22).
- The runner refuses a pending migration numbered below one already applied, except a listed gap (120).
- Use `GPForum::Migration::Plan` for discovery: it reads nested directories, orders globally by numeric version, and refuses duplicate versions. Flat directories remain supported for fixtures and custom plans.
- Directory moves preserve version, description and checksum; existing databases do not reapply moved migrations.

## Running and checking

Run `bin/gpforum help migrate` for the operator interface. The database tests cover migration discovery and application; `t/687-migration-plan.t` covers nested order and duplicate rejection; `t/641-sql-function-migrations.t` checks the API SQL contracts.

## Inventory

### Initial schema and integrity (001–051)

- [001_core_identity.sql](001-schema/001_core_identity.sql)
- [002_event_audit.sql](001-schema/002_event_audit.sql)
- [003_forum_projection.sql](001-schema/003_forum_projection.sql)
- [004_platform_governance.sql](001-schema/004_platform_governance.sql)
- [005_notifications_subscriptions.sql](001-schema/005_notifications_subscriptions.sql)
- [006_attachments.sql](001-schema/006_attachments.sql)
- [007_advanced_community.sql](001-schema/007_advanced_community.sql)
- [008_moderation_review.sql](001-schema/008_moderation_review.sql)
- [009_admin_authorization.sql](001-schema/009_admin_authorization.sql)
- [010_import_export.sql](001-schema/010_import_export.sql)
- [011_plugins.sql](001-schema/011_plugins.sql)
- [012_personal_feed_indexes.sql](001-schema/012_personal_feed_indexes.sql)
- [013_public_profile_indexes.sql](001-schema/013_public_profile_indexes.sql)
- [014_hot_path_indexes.sql](001-schema/014_hot_path_indexes.sql)
- [015_production_evidence_indexes.sql](001-schema/015_production_evidence_indexes.sql)
- [016_security_abuse_hardening.sql](001-schema/016_security_abuse_hardening.sql)
- [017_load_observability_indexes.sql](001-schema/017_load_observability_indexes.sql)
- [018_search_product_hardening.sql](001-schema/018_search_product_hardening.sql)
- [019_user_locale_preference.sql](001-schema/019_user_locale_preference.sql)
- [020_user_theme_preference.sql](001-schema/020_user_theme_preference.sql)
- [021_outbox_delivery_reliability.sql](001-schema/021_outbox_delivery_reliability.sql)
- [022_outbox_concurrent_claim.sql](001-schema/022_outbox_concurrent_claim.sql)
- [023_realtime_outbox_polling.sql](001-schema/023_realtime_outbox_polling.sql)
- [024_privacy_erasure_job_idempotency.sql](001-schema/024_privacy_erasure_job_idempotency.sql)
- [025_identity_lifecycle_tokens.sql](001-schema/025_identity_lifecycle_tokens.sql)
- [026_concurrency_uniqueness.sql](001-schema/026_concurrency_uniqueness.sql)
- [027_privacy_resource_uniqueness.sql](001-schema/027_privacy_resource_uniqueness.sql)
- [028_reputation_source_uniqueness.sql](001-schema/028_reputation_source_uniqueness.sql)
- [029_reputation_source_required.sql](001-schema/029_reputation_source_required.sql)
- [030_identity_open_token_uniqueness.sql](001-schema/030_identity_open_token_uniqueness.sql)
- [031_role_binding_active_uniqueness.sql](001-schema/031_role_binding_active_uniqueness.sql)
- [032_plugin_hook_uniqueness.sql](001-schema/032_plugin_hook_uniqueness.sql)
- [033_dead_letter_source_uniqueness.sql](001-schema/033_dead_letter_source_uniqueness.sql)
- [034_import_failure_source_uniqueness.sql](001-schema/034_import_failure_source_uniqueness.sql)
- [035_projection_generation_source_uniqueness.sql](001-schema/035_projection_generation_source_uniqueness.sql)
- [036_credential_active_password_uniqueness.sql](001-schema/036_credential_active_password_uniqueness.sql)
- [037_index_redundancy_cleanup.sql](001-schema/037_index_redundancy_cleanup.sql)
- [038_monthly_log_partitions.sql](001-schema/038_monthly_log_partitions.sql)
- [039_audit_chain_tip_index.sql](001-schema/039_audit_chain_tip_index.sql)
- [040_event_idempotency_claims.sql](001-schema/040_event_idempotency_claims.sql)
- [041_viewer_and_profile_thread_indexes.sql](001-schema/041_viewer_and_profile_thread_indexes.sql)
- [042_search_title_normalized_not_null.sql](001-schema/042_search_title_normalized_not_null.sql)
- [043_attachment_scan_engine.sql](001-schema/043_attachment_scan_engine.sql)
- [044_user_timezone.sql](001-schema/044_user_timezone.sql)
- [045_scrub_login_sessions.sql](001-schema/045_scrub_login_sessions.sql)
- [046_thread_last_activity_backfill.sql](001-schema/046_thread_last_activity_backfill.sql)
- [047_feed_items_by_item.sql](001-schema/047_feed_items_by_item.sql)
- [048_search_candidate_order.sql](001-schema/048_search_candidate_order.sql)
- [049_rolling_partitions.sql](001-schema/049_rolling_partitions.sql)
- [050_auto_theme.sql](001-schema/050_auto_theme.sql)
- [051_fold_thread_counter_shards.sql](001-schema/051_fold_thread_counter_shards.sql)

### Versioned PostgreSQL API (052–099)

- [052_api_schema_and_canonical_json.sql](002-function-api/052_api_schema_and_canonical_json.sql)
- [053_forum_thread_page_functions.sql](002-function-api/053_forum_thread_page_functions.sql)
- [054_forum_reply_functions.sql](002-function-api/054_forum_reply_functions.sql)
- [055_runtime_prologue_functions.sql](002-function-api/055_runtime_prologue_functions.sql)
- [056_forum_read_functions.sql](002-function-api/056_forum_read_functions.sql)
- [057_forum_write_functions.sql](002-function-api/057_forum_write_functions.sql)
- [058_notification_read_functions.sql](002-function-api/058_notification_read_functions.sql)
- [059_runtime_api_boundaries.sql](002-function-api/059_runtime_api_boundaries.sql)
- [060_identity_functions.sql](002-function-api/060_identity_functions.sql)
- [061_shared_outbox_functions.sql](002-function-api/061_shared_outbox_functions.sql)
- [062_community_notification_functions.sql](002-function-api/062_community_notification_functions.sql)
- [063_forum_read_marker_functions.sql](002-function-api/063_forum_read_marker_functions.sql)
- [064_search_functions.sql](002-function-api/064_search_functions.sql)
- [065_moderation_functions.sql](002-function-api/065_moderation_functions.sql)
- [066_admin_functions.sql](002-function-api/066_admin_functions.sql)
- [067_attachment_functions.sql](002-function-api/067_attachment_functions.sql)
- [068_privacy_portability_plugin_functions.sql](002-function-api/068_privacy_portability_plugin_functions.sql)
- [069_operations_realtime_functions.sql](002-function-api/069_operations_realtime_functions.sql)
- [070_partition_horizon_functions.sql](002-function-api/070_partition_horizon_functions.sql)
- [099_remaining_runtime_api_boundaries.sql](002-function-api/099_remaining_runtime_api_boundaries.sql)

### Application evolution (100 onward)

- [100_optimized_search_functions.sql](003-evolution/100_optimized_search_functions.sql)
- [101_forum_post_context_functions.sql](003-evolution/101_forum_post_context_functions.sql)
- [102_search_custom_plans.sql](003-evolution/102_search_custom_plans.sql)
- [103_forum_drafts.sql](003-evolution/103_forum_drafts.sql)
- [104_thread_action_commands.sql](003-evolution/104_thread_action_commands.sql)
- [105_drop_unwired_subsystems.sql](003-evolution/105_drop_unwired_subsystems.sql)
- [106_identity_command_functions.sql](003-evolution/106_identity_command_functions.sql)
- [107_category_activity.sql](003-evolution/107_category_activity.sql)
- [108_thread_pinning.sql](003-evolution/108_thread_pinning.sql)
- [109_post_likes.sql](003-evolution/109_post_likes.sql)
- [110_search_scopes.sql](003-evolution/110_search_scopes.sql)
- [111_profile_bio.sql](003-evolution/111_profile_bio.sql)
- [112_member_relations.sql](003-evolution/112_member_relations.sql)
- [113_site_announcements.sql](003-evolution/113_site_announcements.sql)
- [114_reply_links.sql](003-evolution/114_reply_links.sql)
- [115_automod.sql](003-evolution/115_automod.sql)
- [116_first_post_review.sql](003-evolution/116_first_post_review.sql)
- [117_thread_tags.sql](003-evolution/117_thread_tags.sql)
- [118_notification_type_preferences.sql](003-evolution/118_notification_type_preferences.sql)
- [119_notification_digests.sql](003-evolution/119_notification_digests.sql)
- [121_bookmark_folders.sql](003-evolution/121_bookmark_folders.sql)
- [122_notification_digest_windows.sql](003-evolution/122_notification_digest_windows.sql)
- [123_notification_digest_sent.sql](003-evolution/123_notification_digest_sent.sql)
- [124_thread_page_reads.sql](003-evolution/124_thread_page_reads.sql)
