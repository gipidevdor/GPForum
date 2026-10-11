-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.moderation_target_v1(p_kind text, p_target_id uuid, p_hold boolean)
RETURNS TABLE(target_id uuid, moderation_state text, locked_at timestamptz, hidden_at timestamptz)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_kind = 'post' THEN
        IF p_hold THEN
            RETURN QUERY SELECT p.post_id, p.moderation_state, p.locked_at, p.hidden_at FROM public.posts p WHERE p.post_id = p_target_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT p.post_id, p.moderation_state, p.locked_at, p.hidden_at FROM public.posts p WHERE p.post_id = p_target_id;
        END IF;
    ELSIF p_kind = 'thread' THEN
        IF p_hold THEN
            RETURN QUERY SELECT t.thread_id, t.moderation_state, t.locked_at, NULL::timestamptz FROM public.threads t WHERE t.thread_id = p_target_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT t.thread_id, t.moderation_state, t.locked_at, NULL::timestamptz FROM public.threads t WHERE t.thread_id = p_target_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_v1(text, uuid, boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_update_v1(p_kind text, p_target_id uuid, p_changes jsonb)
RETURNS TABLE(changed_count bigint)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_kind = 'post' THEN
        UPDATE public.posts p SET
          moderation_state = CASE WHEN p_changes ? 'moderation_state' THEN p_changes->>'moderation_state' ELSE p.moderation_state END,
          hidden_at = CASE WHEN p_changes ? 'hidden_at' THEN (p_changes->>'hidden_at')::timestamptz ELSE p.hidden_at END,
          locked_at = CASE WHEN p_changes ? 'locked_at' THEN (p_changes->>'locked_at')::timestamptz ELSE p.locked_at END
        WHERE p.post_id = p_target_id;
    ELSIF p_kind = 'thread' THEN
        UPDATE public.threads t SET
          moderation_state = CASE WHEN p_changes ? 'moderation_state' THEN p_changes->>'moderation_state' ELSE t.moderation_state END,
          locked_at = CASE WHEN p_changes ? 'locked_at' THEN (p_changes->>'locked_at')::timestamptz ELSE t.locked_at END
        WHERE t.thread_id = p_target_id;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
    RETURN QUERY SELECT 1::bigint;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v1(text, uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_find_v1(p_action_id uuid, p_command_id uuid, p_action_type text, p_target_type text, p_target_id uuid)
RETURNS SETOF public.moderation_actions
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_action_id IS NOT NULL THEN
        RETURN QUERY SELECT a.* FROM public.moderation_actions a WHERE a.moderation_action_id = p_action_id;
    ELSIF p_command_id IS NOT NULL THEN
        RETURN QUERY SELECT a.* FROM public.moderation_actions a WHERE a.command_id = p_command_id LIMIT 1;
    ELSE
        RETURN QUERY SELECT a.* FROM public.moderation_actions a WHERE a.action_type = p_action_type
        AND a.target_type = p_target_type AND a.target_id = p_target_id AND a.reversed_at IS NULL
        ORDER BY a.created_at DESC LIMIT 1;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_find_v1(uuid, uuid, text, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_update_v1(p_action_id uuid, p_changes jsonb)
RETURNS SETOF public.moderation_actions
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.moderation_actions a SET
      reversed_at = (p_changes->>'reversed_at')::timestamptz,
      reversed_by_user_id = (p_changes->>'reversed_by_user_id')::uuid
    WHERE a.moderation_action_id = p_action_id RETURNING a.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_update_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_find_v1(p_report_id uuid, p_reporter_user_id uuid, p_target_type text, p_target_id uuid, p_hold boolean)
RETURNS SETOF public.reports
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_report_id IS NOT NULL THEN
        IF p_hold THEN
            RETURN QUERY SELECT r.* FROM public.reports r WHERE r.report_id = p_report_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT r.* FROM public.reports r WHERE r.report_id = p_report_id;
        END IF;
    ELSE
        RETURN QUERY SELECT r.* FROM public.reports r WHERE r.reporter_user_id = p_reporter_user_id
        AND r.target_type = p_target_type AND r.target_id = p_target_id AND r.status IN ('open','triaged')
        ORDER BY r.created_at DESC LIMIT 1;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_find_v1(uuid, uuid, text, uuid, boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_update_v1(p_report_id uuid, p_changes jsonb)
RETURNS SETOF public.reports
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.reports r SET
      assigned_moderator_user_id = CASE WHEN p_changes ? 'assigned_moderator_user_id' THEN (p_changes->>'assigned_moderator_user_id')::uuid ELSE r.assigned_moderator_user_id END,
      status = CASE WHEN p_changes ? 'status' THEN p_changes->>'status' ELSE r.status END,
      resolved_at = CASE WHEN p_changes ? 'resolved_at' THEN (p_changes->>'resolved_at')::timestamptz ELSE r.resolved_at END,
      resolution = CASE WHEN p_changes ? 'resolution' THEN p_changes->>'resolution' ELSE r.resolution END
    WHERE r.report_id = p_report_id RETURNING r.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_update_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_queue_v1(p_status text, p_row_limit integer)
RETURNS SETOF public.reports
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT r.* FROM public.reports r WHERE r.status = p_status
    ORDER BY r.created_at ASC, r.report_id ASC LIMIT p_row_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_queue_v1(text, integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_find_v1(p_suspension_id uuid)
RETURNS SETOF public.suspensions
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT s.* FROM public.suspensions s WHERE s.suspension_id = p_suspension_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_find_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_update_v1(p_suspension_id uuid, p_revoked_at timestamptz)
RETURNS SETOF public.suspensions
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.suspensions s SET revoked_at = p_revoked_at WHERE s.suspension_id = p_suspension_id RETURNING s.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_update_v1(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_insert_v1(p_values jsonb)
RETURNS SETOF public.moderation_actions
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.moderation_actions (moderation_action_id, actor_user_id, action_type, target_type, target_id, reason, metadata, created_at, reversed_at, reversed_by_user_id, command_id)
    SELECT r.moderation_action_id, r.actor_user_id, r.action_type, r.target_type, r.target_id, r.reason, r.metadata, r.created_at, r.reversed_at, r.reversed_by_user_id, r.command_id FROM jsonb_populate_record(NULL::public.moderation_actions, p_values) r RETURNING *;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_insert_v1(p_values jsonb)
RETURNS SETOF public.reports
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.reports (report_id, reporter_user_id, target_type, target_id, reason, details, status, assigned_moderator_user_id, created_at, resolved_at, resolution)
    SELECT r.report_id, r.reporter_user_id, r.target_type, r.target_id, r.reason, r.details, r.status, r.assigned_moderator_user_id, r.created_at, r.resolved_at, r.resolution FROM jsonb_populate_record(NULL::public.reports, p_values) r RETURNING *;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_insert_v1(p_values jsonb)
RETURNS SETOF public.suspensions
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.suspensions (suspension_id, user_id, actor_user_id, reason, valid_from, valid_to, revoked_at, metadata)
    SELECT r.suspension_id, r.user_id, r.actor_user_id, r.reason, r.valid_from, r.valid_to, r.revoked_at, r.metadata FROM jsonb_populate_record(NULL::public.suspensions, p_values) r RETURNING *;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_list_v1(p_target_type text, p_target_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS SETOF public.moderation_actions
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_after_at IS NULL THEN
        RETURN QUERY SELECT a.* FROM public.moderation_actions a WHERE (p_target_type IS NULL OR a.target_type = p_target_type) AND (p_target_id IS NULL OR a.target_id = p_target_id)
        ORDER BY a.created_at DESC, a.moderation_action_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.* FROM public.moderation_actions a WHERE (p_target_type IS NULL OR a.target_type = p_target_type) AND (p_target_id IS NULL OR a.target_id = p_target_id)
        AND (a.created_at, a.moderation_action_id) < (p_after_at, p_after_id)
        ORDER BY a.created_at DESC, a.moderation_action_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_list_v1(text, uuid, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_list_v1(p_user_id uuid, p_active_only boolean, p_now timestamptz, p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS SETOF public.suspensions
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_after_at IS NULL THEN
        RETURN QUERY SELECT a.* FROM public.suspensions a WHERE (p_user_id IS NULL OR a.user_id = p_user_id) AND (NOT p_active_only OR (a.revoked_at IS NULL AND (a.valid_to IS NULL OR a.valid_to >= p_now)))
        ORDER BY a.valid_from DESC, a.suspension_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.* FROM public.suspensions a WHERE (p_user_id IS NULL OR a.user_id = p_user_id) AND (NOT p_active_only OR (a.revoked_at IS NULL AND (a.valid_to IS NULL OR a.valid_to >= p_now)))
        AND (a.valid_from, a.suspension_id) < (p_after_at, p_after_id)
        ORDER BY a.valid_from DESC, a.suspension_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_list_v1(uuid, boolean, timestamptz, timestamptz, uuid, integer) FROM PUBLIC;

COMMIT;
