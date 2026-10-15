-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A category in the index said its name and its description and nothing of
-- what goes on in it. The list a reader sees now carries, for each category,
-- how many discussions it holds that the reader may read and when the last
-- of them moved: one aggregate per category over the threads index that the
-- category page reads, and the same readability rule the lists apply to a
-- thread's own visibility (ADR 0102). A new version, as ADR 0126 section 2
-- asks: the shipped one stays.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_list_categories_v3(
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    thread_count bigint,
    last_activity_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT me.category_id, me.space_id, me.slug, me.title, me.description,
    me.visibility, me.position, me.version, me.permission_version,
    me.created_at, me.updated_at, me.deleted_at,
    activity.thread_count, activity.last_activity_at
FROM public.categories me
JOIN public.spaces space ON space.space_id = me.space_id
CROSS JOIN LATERAL (
    SELECT count(*) AS thread_count,
        max(thread.last_activity_at) AS last_activity_at
    FROM public.threads thread
    WHERE thread.category_id = me.category_id
        AND thread.deleted_at IS NULL
        AND thread.moderation_state IN ('visible', 'locked')
        AND (p_global_read
            OR thread.visibility = 'public'
            OR (p_member AND thread.visibility = 'members'))
) AS activity
WHERE me.deleted_at IS NULL
    AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR me.space_id = ANY(p_space_ids)))))
    AND (space.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR space.visibility = 'public'
            OR (p_member AND space.visibility = 'members')
            OR (space.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR me.space_id = ANY(p_space_ids)))))
ORDER BY me.position ASC, me.title ASC, me.category_id ASC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v3(boolean, boolean,
    uuid[], uuid[], integer) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.forum_list_categories_v4(
p_member boolean, p_global_read boolean, p_category_ids uuid[],
p_space_ids uuid[], p_row_limit integer
)
RETURNS TABLE (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    thread_count bigint,
    last_activity_at timestamptz
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT * FROM api.forum_list_categories_v3(p_member, p_global_read,
    p_category_ids, p_space_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v4(boolean, boolean,
    uuid[], uuid[], integer) FROM PUBLIC;

COMMIT;
