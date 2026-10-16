-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Static admin catalogue, scopes, console and audit operations. Validated
-- commands keep the transaction shared with their event/audit calls.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.admin_lookup_role_v1(p_query jsonb)
RETURNS SETOF public.roles
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.* FROM public.roles r WHERE r.name = p_query->>'name' LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_permission_v1(p_query jsonb)
RETURNS SETOF public.permissions
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.* FROM public.permissions r WHERE r.resource_type = p_query->>'resource_type' AND r.action = p_query->>'action' LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_permission_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_role_permission_v1(p_query jsonb)
RETURNS SETOF public.role_permissions
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.* FROM public.role_permissions r WHERE r.role_id = (p_query->>'role_id')::uuid AND r.permission_id = (p_query->>'permission_id')::uuid LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_permission_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_audit_v1(p_query jsonb)
RETURNS SETOF public.audit_log
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.* FROM public.audit_log r WHERE r.action = p_query->>'action' AND r.target_id = (p_query->>'target_id')::uuid LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_audit_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lookup_binding_v1(p_query jsonb)
RETURNS SETOF public.role_bindings
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.* FROM public.role_bindings r WHERE r.role_id = (p_query->>'role_id')::uuid AND r.resource_type = p_query->>'resource_type' AND r.revoked_at IS NULL
        AND (NOT p_query ? 'user_id' OR r.user_id IS NOT DISTINCT FROM (p_query->>'user_id')::uuid)
        AND (NOT p_query ? 'resource_id' OR r.resource_id IS NOT DISTINCT FROM (p_query->>'resource_id')::uuid)
        AND (NOT p_query ? 'space_id' OR r.space_id IS NOT DISTINCT FROM (p_query->>'space_id')::uuid) LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_binding_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_attachment_audits_v1(p_action text, p_target_id uuid, p_target_type text)
RETURNS TABLE(metadata jsonb)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT a.metadata FROM public.audit_log a WHERE a.action = p_action AND a.target_id = p_target_id
        AND a.target_type = p_target_type;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_attachment_audits_v1(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_role_v1(p_values jsonb)
RETURNS SETOF public.roles
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.roles (role_id, name, description, created_at)
    VALUES ((p_values->>'role_id')::uuid, (p_values->>'name')::text, (p_values->>'description')::text, (p_values->>'created_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_permission_v1(p_values jsonb)
RETURNS SETOF public.permissions
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.permissions (permission_id, name, resource_type, action, created_at)
    VALUES ((p_values->>'permission_id')::uuid, (p_values->>'name')::text, (p_values->>'resource_type')::text, (p_values->>'action')::text, (p_values->>'created_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_permission_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_role_permission_v1(p_values jsonb)
RETURNS SETOF public.role_permissions
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.role_permissions (role_id, permission_id, created_at)
    VALUES ((p_values->>'role_id')::uuid, (p_values->>'permission_id')::uuid, (p_values->>'created_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_permission_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_binding_v1(p_values jsonb)
RETURNS SETOF public.role_bindings
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.role_bindings (binding_id, user_id, role_id, resource_type, resource_id, space_id, created_by_user_id, created_at, revoked_at)
    VALUES ((p_values->>'binding_id')::uuid, (p_values->>'user_id')::uuid, (p_values->>'role_id')::uuid, (p_values->>'resource_type')::text, (p_values->>'resource_id')::uuid, (p_values->>'space_id')::uuid, (p_values->>'created_by_user_id')::uuid, (p_values->>'created_at')::timestamptz, (p_values->>'revoked_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_binding_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_space_v1(p_values jsonb)
RETURNS SETOF public.spaces
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.spaces (space_id, slug, title, description, visibility, position, version, permission_version, created_at, updated_at, deleted_at)
    VALUES ((p_values->>'space_id')::uuid, (p_values->>'slug')::text, (p_values->>'title')::text, (p_values->>'description')::text, (p_values->>'visibility')::text, (p_values->>'position')::integer, (p_values->>'version')::bigint, (p_values->>'permission_version')::bigint, (p_values->>'created_at')::timestamptz, (p_values->>'updated_at')::timestamptz, (p_values->>'deleted_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_space_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_insert_category_v1(p_values jsonb)
RETURNS SETOF public.categories
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.categories (category_id, space_id, slug, title, description, visibility, position, version, permission_version, created_at, updated_at, deleted_at)
    VALUES ((p_values->>'category_id')::uuid, (p_values->>'space_id')::uuid, (p_values->>'slug')::text, (p_values->>'title')::text, (p_values->>'description')::text, (p_values->>'visibility')::text, (p_values->>'position')::integer, (p_values->>'version')::bigint, (p_values->>'permission_version')::bigint, (p_values->>'created_at')::timestamptz, (p_values->>'updated_at')::timestamptz, (p_values->>'deleted_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_category_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_update_category_v1(p_category_id uuid, p_values jsonb)
RETURNS SETOF public.categories
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.categories c SET description = (p_values->>'description')::text, position = (p_values->>'position')::integer, slug = (p_values->>'slug')::text, title = (p_values->>'title')::text, updated_at = (p_values->>'updated_at')::timestamptz, version = (p_values->>'version')::bigint, visibility = (p_values->>'visibility')::text
        WHERE c.category_id = p_category_id RETURNING c.*;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_update_category_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_lock_binding_v1(p_binding_id uuid)
RETURNS SETOF public.role_bindings
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT b.* FROM public.role_bindings b WHERE b.binding_id = p_binding_id FOR UPDATE;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lock_binding_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_revoke_binding_v1(p_binding_id uuid, p_revoked_at timestamptz)
RETURNS SETOF public.role_bindings
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.role_bindings b SET revoked_at = p_revoked_at WHERE b.binding_id = p_binding_id RETURNING b.*;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_revoke_binding_v1(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.admin_list_roles_v1(p_row_limit integer)
RETURNS SETOF public.roles
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM public.roles ORDER BY name LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_roles_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_permissions_v1(p_row_limit integer)
RETURNS SETOF public.permissions
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM public.permissions ORDER BY resource_type, action, name LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_permissions_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_list_categories_v1(p_row_limit integer)
RETURNS SETOF public.categories
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM public.categories WHERE deleted_at IS NULL ORDER BY position, title, category_id LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_categories_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_roles_for_user_v1(p_user_id uuid, p_row_limit integer)
RETURNS SETOF public.role_bindings
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT b.* FROM public.role_bindings b WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
        ORDER BY b.resource_type, b.role_id LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_roles_for_user_v1(uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_permissions_for_role_v1(p_role_id uuid, p_row_limit integer)
RETURNS SETOF public.role_permissions
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.* FROM public.role_permissions r WHERE r.role_id = p_role_id ORDER BY r.permission_id LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permissions_for_role_v1(uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_space_by_id_v1(p_space_id uuid)
RETURNS SETOF public.spaces
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT s.* FROM public.spaces s WHERE s.space_id = p_space_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_id_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_space_by_slug_v1(p_slug text)
RETURNS SETOF public.spaces
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT s.* FROM public.spaces s WHERE s.slug = p_slug LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_slug_v1(text) FROM PUBLIC;

CREATE FUNCTION api.admin_first_live_space_v1()
RETURNS SETOF public.spaces
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT s.* FROM public.spaces s WHERE s.deleted_at IS NULL ORDER BY s.position, s.slug LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_first_live_space_v1() FROM PUBLIC;

CREATE FUNCTION api.admin_category_by_id_v1(p_category_id uuid)
RETURNS SETOF public.categories
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.* FROM public.categories c WHERE c.category_id = p_category_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_category_by_id_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_live_category_by_slug_v1(p_space_id uuid, p_slug text)
RETURNS SETOF public.categories
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.* FROM public.categories c WHERE c.space_id = p_space_id AND c.slug = p_slug
        AND c.deleted_at IS NULL LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_live_category_by_slug_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.admin_console_users_v1(p_status text, p_row_limit integer)
RETURNS TABLE(id uuid, username text, display_name text, email_normalized text, status text, trust_level integer, email_verified_at timestamptz, created_at timestamptz, updated_at timestamptz, deleted_at timestamptz)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.id, r.username, r.display_name, r.email_normalized, r.status, r.trust_level, r.email_verified_at, r.created_at, r.updated_at, r.deleted_at FROM public.users r WHERE r.deleted_at IS NULL AND (p_status IS NULL OR r.status = p_status)
        ORDER BY r.created_at DESC, r.username ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_users_v1(text, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_reports_v1(p_status text, p_row_limit integer)
RETURNS TABLE(report_id uuid, reporter_user_id uuid, target_type text, target_id uuid, reason text, details text, status text, assigned_moderator_user_id uuid, created_at timestamptz, resolved_at timestamptz, resolution text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.report_id, r.reporter_user_id, r.target_type, r.target_id, r.reason, r.details, r.status, r.assigned_moderator_user_id, r.created_at, r.resolved_at, r.resolution FROM public.reports r WHERE r.status = p_status
        ORDER BY r.created_at ASC, r.report_id ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_reports_v1(text, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_outbox_v1(p_status text, p_row_limit integer)
RETURNS TABLE(outbox_id uuid, event_id uuid, queue text, job_type text, idempotency_key text, available_at timestamptz, created_at timestamptz, locked_at timestamptz, attempts integer, status text, last_error text, next_attempt_at timestamptz, locked_by text, locked_until timestamptz, attempt_count integer, last_error_class text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.outbox_id, r.event_id, r.queue, r.job_type, r.idempotency_key, r.available_at, r.created_at, r.locked_at, r.attempts, r.status, r.last_error, r.next_attempt_at, r.locked_by, r.locked_until, r.attempt_count, r.last_error_class FROM public.outbox_messages r WHERE (p_status IS NULL OR r.status = p_status)
        ORDER BY r.created_at DESC, r.outbox_id DESC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_outbox_v1(text, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_console_email_v1(p_user_id uuid)
RETURNS TABLE(email_normalized text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT u.email_normalized FROM public.users u WHERE u.id = p_user_id AND u.deleted_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_email_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_console_counts_v1(p_dead_letters boolean)
RETURNS TABLE(total bigint)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_dead_letters THEN RETURN QUERY SELECT count(*) FROM public.dead_letters;
    ELSE RETURN QUERY SELECT count(*) FROM public.outbox_messages;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_counts_v1(boolean) FROM PUBLIC;

CREATE FUNCTION api.admin_console_dead_letters_v1(p_row_limit integer)
RETURNS TABLE(dead_letter_id uuid, source_table text, source_id uuid, error_class text, error_message text, failure_type text, retry_count integer, first_failed_at timestamptz, last_failed_at timestamptz, replay_status text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT d.dead_letter_id, d.source_table, d.source_id, d.error_class, d.error_message, d.failure_type, d.retry_count, d.first_failed_at, d.last_failed_at,
        COALESCE((SELECT r.status FROM public.outbox_messages r
            WHERE r.idempotency_key = 'dead-letter-replay:' || d.dead_letter_id::text),
            (SELECT 'replayed'::text FROM public.audit_log a WHERE a.action = 'outbox.dead_letter_replayed'
                AND a.target_type = 'dead_letter' AND a.target_id = d.dead_letter_id LIMIT 1))
        FROM public.dead_letters d ORDER BY d.last_failed_at DESC, d.dead_letter_id DESC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_dead_letters_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_audit_recent_v1(p_row_limit integer)
RETURNS SETOF public.audit_log
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT a.* FROM public.audit_log a ORDER BY a.created_at DESC, a.audit_id DESC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_recent_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.admin_audit_page_v1(p_filters jsonb, p_after jsonb, p_row_limit integer)
RETURNS SETOF public.audit_log
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_after IS NULL THEN
        RETURN QUERY SELECT a.* FROM public.audit_log a WHERE (p_filters->>'actor_id' IS NULL OR a.actor_id = (p_filters->>'actor_id')::uuid)
        AND (p_filters->>'action' IS NULL OR a.action = (p_filters->>'action')::text)
        AND (p_filters->>'target_type' IS NULL OR a.target_type = (p_filters->>'target_type')::text)
        AND (p_filters->>'target_id' IS NULL OR a.target_id = (p_filters->>'target_id')::uuid)
        AND (p_filters->>'correlation_id' IS NULL OR a.correlation_id = (p_filters->>'correlation_id')::uuid)
        AND (p_filters->>'from' IS NULL OR a.created_at >= ((p_filters->>'from') || 'T00:00:00Z')::timestamptz)
        AND (p_filters->>'until' IS NULL OR a.created_at <= ((p_filters->>'until') || 'T23:59:59.999999Z')::timestamptz) ORDER BY a.created_at DESC, a.audit_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.* FROM public.audit_log a WHERE (p_filters->>'actor_id' IS NULL OR a.actor_id = (p_filters->>'actor_id')::uuid)
        AND (p_filters->>'action' IS NULL OR a.action = (p_filters->>'action')::text)
        AND (p_filters->>'target_type' IS NULL OR a.target_type = (p_filters->>'target_type')::text)
        AND (p_filters->>'target_id' IS NULL OR a.target_id = (p_filters->>'target_id')::uuid)
        AND (p_filters->>'correlation_id' IS NULL OR a.correlation_id = (p_filters->>'correlation_id')::uuid)
        AND (p_filters->>'from' IS NULL OR a.created_at >= ((p_filters->>'from') || 'T00:00:00Z')::timestamptz)
        AND (p_filters->>'until' IS NULL OR a.created_at <= ((p_filters->>'until') || 'T23:59:59.999999Z')::timestamptz)
            AND a.created_at <= (p_after->>'created_at')::timestamptz
            AND (a.created_at, a.audit_id) < ((p_after->>'created_at')::timestamptz, (p_after->>'audit_id')::uuid)
            ORDER BY a.created_at DESC, a.audit_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_page_v1(jsonb, jsonb, integer) FROM PUBLIC;

CREATE FUNCTION api.admin_allow_slow_answer_v1(p_idle_ms integer)
RETURNS TABLE(timeout text)
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT set_config('idle_in_transaction_session_timeout', p_idle_ms::text, true);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_allow_slow_answer_v1(integer) FROM PUBLIC;

COMMIT;
