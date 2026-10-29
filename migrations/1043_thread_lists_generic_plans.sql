-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- The two thread lists planned once. Each forced a custom plan, so every
-- home page and every category page planned its list again -- most of the
-- call: on 100,000 threads, per call, the latest list 0.354 ms under the
-- custom plan and 0.078 generic, the category list 0.426 and 0.179. The
-- generic plans read the same indexes (EXPLAIN (GENERIC_PLAN) against the
-- custom plans, 2026-10-29): the predicates of idx_threads_public_activity,
-- idx_threads_category_activity_visible_locked and
-- idx_threads_deleted_category_activity are written in the bodies as
-- literals (live, visible or locked, public), so a plan that does not know
-- the parameters still implies them; only the viewer's standing is a
-- filter on the scan, as it was. The bodies are unchanged. The previous
-- boundaries stay for the previous release's workers (ADR 0126, section 2).
-- forum_list_categories keeps its custom plan: its count's predicate on
-- thread visibility depends on the standing, and the list is cached per
-- standing (CategoryReader).

-- api.forum_list_public_threads_v1, planned once.
CREATE FUNCTION api.forum_list_public_threads_v3(
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        JOIN public.categories category ON category.category_id = me.category_id
        JOIN public.spaces space ON space.space_id = category.space_id
        WHERE me.deleted_at IS NULL
            AND me.moderation_state IN ('visible', 'locked')
            AND me.visibility = 'public'
            AND (category.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR category.visibility = 'public'
            OR (p_member AND category.visibility = 'members')
            OR (category.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
            AND (space.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR space.visibility = 'public'
            OR (p_member AND space.visibility = 'members')
            OR (space.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
        ORDER BY me.last_activity_at DESC, me.thread_id DESC
        LIMIT p_row_limit;
    ELSE
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        JOIN public.categories category ON category.category_id = me.category_id
        JOIN public.spaces space ON space.space_id = category.space_id
        WHERE me.deleted_at IS NULL
            AND me.moderation_state IN ('visible', 'locked')
            AND me.visibility = 'public'
            AND (category.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR category.visibility = 'public'
            OR (p_member AND category.visibility = 'members')
            OR (category.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
            AND (space.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR space.visibility = 'public'
            OR (p_member AND space.visibility = 'members')
            OR (space.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
            AND me.last_activity_at <= p_after_activity
            AND (me.last_activity_at < p_after_activity
                OR (me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
        ORDER BY me.last_activity_at DESC, me.thread_id DESC
        LIMIT p_row_limit;
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v3(boolean, boolean, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.forum_list_public_threads_v4(
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_public_threads_v3(p_member, p_global_read, p_category_ids, p_space_ids, p_after_activity, p_after_thread_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v4(boolean, boolean, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- api.forum_list_category_threads_v1, planned once.
CREATE FUNCTION api.forum_list_category_threads_v3(
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_pinned boolean,
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_viewer_user_id IS NULL AND p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NULL AND p_after_thread_id IS NOT NULL AND p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NULL AND p_after_thread_id IS NOT NULL AND NOT p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND me.last_activity_at <= p_after_activity
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NOT NULL AND p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id IN (
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
UNION ALL
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NOT NULL AND me.author_user_id = p_viewer_user_id
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
        )
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NOT NULL AND p_after_thread_id IS NOT NULL AND p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id IN (
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
UNION ALL
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NOT NULL AND me.author_user_id = p_viewer_user_id
            AND me.pinned <= p_after_pinned
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
        )
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NOT NULL AND p_after_thread_id IS NOT NULL AND NOT p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id IN (
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND me.last_activity_at <= p_after_activity
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
UNION ALL
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NOT NULL AND me.author_user_id = p_viewer_user_id
            AND me.pinned <= p_after_pinned
            AND me.last_activity_at <= p_after_activity
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
        )
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSE
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'incomplete category cursor';
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v3(uuid, boolean, boolean, uuid, uuid, boolean, timestamptz, uuid, integer)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.forum_list_category_threads_v4(
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_pinned boolean,
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_category_threads_v3(p_category_id, p_member, p_global_read, p_scope_user_id, p_viewer_user_id, p_after_pinned, p_after_activity, p_after_thread_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v4(uuid, boolean, boolean, uuid, uuid, boolean, timestamptz, uuid, integer)
    FROM PUBLIC;
