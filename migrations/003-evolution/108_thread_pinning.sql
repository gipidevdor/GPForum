-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A thread's pinned flag has ordered every list since the first projection,
-- and nothing could set it. Staff now pin and unpin a thread the way they
-- lock one: the moderation target carries the flag so the action store can
-- see whether the pin is already on, and the target update can write it.
-- The reader of a request learns, with the grants it already resolves,
-- whether it moderates threads, so the thread page can offer the staff
-- actions without a second permission lookup. New versions, as ADR 0126
-- section 2 asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_resolve_viewer_v3(p_user_id uuid)
RETURNS TABLE (status text, suspended boolean, grants json,
    moderates boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.status,
    EXISTS (SELECT 1 FROM public.suspensions s WHERE s.user_id = u.id
        AND s.revoked_at IS NULL AND s.valid_from <= now()
        AND (s.valid_to IS NULL OR s.valid_to > now())) AS suspended,
    coalesce((SELECT json_agg(json_build_object('resource_type',
        b.resource_type, 'resource_id', b.resource_id, 'space_id', b.space_id))
        FROM public.role_bindings b
        JOIN public.role_permissions rp ON rp.role_id = b.role_id
        JOIN public.permissions p ON p.permission_id = rp.permission_id
        WHERE b.user_id = u.id AND b.revoked_at IS NULL
            AND p.resource_type = 'category' AND p.action = 'read'), '[]')
        AS grants,
    -- The global binding is the one the moderation routes accept for every
    -- thread (Controller::Moderation::Base scopes a write to the thread or
    -- to nothing); a binding on one thread or one space is not the page's.
    EXISTS (SELECT 1 FROM public.role_bindings b
        JOIN public.role_permissions rp ON rp.role_id = b.role_id
        JOIN public.permissions p ON p.permission_id = rp.permission_id
        WHERE b.user_id = u.id AND b.revoked_at IS NULL
            AND b.resource_id IS NULL AND b.space_id IS NULL
            AND p.resource_type = 'thread' AND p.action = 'moderate')
        AS moderates
    FROM public.users u WHERE u.id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v3(uuid) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.forum_resolve_viewer_v4(
p_user_id uuid
)
RETURNS TABLE (status text, suspended boolean, grants json,
    moderates boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_resolve_viewer_v3(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v4(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_v3(p_kind text, p_target_id uuid,
    p_hold boolean)
RETURNS TABLE(target_id uuid, moderation_state text, locked_at timestamptz,
    hidden_at timestamptz, pinned boolean)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_kind = 'post' THEN
        IF p_hold THEN
            RETURN QUERY SELECT p.post_id, p.moderation_state, p.locked_at,
                p.hidden_at, NULL::boolean
                FROM public.posts p WHERE p.post_id = p_target_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT p.post_id, p.moderation_state, p.locked_at,
                p.hidden_at, NULL::boolean
                FROM public.posts p WHERE p.post_id = p_target_id;
        END IF;
    ELSIF p_kind = 'thread' THEN
        IF p_hold THEN
            RETURN QUERY SELECT t.thread_id, t.moderation_state, t.locked_at,
                NULL::timestamptz, t.pinned
                FROM public.threads t WHERE t.thread_id = p_target_id
                FOR UPDATE;
        ELSE
            RETURN QUERY SELECT t.thread_id, t.moderation_state, t.locked_at,
                NULL::timestamptz, t.pinned
                FROM public.threads t WHERE t.thread_id = p_target_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_v3(text, uuid, boolean)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_target_v4(
p_kind text, p_target_id uuid, p_hold boolean
)
RETURNS TABLE(target_id uuid, moderation_state text, locked_at timestamptz,
    hidden_at timestamptz, pinned boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_target_v3(p_kind, p_target_id, p_hold);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_v4(text, uuid, boolean)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_target_update_v3(p_kind text, p_target_id uuid,
    p_changes jsonb)
RETURNS TABLE(changed_count bigint)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_kind = 'post' THEN
        UPDATE public.posts p SET
          moderation_state = CASE WHEN p_changes ? 'moderation_state'
              THEN p_changes->>'moderation_state'
              ELSE p.moderation_state END,
          hidden_at = CASE WHEN p_changes ? 'hidden_at'
              THEN (p_changes->>'hidden_at')::timestamptz
              ELSE p.hidden_at END,
          locked_at = CASE WHEN p_changes ? 'locked_at'
              THEN (p_changes->>'locked_at')::timestamptz
              ELSE p.locked_at END
        WHERE p.post_id = p_target_id;
    ELSIF p_kind = 'thread' THEN
        UPDATE public.threads t SET
          moderation_state = CASE WHEN p_changes ? 'moderation_state'
              THEN p_changes->>'moderation_state'
              ELSE t.moderation_state END,
          locked_at = CASE WHEN p_changes ? 'locked_at'
              THEN (p_changes->>'locked_at')::timestamptz
              ELSE t.locked_at END,
          pinned = CASE WHEN p_changes ? 'pinned'
              THEN (p_changes->>'pinned')::boolean
              ELSE t.pinned END
        WHERE t.thread_id = p_target_id;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
    RETURN QUERY SELECT 1::bigint;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v3(text, uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_target_update_v4(
p_kind text, p_target_id uuid, p_changes jsonb
)
RETURNS TABLE(changed_count bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_target_update_v3(p_kind, p_target_id,
    p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v4(text, uuid, jsonb)
    FROM PUBLIC;

COMMIT;
