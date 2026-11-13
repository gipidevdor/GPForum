-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: api entry points.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.admin_address_ban_covering_v2(
    p_address inet,
    p_now timestamptz
)
RETURNS TABLE (
    ban_id uuid,
    address_range text,
    scope text,
    expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_covering_v1(p_address, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_covering_v2(p_address inet, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.admin_address_ban_edit_v2(
    p_ban_id uuid,
    p_scope text,
    p_reason text,
    p_expires_at timestamptz,
    p_actor_user_id uuid,
    p_actor_address inet,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, ban_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_edit_v1(p_ban_id, p_scope, p_reason,
    p_expires_at, p_actor_user_id, p_actor_address, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_edit_v2(p_ban_id uuid, p_scope text, p_reason text, p_expires_at timestamp with time zone, p_actor_user_id uuid, p_actor_address inet, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_address_ban_lift_v2(
    p_ban_id uuid,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, ban_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_lift_v1(p_ban_id, p_actor_user_id,
    p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_lift_v2(p_ban_id uuid, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_address_ban_place_v2(
    p_ban_id uuid,
    p_range cidr,
    p_scope text,
    p_reason text,
    p_expires_at timestamptz,
    p_actor_user_id uuid,
    p_actor_address inet,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, ban_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_place_v1(p_ban_id, p_range, p_scope,
    p_reason, p_expires_at, p_actor_user_id, p_actor_address, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_place_v2(p_ban_id uuid, p_range cidr, p_scope text, p_reason text, p_expires_at timestamp with time zone, p_actor_user_id uuid, p_actor_address inet, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_address_bans_v2(
    p_now timestamptz,
    p_row_limit integer
)
RETURNS TABLE (
    ban_id uuid,
    address_range text,
    scope text,
    reason text,
    created_at timestamptz,
    created_by_username text,
    expires_at timestamptz,
    updated_at timestamptz,
    updated_by_username text,
    lifted_at timestamptz,
    lifted_by_username text,
    state text,
    live_total bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_bans_v1(p_now, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_bans_v2(p_now timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_allow_slow_answer_v2(p_idle_ms integer)
RETURNS TABLE (timeout text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_allow_slow_answer_v1(p_idle_ms);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_allow_slow_answer_v2(p_idle_ms integer) FROM PUBLIC;

CREATE FUNCTION api.admin_announcement_by_id_v2(p_announcement_id uuid)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_announcement_by_id_v1(p_announcement_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_announcement_by_id_v2(p_announcement_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_attachment_audits_v2(
    p_action text,
    p_target_id uuid,
    p_target_type text
)
RETURNS TABLE (metadata jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_attachment_audits_v1(p_action, p_target_id, p_target_type);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_attachment_audits_v2(p_action text, p_target_id uuid, p_target_type text) FROM PUBLIC;

CREATE FUNCTION api.admin_audit_recent_v2(p_row_limit integer)
RETURNS SETOF api.admin_audit_entry_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_audit_recent_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_recent_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_category_by_id_v2(p_category_id uuid)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_category_by_id_v1(p_category_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_category_by_id_v2(p_category_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_console_counts_v2(p_dead_letters boolean)
RETURNS TABLE (total bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_counts_v1(p_dead_letters);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_counts_v2(p_dead_letters boolean) FROM PUBLIC;

CREATE FUNCTION api.admin_console_dead_letters_v2(p_row_limit integer)
RETURNS TABLE (
    dead_letter_id uuid,
    source_table text,
    source_id uuid,
    error_class text,
    error_message text,
    failure_type text,
    retry_count integer,
    first_failed_at timestamptz,
    last_failed_at timestamptz,
    replay_status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_dead_letters_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_dead_letters_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_email_v2(p_user_id uuid)
RETURNS TABLE (email_normalized text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_email_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_email_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_console_reports_v2(
    p_status text,
    p_row_limit integer
)
RETURNS TABLE (
    report_id uuid,
    reporter_user_id uuid,
    target_type text,
    target_id uuid,
    reason text,
    details text,
    status text,
    assigned_moderator_user_id uuid,
    created_at timestamptz,
    resolved_at timestamptz,
    resolution text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_reports_v1(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_reports_v2(p_status text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_first_live_space_v2()
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_first_live_space_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.admin_first_live_space_v2() FROM PUBLIC;

CREATE FUNCTION api.admin_insert_announcement_v2(p_values jsonb)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_announcement_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_announcement_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_binding_v2(p_values jsonb)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_binding_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_binding_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_category_v2(p_values jsonb)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_category_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_category_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_permission_v2(p_values jsonb)
RETURNS SETOF api.admin_permission_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_permission_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_permission_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_role_permission_v2(p_values jsonb)
RETURNS SETOF api.admin_role_permission_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_role_permission_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_permission_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_role_v2(p_values jsonb)
RETURNS SETOF api.admin_role_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_role_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_space_v2(p_values jsonb)
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_space_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_space_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_list_announcements_v2(p_row_limit integer)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_announcements_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_announcements_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_categories_v2(p_row_limit integer)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_categories_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_categories_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_permissions_v2(p_row_limit integer)
RETURNS SETOF api.admin_permission_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_permissions_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_permissions_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_roles_v2(p_row_limit integer)
RETURNS SETOF api.admin_role_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_roles_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_roles_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_live_category_by_slug_v2(
    p_space_id uuid,
    p_slug text
)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_live_category_by_slug_v1(p_space_id, p_slug);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_live_category_by_slug_v2(p_space_id uuid, p_slug text) FROM PUBLIC;

CREATE FUNCTION api.admin_lock_binding_v2(p_binding_id uuid)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lock_binding_v1(p_binding_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lock_binding_v2(p_binding_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_audit_v2(p_query jsonb)
RETURNS SETOF api.admin_audit_entry_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_audit_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_audit_v2(p_query jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_binding_v2(p_query jsonb)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_binding_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_binding_v2(p_query jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_permission_v2(p_query jsonb)
RETURNS SETOF api.admin_permission_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_permission_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_permission_v2(p_query jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_role_permission_v2(p_query jsonb)
RETURNS SETOF api.admin_role_permission_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_role_permission_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_permission_v2(p_query jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_role_v2(p_query jsonb)
RETURNS SETOF api.admin_role_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_lookup_role_v1(p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_v2(p_query jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_permission_allowed_v4(
    p_user_id uuid,
    p_resource_type text,
    p_action text,
    p_resource_id uuid,
    p_space_id uuid
)
RETURNS TABLE (allowed boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_permission_allowed_v3(p_user_id, p_resource_type,
    p_action, p_resource_id, p_space_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v4(p_user_id uuid, p_resource_type text, p_action text, p_resource_id uuid, p_space_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_retire_announcement_v2(
    p_announcement_id uuid,
    p_values jsonb
)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_retire_announcement_v1(p_announcement_id, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_retire_announcement_v2(p_announcement_id uuid, p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_revoke_binding_v2(
    p_binding_id uuid,
    p_revoked_at timestamptz
)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_revoke_binding_v1(p_binding_id, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_revoke_binding_v2(p_binding_id uuid, p_revoked_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.admin_roles_for_user_v2(
    p_user_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_roles_for_user_v1(p_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_roles_for_user_v2(p_user_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_member_v2(p_user_id uuid)
RETURNS TABLE (state text, confirmed_at timestamptz, recovery_left integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_member_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_member_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_policy_set_v2(
    p_required boolean,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_policy_set_v1(p_required,
    p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_set_v2(p_required boolean, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_policy_v2()
RETURNS TABLE (
    staff_required boolean,
    updated_at timestamptz,
    updated_by_username text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_policy_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_v2() FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_reset_v2(
    p_user_id uuid,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_reset_v1(p_user_id, p_actor_user_id,
    p_now, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_reset_v2(p_user_id uuid, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb, p_mail jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_staff_v2(p_row_limit integer)
RETURNS TABLE (
    user_id uuid,
    username text,
    display_name text,
    enabled boolean,
    confirmed_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_staff_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_staff_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.admin_space_by_id_v2(p_space_id uuid)
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_space_by_id_v1(p_space_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_id_v2(p_space_id uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_space_by_slug_v2(p_slug text)
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_space_by_slug_v1(p_slug);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_slug_v2(p_slug text) FROM PUBLIC;

CREATE FUNCTION api.admin_update_category_v2(
    p_category_id uuid,
    p_values jsonb
)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_update_category_v1(p_category_id, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_update_category_v2(p_category_id uuid, p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_image_v2(
    p_user_id uuid,
    p_variant_type text
)
RETURNS TABLE (
    attachment_id uuid,
    object_key text,
    media_type text,
    byte_size bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_image_v1(p_user_id, p_variant_type);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_image_v2(p_user_id uuid, p_variant_type text) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_objects_v2(
    p_user_id uuid,
    p_attachment_id uuid
)
RETURNS TABLE (attachment_id uuid, object_key text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_objects_v1(p_user_id, p_attachment_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_objects_v2(p_user_id uuid, p_attachment_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_offer_v2(
    p_user_id uuid,
    p_attachment_id uuid,
    p_now timestamptz
)
RETURNS TABLE (status text, replaced_attachment_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_offer_v1(p_user_id, p_attachment_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_offer_v2(p_user_id uuid, p_attachment_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_remove_v2(
    p_user_id uuid,
    p_attachment_id uuid,
    p_audit jsonb
)
RETURNS TABLE (status text, attachment_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_remove_v1(p_user_id, p_attachment_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_remove_v2(p_user_id uuid, p_attachment_id uuid, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_settle_v2(
    p_user_id uuid,
    p_attachment_id uuid,
    p_outcome text,
    p_now timestamptz
)
RETURNS TABLE (status text, replaced_attachment_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_settle_v1(p_user_id, p_attachment_id, p_outcome, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_settle_v2(p_user_id uuid, p_attachment_id uuid, p_outcome text, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_status_v2(p_user_id uuid)
RETURNS TABLE (
    attachment_id uuid,
    shown_at timestamptz,
    pending_attachment_id uuid,
    pending_state text,
    pending_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_status_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_status_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_bookmark_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_bookmark_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_bookmark_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_create_mention_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_create_mention_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_create_mention_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_find_bookmark_v2(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF api.community_bookmark_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_find_bookmark_v1(p_user_id, p_target_type, p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_find_bookmark_v2(p_user_id uuid, p_target_type text, p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_like_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_like_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_like_post_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_like_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_post_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_list_bookmarks_v4(
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
    p_row_limit integer,
    p_folder text
)
RETURNS TABLE (
    bookmark_id uuid,
    user_id uuid,
    target_type text,
    target_id uuid,
    note text,
    created_at timestamptz,
    deleted_at timestamptz,
    source_thread_id uuid,
    source_thread_title text,
    folder text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT * FROM api.community_list_bookmarks_v3(p_user_id, p_filter_sources,
    p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids,
    p_target_type, p_after_created_at, p_after_id, p_row_limit, p_folder);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmarks_v4(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_target_type text, p_after_created_at timestamp with time zone, p_after_id uuid, p_row_limit integer, p_folder text) FROM PUBLIC;

CREATE FUNCTION api.community_list_feed_v4(
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
RETURNS TABLE (
    user_id uuid,
    item_type text,
    item_id uuid,
    created_at timestamptz,
    rank_score numeric,
    visibility_version bigint,
    permission_version bigint,
    source_thread_id uuid,
    source_thread_title text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_feed_v3(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_feed_v4(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_after_created_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.community_list_mentions_v4(
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
RETURNS TABLE (
    mention_id uuid,
    source_type text,
    source_id uuid,
    actor_id uuid,
    mentioned_user_id uuid,
    mentioned_username text,
    created_at timestamptz,
    actor_username text,
    actor_display_name text,
    source_thread_id uuid,
    source_thread_title text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_mentions_v3(p_user_id, p_filter_sources,
    p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids,
    p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_mentions_v4(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_after_created_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.community_message_conversation_v2(
    p_conversation_id uuid,
    p_user_id uuid
)
RETURNS TABLE (
    conversation_id uuid,
    other_user_id uuid,
    other_username text,
    other_display_name text,
    other_gone boolean,
    unread_count integer,
    last_read_at timestamptz,
    created_at timestamptz,
    reader_blocks boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_conversation_v1(p_conversation_id,
    p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_v2(p_conversation_id uuid, p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_message_conversation_with_v2(
    p_user_id uuid,
    p_username text
)
RETURNS TABLE (
    other_user_id uuid,
    other_username text,
    other_display_name text,
    conversation_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_conversation_with_v1(p_user_id,
    p_username);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_with_v2(p_user_id uuid, p_username text) FROM PUBLIC;

CREATE FUNCTION api.community_message_for_report_v2(
    p_message_id uuid,
    p_user_id uuid
)
RETURNS TABLE (message_id uuid, conversation_id uuid, author_user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_for_report_v1(p_message_id, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_for_report_v2(p_message_id uuid, p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_message_inbox_v2(
    p_user_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    conversation_id uuid,
    other_user_id uuid,
    other_username text,
    other_display_name text,
    other_gone boolean,
    last_message_at timestamptz,
    unread_count integer,
    last_author_user_id uuid,
    last_excerpt text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_inbox_v1(p_user_id, p_after_at,
    p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_inbox_v2(p_user_id uuid, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.community_message_list_v2(
    p_conversation_id uuid,
    p_user_id uuid,
    p_before_position bigint,
    p_row_limit integer
)
RETURNS TABLE (
    message_id uuid,
    author_user_id uuid,
    author_username text,
    author_display_name text,
    body text,
    created_at timestamptz,
    message_position bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_list_v1(p_conversation_id, p_user_id,
    p_before_position, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_list_v2(p_conversation_id uuid, p_user_id uuid, p_before_position bigint, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.community_message_mark_read_v2(
    p_conversation_id uuid,
    p_user_id uuid,
    p_now timestamptz
)
RETURNS TABLE (status text, notifications_read integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_mark_read_v1(p_conversation_id,
    p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_mark_read_v2(p_conversation_id uuid, p_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.community_message_participant_v2(
    p_message_id uuid,
    p_user_id uuid
)
RETURNS TABLE (participant boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_participant_v1(p_message_id, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_participant_v2(p_message_id uuid, p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_message_reply_v2(p_row jsonb)
RETURNS TABLE (
    status text,
    conversation_id uuid,
    message_id uuid,
    recipient_user_id uuid,
    started boolean,
    first_unread boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_reply_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_reply_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_message_start_v2(p_row jsonb)
RETURNS TABLE (
    status text,
    conversation_id uuid,
    message_id uuid,
    recipient_user_id uuid,
    started boolean,
    first_unread boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_start_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_start_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_post_likes_v2(
    p_post_ids uuid[],
    p_viewer_user_id uuid
)
RETURNS TABLE (post_id uuid, like_count bigint, liked boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_post_likes_v1(p_post_ids, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_likes_v2(p_post_ids uuid[], p_viewer_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_post_reactions_v2(
    p_post_ids uuid[],
    p_viewer_user_id uuid
)
RETURNS TABLE (
    post_id uuid,
    reaction text,
    reaction_count bigint,
    reacted boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_post_reactions_v1(p_post_ids, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_reactions_v2(p_post_ids uuid[], p_viewer_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_project_feed_v2(p_row jsonb, p_user_ids uuid[])
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_project_feed_v1(p_row, p_user_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.community_project_feed_v2(p_row jsonb, p_user_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.community_react_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_react_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_react_post_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_react_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_post_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_record_reputation_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_record_reputation_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_record_reputation_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_relation_between_v2(
    p_owner_user_id uuid,
    p_other_user_id uuid
)
RETURNS TABLE (kind text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_between_v1(p_owner_user_id,
    p_other_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_between_v2(p_owner_user_id uuid, p_other_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_relation_list_v2(p_owner_user_id uuid)
RETURNS TABLE (
    other_user_id uuid,
    username text,
    display_name text,
    kind text,
    created_at timestamptz,
    updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_list_v1(p_owner_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_list_v2(p_owner_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_relation_remove_v2(
    p_owner_user_id uuid,
    p_username text
)
RETURNS TABLE (removed bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_remove_v1(p_owner_user_id, p_username);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_remove_v2(p_owner_user_id uuid, p_username text) FROM PUBLIC;

CREATE FUNCTION api.community_relation_set_v2(
    p_owner_user_id uuid,
    p_username text,
    p_kind text,
    p_now timestamptz
)
RETURNS TABLE (status text, other_user_id uuid, username text, kind text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_set_v1(p_owner_user_id, p_username,
    p_kind, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_set_v2(p_owner_user_id uuid, p_username text, p_kind text, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.community_remove_feed_v2(p_item_type text, p_item_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_remove_feed_v1(p_item_type, p_item_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_feed_v2(p_item_type text, p_item_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_remove_thread_feed_v2(p_thread_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_remove_thread_feed_v1(p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_thread_feed_v2(p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_resolve_mention_users_v2(p_usernames text[])
RETURNS TABLE (id uuid, username text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_resolve_mention_users_v1(p_usernames);
$$;
REVOKE EXECUTE ON FUNCTION api.community_resolve_mention_users_v2(p_usernames text[]) FROM PUBLIC;

CREATE FUNCTION api.community_save_bookmark_v2(p_row jsonb, p_restore boolean)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_save_bookmark_v1(p_row, p_restore);
$$;
REVOKE EXECUTE ON FUNCTION api.community_save_bookmark_v2(p_row jsonb, p_restore boolean) FROM PUBLIC;

CREATE FUNCTION api.community_set_bookmark_folder_v2(
    p_bookmark_id uuid,
    p_user_id uuid,
    p_folder text
)
RETURNS TABLE (bookmark_id uuid, folder text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_set_bookmark_folder_v1(p_bookmark_id, p_user_id,
    p_folder);
$$;
REVOKE EXECUTE ON FUNCTION api.community_set_bookmark_folder_v2(p_bookmark_id uuid, p_user_id uuid, p_folder text) FROM PUBLIC;

CREATE FUNCTION api.community_subscribe_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_subscribe_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_subscribe_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unlike_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unlike_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unlike_post_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unlike_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_post_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unreact_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unreact_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unreact_post_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unreact_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_post_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_active_announcements_v2(p_row_limit integer)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_active_announcements_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_active_announcements_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_find_v2(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_now timestamptz
)
RETURNS TABLE (draft json)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_find_v1(p_owner_user_id, p_draft_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_find_v2(p_owner_user_id uuid, p_draft_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_list_v2(
    p_owner_user_id uuid,
    p_now timestamptz
)
RETURNS TABLE (draft json)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_list_v1(p_owner_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_list_v2(p_owner_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_purge_v2(
    p_now timestamptz,
    p_row_limit integer
)
RETURNS TABLE (deleted bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_purge_v1(p_now,p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_purge_v2(p_now timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_remove_v2(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_now timestamptz
)
RETURNS TABLE (status text, draft json, error text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_remove_v1(p_owner_user_id, p_draft_id, p_draft_revision, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_remove_v2(p_owner_user_id uuid, p_draft_id uuid, p_draft_revision bigint, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_find_category_v2(p_category_id uuid)
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_category_v1(p_category_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_category_v2(p_category_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_post_v2(p_post_id uuid)
RETURNS SETOF api.forum_post_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_post_v1(p_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_post_v2(p_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_visible_post_v2(p_post_id uuid)
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_visible_post_v1(p_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_visible_post_v2(p_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_list_categories_v4(
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
    deleted_at timestamptz,
    thread_count bigint,
    last_activity_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT * FROM api.forum_list_categories_v3(p_member, p_global_read,
    p_category_ids, p_space_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v4(p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_tagged_threads_v2(
    p_tag_slug text,
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
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
    category_title text,
    reply_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_tagged_threads_v1(p_tag_slug, p_category_id,
    p_member, p_global_read, p_scope_user_id, p_category_ids, p_space_ids,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tagged_threads_v2(p_tag_slug text, p_category_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_tags_v2(
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (slug text, name text, thread_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_tags_v1(p_member, p_global_read, p_scope_user_id,
    p_category_ids, p_space_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tags_v2(p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_mark_read_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_mark_read_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_mark_read_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_post_context_v2(p_post_id uuid)
RETURNS TABLE (post json, thread json)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_post_context_v1(p_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_context_v2(p_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_post_placement_v2(p_source_id uuid)
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_post_placement_v1(p_source_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_placement_v2(p_source_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_read_marker_command_v2(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_read_marker_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_marker_command_v2(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_read_state_v2(p_user_id uuid, p_thread_id uuid)
RETURNS SETOF api.forum_read_state_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_read_state_v1(p_user_id, p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_state_v2(p_user_id uuid, p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_reply_targets_v2(p_post_ids uuid[])
RETURNS TABLE (
    post_id uuid,
    reply_to_post_id uuid,
    reply_to_position bigint,
    reply_to_author_username text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_reply_targets_v1(p_post_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_reply_targets_v2(p_post_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_head_v2(p_thread_id uuid)
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_head_v1(p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_head_v2(p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_v4(
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
    author_display_name text,
    author_avatar_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_posts_v3(p_thread_id, p_standing, p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v4(p_thread_id uuid, p_standing text, p_viewer_user_id uuid, p_after_position bigint, p_after_post_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_placement_v2(p_source_id uuid)
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_placement_v1(p_source_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_placement_v2(p_source_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_tags_v2(p_thread_ids uuid[])
RETURNS TABLE (thread_id uuid, slug text, name text, tag_position smallint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_tags_v1(p_thread_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_tags_v2(p_thread_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.identity_active_password_v2(p_user_id uuid)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_active_password_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_active_password_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_consume_token_v2(
    p_token_hash text,
    p_token_type text,
    p_now timestamptz,
    p_now_epoch bigint
)
RETURNS TABLE (result_code text, token_row jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_consume_token_v1(p_token_hash, p_token_type, p_now, p_now_epoch);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_consume_token_v2(p_token_hash text, p_token_type text, p_now timestamp with time zone, p_now_epoch bigint) FROM PUBLIC;

CREATE FUNCTION api.identity_credential_by_id_v2(p_credential_id uuid)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_credential_by_id_v1(p_credential_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_credential_by_id_v2(p_credential_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_hold_password_v2(
    p_user_id uuid,
    p_credential_id uuid
)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_hold_password_v1(p_user_id, p_credential_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_hold_password_v2(p_user_id uuid, p_credential_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_credential_v2(p_values jsonb)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_insert_credential_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_credential_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_token_v2(p_values jsonb)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_insert_token_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_token_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_user_v2(p_values jsonb)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_insert_user_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_user_v2(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_lock_passwords_v2(p_user_id uuid)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_lock_passwords_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_lock_passwords_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_counts_v2(p_user_id uuid)
RETURNS TABLE (
    public_threads bigint,
    public_replies bigint,
    total_public bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_counts_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_counts_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_replies_v2(
    p_user_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    thread_title text,
    thread_slug text,
    body text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_replies_v1(p_user_id, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_replies_v2(p_user_id uuid, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_threads_v2(
    p_user_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    visibility text,
    moderation_state text,
    last_activity_at timestamptz,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_threads_v1(p_user_id, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_threads_v2(p_user_id uuid, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_trust_v2(p_user_id uuid)
RETURNS SETOF api.identity_trust_snapshot_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_profile_trust_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_trust_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_registration_duplicates_v2(
    p_username text,
    p_email text
)
RETURNS TABLE (username_taken boolean, email_taken boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_registration_duplicates_v1(p_username, p_email);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_registration_duplicates_v2(p_username text, p_email text) FROM PUBLIC;

CREATE FUNCTION api.identity_revoke_passwords_v2(
    p_ids jsonb,
    p_revoked_at timestamptz
)
RETURNS TABLE (updated integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_revoke_passwords_v1(p_ids, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_revoke_passwords_v2(p_ids jsonb, p_revoked_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.identity_rotate_token_v2(p_token_id uuid, p_values jsonb)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_rotate_token_v1(p_token_id, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_rotate_token_v2(p_token_id uuid, p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_begin_v2(
    p_user_id uuid,
    p_secret_sealed text,
    p_key_id text,
    p_now timestamptz
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_begin_v1(p_user_id, p_secret_sealed,
    p_key_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_begin_v2(p_user_id uuid, p_secret_sealed text, p_key_id text, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_cancel_v2(p_user_id uuid)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_cancel_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_cancel_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_challenge_open_v2(p_row jsonb)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_challenge_open_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_open_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_challenge_v2(
    p_token_hash text,
    p_now timestamptz
)
RETURNS TABLE (
    user_id uuid,
    open boolean,
    secret_sealed text,
    key_id text,
    last_step bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_challenge_v1(p_token_hash, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_v2(p_token_hash text, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_confirm_v2(
    p_user_id uuid,
    p_step bigint,
    p_code_hashes text[],
    p_now timestamptz,
    p_keep_session_id uuid,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (status text, sessions_revoked integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_confirm_v1(p_user_id, p_step,
    p_code_hashes, p_now, p_keep_session_id, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_confirm_v2(p_user_id uuid, p_step bigint, p_code_hashes text[], p_now timestamp with time zone, p_keep_session_id uuid, p_audit jsonb, p_mail jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_disable_v2(
    p_user_id uuid,
    p_step bigint,
    p_recovery_hash text,
    p_now timestamptz,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_disable_v1(p_user_id, p_step,
    p_recovery_hash, p_now, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_disable_v2(p_user_id uuid, p_step bigint, p_recovery_hash text, p_now timestamp with time zone, p_audit jsonb, p_mail jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_renew_v2(
    p_user_id uuid,
    p_step bigint,
    p_code_hashes text[],
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_renew_v1(p_user_id, p_step,
    p_code_hashes, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_renew_v2(p_user_id uuid, p_step bigint, p_code_hashes text[], p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_status_v2(p_user_id uuid)
RETURNS TABLE (
    state text,
    secret_sealed text,
    key_id text,
    last_step bigint,
    confirmed_at timestamptz,
    recovery_left integer,
    staff boolean,
    staff_required boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_status_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_status_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_token_by_id_v2(p_token_id uuid)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_token_by_id_v1(p_token_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_token_by_id_v2(p_token_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_unused_token_v2(
    p_user_id uuid,
    p_token_type text
)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_unused_token_v1(p_user_id, p_token_type);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_unused_token_v2(p_user_id uuid, p_token_type text) FROM PUBLIC;

CREATE FUNCTION api.identity_user_by_id_v2(p_user_id uuid)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_user_by_id_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_id_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_user_by_identifier_v2(
    p_identifier text,
    p_by_email boolean
)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_user_by_identifier_v1(p_identifier, p_by_email);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_identifier_v2(p_identifier text, p_by_email boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_list_v2(
    p_target_type text,
    p_target_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_list_v1(p_target_type, p_target_id, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_list_v2(p_target_type text, p_target_id uuid, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_record_v4(
    p_report jsonb,
    p_event jsonb,
    p_event_outbox_id text,
    p_report_audit jsonb,
    p_audits jsonb
)
RETURNS TABLE (report_id uuid, flagged boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_record_v3(p_report, p_event,
    p_event_outbox_id, p_report_audit, p_audits);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v4(p_report jsonb, p_event jsonb, p_event_outbox_id text, p_report_audit jsonb, p_audits jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_rules_v4(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_rules_v3(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v4(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_settings_set_v2(
    p_link_limit integer,
    p_link_trust_below integer,
    p_link_action text,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_settings_set_v1(p_link_limit,
    p_link_trust_below, p_link_action, p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_settings_set_v2(p_link_limit integer, p_link_trust_below integer, p_link_action text, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_note_add_v2(
    p_note_id uuid,
    p_subject_user_id uuid,
    p_author_user_id uuid,
    p_body text,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, note_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_note_add_v1(p_note_id, p_subject_user_id,
    p_author_user_id, p_body, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_add_v2(p_note_id uuid, p_subject_user_id uuid, p_author_user_id uuid, p_body text, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_note_delete_v2(
    p_note_id uuid,
    p_subject_user_id uuid,
    p_audit jsonb
)
RETURNS TABLE (status text, note_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_note_delete_v1(p_note_id,
    p_subject_user_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_delete_v2(p_note_id uuid, p_subject_user_id uuid, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_note_edit_v2(
    p_note_id uuid,
    p_subject_user_id uuid,
    p_editor_user_id uuid,
    p_body text,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, note_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_note_edit_v1(p_note_id,
    p_subject_user_id, p_editor_user_id, p_body, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_edit_v2(p_note_id uuid, p_subject_user_id uuid, p_editor_user_id uuid, p_body text, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_notes_for_reports_v2(
    p_report_ids uuid[],
    p_per_member integer
)
RETURNS TABLE (
    report_id uuid,
    subject_user_id uuid,
    subject_username text,
    note_total bigint,
    note_id uuid,
    author_username text,
    body text,
    created_at timestamptz,
    updated_at timestamptz,
    updated_by_username text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_notes_for_reports_v1(p_report_ids,
    p_per_member);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_for_reports_v2(p_report_ids uuid[], p_per_member integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_notes_v2(
    p_subject_user_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    note_id uuid,
    subject_user_id uuid,
    author_user_id uuid,
    author_username text,
    body text,
    created_at timestamptz,
    updated_at timestamptz,
    updated_by_user_id uuid,
    updated_by_username text,
    note_total bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_notes_v1(p_subject_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_v2(p_subject_user_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_reported_message_v2(
    p_report_id uuid,
    p_audit jsonb
)
RETURNS TABLE (
    status text,
    report_id uuid,
    message_id uuid,
    author_user_id uuid,
    author_username text,
    body text,
    created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_reported_message_v1(p_report_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_reported_message_v2(p_report_id uuid, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_decide_v2(
    p_review_id uuid,
    p_status text,
    p_actor_user_id uuid,
    p_reason text,
    p_post_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (
    status text,
    review_status text,
    author_user_id uuid,
    kind text,
    thread_id uuid,
    post_id uuid
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_decide_v1(p_review_id, p_status,
    p_actor_user_id, p_reason, p_post_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_decide_v2(p_review_id uuid, p_status text, p_actor_user_id uuid, p_reason text, p_post_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_mine_v4(
    p_user_id uuid,
    p_row_limit integer,
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[]
)
RETURNS TABLE (
    review_id uuid,
    kind text,
    category_id uuid,
    category_title text,
    thread_id uuid,
    thread_title text,
    title text,
    body_rendered_safe text,
    status text,
    decision_reason text,
    post_id uuid,
    created_at timestamptz,
    decided_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_mine_v3(p_user_id, p_row_limit,
    p_member, p_global_read, p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v4(p_user_id uuid, p_row_limit integer, p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_queue_v2(p_row_limit integer)
RETURNS TABLE (
    review_id uuid,
    kind text,
    author_user_id uuid,
    author_username text,
    category_id uuid,
    category_title text,
    thread_id uuid,
    thread_title text,
    title text,
    body_rendered_safe text,
    reason text,
    details jsonb,
    created_at timestamptz,
    pending_total bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_queue_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_queue_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_settings_set_v2(
    p_first_posts integer,
    p_flagged boolean,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_settings_set_v1(p_first_posts,
    p_flagged, p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_settings_set_v2(p_first_posts integer, p_flagged boolean, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_list_v2(
    p_user_id uuid,
    p_active_only boolean,
    p_now timestamptz,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_list_v1(p_user_id, p_active_only, p_now, p_after_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_list_v2(p_user_id uuid, p_active_only boolean, p_now timestamp with time zone, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_watched_word_add_v2(
    p_word_id uuid,
    p_phrase text,
    p_action text,
    p_replacement text,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, word_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_watched_word_add_v1(p_word_id, p_phrase,
    p_action, p_replacement, p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_add_v2(p_word_id uuid, p_phrase text, p_action text, p_replacement text, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_watched_word_list_v2()
RETURNS TABLE (
    word_id uuid,
    phrase text,
    action text,
    replacement text,
    created_by_user_id uuid,
    created_by_username text,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_watched_word_list_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_list_v2() FROM PUBLIC;

CREATE FUNCTION api.moderation_watched_word_remove_v2(
    p_word_id uuid,
    p_audit jsonb
)
RETURNS TABLE (removed bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_watched_word_remove_v1(p_word_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_remove_v2(p_word_id uuid, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_deliver_v2(
    p_notification jsonb,
    p_inbox jsonb,
    p_idempotency_key text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_deliver_v1(p_notification, p_inbox, p_idempotency_key);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_deliver_v2(p_notification jsonb, p_inbox jsonb, p_idempotency_key text) FROM PUBLIC;

CREATE FUNCTION api.notification_delivery_plan_v4(
    p_user_id uuid,
    p_notification_type text
)
RETURNS TABLE (
    event_type text,
    in_app boolean,
    email boolean,
    email_address text,
    locale text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_delivery_plan_v3(p_user_id,
    p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v4(p_user_id uuid, p_notification_type text) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_claim_v2(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_event_id uuid,
    p_now timestamptz
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_claim_v1(p_user_id, p_frequency,
    p_period_start, p_event_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_claim_v2(p_user_id uuid, p_frequency text, p_period_start timestamp with time zone, p_event_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_due_v4(
    p_now timestamptz,
    p_after_start timestamptz,
    p_after_user_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    user_id uuid,
    frequency text,
    period_start timestamptz,
    period_end timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_due_v3(p_now, p_after_start,
    p_after_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_due_v4(p_now timestamp with time zone, p_after_start timestamp with time zone, p_after_user_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_items_v4(
    p_user_id uuid,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    title text,
    category_title text,
    new_posts integer,
    first_unread_position bigint,
    last_post_at timestamptz,
    thread_total integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_items_v3(p_user_id, p_period_start,
    p_period_end, p_member, p_global_read, p_category_ids, p_space_ids,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_items_v4(p_user_id uuid, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_plan_v4(
    p_user_id uuid,
    p_now timestamptz
)
RETURNS TABLE (
    digest boolean,
    frequency text,
    email_address text,
    locale text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_plan_v3(p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v4(p_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_purge_v2(
    p_before timestamptz,
    p_row_limit integer
)
RETURNS TABLE (deleted integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_purge_v1(p_before, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_purge_v2(p_before timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_release_v2(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_event_id uuid
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_release_v1(p_user_id, p_frequency,
    p_period_start, p_event_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_release_v2(p_user_id uuid, p_frequency text, p_period_start timestamp with time zone, p_event_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_unsubscribe_v2(
    p_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_unsubscribe_v1(p_user_id, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_unsubscribe_v2(p_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_find_subscription_v2(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF api.notification_subscription_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_find_subscription_v1(p_user_id, p_target_type, p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_find_subscription_v2(p_user_id uuid, p_target_type text, p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_list_preferences_v2(p_user_id uuid)
RETURNS SETOF api.notification_preference_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_preferences_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_preferences_v2(p_user_id uuid) FROM PUBLIC;

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
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_mark_all_read_v1(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_read_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_all_read_v2(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_read_at text) FROM PUBLIC;

CREATE FUNCTION api.notification_mark_read_v2(
    p_notification_id uuid,
    p_recipient_user_id uuid,
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_mark_read_v1(p_notification_id, p_recipient_user_id, p_read_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_read_v2(p_notification_id uuid, p_recipient_user_id uuid, p_read_at text) FROM PUBLIC;

CREATE FUNCTION api.notification_save_subscription_v2(
    p_row jsonb,
    p_restore boolean
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_save_subscription_v1(p_row, p_restore);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_save_subscription_v2(p_row jsonb, p_restore boolean) FROM PUBLIC;

CREATE FUNCTION api.notification_set_preference_v2(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_set_preference_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_preference_v2(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_set_type_preferences_v4(
    p_user_id uuid,
    p_preferences jsonb,
    p_now timestamptz
)
RETURNS TABLE (status text, changed integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_set_type_preferences_v3(p_user_id,
    p_preferences, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_type_preferences_v4(p_user_id uuid, p_preferences jsonb, p_now timestamp with time zone) FROM PUBLIC;

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
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_stamp_subscription_v1(p_id, p_by_target, p_user_id, p_target_type, p_target_id, p_column, p_stamped_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_stamp_subscription_v2(p_id uuid, p_by_target boolean, p_user_id uuid, p_target_type text, p_target_id uuid, p_column text, p_stamped_at text) FROM PUBLIC;

CREATE FUNCTION api.notification_type_preferences_v4(p_user_id uuid)
RETURNS TABLE (event_type text, channel text, enabled boolean, stored boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_type_preferences_v3(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_type_preferences_v4(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_unsubscribe_v4(
    p_user_id uuid,
    p_scope text,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, scope text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unsubscribe_v3(p_user_id, p_scope, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unsubscribe_v4(p_user_id uuid, p_scope text, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_command_finish_v2(p_command_id uuid, p_changes jsonb)
RETURNS TABLE (success boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_command_finish_v1(p_command_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_finish_v2(p_command_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_command_insert_v2(p_command jsonb)
RETURNS TABLE (document json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_command_insert_v1(p_command);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_insert_v2(p_command jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_command_lookup_v2(p_key text, p_command_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_command_lookup_v1(p_key, p_command_id);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_lookup_v2(p_key text, p_command_id uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_doctor_outbox_v2()
RETURNS TABLE (
    waiting bigint,
    oldest_seconds numeric,
    last_sent_seconds numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_doctor_outbox_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_doctor_outbox_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_event_claim_v2(
    p_operation text,
    p_key text,
    p_event_id text,
    p_now text,
    p_expired_before text
)
RETURNS TABLE (claimed boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_event_claim_v1(p_operation, p_key, p_event_id, p_now, p_expired_before);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_event_claim_v2(p_operation text, p_key text, p_event_id text, p_now text, p_expired_before text) FROM PUBLIC;

CREATE FUNCTION api.ops_event_recorded_v2(p_key text)
RETURNS TABLE (recorded boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_event_recorded_v1(p_key);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_event_recorded_v2(p_key text) FROM PUBLIC;

CREATE FUNCTION api.ops_partition_horizon_v2()
RETURNS TABLE (
    table_name text,
    horizon_epoch numeric,
    default_has_rows boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_partition_horizon_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_horizon_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_partition_registry_v2()
RETURNS SETOF api.ops_partition_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_partition_registry_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_registry_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_publish_notification_v2(
    p_channel text,
    p_payload text
)
RETURNS TABLE (sent boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_publish_notification_v1(p_channel, p_payload);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notification_v2(p_channel text, p_payload text) FROM PUBLIC;

CREATE FUNCTION api.ops_query_budget_list_v2(p_row_limit integer)
RETURNS SETOF api.ops_query_budget_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_query_budget_list_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_list_v2(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.ops_query_budget_sync_v2(
    p_rows jsonb,
    p_endpoint_names text[]
)
RETURNS TABLE (written bigint, removed text[])
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_query_budget_sync_v1(p_rows, p_endpoint_names);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_sync_v2(p_rows jsonb, p_endpoint_names text[]) FROM PUBLIC;

CREATE FUNCTION api.ops_rate_limit_check_v2(
    p_scope text,
    p_actor_hash text,
    p_action text,
    p_window_start timestamptz,
    p_window_seconds integer,
    p_limit integer,
    p_now timestamptz,
    p_expires_at timestamptz
)
RETURNS TABLE (
    scope text,
    actor_hash text,
    action text,
    window_started_at timestamptz,
    observed_count integer,
    blocked_count integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_rate_limit_check_v1(p_scope, p_actor_hash, p_action, p_window_start, p_window_seconds, p_limit, p_now, p_expires_at);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_check_v2(p_scope text, p_actor_hash text, p_action text, p_window_start timestamp with time zone, p_window_seconds integer, p_limit integer, p_now timestamp with time zone, p_expires_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.ops_rate_limit_snapshot_v2(p_now timestamptz)
RETURNS TABLE (buckets bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_rate_limit_snapshot_v1(p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_snapshot_v2(p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.ops_realtime_settled_v2(p_settle_seconds integer)
RETURNS TABLE (settled_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_realtime_settled_v1(p_settle_seconds);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_settled_v2(p_settle_seconds integer) FROM PUBLIC;

CREATE FUNCTION api.ops_record_audit_v2(p_audit jsonb, p_explicit boolean)
RETURNS TABLE (audit json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_record_audit_v1(p_audit, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_record_audit_v2(p_audit jsonb, p_explicit boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_record_event_v2(
    p_event jsonb,
    p_outbox_id text,
    p_outbox_extras jsonb,
    p_explicit boolean
)
RETURNS TABLE (event json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_record_event_v1(p_event, p_outbox_id, p_outbox_extras, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_record_event_v2(p_event jsonb, p_outbox_id text, p_outbox_extras jsonb, p_explicit boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_replication_position_v2()
RETURNS TABLE (
    replay_age_seconds double precision,
    replay_pending_bytes bigint,
    receiving boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_position_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_position_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_replication_recovery_v2()
RETURNS TABLE (in_recovery boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_recovery_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_recovery_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_replication_slots_v2(p_standby boolean)
RETURNS TABLE (
    slot_name text,
    slot_type text,
    active boolean,
    wal_status text,
    retained_bytes bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_slots_v1(p_standby);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_slots_v2(p_standby boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_replication_standbys_v2()
RETURNS TABLE (
    application_name text,
    state text,
    sync_state text,
    replay_lag_seconds double precision,
    bytes_behind bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_replication_standbys_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_standbys_v2() FROM PUBLIC;

CREATE FUNCTION api.ops_worker_aggregate_v2(
    p_aggregate_type text,
    p_aggregate_id uuid
)
RETURNS TABLE (author_user_id uuid, thread_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_worker_aggregate_v1(p_aggregate_type, p_aggregate_id);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_worker_aggregate_v2(p_aggregate_type text, p_aggregate_id uuid) FROM PUBLIC;

CREATE FUNCTION api.outbox_dead_letter_v2(p_letter jsonb)
RETURNS TABLE (letter json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_dead_letter_v1(p_letter);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_dead_letter_v2(p_letter jsonb) FROM PUBLIC;

CREATE FUNCTION api.outbox_replay_dead_letter_v2(
    p_input jsonb,
    p_ids jsonb,
    p_now text
)
RETURNS TABLE (result json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_replay_dead_letter_v1(p_input, p_ids, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_replay_dead_letter_v2(p_input jsonb, p_ids jsonb, p_now text) FROM PUBLIC;

CREATE FUNCTION api.privacy_discard_exports_v2(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_discard_exports_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_discard_exports_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.privacy_find_v2(
    p_source text,
    p_id uuid,
    p_lock_row boolean
)
RETURNS TABLE (document json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_find_v1(p_source, p_id, p_lock_row);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_find_v2(p_source text, p_id uuid, p_lock_row boolean) FROM PUBLIC;

CREATE FUNCTION api.privacy_insert_v2(p_source text, p_row jsonb)
RETURNS TABLE (document json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_insert_v1(p_source, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_insert_v2(p_source text, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_latest_v2(p_source text, p_query jsonb)
RETURNS TABLE (document json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_latest_v1(p_source, p_query);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_latest_v2(p_source text, p_query jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_may_export_v2(p_user_id uuid)
RETURNS TABLE (allowed boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_may_export_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_may_export_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.privacy_review_v2(
    p_source text,
    p_query jsonb,
    p_row_limit integer,
    p_oldest boolean
)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_review_v1(p_source, p_query, p_row_limit, p_oldest);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_review_v2(p_source text, p_query jsonb, p_row_limit integer, p_oldest boolean) FROM PUBLIC;

CREATE FUNCTION api.privacy_update_v4(
    p_source text,
    p_id uuid,
    p_changes jsonb
)
RETURNS TABLE (document json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_update_v3(p_source, p_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_update_v4(p_source text, p_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.search_autocomplete_v8(
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
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    source_created_at timestamptz,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_autocomplete_v7(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_like_pattern, p_row_limit)
$$;
REVOKE EXECUTE ON FUNCTION api.search_autocomplete_v8(p_permission_mode text, p_visibility_values text[], p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_like_pattern text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.search_latest_rebuild_v2()
RETURNS TABLE (event_type text, payload text, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_latest_rebuild_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.search_latest_rebuild_v2() FROM PUBLIC;

CREATE FUNCTION api.search_live_ids_v2(
    p_entity_type text,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (entity_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_live_ids_v1(p_entity_type, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.search_live_ids_v2(p_entity_type text, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.search_prune_candidates_v2(p_entity_type text)
RETURNS TABLE (entity_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_prune_candidates_v1(p_entity_type);
$$;
REVOKE EXECUTE ON FUNCTION api.search_prune_candidates_v2(p_entity_type text) FROM PUBLIC;

CREATE FUNCTION api.search_remove_document_v2(
    p_entity_type text,
    p_entity_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_remove_document_v1(p_entity_type, p_entity_id);
$$;
REVOKE EXECUTE ON FUNCTION api.search_remove_document_v2(p_entity_type text, p_entity_id uuid) FROM PUBLIC;

CREATE FUNCTION api.search_remove_post_batch_v2(
    p_thread_id uuid,
    p_post_ids uuid[]
)
RETURNS TABLE (removed bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_remove_post_batch_v1(p_thread_id, p_post_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.search_remove_post_batch_v2(p_thread_id uuid, p_post_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.search_set_timeout_v2(p_timeout text)
RETURNS TABLE (timeout text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_set_timeout_v1(p_timeout);
$$;
REVOKE EXECUTE ON FUNCTION api.search_set_timeout_v2(p_timeout text) FROM PUBLIC;

CREATE FUNCTION api.search_thread_post_batch_v2(
    p_thread_id uuid,
    p_after_position bigint,
    p_row_limit integer
)
RETURNS TABLE (post_id uuid, "position" bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_thread_post_batch_v1(p_thread_id, p_after_position, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.search_thread_post_batch_v2(p_thread_id uuid, p_after_position bigint, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.session_create_v2(
    p_session_id uuid,
    p_user_id uuid,
    p_session_hash text,
    p_created_at timestamptz,
    p_last_seen_at timestamptz,
    p_expires_at timestamptz,
    p_revoked_at timestamptz,
    p_ip_hash text,
    p_user_agent_hash text,
    p_retry boolean
)
RETURNS TABLE (
    result_code text,
    session_id uuid,
    user_id uuid,
    session_hash text,
    created_at timestamptz,
    last_seen_at timestamptz,
    expires_at timestamptz,
    revoked_at timestamptz,
    ip_hash text,
    user_agent_hash text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_create_v1(p_session_id, p_user_id, p_session_hash, p_created_at, p_last_seen_at, p_expires_at, p_revoked_at, p_ip_hash, p_user_agent_hash, p_retry);
$$;
REVOKE EXECUTE ON FUNCTION api.session_create_v2(p_session_id uuid, p_user_id uuid, p_session_hash text, p_created_at timestamp with time zone, p_last_seen_at timestamp with time zone, p_expires_at timestamp with time zone, p_revoked_at timestamp with time zone, p_ip_hash text, p_user_agent_hash text, p_retry boolean) FROM PUBLIC;

CREATE FUNCTION api.session_live_v2(p_session_ids uuid[], p_now timestamptz)
RETURNS TABLE (session_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_live_v1(p_session_ids, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.session_live_v2(p_session_ids uuid[], p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.session_lookup_v2(p_session_id uuid, p_user_id uuid)
RETURNS SETOF api.identity_session_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_lookup_v1(p_session_id, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.session_lookup_v2(p_session_id uuid, p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.session_revoke_user_v2(
    p_user_id uuid,
    p_revoked_at timestamptz,
    p_keep_session_id uuid
)
RETURNS TABLE (revoked_count bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_revoke_user_v1(p_user_id, p_revoked_at, p_keep_session_id);
$$;
REVOKE EXECUTE ON FUNCTION api.session_revoke_user_v2(p_user_id uuid, p_revoked_at timestamp with time zone, p_keep_session_id uuid) FROM PUBLIC;

CREATE FUNCTION api.session_revoke_v2(
    p_session_id uuid,
    p_user_id uuid,
    p_revoked_at timestamptz
)
RETURNS TABLE (
    result_code text,
    session_id uuid,
    user_id uuid,
    session_hash text,
    created_at timestamptz,
    last_seen_at timestamptz,
    expires_at timestamptz,
    revoked_at timestamptz,
    ip_hash text,
    user_agent_hash text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_revoke_v1(p_session_id, p_user_id, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.session_revoke_v2(p_session_id uuid, p_user_id uuid, p_revoked_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.session_validate_v2(
    p_session_id uuid,
    p_user_id uuid,
    p_token_hash text,
    p_now timestamptz,
    p_touch_interval_seconds integer
)
RETURNS TABLE (
    result_code text,
    session_id uuid,
    user_id uuid,
    session_hash text,
    created_at timestamptz,
    last_seen_at timestamptz,
    expires_at timestamptz,
    revoked_at timestamptz,
    ip_hash text,
    user_agent_hash text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_validate_v1(p_session_id, p_user_id, p_token_hash, p_now, p_touch_interval_seconds);
$$;
REVOKE EXECUTE ON FUNCTION api.session_validate_v2(p_session_id uuid, p_user_id uuid, p_token_hash text, p_now timestamp with time zone, p_touch_interval_seconds integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_active_suspension_v4(
p_user_id uuid, p_now timestamptz
)
RETURNS TABLE (suspension_id uuid, user_id uuid, actor_user_id uuid, reason text,
    valid_from timestamptz, valid_to timestamptz, revoked_at timestamptz,
    metadata jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_active_suspension_v3(p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v4(p_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.moderation_can_participate_v4(
p_user_id uuid, p_now timestamptz
)
RETURNS TABLE (ok integer, reason text, suspension_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_can_participate_v3(p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v4(p_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.notification_category_follow_v2(p_actor uuid, p_command uuid, p_category_id uuid, p_operation text)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_category_follow_v1(p_actor, p_command, p_category_id, p_operation);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_category_follow_v2(p_actor uuid, p_command uuid, p_category_id uuid, p_operation text) FROM PUBLIC;

CREATE FUNCTION api.admin_registration_state_v2(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_registration_state_v1(p_actor);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_registration_state_v2(p_actor uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_registration_change_v2(p_actor uuid, p_command uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_registration_change_v1(p_actor, p_command, p_operation, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_registration_change_v2(p_actor uuid, p_command uuid, p_operation text, p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_register_command_v4(p_log jsonb, p_answer jsonb, p_accepted jsonb, p_refused jsonb, p_user jsonb, p_credential jsonb, p_event jsonb, p_event_outbox_id text, p_audit jsonb, p_token jsonb, p_token_audit jsonb, p_mail_event jsonb, p_mail_outbox_id text, p_mail_outbox_extras jsonb, p_invitation_hash text)
RETURNS TABLE (outcome text, response json, stored_user json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_register_command_v3(p_log, p_answer, p_accepted, p_refused, p_user, p_credential, p_event, p_event_outbox_id, p_audit, p_token, p_token_audit, p_mail_event, p_mail_outbox_id, p_mail_outbox_extras, p_invitation_hash);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_register_command_v4(p_log jsonb, p_answer jsonb, p_accepted jsonb, p_refused jsonb, p_user jsonb, p_credential jsonb, p_event jsonb, p_event_outbox_id text, p_audit jsonb, p_token jsonb, p_token_audit jsonb, p_mail_event jsonb, p_mail_outbox_id text, p_mail_outbox_extras jsonb, p_invitation_hash text) FROM PUBLIC;

CREATE FUNCTION api.identity_update_user_v6(p_user_id uuid, p_changes jsonb)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_update_user_v5(p_user_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v6(p_user_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfers_v2(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_thread_transfers_v1(p_actor);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfers_v2(p_actor uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_redirect_v2(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (target_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_redirect_v1(p_actor, p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_redirect_v2(p_actor uuid, p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_retention_purge_v4(p_source text, p_cutoff timestamptz, p_row_limit integer)
RETURNS TABLE (deleted bigint, ok integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_retention_purge_v3(p_source, p_cutoff, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v4(p_source text, p_cutoff timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_signature_v2(p_body_id uuid)
RETURNS TABLE (envelope json)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_signature_v1(p_body_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signature_v2(p_body_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_member_v2(p_user_id uuid, p_email text)
RETURNS TABLE (id uuid, email_normalized text, trust_level integer, email_verified_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_member_v1(p_user_id, p_email);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_member_v2(p_user_id uuid, p_email text) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_attest_body_v2(p_body_id uuid, p_post_id uuid, p_source text, p_envelope jsonb)
RETURNS TABLE (saved boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_attest_body_v1(p_body_id, p_post_id, p_source, p_envelope);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_attest_body_v2(p_body_id uuid, p_post_id uuid, p_source text, p_envelope jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_sitemap_count_v2()
RETURNS TABLE(total bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.forum_sitemap_count_v1(); $$;
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_count_v2() FROM PUBLIC;

CREATE FUNCTION api.forum_sitemap_page_v2(p_page integer)
RETURNS TABLE(kind text, resource_id uuid, slug text, changed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.forum_sitemap_page_v1(p_page); $$;
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_page_v2(p_page integer) FROM PUBLIC;

CREATE FUNCTION api.ops_audit_chain_verify_v2(p_chain_key text)
RETURNS TABLE (chain_position bigint, audit_id uuid, problem text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_audit_chain_verify_v1(p_chain_key);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_audit_chain_verify_v2(p_chain_key text) FROM PUBLIC;

CREATE FUNCTION api.notification_unread_count_v8(
    p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[]
)
RETURNS TABLE (unread_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unread_count_v7(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v8(p_recipient_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_deliver_v2(p_recipients jsonb)
RETURNS TABLE (
    recipient_user_id uuid,
    outcome text,
    result jsonb,
    unread_count bigint,
    email_queued boolean,
    error text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_deliver_v1(p_recipients);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_deliver_v2(p_recipients jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_publish_notifications_v2(p_channel text, p_payloads text[])
RETURNS TABLE (sent integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_publish_notifications_v1(p_channel, p_payloads);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notifications_v2(p_channel text, p_payloads text[]) FROM PUBLIC;

CREATE FUNCTION api.attachment_post_files_v2(
    p_target_type text,
    p_post_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_post_files_v1(p_target_type, p_post_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_post_files_v2(p_target_type text, p_post_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_signatures_v2(p_body_ids uuid[])
RETURNS TABLE (body_id uuid, envelope json)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_signatures_v1(p_body_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signatures_v2(p_body_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_find_listed_post_v4(
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_listed_post_v3(p_post_id, p_thread_id, p_member, p_global_read, p_scope_user_id, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v4(p_post_id uuid, p_thread_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_viewer_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_list_inbox_v8(
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
    recipient_user_id uuid,
    notification_id uuid,
    created_at timestamptz,
    read_at timestamptz,
    rank_score numeric,
    source_type text,
    source_id uuid,
    notification_type text,
    payload jsonb,
    source_thread_id uuid,
    source_thread_title text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_inbox_v7(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids, p_after_created_at,
    p_after_notification_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v8(p_recipient_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_after_created_at timestamp with time zone, p_after_notification_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_category_threads_v4(
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_category_threads_v3(p_category_id, p_member, p_global_read, p_scope_user_id, p_viewer_user_id, p_after_pinned, p_after_activity, p_after_thread_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v4(p_category_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_viewer_user_id uuid, p_after_pinned boolean, p_after_activity timestamp with time zone, p_after_thread_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_set_thread_tags_v4(
    p_thread_id uuid,
    p_slugs text[],
    p_names text[]
)
RETURNS TABLE (slug text, name text, tag_position smallint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_set_thread_tags_v3(p_thread_id, p_slugs, p_names);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_set_thread_tags_v4(p_thread_id uuid, p_slugs text[], p_names text[]) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_save_v4(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_kind text,
    p_category_id uuid,
    p_thread_id uuid,
    p_title text,
    p_body_source text,
    p_visibility text,
    p_command_id text,
    p_now timestamptz
)
RETURNS TABLE (status text, draft json, error text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_save_v3(p_owner_user_id, p_draft_id,
    p_draft_revision, p_kind, p_category_id, p_thread_id, p_title,
    p_body_source, p_visibility, p_command_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_save_v4(p_owner_user_id uuid, p_draft_id uuid, p_draft_revision bigint, p_kind text, p_category_id uuid, p_thread_id uuid, p_title text, p_body_source text, p_visibility text, p_command_id text, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_link_reply_v4(
    p_post_id uuid,
    p_reply_to_post_id uuid
)
RETURNS TABLE (linked boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_link_reply_v3(p_post_id, p_reply_to_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_link_reply_v4(p_post_id uuid, p_reply_to_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_thread_activity_v4(p_thread_id uuid, p_at text)
RETURNS TABLE (bumped bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_thread_activity_v3(p_thread_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_thread_activity_v4(p_thread_id uuid, p_at text) FROM PUBLIC;

CREATE FUNCTION api.ops_outbox_metrics_v4(p_now timestamptz)
RETURNS TABLE (
    pending bigint,
    failed bigint,
    retry_backlog bigint,
    dead_letters bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_outbox_metrics_v3(p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_outbox_metrics_v4(p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_hold_v4(
    p_review_id uuid,
    p_author_user_id uuid,
    p_command_id text,
    p_kind text,
    p_category_id uuid,
    p_thread_id uuid,
    p_title text,
    p_body_source text,
    p_body_rendered_safe text,
    p_visibility text,
    p_reply_to_post_id uuid,
    p_reason text,
    p_details jsonb,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_now timestamptz,
    p_audit jsonb,
    p_tags text
)
RETURNS TABLE (status text, review_id uuid, review_status text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_hold_v3(p_review_id, p_author_user_id,
    p_command_id, p_kind, p_category_id, p_thread_id, p_title, p_body_source,
    p_body_rendered_safe, p_visibility, p_reply_to_post_id, p_reason,
    p_details, p_draft_id, p_draft_revision, p_now, p_audit, p_tags);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_hold_v4(p_review_id uuid, p_author_user_id uuid, p_command_id text, p_kind text, p_category_id uuid, p_thread_id uuid, p_title text, p_body_source text, p_body_rendered_safe text, p_visibility text, p_reply_to_post_id uuid, p_reason text, p_details jsonb, p_draft_id uuid, p_draft_revision bigint, p_now timestamp with time zone, p_audit jsonb, p_tags text) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_take_v4(p_review_id uuid)
RETURNS TABLE (
    review_id uuid,
    author_user_id uuid,
    command_id text,
    kind text,
    category_id uuid,
    thread_id uuid,
    title text,
    body_source text,
    visibility text,
    reply_to_post_id uuid,
    reason text,
    status text,
    post_id uuid,
    tags text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_take_v3(p_review_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_take_v4(p_review_id uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_challenge_answer_v4(
    p_token_hash text,
    p_step bigint,
    p_recovery_hash text,
    p_resealed text,
    p_key_id text,
    p_now timestamptz,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (
    status text,
    user_id uuid,
    method text,
    recovery_left integer,
    attempts_left integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_challenge_answer_v3(p_token_hash,
    p_step, p_recovery_hash, p_resealed, p_key_id, p_now, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_answer_v4(p_token_hash text, p_step bigint, p_recovery_hash text, p_resealed text, p_key_id text, p_now timestamp with time zone, p_audit jsonb, p_mail jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v10(p_user_id uuid)
RETURNS TABLE (
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_resolve_viewer_v9(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v10(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_subscribers_v6(p_target_type text, p_target_id uuid, p_notification_type text)
RETURNS TABLE (user_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_subscribers_v5(p_target_type, p_target_id, p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_subscribers_v6(p_target_type text, p_target_id uuid, p_notification_type text) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_candidates_v4(
    p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid
)
RETURNS TABLE (
    user_id uuid,
    in_app boolean,
    email boolean,
    email_address text,
    locale text,
    event_type text,
    silenced boolean,
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_candidates_v3(p_target_type, p_target_id, p_notification_type, p_actor_id, p_excluded_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_candidates_v4(p_target_type text, p_target_id uuid, p_notification_type text, p_actor_id uuid, p_excluded_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v8(
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
    p_recorded_at text,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_post_signature jsonb
)
RETURNS TABLE (outcome text,
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
    deleted_by text)
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_create_reply_v7(p_idempotency_key, p_command_type, p_actor_id, p_request_hash, p_command_id, p_command_correlation_id, p_command_at, p_answer, p_store_refusals, p_post_id, p_thread_id, p_author_user_id, p_current_body_id, p_current_revision_id, p_position, p_visibility, p_moderation_state, p_version, p_visibility_version, p_permission_version, p_hidden_at, p_locked_at, p_deleted_at, p_deleted_by, p_body_id, p_body_post_id, p_body_format, p_body_source, p_body_rendered_safe, p_source_hash, p_revision_id, p_revision_post_id, p_revision_body_id, p_editor_user_id, p_revision_number, p_edit_reason, p_correlation_id, p_event_id, p_outbox_id, p_audit_id, p_recorded_at, p_draft_id, p_draft_revision, p_post_signature);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v8(p_idempotency_key text, p_command_type text, p_actor_id text, p_request_hash text, p_command_id text, p_command_correlation_id text, p_command_at text, p_answer jsonb, p_store_refusals jsonb, p_post_id text, p_thread_id text, p_author_user_id text, p_current_body_id text, p_current_revision_id text, p_position bigint, p_visibility text, p_moderation_state text, p_version bigint, p_visibility_version bigint, p_permission_version bigint, p_hidden_at text, p_locked_at text, p_deleted_at text, p_deleted_by text, p_body_id text, p_body_post_id text, p_body_format text, p_body_source text, p_body_rendered_safe text, p_source_hash text, p_revision_id text, p_revision_post_id text, p_revision_body_id text, p_editor_user_id text, p_revision_number integer, p_edit_reason text, p_correlation_id text, p_event_id text, p_outbox_id text, p_audit_id text, p_recorded_at text, p_draft_id uuid, p_draft_revision bigint, p_post_signature jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_unsigned_bodies_v4(p_after uuid)
RETURNS TABLE (body_id uuid, post_id uuid, body_format text, body_source text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_unsigned_bodies_v3(p_after);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_unsigned_bodies_v4(p_after uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_reads_v8(
    p_thread_id uuid,
    p_post_ids uuid[],
    p_viewer_user_id uuid,
    p_engagement_target_type text,
    p_link_target_type text,
    p_link_post_ids uuid[],
    p_link_row_limit integer
)
RETURNS TABLE (
    part text,
    ordinal bigint,
    post_id uuid,
    like_count bigint,
    liked boolean,
    reply_to_post_id uuid,
    reply_to_position bigint,
    reply_to_author_username text,
    thread_id uuid,
    slug text,
    name text,
    tag_position smallint,
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    bookmark_id uuid,
    user_id uuid,
    note text,
    deleted_at timestamptz,
    subscription_id uuid,
    preference text,
    muted_at timestamptz,
    revoked_at timestamptz,
    last_read_position bigint,
    last_read_at timestamptz,
    reaction text,
    reaction_count bigint,
    reacted boolean,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_reads_v7(p_thread_id, p_post_ids, p_viewer_user_id, p_engagement_target_type, p_link_target_type, p_link_post_ids, p_link_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v8(p_thread_id uuid, p_post_ids uuid[], p_viewer_user_id uuid, p_engagement_target_type text, p_link_target_type text, p_link_post_ids uuid[], p_link_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_update_v4(
    p_action_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_update_v3(p_action_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_update_v4(p_action_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_audit_page_v4(
    p_filters jsonb,
    p_after jsonb,
    p_row_limit integer
)
RETURNS SETOF api.admin_audit_entry_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_audit_page_v3(p_filters, p_after, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_page_v4(p_filters jsonb, p_after jsonb, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.community_list_bookmark_folders_v4(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_target_type text
)
RETURNS TABLE (folder text, bookmark_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_bookmark_folders_v3(p_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids, p_target_type);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmark_folders_v4(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_target_type text) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_update_v6(
    p_kind text,
    p_target_id uuid,
    p_changes jsonb
)
RETURNS TABLE (changed_count bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_target_update_v5(p_kind, p_target_id,
    p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v6(p_kind text, p_target_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_record_v6(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_thread_count integer,
    p_now timestamptz,
    p_event jsonb,
    p_outbox_id text,
    p_outbox_extras jsonb,
    p_explicit boolean
)
RETURNS TABLE (status text, event_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_record_v5(p_user_id, p_frequency,
    p_period_start, p_period_end, p_thread_count, p_now, p_event,
    p_outbox_id, p_outbox_extras, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v6(p_user_id uuid, p_frequency text, p_period_start timestamp with time zone, p_period_end timestamp with time zone, p_thread_count integer, p_now timestamp with time zone, p_event jsonb, p_outbox_id text, p_outbox_extras jsonb, p_explicit boolean) FROM PUBLIC;

CREATE FUNCTION api.community_stamp_bookmark_v4(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_column text,
    p_stamped_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_stamp_bookmark_v3(p_user_id, p_target_type,
    p_target_id, p_column, p_stamped_at);
$$;
REVOKE EXECUTE ON FUNCTION api.community_stamp_bookmark_v4(p_user_id uuid, p_target_type text, p_target_id uuid, p_column text, p_stamped_at text) FROM PUBLIC;

CREATE FUNCTION api.attachment_find_v4(
    p_attachment_id uuid,
    p_object_key text,
    p_hold boolean
)
RETURNS SETOF api.attachment_file_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_find_v3(p_attachment_id, p_object_key, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_find_v4(p_attachment_id uuid, p_object_key text, p_hold boolean) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_post_v4(p_target_id uuid)
RETURNS SETOF api.forum_post_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_source_post_v3(p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_post_v4(p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_thread_v4(p_target_id uuid)
RETURNS SETOF api.forum_thread_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_source_thread_v3(p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_thread_v4(p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_variants_v4(
    p_attachment_id uuid,
    p_variant_type text,
    p_object_key text,
    p_row_limit integer
)
RETURNS SETOF api.attachment_variant_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_variants_v3(p_attachment_id, p_variant_type, p_object_key, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variants_v4(p_attachment_id uuid, p_variant_type text, p_object_key text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_update_v4(
    p_attachment_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.attachment_file_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_update_v3(p_attachment_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_update_v4(p_attachment_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_insert_v4(p_values jsonb)
RETURNS SETOF api.attachment_file_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_insert_v3(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_insert_v4(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_link_insert_v4(p_values jsonb)
RETURNS SETOF api.attachment_link_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_link_insert_v3(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_link_insert_v4(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_variant_insert_v4(p_values jsonb)
RETURNS SETOF api.attachment_variant_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_variant_insert_v3(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variant_insert_v4(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_confirm_clean_v4(
    p_attachment_id uuid,
    p_scan_engine text,
    p_scanned_at timestamptz
)
RETURNS TABLE (changed_count bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_confirm_clean_v3(p_attachment_id, p_scan_engine, p_scanned_at);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_confirm_clean_v4(p_attachment_id uuid, p_scan_engine text, p_scanned_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.attachment_orphans_v4(
    p_cutoff timestamptz,
    p_row_limit integer
)
RETURNS SETOF api.attachment_file_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_orphans_v3(p_cutoff, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_orphans_v4(p_cutoff timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_failure_v4(
    p_attachment_id uuid,
    p_error text
)
RETURNS TABLE (changed_count bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_scan_failure_v3(p_attachment_id, p_error);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_failure_v4(p_attachment_id uuid, p_error text) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_queue_v4(
    p_pending boolean,
    p_row_limit integer
)
RETURNS TABLE (attachment_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_scan_queue_v3(p_pending, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_queue_v4(p_pending boolean, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_verdict_v4(
    p_attachment_id uuid,
    p_changes jsonb
)
RETURNS TABLE (changed_count bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_scan_verdict_v3(p_attachment_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_verdict_v4(p_attachment_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_find_v4(
    p_action_id uuid,
    p_command_id uuid,
    p_action_type text,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_find_v3(p_action_id, p_command_id, p_action_type, p_target_type, p_target_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_find_v4(p_action_id uuid, p_command_id uuid, p_action_type text, p_target_type text, p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_insert_v4(p_values jsonb)
RETURNS SETOF api.moderation_action_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_action_insert_v3(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_insert_v4(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_find_v4(
    p_report_id uuid,
    p_reporter_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_hold boolean
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_find_v3(p_report_id, p_reporter_user_id, p_target_type, p_target_id, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_find_v4(p_report_id uuid, p_reporter_user_id uuid, p_target_type text, p_target_id uuid, p_hold boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_insert_v4(p_values jsonb)
RETURNS SETOF api.moderation_report_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_insert_v3(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_insert_v4(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_queue_v4(
    p_status text,
    p_row_limit integer
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_queue_v3(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_queue_v4(p_status text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_update_v4(
    p_report_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_report_update_v3(p_report_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_update_v4(p_report_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_find_v4(p_suspension_id uuid)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_find_v3(p_suspension_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_find_v4(p_suspension_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_update_v4(
    p_suspension_id uuid,
    p_revoked_at timestamptz
)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_update_v3(p_suspension_id, p_revoked_at);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_update_v4(p_suspension_id uuid, p_revoked_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_v6(
    p_kind text,
    p_target_id uuid,
    p_hold boolean
)
RETURNS TABLE (
    target_id uuid,
    moderation_state text,
    locked_at timestamptz,
    hidden_at timestamptz,
    pinned boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_target_v5(p_kind, p_target_id, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_v6(p_kind text, p_target_id uuid, p_hold boolean) FROM PUBLIC;

CREATE FUNCTION api.admin_console_users_v4(p_status text, p_row_limit integer)
RETURNS TABLE (
    id uuid,
    username text,
    display_name text,
    email_normalized text,
    status text,
    trust_level integer,
    email_verified_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_users_v3(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_users_v4(p_status text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.ops_readiness_probe_v4(p_source text)
RETURNS TABLE (ready boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_readiness_probe_v3(p_source);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_readiness_probe_v4(p_source text) FROM PUBLIC;

CREATE FUNCTION api.attachment_links_v6(
    p_attachment_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.attachment_link_v1
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_links_v5(p_attachment_id, p_target_type,
    p_target_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_links_v6(p_attachment_id uuid, p_target_type text, p_target_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.privacy_release_hold_v2(
    p_hold_id uuid,
    p_ended_at timestamptz
)
RETURNS TABLE (hold json, request json)
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_release_hold_v1(p_hold_id, p_ended_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_release_hold_v2(p_hold_id uuid, p_ended_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_store_write_v8(
    p_store_type text,
    p_command jsonb,
    p_record jsonb
)
RETURNS TABLE (stored json)
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_store_write_v7(p_store_type, p_command, p_record);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v8(p_store_type text, p_command jsonb, p_record jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v10(
    p_log jsonb,
    p_answer jsonb,
    p_store_type text,
    p_command jsonb,
    p_record jsonb,
    p_draft_id uuid,
    p_draft_revision bigint
)
RETURNS TABLE (outcome text, response json, stored json)
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_write_command_v9(p_log, p_answer, p_store_type, p_command, p_record, p_draft_id, p_draft_revision);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v10(p_log jsonb, p_answer jsonb, p_store_type text, p_command jsonb, p_record jsonb, p_draft_id uuid, p_draft_revision bigint) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_v6(p_actor uuid, p_command uuid, p_source_id uuid, p_target_id uuid, p_operation text, p_post_numbers bigint[], p_title text, p_reason text)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_thread_transfer_v5(p_actor, p_command, p_source_id, p_target_id, p_operation, p_post_numbers, p_title, p_reason);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_v6(p_actor uuid, p_command uuid, p_source_id uuid, p_target_id uuid, p_operation text, p_post_numbers bigint[], p_title text, p_reason text) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_undo_v6(p_actor uuid, p_command uuid, p_transfer_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_thread_transfer_undo_v5(p_actor, p_command, p_transfer_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_undo_v6(p_actor uuid, p_command uuid, p_transfer_id uuid) FROM PUBLIC;

CREATE FUNCTION api.outbox_claim_ready_v6(
    p_now text,
    p_locked_until text,
    p_worker_id text,
    p_row_limit integer
)
RETURNS SETOF api.outbox_message_v2
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_claim_ready_v5(p_now, p_locked_until, p_worker_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_claim_ready_v6(p_now text, p_locked_until text, p_worker_id text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.ops_realtime_poll_v6(
    p_after_next_at timestamptz,
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_settled_at timestamptz,
    p_settle_seconds integer,
    p_row_limit integer
)
RETURNS SETOF api.outbox_message_v2
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_realtime_poll_v5(p_after_next_at, p_after_created_at,
    p_after_id, p_settled_at, p_settle_seconds, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_poll_v6(p_after_next_at timestamp with time zone, p_after_created_at timestamp with time zone, p_after_id uuid, p_settled_at timestamp with time zone, p_settle_seconds integer, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.outbox_owned_write_v4(
    p_outbox_id uuid,
    p_worker_id text,
    p_changes jsonb
)
RETURNS TABLE (landed boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_owned_write_v3(p_outbox_id, p_worker_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_owned_write_v4(p_outbox_id uuid, p_worker_id text, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_console_outbox_v4(
    p_status text,
    p_row_limit integer
)
RETURNS TABLE (
    outbox_id uuid,
    event_id uuid,
    queue text,
    job_type text,
    idempotency_key text,
    available_at timestamptz,
    created_at timestamptz,
    locked_at timestamptz,
    status text,
    last_error text,
    next_attempt_at timestamptz,
    locked_by text,
    locked_until timestamptz,
    attempt_count integer,
    last_error_class text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_console_outbox_v3(p_status, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_outbox_v4(p_status text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_lock_member_v2(p_user_id uuid)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_lock_member_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_lock_member_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_insert_v6(p_values jsonb)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_insert_v5(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_insert_v6(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_queue_suspension_ends_v2(
    p_now timestamptz,
    p_row_limit integer
)
RETURNS TABLE (queued bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_queue_suspension_ends_v1(p_now, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_queue_suspension_ends_v2(p_now timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.search_observe_lag_v4()
RETURNS TABLE (pending bigint, oldest_pending_at text, lag_seconds bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_observe_lag_v3();
$$;
REVOKE EXECUTE ON FUNCTION api.search_observe_lag_v4() FROM PUBLIC;

CREATE FUNCTION api.forum_list_public_threads_v6(
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
    reply_count bigint,
    excerpt text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_public_threads_v5(p_member, p_global_read, p_category_ids, p_space_ids, p_after_activity, p_after_thread_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v6(p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_after_activity timestamp with time zone, p_after_thread_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.search_index_entity_v4(
    p_entity_type text,
    p_entity_id uuid,
    p_document_id uuid,
    p_indexed_at text,
    p_config text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_index_entity_v3(p_entity_type, p_entity_id, p_document_id, p_indexed_at, p_config);
$$;
REVOKE EXECUTE ON FUNCTION api.search_index_entity_v4(p_entity_type text, p_entity_id uuid, p_document_id uuid, p_indexed_at text, p_config text) FROM PUBLIC;

CREATE FUNCTION api.search_ranked_v16(
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
    p_row_limit integer,
    p_entity_type text
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    body text,
    source_created_at timestamptz,
    indexed_at timestamptz,
    rank_score double precision,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text,
    candidate_count bigint,
    thread_owner_user_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_ranked_v15(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_like_pattern, p_config, p_candidate_limit, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit, p_entity_type)
$$;
REVOKE EXECUTE ON FUNCTION api.search_ranked_v16(p_permission_mode text, p_visibility_values text[], p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_query text, p_like_pattern text, p_config text, p_candidate_limit integer, p_category_filter uuid, p_author_filter uuid, p_from_at timestamp with time zone, p_to_at timestamp with time zone, p_to_exclusive boolean, p_row_limit integer, p_entity_type text) FROM PUBLIC;

CREATE FUNCTION api.search_thread_ranked_v8(
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
    p_row_limit integer,
    p_entity_type text,
    p_thread_filter uuid
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    body text,
    source_created_at timestamptz,
    indexed_at timestamptz,
    rank_score double precision,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text,
    candidate_count bigint,
    thread_owner_user_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_thread_ranked_v7(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_like_pattern, p_config, p_candidate_limit, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit, p_entity_type, p_thread_filter);
$$;
REVOKE EXECUTE ON FUNCTION api.search_thread_ranked_v8(p_permission_mode text, p_visibility_values text[], p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_query text, p_like_pattern text, p_config text, p_candidate_limit integer, p_category_filter uuid, p_author_filter uuid, p_from_at timestamp with time zone, p_to_at timestamp with time zone, p_to_exclusive boolean, p_row_limit integer, p_entity_type text, p_thread_filter uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_filter_tagged_threads_v2(
    p_tag_slugs text[],
    p_tag_match text,
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer,
    p_after_activity timestamptz,
    p_after_thread_id uuid
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
    category_title text,
    reply_count bigint
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_filter_tagged_threads_v1(p_tag_slugs, p_tag_match, p_category_id, p_member, p_global_read, p_scope_user_id, p_category_ids, p_space_ids, p_row_limit, p_after_activity, p_after_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_filter_tagged_threads_v2(p_tag_slugs text[], p_tag_match text, p_category_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer, p_after_activity timestamp with time zone, p_after_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.search_tagged_ranked_v2(
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
    p_row_limit integer,
    p_entity_type text,
    p_tag_slugs text[],
    p_tag_match text
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    body text,
    source_created_at timestamptz,
    indexed_at timestamptz,
    rank_score double precision,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text,
    candidate_count bigint,
    thread_owner_user_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_tagged_ranked_v1(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_like_pattern, p_config, p_candidate_limit, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit, p_entity_type, p_tag_slugs, p_tag_match)
$$;
REVOKE EXECUTE ON FUNCTION api.search_tagged_ranked_v2(p_permission_mode text, p_visibility_values text[], p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_query text, p_like_pattern text, p_config text, p_candidate_limit integer, p_category_filter uuid, p_author_filter uuid, p_from_at timestamp with time zone, p_to_at timestamp with time zone, p_to_exclusive boolean, p_row_limit integer, p_entity_type text, p_tag_slugs text[], p_tag_match text) FROM PUBLIC;

CREATE FUNCTION api.search_tagged_thread_ranked_v2(
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
    p_row_limit integer,
    p_entity_type text,
    p_thread_filter uuid,
    p_tag_slugs text[],
    p_tag_match text
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    body text,
    source_created_at timestamptz,
    indexed_at timestamptz,
    rank_score double precision,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text,
    candidate_count bigint,
    thread_owner_user_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_tagged_thread_ranked_v1(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_like_pattern, p_config, p_candidate_limit, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit, p_entity_type, p_thread_filter, p_tag_slugs, p_tag_match);
$$;
REVOKE EXECUTE ON FUNCTION api.search_tagged_thread_ranked_v2(p_permission_mode text, p_visibility_values text[], p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_query text, p_like_pattern text, p_config text, p_candidate_limit integer, p_category_filter uuid, p_author_filter uuid, p_from_at timestamp with time zone, p_to_at timestamp with time zone, p_to_exclusive boolean, p_row_limit integer, p_entity_type text, p_thread_filter uuid, p_tag_slugs text[], p_tag_match text) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_change_v8(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_poll_change_v7(p_actor, p_command, p_thread_id, p_operation, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_change_v8(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_read_v4(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_poll_read_v3(p_actor, p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_read_v4(p_actor uuid, p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v30(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.portability_export_parts_v29(p_user_id); $$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v30(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.community_follow_change_v2(p_actor uuid,p_command uuid,p_username text,p_operation text)
RETURNS TABLE(result jsonb) LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.community_follow_change_v1(p_actor, p_command, p_username, p_operation); $$;
REVOKE EXECUTE ON FUNCTION api.community_follow_change_v2(p_actor uuid, p_command uuid, p_username text, p_operation text) FROM PUBLIC;

CREATE FUNCTION api.community_follow_state_v2(p_actor uuid,p_target uuid)
RETURNS TABLE(following boolean) LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.community_follow_state_v1(p_actor, p_target); $$;
REVOKE EXECUTE ON FUNCTION api.community_follow_state_v2(p_actor uuid, p_target uuid) FROM PUBLIC;

CREATE FUNCTION api.community_followed_users_v2(p_actor uuid)
RETURNS TABLE(user_id uuid,username text,display_name text) LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.community_followed_users_v1(p_actor); $$;
REVOKE EXECUTE ON FUNCTION api.community_followed_users_v2(p_actor uuid) FROM PUBLIC;

CREATE FUNCTION api.community_follow_feed_v2(p_actor uuid,p_member boolean,p_global_read boolean,p_category_ids uuid[],p_space_ids uuid[],
    p_after_at timestamptz,p_after_id uuid,p_row_limit integer)
RETURNS TABLE(item_id uuid,item_type text,thread_id uuid,title text,username text,display_name text,created_at timestamptz) LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.community_follow_feed_v1(p_actor, p_member, p_global_read, p_category_ids, p_space_ids, p_after_at, p_after_id, p_row_limit); $$;
REVOKE EXECUTE ON FUNCTION api.community_follow_feed_v2(p_actor uuid, p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v32(p_source text,p_user_id uuid,p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.privacy_revoke_user_v31(p_source,p_user_id,p_at); $$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v32(p_source text, p_user_id uuid, p_at text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_create_v2(p_object_key text, p_byte_size bigint, p_checksum text)
RETURNS TABLE (created boolean)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_create_v1(p_object_key, p_byte_size, p_checksum) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_create_v2(p_object_key text, p_byte_size bigint, p_checksum text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_chunk_insert_v2(p_object_key text, p_chunk_number integer, p_data bytea)
RETURNS TABLE (written boolean)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_chunk_insert_v1(p_object_key, p_chunk_number, p_data) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_chunk_insert_v2(p_object_key text, p_chunk_number integer, p_data bytea) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_finish_v2(p_object_key text)
RETURNS TABLE (finished boolean)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_finish_v1(p_object_key) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_finish_v2(p_object_key text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_info_v2(p_object_key text)
RETURNS TABLE (byte_size bigint, checksum text, modified_at double precision)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_info_v1(p_object_key) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_info_v2(p_object_key text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_chunk_v2(p_object_key text, p_chunk_number integer)
RETURNS TABLE (data bytea)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_chunk_v1(p_object_key, p_chunk_number) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_chunk_v2(p_object_key text, p_chunk_number integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_delete_v2(p_object_key text)
RETURNS TABLE (deleted boolean)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_delete_v1(p_object_key) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_delete_v2(p_object_key text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_import_candidates_v2(p_after_key text, p_row_limit integer)
RETURNS TABLE (object_key text, byte_size bigint, checksum text, attachment_id uuid)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_object_import_candidates_v1(p_after_key, p_row_limit) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_import_candidates_v2(p_after_key text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_submit_v2(p_attachment_id uuid, p_source_kind text, p_source_url text)
RETURNS TABLE (submitted boolean) LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_review_submit_v1(p_attachment_id, p_source_kind, p_source_url) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_submit_v2(p_attachment_id uuid, p_source_kind text, p_source_url text) FROM PUBLIC;

CREATE FUNCTION api.attachment_content_blocked_v2(p_checksum text)
RETURNS TABLE (blocked boolean) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_content_blocked_v1(p_checksum) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_content_blocked_v2(p_checksum text) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_queue_v2(p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS TABLE (result jsonb) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_review_queue_v1(p_after_at, p_after_id, p_row_limit) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_queue_v2(p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_find_v2(p_attachment_id uuid)
RETURNS TABLE (result jsonb) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_review_find_v1(p_attachment_id) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_find_v2(p_attachment_id uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_decide_v2(p_attachment_id uuid, p_actor uuid, p_status text, p_reason text)
RETURNS TABLE (status text) LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_review_decide_v1(p_attachment_id, p_actor, p_status, p_reason) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_decide_v2(p_attachment_id uuid, p_actor uuid, p_status text, p_reason text) FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_state_v2()
RETURNS TABLE(revision bigint,settings jsonb) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.admin_configuration_state_v1() $$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_state_v2() FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_change_v2(p_actor uuid,p_command uuid,p_expected bigint,
    p_section text,p_key text,p_operation text,p_value jsonb,p_request_hash text)
RETURNS TABLE(result jsonb) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.admin_configuration_change_v1(p_actor,p_command,p_expected,p_section,p_key,p_operation,p_value,p_request_hash) $$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_change_v2(p_actor uuid, p_command uuid, p_expected bigint, p_section text, p_key text, p_operation text, p_value jsonb, p_request_hash text) FROM PUBLIC;

CREATE TRIGGER attachment_content_guard BEFORE UPDATE ON public.attachments FOR EACH ROW EXECUTE FUNCTION public.gpforum_attachment_review_guard();

CREATE TRIGGER attachment_object_owner AFTER INSERT ON public.attachments FOR EACH ROW EXECUTE FUNCTION public.gpforum_attachment_object_owner();

CREATE TRIGGER attachment_variant_object_delete AFTER DELETE ON public.attachment_variants FOR EACH ROW EXECUTE FUNCTION public.gpforum_attachment_variant_object_delete();

CREATE TRIGGER attachment_variant_object_owner AFTER INSERT ON public.attachment_variants FOR EACH ROW EXECUTE FUNCTION public.gpforum_attachment_object_owner();

CREATE TRIGGER poll_ballot_reset BEFORE UPDATE OF option_number ON public.poll_ballots FOR EACH ROW EXECUTE FUNCTION api.core_poll_ballot_reset_v1();

CREATE TRIGGER poll_extra_counter AFTER INSERT OR DELETE ON public.poll_ballot_extra_choices FOR EACH ROW EXECUTE FUNCTION api.core_poll_extra_counter_v1();

COMMIT;
