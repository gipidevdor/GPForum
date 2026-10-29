-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- The mbox archive of a thread or a category asked for each post's signature
-- in a statement of its own, inside the one repeatable-read transaction the
-- export holds: a hundred statements per page of posts, and the transaction
-- that long. The signatures of a page's posts are one statement now
-- (Service::Discovery::Archive); the one-signature function stays for the
-- permalink's /signature.
CREATE FUNCTION api.forum_protocol_signatures_v1(p_body_ids uuid[])
RETURNS TABLE (body_id uuid, envelope json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.body_id, s.envelope::json FROM public.post_signatures s WHERE s.body_id = ANY(p_body_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signatures_v1(uuid[]) FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.forum_protocol_signatures_v2(p_body_ids uuid[])
RETURNS TABLE (body_id uuid, envelope json)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_signatures_v1(p_body_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signatures_v2(uuid[]) FROM PUBLIC;
