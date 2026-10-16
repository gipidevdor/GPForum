-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126: forum indexes and single-row reads. These are the projections,
-- joins, visibility filters and bounded keysets of the readers, with input
-- values bound at the function boundary. Each cursor keeps its own statement;
-- a category's signed-in page retains the two independently limited index
-- scans (live rows and the reader's deleted rows) before their outer merge.
-- Grant-sensitive lists use custom plans so each viewer's constant standing
-- and grants simplify before planning. Primary-key lookups keep generic plans.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_find_category_v1(
    p_category_id uuid
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
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.category_id, me.space_id, me.slug, me.title, me.description, me.visibility, me.position, me.version, me.permission_version, me.created_at, me.updated_at, me.deleted_at, space.visibility
FROM public.categories me
JOIN public.spaces space ON space.space_id = me.space_id
WHERE me.category_id = p_category_id
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_category_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_list_categories_v1(
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
    deleted_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT me.category_id, me.space_id, me.slug, me.title, me.description, me.visibility, me.position, me.version, me.permission_version, me.created_at, me.updated_at, me.deleted_at
FROM public.categories me
JOIN public.spaces space ON space.space_id = me.space_id
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
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v1(boolean, boolean, uuid[], uuid[], integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_category_threads_v1(
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
SET plan_cache_mode = force_custom_plan
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
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v1(uuid, boolean, boolean, uuid, uuid, boolean, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_public_threads_v1(
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
SET plan_cache_mode = force_custom_plan
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
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v1(boolean, boolean, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_find_post_v1(
    p_post_id uuid
)
RETURNS SETOF public.posts
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.* FROM public.posts me WHERE me.post_id = p_post_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_post_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_visible_post_v1(
    p_post_id uuid
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    current_revision_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    version bigint,
    visibility_version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    hidden_at timestamptz,
    locked_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid,
    thread_visibility text,
    thread_author uuid,
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id, me.current_revision_id, me.position, me.visibility, me.moderation_state, me.version, me.visibility_version, me.permission_version, me.created_at, me.updated_at, me.hidden_at, me.locked_at, me.deleted_at, me.deleted_by, thread.visibility,
    thread.author_user_id, thread.category_id, category.visibility,
    category.space_id, space.visibility
FROM public.posts me
JOIN public.threads thread ON thread.thread_id = me.thread_id
JOIN public.categories category ON category.category_id = thread.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE me.post_id = p_post_id
    AND me.deleted_at IS NULL AND me.moderation_state = 'visible'
    AND thread.deleted_at IS NULL
    AND thread.moderation_state IN ('visible', 'locked')
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_visible_post_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_listed_post_v1(
    p_post_id uuid,
    p_thread_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    deleted_at timestamptz,
    body text,
    body_source text,
    author_username text,
    author_display_name text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at, me.deleted_at,
    current_body.body_rendered_safe, current_body.body_source,
    author.username, author.display_name
FROM public.posts me
LEFT JOIN public.post_bodies current_body ON current_body.body_id = me.current_body_id
JOIN public.users author ON author.id = me.author_user_id
WHERE me.post_id = p_post_id AND me.thread_id = p_thread_id
    AND me.moderation_state = 'visible'
    AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
    AND (me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id)
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v1(uuid, uuid, boolean, boolean, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_placement_v1(
    p_source_id uuid
)
RETURNS TABLE (
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_deleted_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT c.category_id, c.visibility, c.space_id, s.visibility,
    t.author_user_id, t.visibility, t.deleted_at, t.moderation_state, c.deleted_at
FROM public.threads t
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
WHERE t.thread_id = p_source_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_placement_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_post_placement_v1(
    p_source_id uuid
)
RETURNS TABLE (
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text,
    thread_author uuid,
    thread_visibility text,
    post_author uuid,
    post_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_deleted_at timestamptz,
    post_deleted_at timestamptz,
    post_state text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT c.category_id, c.visibility, c.space_id, s.visibility,
    t.author_user_id, t.visibility, p.author_user_id, p.visibility,
    t.deleted_at, t.moderation_state, c.deleted_at, p.deleted_at, p.moderation_state
FROM public.posts p
JOIN public.threads t ON t.thread_id = p.thread_id
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
WHERE p.post_id = p_source_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_placement_v1(uuid) FROM PUBLIC;

-- The original prepared path permits different users for visibility scope
-- and ownership of deleted rows. Preserve that case without a client-built
-- resultset: its first and cursor pages keep independent statements.
CREATE FUNCTION api.forum_thread_page_posts_scoped_v1(
    p_thread_id uuid,
    p_standing text,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid, thread_id uuid, author_user_id uuid, current_body_id uuid,
    "position" bigint, visibility text, moderation_state text,
    created_at timestamptz, deleted_at timestamptz, body text,
    body_source text, author_username text, author_display_name text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_after_post_id IS NULL THEN
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id,
            me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id = p_thread_id
            AND me.moderation_state = 'visible'
            AND ((p_standing = 'global' AND me.visibility IN ('public', 'members', 'private'))
                OR (p_standing = 'member' AND
                    (me.visibility IN ('public', 'members')
                        OR (me.visibility = 'private' AND me.author_user_id = p_scope_user_id)))
                OR (p_standing = 'anonymous' AND me.visibility = 'public'))
            AND (me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id)
        ORDER BY me.position ASC, me.post_id ASC LIMIT p_row_limit;
    ELSE
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id,
            me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id = p_thread_id
            AND me.moderation_state = 'visible'
            AND ((p_standing = 'global' AND me.visibility IN ('public', 'members', 'private'))
                OR (p_standing = 'member' AND
                    (me.visibility IN ('public', 'members')
                        OR (me.visibility = 'private' AND me.author_user_id = p_scope_user_id)))
                OR (p_standing = 'anonymous' AND me.visibility = 'public'))
            AND (me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id)
            AND me.position >= p_after_position
            AND (me.position > p_after_position
                OR (me.position = p_after_position AND me.post_id > p_after_post_id))
        ORDER BY me.position ASC, me.post_id ASC LIMIT p_row_limit;
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_scoped_v1(uuid, text, uuid, uuid, bigint, uuid, integer) FROM PUBLIC;

COMMIT;
