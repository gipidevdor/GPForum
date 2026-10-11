-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0127: typed EXECUTE-only entry points for all later areas.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.ops_doctor_outbox_v2(

)
RETURNS TABLE(waiting bigint, oldest_seconds numeric, last_sent_seconds numeric)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_doctor_outbox_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_doctor_outbox_v2() FROM PUBLIC;

CREATE FUNCTION api.search_ranked_v2(
p_permission_mode text,
    p_visibility_values text[],
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_query text,
    p_like_pattern text,
    p_config text,
    p_candidate_limit integer,
    p_category_filter uuid,
    p_author_filter uuid,
    p_from_at timestamptz,
    p_to_at timestamptz,
    p_to_exclusive boolean,
    p_row_limit integer
)
RETURNS TABLE (search_document_id uuid, entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, permission_scope text, visibility_version bigint, permission_version bigint, language text, title text, title_normalized text, body text, search_vector tsvector, source_version bigint, source_created_at timestamptz, indexed_at timestamptz, rank_score double precision, author_username text, author_display_name text, category_visibility text, space_visibility text, candidate_count bigint, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_ranked_v1(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_like_pattern, p_config, p_candidate_limit, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.search_ranked_v2(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, text, text, integer, uuid, uuid, timestamptz, timestamptz, boolean, integer) FROM PUBLIC;

CREATE FUNCTION api.search_autocomplete_v2(
p_permission_mode text,
    p_visibility_values text[],
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_like_pattern text,
    p_row_limit integer
)
RETURNS TABLE (search_document_id uuid, entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, permission_scope text, visibility_version bigint, permission_version bigint, language text, title text, title_normalized text, body text, search_vector tsvector, source_version bigint, source_created_at timestamptz, indexed_at timestamptz, author_username text, author_display_name text, category_visibility text, space_visibility text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_autocomplete_v1(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_like_pattern, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.search_autocomplete_v2(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, integer) FROM PUBLIC;

CREATE FUNCTION api.search_set_timeout_v2(
p_timeout text
)
RETURNS TABLE (timeout text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_set_timeout_v1(p_timeout);
$$;
REVOKE EXECUTE ON FUNCTION api.search_set_timeout_v2(text) FROM PUBLIC;

CREATE FUNCTION api.search_index_entity_v2(
p_entity_type text,
    p_entity_id uuid,
    p_document_id uuid,
    p_indexed_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_index_entity_v1(p_entity_type, p_entity_id, p_document_id, p_indexed_at);
$$;
REVOKE EXECUTE ON FUNCTION api.search_index_entity_v2(text, uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.search_remove_document_v2(
p_entity_type text,
    p_entity_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_remove_document_v1(p_entity_type, p_entity_id);
$$;
REVOKE EXECUTE ON FUNCTION api.search_remove_document_v2(text, uuid) FROM PUBLIC;

CREATE FUNCTION api.search_thread_post_batch_v2(
p_thread_id uuid,
    p_after_position bigint,
    p_row_limit integer
)
RETURNS TABLE (post_id uuid, "position" bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_thread_post_batch_v1(p_thread_id, p_after_position, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.search_thread_post_batch_v2(uuid, bigint, integer) FROM PUBLIC;

CREATE FUNCTION api.search_live_ids_v2(
p_entity_type text,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (entity_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_live_ids_v1(p_entity_type, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.search_live_ids_v2(text, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.search_prune_candidates_v2(
p_entity_type text
)
RETURNS TABLE (entity_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_prune_candidates_v1(p_entity_type);
$$;
REVOKE EXECUTE ON FUNCTION api.search_prune_candidates_v2(text) FROM PUBLIC;

CREATE FUNCTION api.search_remove_post_batch_v2(
p_thread_id uuid,
    p_post_ids uuid[]
)
RETURNS TABLE (removed bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_remove_post_batch_v1(p_thread_id, p_post_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.search_remove_post_batch_v2(uuid, uuid[]) FROM PUBLIC;

CREATE FUNCTION api.search_observe_lag_v2(

)
RETURNS TABLE (pending bigint, oldest_pending_at text, lag_seconds bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_observe_lag_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.search_observe_lag_v2() FROM PUBLIC;

CREATE FUNCTION api.search_latest_rebuild_v2(

)
RETURNS TABLE (event_type text, payload text, created_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_latest_rebuild_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.search_latest_rebuild_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_partition_horizon_v2(

)
RETURNS TABLE(table_name text, horizon_epoch numeric, default_has_rows boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_partition_horizon_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_horizon_v2() FROM PUBLIC;

CREATE FUNCTION api.forum_next_position_v2(
p_thread_id uuid
)
RETURNS TABLE(next_position bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_next_position_v1(p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_next_position_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.privacy_insert_v2(
p_source text, p_row jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_insert_v1(p_source, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_insert_v2(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.portability_insert_v2(
p_source text, p_row jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_insert_v1(p_source, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_insert_v2(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.plugin_insert_v2(
p_source text, p_row jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.plugin_insert_v1(p_source, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.plugin_insert_v2(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_find_v2(
p_source text, p_id uuid, p_lock_row boolean
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_find_v1(p_source, p_id, p_lock_row);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_find_v2(text, uuid, boolean) FROM PUBLIC;

CREATE FUNCTION api.privacy_latest_v2(
p_source text, p_query jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_latest_v1(p_source, p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_latest_v2(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_review_v2(
p_source text, p_query jsonb, p_row_limit integer, p_oldest boolean
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_review_v1(p_source, p_query, p_row_limit, p_oldest);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_review_v2(text, jsonb, integer, boolean) FROM PUBLIC;

CREATE FUNCTION api.privacy_update_v2(
p_source text, p_id uuid, p_changes jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_update_v1(p_source, p_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_update_v2(text, uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v2(
p_source text, p_user_id uuid, p_at text
)
RETURNS TABLE(revoked bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v1(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v2(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.privacy_may_export_v2(
p_user_id uuid
)
RETURNS TABLE(allowed boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_may_export_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_may_export_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.privacy_discard_exports_v2(
p_user_id uuid
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_discard_exports_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_discard_exports_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_find_v2(
p_source text, p_query jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_find_v1(p_source, p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_find_v2(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.portability_progress_v2(
p_job_id uuid, p_progress jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_progress_v1(p_job_id, p_progress);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_progress_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.plugin_find_v2(
p_source text, p_query jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.plugin_find_v1(p_source, p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.plugin_find_v2(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.plugin_status_v2(
p_plugin_id uuid, p_status text, p_at text
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.plugin_status_v1(p_plugin_id, p_status, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.plugin_status_v2(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.plugin_hooks_v2(
p_hook_name text
)
RETURNS SETOF public.plugin_hooks
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.plugin_hooks_v1(p_hook_name);
$$;
REVOKE EXECUTE ON FUNCTION api.plugin_hooks_v2(text) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v2(
p_user_id uuid
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_publish_notification_v2(
p_channel text, p_payload text
)
RETURNS TABLE(sent boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_publish_notification_v1(p_channel, p_payload);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notification_v2(text, text) FROM PUBLIC;

CREATE FUNCTION api.ops_retention_purge_v2(
p_source text, p_cutoff timestamptz, p_row_limit integer
)
RETURNS TABLE(deleted bigint, ok integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_retention_purge_v1(p_source, p_cutoff, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v2(text, timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.ops_outbox_metrics_v2(
p_now timestamptz
)
RETURNS TABLE(pending bigint, failed bigint, retry_backlog bigint, dead_letters bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_outbox_metrics_v1(p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_outbox_metrics_v2(timestamptz) FROM PUBLIC;

CREATE FUNCTION api.ops_readiness_probe_v2(
p_source text
)
RETURNS TABLE(ready boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_readiness_probe_v1(p_source);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_readiness_probe_v2(text) FROM PUBLIC;

CREATE FUNCTION api.ops_query_budget_list_v2(
p_row_limit integer
)
RETURNS SETOF public.endpoint_query_budgets
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_query_budget_list_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_list_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.ops_query_budget_sync_v2(
p_rows jsonb, p_endpoint_names text[]
)
RETURNS TABLE(written bigint, removed text[])
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_query_budget_sync_v1(p_rows, p_endpoint_names);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_sync_v2(jsonb, text[]) FROM PUBLIC;

CREATE FUNCTION api.ops_partition_registry_v2(

)
RETURNS SETOF public.partition_registry
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_partition_registry_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_registry_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_realtime_settled_v2(
p_settle_seconds integer
)
RETURNS TABLE(settled_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_realtime_settled_v1(p_settle_seconds);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_settled_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.ops_realtime_poll_v2(
p_after_next_at timestamptz, p_after_created_at timestamptz, p_after_id uuid, p_settled_at timestamptz, p_settle_seconds integer, p_row_limit integer
)
RETURNS SETOF public.outbox_messages
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_realtime_poll_v1(p_after_next_at, p_after_created_at, p_after_id, p_settled_at, p_settle_seconds, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_poll_v2(timestamptz, timestamptz, uuid, timestamptz, integer, integer) FROM PUBLIC;

CREATE FUNCTION api.ops_replication_recovery_v2(

)
RETURNS TABLE(in_recovery boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_recovery_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_recovery_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_replication_standbys_v2(

)
RETURNS TABLE(application_name text, state text, sync_state text, replay_lag_seconds double precision, bytes_behind bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_standbys_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_standbys_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_replication_slots_v2(
p_standby boolean
)
RETURNS TABLE(slot_name text, slot_type text, active boolean, wal_status text, retained_bytes bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_slots_v1(p_standby);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_slots_v2(boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_replication_position_v2(

)
RETURNS TABLE(replay_age_seconds double precision, replay_pending_bytes bigint, receiving boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_position_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_position_v2() FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_role_v2(
p_query jsonb
)
RETURNS SETOF public.roles
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_role_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_permission_v2(
p_query jsonb
)
RETURNS SETOF public.permissions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_permission_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_permission_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_role_permission_v2(
p_query jsonb
)
RETURNS SETOF public.role_permissions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_role_permission_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_permission_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_audit_v2(
p_query jsonb
)
RETURNS SETOF public.audit_log
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_audit_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_audit_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_binding_v2(
p_query jsonb
)
RETURNS SETOF public.role_bindings
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_binding_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_binding_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_attachment_audits_v2(
p_action text, p_target_id uuid, p_target_type text
)
RETURNS TABLE(metadata jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_attachment_audits_v1(p_action, p_target_id, p_target_type);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_attachment_audits_v2(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_role_v2(
p_values jsonb
)
RETURNS SETOF public.roles
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_role_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_permission_v2(
p_values jsonb
)
RETURNS SETOF public.permissions
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_permission_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_permission_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_role_permission_v2(
p_values jsonb
)
RETURNS SETOF public.role_permissions
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_role_permission_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_permission_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_binding_v2(
p_values jsonb
)
RETURNS SETOF public.role_bindings
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_binding_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_binding_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_space_v2(
p_values jsonb
)
RETURNS SETOF public.spaces
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_space_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_space_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_category_v2(
p_values jsonb
)
RETURNS SETOF public.categories
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_category_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_category_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_update_category_v2(
p_category_id uuid, p_values jsonb
)
RETURNS SETOF public.categories
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_update_category_v1(p_category_id, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_update_category_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lock_binding_v2(
p_binding_id uuid
)
RETURNS SETOF public.role_bindings
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lock_binding_v1(p_binding_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lock_binding_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_revoke_binding_v2(
p_binding_id uuid, p_revoked_at timestamptz
)
RETURNS SETOF public.role_bindings
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_revoke_binding_v1(p_binding_id, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_revoke_binding_v2(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.admin_list_roles_v2(
p_row_limit integer
)
RETURNS SETOF public.roles
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_roles_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_roles_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_permissions_v2(
p_row_limit integer
)
RETURNS SETOF public.permissions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_permissions_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_permissions_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_categories_v2(
p_row_limit integer
)
RETURNS SETOF public.categories
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_categories_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_categories_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_roles_for_user_v2(
p_user_id uuid, p_row_limit integer
)
RETURNS SETOF public.role_bindings
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_roles_for_user_v1(p_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_roles_for_user_v2(uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_permissions_for_role_v2(
p_role_id uuid, p_row_limit integer
)
RETURNS SETOF public.role_permissions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_permissions_for_role_v1(p_role_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permissions_for_role_v2(uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_space_by_id_v2(
p_space_id uuid
)
RETURNS SETOF public.spaces
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_space_by_id_v1(p_space_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_id_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_space_by_slug_v2(
p_slug text
)
RETURNS SETOF public.spaces
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_space_by_slug_v1(p_slug);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_slug_v2(text) FROM PUBLIC;

CREATE FUNCTION api.admin_first_live_space_v2(

)
RETURNS SETOF public.spaces
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_first_live_space_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.admin_first_live_space_v2() FROM PUBLIC;

CREATE FUNCTION api.admin_category_by_id_v2(
p_category_id uuid
)
RETURNS SETOF public.categories
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_category_by_id_v1(p_category_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_category_by_id_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_live_category_by_slug_v2(
p_space_id uuid, p_slug text
)
RETURNS SETOF public.categories
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_live_category_by_slug_v1(p_space_id, p_slug);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_live_category_by_slug_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.admin_console_users_v2(
p_status text, p_row_limit integer
)
RETURNS TABLE(id uuid, username text, display_name text, email_normalized text, status text, trust_level integer, email_verified_at timestamptz, created_at timestamptz, updated_at timestamptz, deleted_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_users_v1(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_users_v2(text, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_reports_v2(
p_status text, p_row_limit integer
)
RETURNS TABLE(report_id uuid, reporter_user_id uuid, target_type text, target_id uuid, reason text, details text, status text, assigned_moderator_user_id uuid, created_at timestamptz, resolved_at timestamptz, resolution text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_reports_v1(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_reports_v2(text, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_outbox_v2(
p_status text, p_row_limit integer
)
RETURNS TABLE(outbox_id uuid, event_id uuid, queue text, job_type text, idempotency_key text, available_at timestamptz, created_at timestamptz, locked_at timestamptz, attempts integer, status text, last_error text, next_attempt_at timestamptz, locked_by text, locked_until timestamptz, attempt_count integer, last_error_class text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_outbox_v1(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_outbox_v2(text, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_email_v2(
p_user_id uuid
)
RETURNS TABLE(email_normalized text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_email_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_email_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_console_counts_v2(
p_dead_letters boolean
)
RETURNS TABLE(total bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_counts_v1(p_dead_letters);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_counts_v2(boolean) FROM PUBLIC;

CREATE FUNCTION api.admin_console_dead_letters_v2(
p_row_limit integer
)
RETURNS TABLE(dead_letter_id uuid, source_table text, source_id uuid, error_class text, error_message text, failure_type text, retry_count integer, first_failed_at timestamptz, last_failed_at timestamptz, replay_status text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_dead_letters_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_dead_letters_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_audit_recent_v2(
p_row_limit integer
)
RETURNS SETOF public.audit_log
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_audit_recent_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_recent_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_audit_page_v2(
p_filters jsonb, p_after jsonb, p_row_limit integer
)
RETURNS SETOF public.audit_log
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_audit_page_v1(p_filters, p_after, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_page_v2(jsonb, jsonb, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_allow_slow_answer_v2(
p_idle_ms integer
)
RETURNS TABLE(timeout text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_allow_slow_answer_v1(p_idle_ms);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_allow_slow_answer_v2(integer) FROM PUBLIC;

CREATE FUNCTION api.forum_read_state_v2(
p_user_id uuid, p_thread_id uuid
)
RETURNS SETOF public.thread_read_state
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_read_state_v1(p_user_id, p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_state_v2(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_mark_read_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_mark_read_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_mark_read_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_find_v2(
p_attachment_id uuid, p_object_key text, p_hold boolean
)
RETURNS SETOF public.attachments
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_find_v1(p_attachment_id, p_object_key, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_find_v2(uuid, text, boolean) FROM PUBLIC;

CREATE FUNCTION api.attachment_links_v2(
p_attachment_id uuid, p_target_type text, p_target_id uuid, p_post_ids uuid[], p_row_limit integer
)
RETURNS SETOF public.attachment_links
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_links_v1(p_attachment_id, p_target_type, p_target_id, p_post_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_links_v2(uuid, text, uuid, uuid[], integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_variants_v2(
p_attachment_id uuid, p_variant_type text, p_object_key text, p_row_limit integer
)
RETURNS SETOF public.attachment_variants
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_variants_v1(p_attachment_id, p_variant_type, p_object_key, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variants_v2(uuid, text, text, integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_insert_v2(
p_values jsonb
)
RETURNS SETOF public.attachments
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_insert_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_link_insert_v2(
p_values jsonb
)
RETURNS SETOF public.attachment_links
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_link_insert_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_link_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_variant_insert_v2(
p_values jsonb
)
RETURNS SETOF public.attachment_variants
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_variant_insert_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variant_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_update_v2(
p_attachment_id uuid, p_changes jsonb
)
RETURNS SETOF public.attachments
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_update_v1(p_attachment_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_update_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_verdict_v2(
p_attachment_id uuid, p_changes jsonb
)
RETURNS TABLE(changed_count bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_scan_verdict_v1(p_attachment_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_verdict_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_queue_v2(
p_pending boolean, p_row_limit integer
)
RETURNS TABLE(attachment_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_scan_queue_v1(p_pending, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_queue_v2(boolean, integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_confirm_clean_v2(
p_attachment_id uuid, p_scan_engine text, p_scanned_at timestamptz
)
RETURNS TABLE(changed_count bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_confirm_clean_v1(p_attachment_id, p_scan_engine, p_scanned_at);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_confirm_clean_v2(uuid, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_failure_v2(
p_attachment_id uuid, p_error text
)
RETURNS TABLE(changed_count bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_scan_failure_v1(p_attachment_id, p_error);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_failure_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.attachment_orphans_v2(
p_cutoff timestamptz, p_row_limit integer
)
RETURNS SETOF public.attachments
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_orphans_v1(p_cutoff, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_orphans_v2(timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_post_v2(
p_target_id uuid
)
RETURNS SETOF public.posts
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_source_post_v1(p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_post_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_thread_v2(
p_target_id uuid
)
RETURNS SETOF public.threads
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_source_thread_v1(p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_thread_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.community_list_bookmarks_v2(
p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_target_type text,
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (bookmark_id uuid, user_id uuid, target_type text, target_id uuid, note text, created_at timestamptz, deleted_at timestamptz, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_bookmarks_v1(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_target_type, p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmarks_v2(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_list_feed_v2(
p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (user_id uuid, item_type text, item_id uuid, created_at timestamptz, rank_score numeric, visibility_version bigint, permission_version bigint, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_feed_v1(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_feed_v2(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_list_mentions_v2(
p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (mention_id uuid, source_type text, source_id uuid, actor_id uuid, mentioned_user_id uuid, mentioned_username text, created_at timestamptz, actor_username text, actor_display_name text, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_mentions_v1(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_mentions_v2(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_save_bookmark_v2(
p_row jsonb,
    p_restore boolean
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_save_bookmark_v1(p_row, p_restore);
$$;
REVOKE EXECUTE ON FUNCTION api.community_save_bookmark_v2(jsonb, boolean) FROM PUBLIC;

CREATE FUNCTION api.community_find_bookmark_v2(
p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF public.bookmarks
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_find_bookmark_v1(p_user_id, p_target_type, p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_find_bookmark_v2(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.community_stamp_bookmark_v2(
p_id uuid,
    p_by_target boolean,
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_column text,
    p_stamped_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_stamp_bookmark_v1(p_id, p_by_target, p_user_id, p_target_type, p_target_id, p_column, p_stamped_at);
$$;
REVOKE EXECUTE ON FUNCTION api.community_stamp_bookmark_v2(uuid, boolean, uuid, text, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.notification_save_subscription_v2(
p_row jsonb,
    p_restore boolean
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_save_subscription_v1(p_row, p_restore);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_save_subscription_v2(jsonb, boolean) FROM PUBLIC;

CREATE FUNCTION api.notification_find_subscription_v2(
p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF public.subscriptions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_find_subscription_v1(p_user_id, p_target_type, p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_find_subscription_v2(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_stamp_subscription_v2(
p_id uuid,
    p_by_target boolean,
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_column text,
    p_stamped_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_stamp_subscription_v1(p_id, p_by_target, p_user_id, p_target_type, p_target_id, p_column, p_stamped_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_stamp_subscription_v2(uuid, boolean, uuid, text, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.notification_subscribers_v2(
p_target_type text,
    p_target_id uuid,
    p_notification_type text
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_subscribers_v1(p_target_type, p_target_id, p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_subscribers_v2(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_list_preferences_v2(
p_user_id uuid
)
RETURNS SETOF public.notification_preferences
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_preferences_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_preferences_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_set_preference_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_set_preference_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_preference_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_project_feed_v2(
p_row jsonb,
    p_user_ids uuid[]
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_project_feed_v1(p_row, p_user_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.community_project_feed_v2(jsonb, uuid[]) FROM PUBLIC;

CREATE FUNCTION api.community_remove_feed_v2(
p_item_type text,
    p_item_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_remove_feed_v1(p_item_type, p_item_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_feed_v2(text, uuid) FROM PUBLIC;

CREATE FUNCTION api.community_remove_thread_feed_v2(
p_thread_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_remove_thread_feed_v1(p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_thread_feed_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.community_resolve_mention_users_v2(
p_usernames text[]
)
RETURNS TABLE (id uuid, username text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_resolve_mention_users_v1(p_usernames);
$$;
REVOKE EXECUTE ON FUNCTION api.community_resolve_mention_users_v2(text[]) FROM PUBLIC;

CREATE FUNCTION api.community_create_mention_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_create_mention_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_create_mention_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_record_reputation_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_record_reputation_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_record_reputation_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_deliver_v2(
p_notification jsonb,
    p_inbox jsonb,
    p_idempotency_key text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_deliver_v1(p_notification, p_inbox, p_idempotency_key);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_deliver_v2(jsonb, jsonb, text) FROM PUBLIC;

CREATE FUNCTION api.notification_mark_read_v2(
p_notification_id uuid,
    p_recipient_user_id uuid,
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_mark_read_v1(p_notification_id, p_recipient_user_id, p_read_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_read_v2(uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_mark_all_read_v2(
p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_mark_all_read_v1(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_read_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_all_read_v2(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_v2(
p_kind text, p_target_id uuid, p_hold boolean
)
RETURNS TABLE(target_id uuid, moderation_state text, locked_at timestamptz, hidden_at timestamptz)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_target_v1(p_kind, p_target_id, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_v2(text, uuid, boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_update_v2(
p_kind text, p_target_id uuid, p_changes jsonb
)
RETURNS TABLE(changed_count bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_target_update_v1(p_kind, p_target_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v2(text, uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_find_v2(
p_action_id uuid, p_command_id uuid, p_action_type text, p_target_type text, p_target_id uuid
)
RETURNS SETOF public.moderation_actions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_find_v1(p_action_id, p_command_id, p_action_type, p_target_type, p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_find_v2(uuid, uuid, text, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_update_v2(
p_action_id uuid, p_changes jsonb
)
RETURNS SETOF public.moderation_actions
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_update_v1(p_action_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_update_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_find_v2(
p_report_id uuid, p_reporter_user_id uuid, p_target_type text, p_target_id uuid, p_hold boolean
)
RETURNS SETOF public.reports
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_find_v1(p_report_id, p_reporter_user_id, p_target_type, p_target_id, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_find_v2(uuid, uuid, text, uuid, boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_update_v2(
p_report_id uuid, p_changes jsonb
)
RETURNS SETOF public.reports
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_update_v1(p_report_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_update_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_queue_v2(
p_status text, p_row_limit integer
)
RETURNS SETOF public.reports
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_queue_v1(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_queue_v2(text, integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_find_v2(
p_suspension_id uuid
)
RETURNS SETOF public.suspensions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_find_v1(p_suspension_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_find_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_update_v2(
p_suspension_id uuid, p_revoked_at timestamptz
)
RETURNS SETOF public.suspensions
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_update_v1(p_suspension_id, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_update_v2(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_insert_v2(
p_values jsonb
)
RETURNS SETOF public.moderation_actions
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_insert_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_insert_v2(
p_values jsonb
)
RETURNS SETOF public.reports
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_insert_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_insert_v2(
p_values jsonb
)
RETURNS SETOF public.suspensions
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_insert_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_list_v2(
p_target_type text, p_target_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer
)
RETURNS SETOF public.moderation_actions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_list_v1(p_target_type, p_target_id, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_list_v2(text, uuid, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_list_v2(
p_user_id uuid, p_active_only boolean, p_now timestamptz, p_after_at timestamptz, p_after_id uuid, p_row_limit integer
)
RETURNS SETOF public.suspensions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_list_v1(p_user_id, p_active_only, p_now, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_list_v2(uuid, boolean, timestamptz, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.ops_record_event_v2(
p_event jsonb,p_outbox_id text,p_outbox_extras jsonb,p_explicit boolean
)
RETURNS TABLE(event json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_record_event_v1(p_event, p_outbox_id, p_outbox_extras, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_record_event_v2(jsonb, text, jsonb, boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_record_audit_v2(
p_audit jsonb,p_explicit boolean
)
RETURNS TABLE(audit json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_record_audit_v1(p_audit, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_record_audit_v2(jsonb, boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_event_recorded_v2(
p_key text
)
RETURNS TABLE(recorded boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_event_recorded_v1(p_key);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_event_recorded_v2(text) FROM PUBLIC;

CREATE FUNCTION api.ops_command_lookup_v2(
p_key text,p_command_id uuid
)
RETURNS TABLE(document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_command_lookup_v1(p_key, p_command_id);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_lookup_v2(text, uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_command_insert_v2(
p_command jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_command_insert_v1(p_command);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_insert_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_command_finish_v2(
p_command_id uuid,p_changes jsonb
)
RETURNS TABLE(success boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_command_finish_v1(p_command_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_finish_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_event_claim_v2(
p_operation text,p_key text,p_event_id text,p_now text,p_expired_before text
)
RETURNS TABLE(claimed boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_event_claim_v1(p_operation, p_key, p_event_id, p_now, p_expired_before);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_event_claim_v2(text, text, text, text, text) FROM PUBLIC;

CREATE FUNCTION api.outbox_claim_ready_v2(
p_now text,p_locked_until text,p_worker_id text,p_row_limit integer
)
RETURNS SETOF public.outbox_messages
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_claim_ready_v1(p_now, p_locked_until, p_worker_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_claim_ready_v2(text, text, text, integer) FROM PUBLIC;

CREATE FUNCTION api.outbox_owned_write_v2(
p_outbox_id uuid,p_worker_id text,p_changes jsonb
)
RETURNS TABLE(landed boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_owned_write_v1(p_outbox_id, p_worker_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_owned_write_v2(uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.outbox_dead_letter_v2(
p_letter jsonb
)
RETURNS TABLE(letter json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_dead_letter_v1(p_letter);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_dead_letter_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.outbox_replay_dead_letter_v2(
p_input jsonb,p_ids jsonb,p_now text
)
RETURNS TABLE(result json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_replay_dead_letter_v1(p_input, p_ids, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_replay_dead_letter_v2(jsonb, jsonb, text) FROM PUBLIC;

CREATE FUNCTION api.projection_offset_get_v2(
p_projection_name text
)
RETURNS TABLE(document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.projection_offset_get_v1(p_projection_name);
$$;
REVOKE EXECUTE ON FUNCTION api.projection_offset_get_v2(text) FROM PUBLIC;

CREATE FUNCTION api.projection_offset_write_v2(
p_row jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.projection_offset_write_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.projection_offset_write_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.projection_generation_start_v2(
p_row jsonb
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.projection_generation_start_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.projection_generation_start_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.projection_generation_update_v2(
p_generation_id uuid,p_status text
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.projection_generation_update_v1(p_generation_id, p_status);
$$;
REVOKE EXECUTE ON FUNCTION api.projection_generation_update_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.projection_generation_activate_v2(
p_generation_id uuid,p_now text
)
RETURNS TABLE(document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.projection_generation_activate_v1(p_generation_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.projection_generation_activate_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.ops_worker_aggregate_v2(
p_aggregate_type text,p_aggregate_id uuid
)
RETURNS TABLE(author_user_id uuid,thread_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_worker_aggregate_v1(p_aggregate_type, p_aggregate_id);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_worker_aggregate_v2(text, uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_thread_activity_v2(
p_thread_id uuid,p_at text
)
RETURNS TABLE(bumped bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_thread_activity_v1(p_thread_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_thread_activity_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.identity_user_by_id_v2(
p_user_id uuid
)
RETURNS SETOF public.users
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_user_by_id_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_id_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_user_by_identifier_v2(
p_identifier text, p_by_email boolean
)
RETURNS SETOF public.users
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_user_by_identifier_v1(p_identifier, p_by_email);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_identifier_v2(text, boolean) FROM PUBLIC;

CREATE FUNCTION api.identity_registration_duplicates_v2(
p_username text, p_email text
)
RETURNS TABLE(username_taken boolean, email_taken boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_registration_duplicates_v1(p_username, p_email);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_registration_duplicates_v2(text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_user_v2(
p_values jsonb
)
RETURNS SETOF public.users
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_insert_user_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_user_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_update_user_v2(
p_user_id uuid, p_changes jsonb
)
RETURNS SETOF public.users
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_update_user_v1(p_user_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_credential_v2(
p_values jsonb
)
RETURNS SETOF public.credentials
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_insert_credential_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_credential_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_credential_by_id_v2(
p_credential_id uuid
)
RETURNS SETOF public.credentials
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_credential_by_id_v1(p_credential_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_credential_by_id_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_active_password_v2(
p_user_id uuid
)
RETURNS SETOF public.credentials
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_active_password_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_active_password_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_hold_password_v2(
p_user_id uuid, p_credential_id uuid
)
RETURNS SETOF public.credentials
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_hold_password_v1(p_user_id, p_credential_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_hold_password_v2(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_lock_passwords_v2(
p_user_id uuid
)
RETURNS SETOF public.credentials
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_lock_passwords_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_lock_passwords_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_revoke_passwords_v2(
p_ids jsonb, p_revoked_at timestamptz
)
RETURNS TABLE(updated integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_revoke_passwords_v1(p_ids, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_revoke_passwords_v2(jsonb, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_token_v2(
p_values jsonb
)
RETURNS SETOF public.identity_tokens
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_insert_token_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_token_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_token_by_id_v2(
p_token_id uuid
)
RETURNS SETOF public.identity_tokens
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_token_by_id_v1(p_token_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_token_by_id_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_unused_token_v2(
p_user_id uuid, p_token_type text
)
RETURNS SETOF public.identity_tokens
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_unused_token_v1(p_user_id, p_token_type);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_unused_token_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.identity_rotate_token_v2(
p_token_id uuid, p_values jsonb
)
RETURNS SETOF public.identity_tokens
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_rotate_token_v1(p_token_id, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_rotate_token_v2(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_consume_token_v2(
p_token_hash text, p_token_type text, p_now timestamptz, p_now_epoch bigint
)
RETURNS TABLE(result_code text, token_row jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_consume_token_v1(p_token_hash, p_token_type, p_now, p_now_epoch);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_consume_token_v2(text, text, timestamptz, bigint) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_trust_v2(
p_user_id uuid
)
RETURNS SETOF public.trust_score_snapshots
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_trust_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_trust_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_counts_v2(
p_user_id uuid
)
RETURNS TABLE(public_threads bigint, public_replies bigint, total_public bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_counts_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_counts_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_threads_v2(
p_user_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer
)
RETURNS TABLE(thread_id uuid, category_id uuid, author_user_id uuid, title text, slug text, visibility text, moderation_state text, last_activity_at timestamptz, created_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_threads_v1(p_user_id, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_threads_v2(uuid, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_replies_v2(
p_user_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer
)
RETURNS TABLE(post_id uuid, thread_id uuid, author_user_id uuid, "position" bigint, visibility text, moderation_state text, created_at timestamptz, thread_title text, thread_slug text, body text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_replies_v1(p_user_id, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_replies_v2(uuid, timestamptz, uuid, integer) FROM PUBLIC;

COMMIT;
