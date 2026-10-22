-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Sessions and the request prologue: validating a session, touching it,
-- resolving the viewer.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Stores a new session. A taken id answers skipped when it holds the same
-- session and retry_id when another, a taken token hash retry_token, so the
-- caller draws again; with p_retry, a second conflict raises.
CREATE FUNCTION api.session_create_v1(
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
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.session_create_v1(uuid, uuid, text, timestamptz, timestamptz, timestamptz, timestamptz, text, text, boolean)
    FROM PUBLIC;

-- Of the given sessions, the ones neither revoked nor expired.
CREATE FUNCTION api.session_live_v1(p_session_ids uuid[], p_now timestamptz)
RETURNS TABLE (session_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.session_id
FROM public.sessions s
WHERE s.session_id = ANY(p_session_ids)
  AND s.revoked_at IS NULL
  AND date_trunc('second', s.expires_at) > p_now;
$$;
REVOKE EXECUTE ON FUNCTION api.session_live_v1(uuid[], timestamptz)
    FROM PUBLIC;

-- A session by id, and of this member when one is given.
CREATE FUNCTION api.session_lookup_v1(p_session_id uuid, p_user_id uuid)
RETURNS SETOF api.identity_session_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RETURN QUERY SELECT s.session_id, s.user_id, s.session_hash,
            s.created_at, s.last_seen_at, s.expires_at, s.revoked_at,
            s.ip_hash, s.user_agent_hash FROM public.sessions s
            WHERE s.session_id = p_session_id;
    ELSE
        RETURN QUERY SELECT s.session_id, s.user_id, s.session_hash,
            s.created_at, s.last_seen_at, s.expires_at, s.revoked_at,
            s.ip_hash, s.user_agent_hash FROM public.sessions s
            WHERE s.session_id = p_session_id AND s.user_id = p_user_id;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.session_lookup_v1(uuid, uuid) FROM PUBLIC;

-- Revokes a member's live sessions, all but p_keep_session_id when it is
-- given. Answers how many.
CREATE FUNCTION api.session_revoke_user_v1(
    p_user_id uuid,
    p_revoked_at timestamptz,
    p_keep_session_id uuid
)
RETURNS TABLE (revoked_count bigint)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.session_revoke_user_v1(uuid, timestamptz, uuid)
    FROM PUBLIC;

-- Revokes one session, of this member when one is given, and answers it.
CREATE FUNCTION api.session_revoke_v1(
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
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.session_revoke_v1(uuid, uuid, timestamptz)
    FROM PUBLIC;

-- Validates a session against its token's digest and its expiry, and touches
-- its last-seen time when the touch interval has passed.
CREATE FUNCTION api.session_validate_v1(
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
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.session_validate_v1(uuid, uuid, text, timestamptz, integer)
    FROM PUBLIC;

COMMIT;
