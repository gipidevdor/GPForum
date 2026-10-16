-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126, phase 0: the thread page's two statements as functions. Each
-- body is the statement DBIx::Class renders today, taken from
-- ThreadDetailReader::thread_row_resultset and PostReader::
-- thread_posts_resultset (DBIC_TRACE, against the seed) and changed only
-- where the function boundary asks: the request's values are parameters,
-- and the constants each shape binds (a visibility level, the moderation
-- state, the head's LIMIT 1) are written in, so a generic plan can match
-- idx_posts_visible_thread_position's predicate as a custom plan does.
--
-- api.forum_thread_page_head_v1 is the thread's row with its author, its
-- category and its space: one primary key lookup, LANGUAGE sql. Whether the
-- viewer may read it stays ThreadDetailReader's to decide, on the row, as it
-- did.
--
-- api.forum_thread_page_posts_v1 is a page of the thread's posts. The
-- statement has twelve shapes, as PreparedQuery kept twelve: the viewer's
-- standing (global read, member, anonymous), whether they list their own
-- deleted posts (a viewer id), and whether a cursor bounds the page. Each
-- shape keeps its own statement behind its branch, never folded into one
-- with `p IS NULL OR`, whose generic plan cannot use the keyset bound (ADR
-- 0126, section 4); the keyset is written as Infrastructure::Keyset writes
-- it, the bound on the position alone and the lexicographic OR. A member
-- with a viewer id also reads their own private posts; one without (no
-- account behind the viewer) reads public and members' posts.
--
-- Both pin a generic plan: a lookup by key and a keyset page on an index
-- plan the same for every value, and the planning PostgreSQL paid on every
-- call goes (0.165 ms of a 0.28 ms post statement, measured in the
-- inventory).

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_thread_page_head_v1(p_thread_id uuid)
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
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    category_title text,
    category_visibility text,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug,
    me.pinned, me.visibility, me.moderation_state, me.locked_at,
    me.last_activity_at, me.deleted_at, author.username, author.display_name,
    category.title, category.visibility, category.space_id, space.visibility
FROM public.threads me
JOIN public.users author ON author.id = me.author_user_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE me.thread_id = p_thread_id
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_head_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_v1(
    p_thread_id uuid,
    p_standing text,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
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
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_standing = 'global' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NULL THEN
        -- posts:global:any:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public', 'members', 'private')
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'global' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:global:any:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members', 'private')
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'global' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NULL THEN
        -- posts:global:own:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public', 'members', 'private')
            AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'global' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:global:own:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members', 'private')
                AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NULL THEN
        -- posts:member:any:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public', 'members')
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:member:any:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members')
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NULL THEN
        -- posts:member:own:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members')
                OR ( me.author_user_id = p_viewer_user_id
                    AND me.visibility = 'private' ) )
            AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:member:own:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( ( me.visibility IN ('public', 'members')
                OR ( me.author_user_id = p_viewer_user_id
                    AND me.visibility = 'private' ) )
                AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NULL THEN
        -- posts:anonymous:any:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public')
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:anonymous:any:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public')
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NULL THEN
        -- posts:anonymous:own:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public')
            AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:anonymous:own:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public')
                AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSE
        RAISE EXCEPTION USING ERRCODE = 'invalid_parameter_value',
            MESSAGE = 'standing must be global, member or anonymous, and a'
                || ' cursor needs its position';
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION
    api.forum_thread_page_posts_v1(uuid, text, uuid, bigint, uuid, integer)
    FROM PUBLIC;

COMMIT;
