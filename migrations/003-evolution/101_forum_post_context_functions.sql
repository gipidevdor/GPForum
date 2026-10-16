-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Fetch a post and the thread head its author's preflight reads in one
-- invocation. The reader still applies the same viewer visibility rules;
-- writes still recheck their domain rules under the original row locks.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_post_context_v1(p_post_id uuid)
RETURNS TABLE(post json, thread json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (to_jsonb(p) || jsonb_build_object(
        'created_at', p.created_at::text, 'updated_at', p.updated_at::text,
        'hidden_at', p.hidden_at::text, 'locked_at', p.locked_at::text,
        'deleted_at', p.deleted_at::text))::json,
    CASE WHEN head.thread_id IS NOT NULL THEN
        (to_jsonb(head) || jsonb_build_object(
            'pinned', CASE WHEN head.pinned THEN 1 ELSE 0 END,
            'locked_at', head.locked_at::text,
            'last_activity_at', head.last_activity_at::text,
            'deleted_at', head.deleted_at::text))::json
    END
FROM public.posts p
LEFT JOIN LATERAL api.forum_thread_page_head_v1(p.thread_id) head ON true
WHERE p.post_id = p_post_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_context_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_post_context_v2(p_post_id uuid)
RETURNS TABLE(post json, thread json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_post_context_v1(p_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_context_v2(uuid) FROM PUBLIC;

COMMIT;
