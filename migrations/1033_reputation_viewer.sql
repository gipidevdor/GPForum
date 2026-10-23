-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- Resolve trust alongside the existing request viewer. Keep v6 unchanged for
-- workers from the previous release: its prepared result type cannot change.
CREATE FUNCTION api.forum_resolve_viewer_v7(p_user_id uuid)
RETURNS TABLE (
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer
)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.status, v.suspended, v.grants, v.moderates, v.listed,
    CASE WHEN v.status = 'active' AND NOT v.suspended AND u.deleted_at IS NULL
         THEN u.trust_level ELSE 0 END
FROM api.forum_resolve_viewer_v6(p_user_id) v
JOIN public.users u ON u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v7(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v8(p_user_id uuid)
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
SELECT * FROM api.forum_resolve_viewer_v7(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v8(uuid) FROM PUBLIC;
