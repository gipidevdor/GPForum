-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0148: a realtime socket ends with the session it was opened in. Each
-- process asks, every half minute and in one call for all its sockets,
-- which of their sessions are still live -- not revoked, and not past
-- their expiry, to the second as api.session_validate_v1 reads it -- and
-- closes the sockets of the others. A read: an expired session is revoked
-- by the next request that presents it, as before, not here.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.session_live_v1(
    p_session_ids uuid[],
    p_now timestamptz
)
RETURNS TABLE (session_id uuid)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.session_id
FROM public.sessions s
WHERE s.session_id = ANY(p_session_ids)
  AND s.revoked_at IS NULL
  AND date_trunc('second', s.expires_at) > p_now;
$$;
REVOKE EXECUTE ON FUNCTION api.session_live_v1(uuid[], timestamptz) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.session_live_v2(
    p_session_ids uuid[],
    p_now timestamptz
)
RETURNS TABLE (session_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.session_live_v1(p_session_ids, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.session_live_v2(uuid[], timestamptz) FROM PUBLIC;

COMMIT;
