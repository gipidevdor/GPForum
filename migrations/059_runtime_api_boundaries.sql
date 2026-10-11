-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0127: versioned entry points for a separate EXECUTE-only runtime role.
-- The v1 implementations and their original contracts remain unchanged.
-- Every wrapper forwards typed parameters to exactly its own implementation.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.session_lookup_v2(
p_session_id uuid, p_user_id uuid
)
RETURNS SETOF public.sessions
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_lookup_v1(p_session_id, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.session_lookup_v2(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.session_create_v2(
p_session_id uuid, p_user_id uuid, p_session_hash text,
    p_created_at timestamptz, p_last_seen_at timestamptz,
    p_expires_at timestamptz, p_revoked_at timestamptz, p_ip_hash text,
    p_user_agent_hash text, p_retry boolean
)
RETURNS TABLE (result_code text, session_id uuid, user_id uuid, session_hash text,
    created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
    revoked_at timestamptz, ip_hash text, user_agent_hash text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_create_v1(p_session_id, p_user_id, p_session_hash, p_created_at, p_last_seen_at, p_expires_at, p_revoked_at, p_ip_hash, p_user_agent_hash, p_retry);
$$;
REVOKE EXECUTE ON FUNCTION api.session_create_v2(uuid, uuid, text, timestamptz, timestamptz, timestamptz, timestamptz, text, text, boolean) FROM PUBLIC;

CREATE FUNCTION api.session_validate_v2(
p_session_id uuid, p_user_id uuid, p_token_hash text,
    p_now timestamptz, p_touch_interval_seconds integer
)
RETURNS TABLE (result_code text, session_id uuid, user_id uuid, session_hash text,
    created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
    revoked_at timestamptz, ip_hash text, user_agent_hash text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_validate_v1(p_session_id, p_user_id, p_token_hash, p_now, p_touch_interval_seconds);
$$;
REVOKE EXECUTE ON FUNCTION api.session_validate_v2(uuid, uuid, text, timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.session_revoke_v2(
p_session_id uuid, p_user_id uuid,
    p_revoked_at timestamptz
)
RETURNS TABLE (result_code text, session_id uuid, user_id uuid, session_hash text,
    created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
    revoked_at timestamptz, ip_hash text, user_agent_hash text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_revoke_v1(p_session_id, p_user_id, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.session_revoke_v2(uuid, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.session_revoke_user_v2(
p_user_id uuid, p_revoked_at timestamptz,
    p_keep_session_id uuid
)
RETURNS TABLE (revoked_count bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_revoke_user_v1(p_user_id, p_revoked_at, p_keep_session_id);
$$;
REVOKE EXECUTE ON FUNCTION api.session_revoke_user_v2(uuid, timestamptz, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v2(
p_user_id uuid
)
RETURNS TABLE (status text, suspended boolean, grants json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_resolve_viewer_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_rate_limit_check_v2(
p_scope text, p_actor_hash text, p_action text,
    p_window_start timestamptz, p_window_seconds integer, p_limit integer,
    p_now timestamptz, p_expires_at timestamptz
)
RETURNS TABLE (scope text, actor_hash text, action text, window_started_at timestamptz,
    observed_count integer, blocked_count integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_rate_limit_check_v1(p_scope, p_actor_hash, p_action, p_window_start, p_window_seconds, p_limit, p_now, p_expires_at);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_check_v2(text, text, text, timestamptz, integer, integer, timestamptz, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.ops_rate_limit_snapshot_v2(
p_now timestamptz
)
RETURNS TABLE (buckets bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_rate_limit_snapshot_v1(p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_snapshot_v2(timestamptz) FROM PUBLIC;

CREATE FUNCTION api.moderation_active_suspension_v2(
p_user_id uuid, p_now text
)
RETURNS TABLE (suspension_id uuid, user_id uuid, actor_user_id uuid, reason text,
    valid_from timestamptz, valid_to timestamptz, revoked_at timestamptz,
    metadata jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_active_suspension_v1(p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.moderation_can_participate_v2(
p_user_id uuid, p_now text
)
RETURNS TABLE (ok integer, reason text, suspension_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_can_participate_v1(p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.admin_permission_allowed_v2(
p_user_id uuid, p_resource_type text,
    p_action text, p_resource_id uuid, p_space_id uuid
)
RETURNS TABLE (allowed boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_permission_allowed_v1(p_user_id, p_resource_type, p_action, p_resource_id, p_space_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v2(uuid, text, text, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_list_inbox_v2(
p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_notification_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    recipient_user_id uuid, notification_id uuid, created_at timestamptz,
    read_at timestamptz, rank_score numeric, source_type text, source_id uuid,
    notification_type text, payload jsonb, source_thread_id uuid, source_thread_title text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_inbox_v1(p_recipient_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_after_created_at, p_after_notification_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v2(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_unread_count_v2(
p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[]
)
RETURNS TABLE (unread_count bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unread_count_v1(p_recipient_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v2(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_store_write_v2(
p_store_type text,p_command jsonb,p_record jsonb
)
RETURNS TABLE(stored json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_store_write_v1(p_store_type, p_command, p_record);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v2(text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v2(
p_log jsonb,p_answer jsonb,p_store_type text,p_command jsonb,p_record jsonb
)
RETURNS TABLE(outcome text,response json,stored json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_write_command_v1(p_log, p_answer, p_store_type, p_command, p_record);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v2(jsonb, jsonb, text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_find_category_v2(
p_category_id uuid
)
RETURNS TABLE (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    space_visibility text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_category_v1(p_category_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_category_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_list_categories_v2(
p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_categories_v1(p_member, p_global_read, p_category_ids, p_space_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v2(boolean, boolean, uuid[], uuid[], integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_category_threads_v2(
p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_pinned boolean,
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_category_threads_v1(p_category_id, p_member, p_global_read, p_scope_user_id, p_viewer_user_id, p_after_pinned, p_after_activity, p_after_thread_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v2(uuid, boolean, boolean, uuid, uuid, boolean, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_public_threads_v2(
p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_public_threads_v1(p_member, p_global_read, p_category_ids, p_space_ids, p_after_activity, p_after_thread_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v2(boolean, boolean, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_find_post_v2(
p_post_id uuid
)
RETURNS SETOF public.posts
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_post_v1(p_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_post_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_visible_post_v2(
p_post_id uuid
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    current_revision_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    version bigint,
    visibility_version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    hidden_at timestamptz,
    locked_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid,
    thread_visibility text,
    thread_author uuid,
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_visible_post_v1(p_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_visible_post_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_listed_post_v2(
p_post_id uuid,
    p_thread_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    deleted_at timestamptz,
    body text,
    body_source text,
    author_username text,
    author_display_name text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_listed_post_v1(p_post_id, p_thread_id, p_member, p_global_read, p_scope_user_id, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v2(uuid, uuid, boolean, boolean, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_placement_v2(
p_source_id uuid
)
RETURNS TABLE (
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_deleted_at timestamptz
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_placement_v1(p_source_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_placement_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_post_placement_v2(
p_source_id uuid
)
RETURNS TABLE (
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text,
    thread_author uuid,
    thread_visibility text,
    post_author uuid,
    post_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_deleted_at timestamptz,
    post_deleted_at timestamptz,
    post_state text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_post_placement_v1(p_source_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_placement_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_head_v2(
p_thread_id uuid
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    category_title text,
    category_visibility text,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_head_v1(p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_head_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_v2(
p_thread_id uuid,
    p_standing text,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    deleted_at timestamptz,
    body text,
    body_source text,
    author_username text,
    author_display_name text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_posts_v1(p_thread_id, p_standing, p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v2(uuid, text, uuid, bigint, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v2(
p_idempotency_key text,
    p_command_type text,
    p_actor_id text,
    p_request_hash text,
    p_command_id text,
    p_command_correlation_id text,
    p_command_at text,
    p_answer jsonb,
    p_store_refusals jsonb,
    p_post_id text,
    p_thread_id text,
    p_author_user_id text,
    p_current_body_id text,
    p_current_revision_id text,
    p_position bigint,
    p_visibility text,
    p_moderation_state text,
    p_version bigint,
    p_visibility_version bigint,
    p_permission_version bigint,
    p_hidden_at text,
    p_locked_at text,
    p_deleted_at text,
    p_deleted_by text,
    p_body_id text,
    p_body_post_id text,
    p_body_format text,
    p_body_source text,
    p_body_rendered_safe text,
    p_source_hash text,
    p_revision_id text,
    p_revision_post_id text,
    p_revision_body_id text,
    p_editor_user_id text,
    p_revision_number integer,
    p_edit_reason text,
    p_correlation_id text,
    p_event_id text,
    p_outbox_id text,
    p_audit_id text,
    p_recorded_at text
)
RETURNS TABLE (
    outcome text,
    response json,
    skipped boolean,
    post_id text,
    thread_id text,
    author_user_id text,
    current_body_id text,
    current_revision_id text,
    "position" text,
    visibility text,
    moderation_state text,
    version text,
    visibility_version text,
    permission_version text,
    hidden_at text,
    locked_at text,
    deleted_at text,
    deleted_by text
)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_create_reply_v1(p_idempotency_key, p_command_type, p_actor_id, p_request_hash, p_command_id, p_command_correlation_id, p_command_at, p_answer, p_store_refusals, p_post_id, p_thread_id, p_author_user_id, p_current_body_id, p_current_revision_id, p_position, p_visibility, p_moderation_state, p_version, p_visibility_version, p_permission_version, p_hidden_at, p_locked_at, p_deleted_at, p_deleted_by, p_body_id, p_body_post_id, p_body_format, p_body_source, p_body_rendered_safe, p_source_hash, p_revision_id, p_revision_post_id, p_revision_body_id, p_editor_user_id, p_revision_number, p_edit_reason, p_correlation_id, p_event_id, p_outbox_id, p_audit_id, p_recorded_at);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v2(text, text, text, text, text, text, text, jsonb, jsonb, text, text, text, text, text, bigint, text, text, bigint, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text, text, text, text, integer, text, text, text, text, text, text) FROM PUBLIC;


CREATE FUNCTION api.forum_thread_page_posts_scoped_v2(
p_thread_id uuid,
    p_standing text,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid, thread_id uuid, author_user_id uuid, current_body_id uuid,
    "position" bigint, visibility text, moderation_state text,
    created_at timestamptz, deleted_at timestamptz, body text,
    body_source text, author_username text, author_display_name text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_posts_scoped_v1(p_thread_id, p_standing, p_scope_user_id, p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_scoped_v2(uuid, text, uuid, uuid, bigint, uuid, integer) FROM PUBLIC;

COMMIT;
