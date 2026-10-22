-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0146: address and range bans. Staff holding admin_console.manage ban
-- one address or a CIDR range (IPv4 no wider than /16, IPv6 no wider than
-- /32) from registering, from signing in (and registering), or from every
-- write, with a reason and an expiry of at most a year; they edit and lift
-- them from the admin console, and every change is audited without the
-- reason's text. Each write request asks which live ban covers its client
-- address: one GiST lookup on the live ranges. A ban that ended more than 90
-- days ago is deleted the next time one is placed. Bans are not about a
-- member: the export leaves them out (ADR 0074, security data), and the
-- erasure of a staff member removes their name from the bans they placed,
-- edited or lifted.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.address_bans (
    ban_id uuid NOT NULL,
    address_range cidr NOT NULL,
    scope text NOT NULL,
    reason text NOT NULL,
    created_at timestamptz NOT NULL,
    created_by_user_id uuid,
    expires_at timestamptz NOT NULL,
    updated_at timestamptz,
    updated_by_user_id uuid,
    lifted_at timestamptz,
    lifted_by_user_id uuid,
    CONSTRAINT address_bans_pkey PRIMARY KEY (ban_id),
    CONSTRAINT address_bans_created_by_user_id_fkey
        FOREIGN KEY (created_by_user_id)
        REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT address_bans_updated_by_user_id_fkey
        FOREIGN KEY (updated_by_user_id)
        REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT address_bans_lifted_by_user_id_fkey
        FOREIGN KEY (lifted_by_user_id)
        REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT address_bans_scope_check
        CHECK (scope IN ('registration', 'sign_in', 'writes')),
    CONSTRAINT address_bans_reason_check
        CHECK (length(reason) BETWEEN 1 AND 500),
    CONSTRAINT address_bans_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT address_bans_range_check CHECK (
        masklen(address_range)
            >= CASE family(address_range) WHEN 4 THEN 16 ELSE 32 END)
);

-- The live ranges, for the containment lookup every write makes.
CREATE INDEX idx_address_bans_live_range
    ON public.address_bans USING gist (address_range inet_ops)
    WHERE lifted_at IS NULL;
CREATE INDEX idx_address_bans_created
    ON public.address_bans (created_at DESC, ban_id DESC);
CREATE INDEX idx_address_bans_created_by
    ON public.address_bans (created_by_user_id);
CREATE INDEX idx_address_bans_updated_by
    ON public.address_bans (updated_by_user_id);
CREATE INDEX idx_address_bans_lifted_by
    ON public.address_bans (lifted_by_user_id);

-- Places a ban. The ban id is the form's command id: the same submission
-- again answers replayed, and an id another ban holds is a conflict. A
-- range wider than the bounds is too_broad; a sign-in or writes ban that
-- covers the address the staff member writes from is covers_self; a live
-- ban on the very same range is a duplicate, answered with its id.
CREATE FUNCTION api.admin_address_ban_place_v1(p_ban_id uuid,
    p_range cidr, p_scope text, p_reason text, p_expires_at timestamptz,
    p_actor_user_id uuid, p_actor_address inet, p_now timestamptz,
    p_audit jsonb)
RETURNS TABLE(status text, ban_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    held_range cidr;
    held_author uuid;
    live_ban uuid;
BEGIN
    IF p_ban_id IS NULL OR p_range IS NULL OR p_actor_user_id IS NULL
        OR p_scope IS NULL
        OR p_scope NOT IN ('registration', 'sign_in', 'writes')
        OR p_reason IS NULL OR length(p_reason) NOT BETWEEN 1 AND 500
        OR p_now IS NULL OR p_expires_at IS NULL OR p_expires_at <= p_now
        OR p_expires_at > p_now + interval '366 days' OR p_audit IS NULL
    THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    IF masklen(p_range)
        < (CASE family(p_range) WHEN 4 THEN 16 ELSE 32 END)
    THEN
        RETURN QUERY SELECT 'too_broad'::text, NULL::uuid;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(
        hashtextextended('address_ban:' || p_range::text, 0));
    SELECT b.address_range, b.created_by_user_id
        INTO held_range, held_author
        FROM public.address_bans b WHERE b.ban_id = p_ban_id;
    IF FOUND THEN
        IF held_range = p_range AND held_author = p_actor_user_id THEN
            RETURN QUERY SELECT 'replayed'::text, p_ban_id;
        ELSE
            RETURN QUERY SELECT 'conflict'::text, NULL::uuid;
        END IF;
        RETURN;
    END IF;
    IF p_scope IN ('sign_in', 'writes') AND p_actor_address IS NOT NULL
        AND p_range >>= p_actor_address
    THEN
        RETURN QUERY SELECT 'covers_self'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT b.ban_id INTO live_ban FROM public.address_bans b
        WHERE b.address_range = p_range AND b.lifted_at IS NULL
            AND b.expires_at > p_now
        LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT 'duplicate'::text, live_ban;
        RETURN;
    END IF;
    DELETE FROM public.address_bans b
        WHERE coalesce(b.lifted_at, b.expires_at) < p_now - interval '90 days';
    INSERT INTO public.address_bans (ban_id, address_range, scope, reason,
        created_at, created_by_user_id, expires_at)
        VALUES (p_ban_id, p_range, p_scope, p_reason, p_now,
            p_actor_user_id, p_expires_at);
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_ban_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_place_v1(uuid, cidr, text,
    text, timestamptz, uuid, inet, timestamptz, jsonb) FROM PUBLIC;

-- Changes a live ban's scope, reason and, when one is given, its expiry.
-- An ended ban (lifted or expired) is not edited; the same values again
-- change nothing and audit nothing.
CREATE FUNCTION api.admin_address_ban_edit_v1(p_ban_id uuid, p_scope text,
    p_reason text, p_expires_at timestamptz, p_actor_user_id uuid,
    p_actor_address inet, p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, ban_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_ban_id IS NULL OR p_actor_user_id IS NULL OR p_scope IS NULL
        OR p_scope NOT IN ('registration', 'sign_in', 'writes')
        OR p_reason IS NULL OR length(p_reason) NOT BETWEEN 1 AND 500
        OR p_now IS NULL OR p_audit IS NULL
        OR (p_expires_at IS NOT NULL AND (p_expires_at <= p_now
            OR p_expires_at > p_now + interval '366 days'))
    THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT b.address_range, b.scope, b.reason, b.expires_at, b.lifted_at
        INTO held
        FROM public.address_bans b WHERE b.ban_id = p_ban_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    IF held.lifted_at IS NOT NULL OR held.expires_at <= p_now THEN
        RETURN QUERY SELECT 'ended'::text, p_ban_id;
        RETURN;
    END IF;
    IF p_scope IN ('sign_in', 'writes') AND p_actor_address IS NOT NULL
        AND held.address_range >>= p_actor_address
    THEN
        RETURN QUERY SELECT 'covers_self'::text, p_ban_id;
        RETURN;
    END IF;
    IF held.scope = p_scope AND held.reason = p_reason
        AND (p_expires_at IS NULL OR p_expires_at = held.expires_at)
    THEN
        RETURN QUERY SELECT 'unchanged'::text, p_ban_id;
        RETURN;
    END IF;
    UPDATE public.address_bans b
        SET scope = p_scope, reason = p_reason,
            expires_at = coalesce(p_expires_at, b.expires_at),
            updated_at = p_now, updated_by_user_id = p_actor_user_id
        WHERE b.ban_id = p_ban_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_ban_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_edit_v1(uuid, text, text,
    timestamptz, uuid, inet, timestamptz, jsonb) FROM PUBLIC;

-- Lifts a live ban now. A lifted or expired ban answers ended.
CREATE FUNCTION api.admin_address_ban_lift_v1(p_ban_id uuid,
    p_actor_user_id uuid, p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, ban_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_ban_id IS NULL OR p_actor_user_id IS NULL OR p_now IS NULL
        OR p_audit IS NULL
    THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT b.expires_at, b.lifted_at INTO held
        FROM public.address_bans b WHERE b.ban_id = p_ban_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    IF held.lifted_at IS NOT NULL OR held.expires_at <= p_now THEN
        RETURN QUERY SELECT 'ended'::text, p_ban_id;
        RETURN;
    END IF;
    UPDATE public.address_bans b
        SET lifted_at = p_now, lifted_by_user_id = p_actor_user_id
        WHERE b.ban_id = p_ban_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_ban_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_lift_v1(uuid, uuid,
    timestamptz, jsonb) FROM PUBLIC;

-- The bans for the console: the live ones first, newest first, then the
-- ended ones, the most recently ended first; with who placed, edited and
-- lifted each, its state, and how many are live in all.
CREATE FUNCTION api.admin_address_bans_v1(p_now timestamptz,
    p_row_limit integer)
RETURNS TABLE(ban_id uuid, address_range text, scope text, reason text,
    created_at timestamptz, created_by_username text,
    expires_at timestamptz, updated_at timestamptz,
    updated_by_username text, lifted_at timestamptz,
    lifted_by_username text, state text, live_total bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.ban_id, s.address_range::text, s.scope, s.reason, s.created_at,
    c.username, s.expires_at, s.updated_at, e.username, s.lifted_at,
    l.username,
    CASE WHEN s.lifted_at IS NOT NULL THEN 'lifted'
        WHEN NOT s.live THEN 'expired' ELSE 'active' END,
    count(*) FILTER (WHERE s.live) OVER ()
FROM (
    SELECT b.*, (b.lifted_at IS NULL AND b.expires_at > p_now) AS live
    FROM public.address_bans b
) s
LEFT JOIN public.users c ON c.id = s.created_by_user_id
LEFT JOIN public.users e ON e.id = s.updated_by_user_id
LEFT JOIN public.users l ON l.id = s.lifted_by_user_id
ORDER BY s.live DESC,
    CASE WHEN s.live THEN s.created_at
        ELSE coalesce(s.lifted_at, s.expires_at) END DESC,
    s.ban_id DESC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_bans_v1(timestamptz, integer)
    FROM PUBLIC;

-- The live ban that covers an address, the strongest scope first (writes,
-- then sign_in, then registration), then the one that lasts longest; no
-- row when none does. One GiST lookup on idx_address_bans_live_range.
CREATE FUNCTION api.admin_address_ban_covering_v1(p_address inet,
    p_now timestamptz)
RETURNS TABLE(ban_id uuid, address_range text, scope text,
    expires_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.ban_id, b.address_range::text, b.scope, b.expires_at
FROM public.address_bans b
WHERE b.lifted_at IS NULL AND b.address_range >>= p_address
    AND b.expires_at > p_now
ORDER BY CASE b.scope WHEN 'writes' THEN 3 WHEN 'sign_in' THEN 2 ELSE 1 END
    DESC, b.expires_at DESC, b.ban_id
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_covering_v1(inet,
    timestamptz) FROM PUBLIC;

-- An erased staff member's name leaves the bans they placed, edited or
-- lifted; the bans stay, since they are about an address, not about them.
CREATE FUNCTION api.privacy_revoke_user_v21(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'AddressBan' THEN
        UPDATE public.address_bans b
            SET created_by_user_id = nullif(b.created_by_user_id, p_user_id),
                updated_by_user_id = nullif(b.updated_by_user_id, p_user_id),
                lifted_by_user_id = nullif(b.lifted_by_user_id, p_user_id)
            WHERE p_user_id IN (b.created_by_user_id, b.updated_by_user_id,
                b.lifted_by_user_id);
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v19(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v21(text, uuid, text)
    FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.admin_address_ban_place_v2(
p_ban_id uuid, p_range cidr, p_scope text, p_reason text,
p_expires_at timestamptz, p_actor_user_id uuid, p_actor_address inet,
p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, ban_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_place_v1(p_ban_id, p_range, p_scope,
    p_reason, p_expires_at, p_actor_user_id, p_actor_address, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_place_v2(uuid, cidr, text,
    text, timestamptz, uuid, inet, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_address_ban_edit_v2(
p_ban_id uuid, p_scope text, p_reason text, p_expires_at timestamptz,
p_actor_user_id uuid, p_actor_address inet, p_now timestamptz,
p_audit jsonb
)
RETURNS TABLE(status text, ban_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_edit_v1(p_ban_id, p_scope, p_reason,
    p_expires_at, p_actor_user_id, p_actor_address, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_edit_v2(uuid, text, text,
    timestamptz, uuid, inet, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_address_ban_lift_v2(
p_ban_id uuid, p_actor_user_id uuid, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, ban_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_lift_v1(p_ban_id, p_actor_user_id,
    p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_lift_v2(uuid, uuid,
    timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_address_bans_v2(
p_now timestamptz, p_row_limit integer
)
RETURNS TABLE(ban_id uuid, address_range text, scope text, reason text,
    created_at timestamptz, created_by_username text,
    expires_at timestamptz, updated_at timestamptz,
    updated_by_username text, lifted_at timestamptz,
    lifted_by_username text, state text, live_total bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_bans_v1(p_now, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_bans_v2(timestamptz, integer)
    FROM PUBLIC;

CREATE FUNCTION api.admin_address_ban_covering_v2(
p_address inet, p_now timestamptz
)
RETURNS TABLE(ban_id uuid, address_range text, scope text,
    expires_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_address_ban_covering_v1(p_address, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_covering_v2(inet,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v22(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v21(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v22(text, uuid, text)
    FROM PUBLIC;

COMMIT;
