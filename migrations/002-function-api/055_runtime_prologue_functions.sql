-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126 wave 1: the request's session, viewer, participation and rate
-- limit work. Each statement and conflict recovery is kept inside api;
-- bearer tokens, hashes, ids and clocks still come from the application.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.core_session_digest_equals_v1(p_stored text, p_presented text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_stored bytea;
    v_presented bytea;
    v_difference integer := 0;
    v_position integer;
BEGIN
    IF p_stored IS NULL OR p_presented IS NULL
       OR length(p_stored) = 0 OR length(p_stored) <> length(p_presented) THEN
        RETURN false;
    END IF;
    v_stored := convert_to(p_stored, 'UTF8');
    v_presented := convert_to(p_presented, 'UTF8');
    IF length(v_stored) <> length(v_presented) THEN
        RETURN false;
    END IF;
    FOR v_position IN 0 .. length(v_stored) - 1 LOOP
        v_difference := v_difference | (get_byte(v_stored, v_position)
            # get_byte(v_presented, v_position));
    END LOOP;
    RETURN v_difference = 0;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_session_digest_equals_v1(text, text) FROM PUBLIC;

CREATE FUNCTION api.session_lookup_v1(p_session_id uuid, p_user_id uuid)
RETURNS SETOF public.sessions
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RETURN QUERY SELECT s.* FROM public.sessions s
            WHERE s.session_id = p_session_id;
    ELSE
        RETURN QUERY SELECT s.* FROM public.sessions s
            WHERE s.session_id = p_session_id AND s.user_id = p_user_id;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.session_lookup_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.session_create_v1(p_session_id uuid, p_user_id uuid, p_session_hash text,
    p_created_at timestamptz, p_last_seen_at timestamptz,
    p_expires_at timestamptz, p_revoked_at timestamptz, p_ip_hash text,
    p_user_agent_hash text, p_retry boolean)
RETURNS TABLE (result_code text, session_id uuid, user_id uuid, session_hash text,
    created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
    revoked_at timestamptz, ip_hash text, user_agent_hash text)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_session public.sessions%ROWTYPE;
    v_constraint text;
BEGIN
    BEGIN
        INSERT INTO public.sessions (session_id, user_id, session_hash,
            created_at, last_seen_at, expires_at, revoked_at, ip_hash,
            user_agent_hash)
        VALUES (p_session_id, p_user_id, p_session_hash, p_created_at,
            p_last_seen_at, p_expires_at, p_revoked_at, p_ip_hash,
            p_user_agent_hash)
        RETURNING * INTO v_session;
    EXCEPTION WHEN unique_violation THEN
        IF p_retry THEN
            RAISE;
        END IF;
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'sessions_pkey' THEN
            SELECT s.* INTO v_session FROM public.sessions s
                WHERE s.session_id = p_session_id;
            IF FOUND AND v_session.user_id = p_user_id
                AND v_session.session_hash = p_session_hash THEN
                RETURN QUERY SELECT 'skipped'::text, v_session.*;
            ELSE
                RETURN QUERY SELECT 'retry_id'::text, v_session.*;
            END IF;
        ELSE
            RETURN QUERY SELECT 'retry_token'::text, v_session.*;
        END IF;
        RETURN;
    END;
    RETURN QUERY SELECT 'ok'::text, v_session.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.session_create_v1(uuid, uuid, text, timestamptz, timestamptz, timestamptz, timestamptz, text, text, boolean) FROM PUBLIC;

CREATE FUNCTION api.session_validate_v1(p_session_id uuid, p_user_id uuid, p_token_hash text,
    p_now timestamptz, p_touch_interval_seconds integer)
RETURNS TABLE (result_code text, session_id uuid, user_id uuid, session_hash text,
    created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
    revoked_at timestamptz, ip_hash text, user_agent_hash text)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_session public.sessions%ROWTYPE;
BEGIN
    SELECT s.* INTO v_session FROM public.sessions s
        WHERE s.session_id = p_session_id AND s.user_id = p_user_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, v_session.*;
        RETURN;
    END IF;
    IF NOT api.core_session_digest_equals_v1(v_session.session_hash,
        p_token_hash) THEN
        RETURN QUERY SELECT 'invalid_token'::text, v_session.*;
        RETURN;
    END IF;
    IF v_session.revoked_at IS NOT NULL THEN
        RETURN QUERY SELECT 'revoked'::text, v_session.*;
        RETURN;
    END IF;
    -- Identity::Support parses timestamps to whole seconds, discarding the
    -- fractions. Keep the same boundary at expiry and at the touch interval.
    IF date_trunc('second', v_session.expires_at) <= p_now THEN
        UPDATE public.sessions s SET revoked_at = p_now
            WHERE s.session_id = p_session_id;
        v_session.revoked_at := p_now;
        RETURN QUERY SELECT 'expired'::text, v_session.*;
        RETURN;
    END IF;
    IF extract(epoch FROM p_now - date_trunc('second', v_session.last_seen_at))
        >= p_touch_interval_seconds THEN
        UPDATE public.sessions s SET last_seen_at = p_now
            WHERE s.session_id = p_session_id;
        v_session.last_seen_at := p_now;
    END IF;
    RETURN QUERY SELECT 'ok'::text, v_session.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.session_validate_v1(uuid, uuid, text, timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.session_revoke_v1(p_session_id uuid, p_user_id uuid,
    p_revoked_at timestamptz)
RETURNS TABLE (result_code text, session_id uuid, user_id uuid, session_hash text,
    created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
    revoked_at timestamptz, ip_hash text, user_agent_hash text)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_session public.sessions%ROWTYPE;
    v_updated bigint;
BEGIN
    IF p_user_id IS NULL THEN
        SELECT s.* INTO v_session FROM public.sessions s
            WHERE s.session_id = p_session_id;
    ELSE
        SELECT s.* INTO v_session FROM public.sessions s
            WHERE s.session_id = p_session_id AND s.user_id = p_user_id;
    END IF;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, v_session.*;
        RETURN;
    END IF;
    IF v_session.revoked_at IS NOT NULL THEN
        RETURN QUERY SELECT 'skipped'::text, v_session.*;
        RETURN;
    END IF;
    UPDATE public.sessions s
        SET revoked_at = greatest(p_revoked_at, s.created_at)
        WHERE s.session_id = p_session_id AND s.revoked_at IS NULL;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    -- The old store returns the row read before its conditional UPDATE.
    RETURN QUERY SELECT CASE WHEN v_updated = 0 THEN 'skipped' ELSE 'ok' END,
        v_session.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.session_revoke_v1(uuid, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.session_revoke_user_v1(p_user_id uuid, p_revoked_at timestamptz,
    p_keep_session_id uuid)
RETURNS TABLE (revoked_count bigint)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_updated bigint;
BEGIN
    IF p_keep_session_id IS NULL THEN
        UPDATE public.sessions s
            SET revoked_at = greatest(p_revoked_at, s.created_at)
            WHERE s.user_id = p_user_id AND s.revoked_at IS NULL;
    ELSE
        UPDATE public.sessions s
            SET revoked_at = greatest(p_revoked_at, s.created_at)
            WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
                AND s.session_id <> p_keep_session_id;
    END IF;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN QUERY SELECT v_updated;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.session_revoke_user_v1(uuid, timestamptz, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v1(p_user_id uuid)
RETURNS TABLE (status text, suspended boolean, grants json)
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
    FROM public.users u WHERE u.id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_rate_limit_check_v1(p_scope text, p_actor_hash text, p_action text,
    p_window_start timestamptz, p_window_seconds integer, p_limit integer,
    p_now timestamptz, p_expires_at timestamptz)
RETURNS TABLE (scope text, actor_hash text, action text, window_started_at timestamptz,
    observed_count integer, blocked_count integer)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO public.rate_limit_buckets AS b (
        scope, actor_hash, action, window_started_at, window_seconds,
        observed_count, blocked_count, first_seen_at, last_seen_at, expires_at)
    VALUES (p_scope, p_actor_hash, p_action, p_window_start, p_window_seconds,
        1, CASE WHEN 1 > p_limit THEN 1 ELSE 0 END, p_now, p_now, p_expires_at)
    ON CONFLICT ON CONSTRAINT rate_limit_buckets_pkey DO UPDATE SET
        observed_count = b.observed_count + 1,
        blocked_count = b.blocked_count
            + CASE WHEN b.observed_count + 1 > p_limit THEN 1 ELSE 0 END,
        last_seen_at = EXCLUDED.last_seen_at,
        expires_at = EXCLUDED.expires_at
    RETURNING b.scope, b.actor_hash, b.action, b.window_started_at,
        b.observed_count, b.blocked_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_check_v1(text, text, text, timestamptz, integer, integer, timestamptz, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.ops_rate_limit_snapshot_v1(p_now timestamptz)
RETURNS TABLE (buckets bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT count(*) FROM public.rate_limit_buckets b
    WHERE b.expires_at > p_now
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_snapshot_v1(timestamptz) FROM PUBLIC;

CREATE FUNCTION api.moderation_active_suspension_v1(p_user_id uuid, p_now text)
RETURNS TABLE (suspension_id uuid, user_id uuid, actor_user_id uuid, reason text,
    valid_from timestamptz, valid_to timestamptz, revoked_at timestamptz,
    metadata jsonb)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT recent.* FROM (
    SELECT s.* FROM public.suspensions s
        WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
        ORDER BY s.valid_from DESC, s.suspension_id DESC LIMIT 10
) recent
-- The original policy compares the timestamp's text with the supplied
-- clock and examines only these ten rows. Preserve both during migration.
WHERE recent.valid_to IS NULL OR recent.valid_to::text >= p_now
ORDER BY recent.valid_from DESC, recent.suspension_id DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.moderation_can_participate_v1(p_user_id uuid, p_now text)
RETURNS TABLE (ok integer, reason text, suspension_id uuid)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_status text;
    v_suspension uuid;
BEGIN
    SELECT u.status INTO v_status FROM public.users u WHERE u.id = p_user_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 0, 'user_not_found'::text, NULL::uuid;
    ELSIF v_status = 'deleted' THEN
        RETURN QUERY SELECT 0, 'user_deleted'::text, NULL::uuid;
    ELSIF v_status = 'suspended' THEN
        RETURN QUERY SELECT 0, 'suspended'::text, NULL::uuid;
    ELSE
        SELECT s.suspension_id INTO v_suspension
            FROM api.moderation_active_suspension_v1(p_user_id, p_now) s;
        IF FOUND THEN
            RETURN QUERY SELECT 0, 'suspended'::text, v_suspension;
        ELSE
            RETURN QUERY SELECT 1, NULL::text, NULL::uuid;
        END IF;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.admin_permission_allowed_v1(p_user_id uuid, p_resource_type text,
    p_action text, p_resource_id uuid, p_space_id uuid)
RETURNS TABLE (allowed boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (
    SELECT 1 FROM public.role_bindings b
    JOIN public.role_permissions rp ON rp.role_id = b.role_id
    JOIN public.permissions p ON p.permission_id = rp.permission_id
    WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
        AND p.resource_type = p_resource_type AND p.action = p_action
        AND ((b.resource_id IS NULL AND b.space_id IS NULL)
            OR (b.resource_id IS NOT DISTINCT FROM p_resource_id
                AND b.space_id IS NOT DISTINCT FROM p_space_id))
)
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v1(uuid, text, text, uuid, uuid) FROM PUBLIC;

COMMIT;
