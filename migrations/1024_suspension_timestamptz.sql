-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A suspension's end is an instant, and api.moderation_active_suspension_v1
-- compared it as text: 'recent.valid_to::text >= p_now', with p_now the
-- clock's ISO-8601 string. PostgreSQL renders a timestamptz as
-- '2026-05-23 20:00:00+02' (a space, the server's zone) while the clock
-- writes '2026-05-23T12:00:00Z', and a space sorts before a T: on its last
-- day a suspension read as expired, the member could post, and suspending
-- them again inserted a second suspension. v1 also looked at the member's
-- ten most recent unrevoked suspensions only, so an open-ended one behind
-- ten newer expired ones was not found.
--
-- v3 takes the clock as timestamptz and compares instants, as
-- api.moderation_suspension_list_v1 does for active_only, over every
-- unrevoked suspension: the newest one still valid is the active one.
-- api.moderation_can_participate_v3 asks v3. The _v4 boundaries are the
-- SECURITY DEFINER entry points of ADR 0127, each forwarding its typed
-- parameters to exactly its own implementation. v1 and v2 stay installed
-- for the release that still calls them (ADR 0126, section 2).
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.moderation_active_suspension_v3(p_user_id uuid, p_now timestamptz)
RETURNS TABLE (suspension_id uuid, user_id uuid, actor_user_id uuid, reason text,
    valid_from timestamptz, valid_to timestamptz, revoked_at timestamptz,
    metadata jsonb)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.suspension_id, s.user_id, s.actor_user_id, s.reason,
    s.valid_from, s.valid_to, s.revoked_at, s.metadata
FROM public.suspensions s
WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
    AND (s.valid_to IS NULL OR s.valid_to >= p_now)
ORDER BY s.valid_from DESC, s.suspension_id DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v3(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.moderation_can_participate_v3(p_user_id uuid, p_now timestamptz)
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
            FROM api.moderation_active_suspension_v3(p_user_id, p_now) s;
        IF FOUND THEN
            RETURN QUERY SELECT 0, 'suspended'::text, v_suspension;
        ELSE
            RETURN QUERY SELECT 1, NULL::text, NULL::uuid;
        END IF;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v3(uuid, timestamptz) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v4(uuid, timestamptz) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v4(uuid, timestamptz) FROM PUBLIC;

COMMIT;
