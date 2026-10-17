-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0134, amendment of 2026-10-17: the author's list of held posts reads
-- the place each one went as the author reads it now. A thread or
-- category the author can no longer read (moved somewhere private,
-- hidden, deleted) names neither its title nor its id, so the list never
-- shows what became of a place they lost; the author's own words stay. An
-- approved thread links to where it was published: the decision records
-- only the post, so its thread is the post's. New versions, as ADR 0126
-- section 2 asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.moderation_review_mine_v3(p_user_id uuid,
    p_row_limit integer, p_member boolean, p_global_read boolean,
    p_category_ids uuid[], p_space_ids uuid[])
RETURNS TABLE(review_id uuid, kind text, category_id uuid,
    category_title text, thread_id uuid, thread_title text, title text,
    body_rendered_safe text, status text, decision_reason text,
    post_id uuid, created_at timestamptz, decided_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.kind,
    CASE WHEN place.category THEN c.category_id END,
    CASE WHEN place.category THEN c.title END,
    CASE WHEN place.thread THEN t.thread_id END,
    CASE WHEN place.thread THEN t.title END,
    h.title, h.body_rendered_safe, h.status, h.decision_reason,
    CASE WHEN place.post THEN h.post_id END,
    h.created_at, h.decided_at
FROM public.held_posts h
LEFT JOIN public.posts p ON p.post_id = h.post_id
LEFT JOIN public.threads t ON t.thread_id = coalesce(h.thread_id, p.thread_id)
LEFT JOIN public.categories c
    ON c.category_id = coalesce(t.category_id, h.category_id)
LEFT JOIN public.spaces sp ON sp.space_id = c.space_id
CROSS JOIN LATERAL (
    SELECT c.category_id IS NOT NULL AND c.deleted_at IS NULL
        AND sp.deleted_at IS NULL
        AND (p_global_read OR sp.visibility = 'public'
            OR (p_member AND sp.visibility = 'members')
            OR (sp.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids))))
        AND (p_global_read OR c.visibility = 'public'
            OR (p_member AND c.visibility = 'members')
            OR (c.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)))) AS category
) area
CROSS JOIN LATERAL (
    SELECT area.category AND t.thread_id IS NOT NULL
        AND t.deleted_at IS NULL
        AND t.moderation_state IN ('visible', 'locked')
        AND (p_global_read OR t.visibility = 'public'
            OR (p_member AND t.visibility = 'members')
            OR (t.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)
                    OR (p_member AND t.author_user_id = p_user_id))))
        AS thread
) way
CROSS JOIN LATERAL (
    SELECT area.category AS category, way.thread AS thread,
        way.thread AND p.post_id IS NOT NULL AND p.deleted_at IS NULL
        AND p.moderation_state = 'visible'
        AND (p_global_read OR p.visibility = 'public'
            OR (p_member AND p.visibility = 'members')
            OR (p.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)
                    OR (p_member AND p.author_user_id = p_user_id))))
        AS post
) place
WHERE h.author_user_id = p_user_id
    AND (h.status = 'pending' OR h.decided_at > now() - interval '30 days')
ORDER BY h.created_at DESC, h.review_id DESC
LIMIT least(greatest(coalesce(p_row_limit, 50), 1), 200);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v3(uuid, integer,
    boolean, boolean, uuid[], uuid[]) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.moderation_review_mine_v4(
p_user_id uuid, p_row_limit integer, p_member boolean,
p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[]
)
RETURNS TABLE(review_id uuid, kind text, category_id uuid,
    category_title text, thread_id uuid, thread_title text, title text,
    body_rendered_safe text, status text, decision_reason text,
    post_id uuid, created_at timestamptz, decided_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_mine_v3(p_user_id, p_row_limit,
    p_member, p_global_read, p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v4(uuid, integer,
    boolean, boolean, uuid[], uuid[]) FROM PUBLIC;

COMMIT;
