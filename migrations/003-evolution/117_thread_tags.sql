-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A thread carries up to five tags (ADR 0135): short words its author
-- chooses, shared across categories, so a subject is found wherever it is
-- discussed. A tag is one row by its slug (the lower-case form), with the
-- name first given; a thread's tags are rows of their own, written after
-- the thread command, so the command is as it was. The pages read the
-- tags of their threads in one call; a tag page lists the threads a reader
-- may read under one tag, in any category or one; the tag index counts
-- them.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.tags (
    tag_id uuid NOT NULL DEFAULT gen_random_uuid(),
    slug text NOT NULL,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tags_pkey PRIMARY KEY (tag_id),
    CONSTRAINT tags_slug_key UNIQUE (slug),
    CONSTRAINT tags_slug_check CHECK (
        slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(slug) <= 30),
    CONSTRAINT tags_name_check CHECK (length(name) BETWEEN 1 AND 30)
);

CREATE TABLE public.thread_tags (
    thread_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    position smallint NOT NULL,
    CONSTRAINT thread_tags_pkey PRIMARY KEY (thread_id, tag_id),
    CONSTRAINT thread_tags_thread_id_fkey FOREIGN KEY (thread_id)
        REFERENCES public.threads (thread_id),
    CONSTRAINT thread_tags_tag_id_fkey FOREIGN KEY (tag_id)
        REFERENCES public.tags (tag_id),
    CONSTRAINT thread_tags_position_check CHECK (position BETWEEN 1 AND 5)
);
CREATE INDEX idx_thread_tags_tag ON public.thread_tags (tag_id);

-- Replaces a thread's tags with the slugs given, in their order, each with
-- the name given when the tag is new. Slugs and names are the caller's,
-- already normalised; a thread that does not exist takes none. Answers the
-- thread's tags as they are now.
CREATE FUNCTION api.forum_set_thread_tags_v1(p_thread_id uuid, p_slugs text[],
    p_names text[])
RETURNS TABLE (slug text, name text, tag_position smallint)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id)
    THEN
        RETURN;
    END IF;
    INSERT INTO public.tags (slug, name)
    SELECT given.slug, given.name
    FROM unnest(p_slugs, p_names) AS given(slug, name)
    ON CONFLICT ON CONSTRAINT tags_slug_key DO NOTHING;
    DELETE FROM public.thread_tags tt
    WHERE tt.thread_id = p_thread_id
        AND tt.tag_id NOT IN (
            SELECT t.tag_id FROM public.tags t WHERE t.slug = ANY(p_slugs));
    INSERT INTO public.thread_tags (thread_id, tag_id, position)
    SELECT p_thread_id, t.tag_id, given.ordinality
    FROM unnest(p_slugs) WITH ORDINALITY AS given(slug, ordinality)
    JOIN public.tags t ON t.slug = given.slug
    ON CONFLICT ON CONSTRAINT thread_tags_pkey
        DO UPDATE SET position = EXCLUDED.position;
    RETURN QUERY
    SELECT t.slug, t.name, tt.position
    FROM public.thread_tags tt
    JOIN public.tags t ON t.tag_id = tt.tag_id
    WHERE tt.thread_id = p_thread_id
    ORDER BY tt.position;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_set_thread_tags_v1(uuid, text[], text[])
    FROM PUBLIC;

-- The tags of the threads of a page, in each thread's order.
CREATE FUNCTION api.forum_thread_tags_v1(p_thread_ids uuid[])
RETURNS TABLE (thread_id uuid, slug text, name text, tag_position smallint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT tt.thread_id, t.slug, t.name, tt.position
FROM public.thread_tags tt
JOIN public.tags t ON t.tag_id = tt.tag_id
WHERE tt.thread_id = ANY(p_thread_ids)
ORDER BY tt.thread_id, tt.position
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_tags_v1(uuid[]) FROM PUBLIC;

-- The threads under one tag the reader may read (ADR 0102: the thread's
-- own visibility, then its category's and its space's), in every category
-- or in one, newest activity first.
CREATE FUNCTION api.forum_list_tagged_threads_v1(
    p_tag_slug text,
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
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
    category_title text,
    reply_count bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug,
    me.pinned, me.visibility, me.moderation_state, me.locked_at,
    me.last_activity_at, me.created_at, me.deleted_at, author.username,
    author.display_name, category.title,
    COALESCE((SELECT counter.reply_count
        FROM public.thread_counters counter
        WHERE counter.thread_id = me.thread_id), 0)
FROM public.thread_tags tt
JOIN public.tags tag ON tag.tag_id = tt.tag_id
JOIN public.threads me ON me.thread_id = tt.thread_id
JOIN public.users author ON author.id = me.author_user_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE tag.slug = p_tag_slug
    AND (p_category_id IS NULL OR me.category_id = p_category_id)
    AND me.deleted_at IS NULL
    AND me.moderation_state IN ('visible', 'locked')
    AND (p_global_read OR me.visibility = 'public'
        OR (p_member AND me.visibility = 'members')
        OR (me.visibility = 'private' AND p_member
            AND me.author_user_id = p_scope_user_id))
    AND (p_global_read OR category.visibility = 'public'
        OR (p_member AND category.visibility = 'members')
        OR (category.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
    AND (p_global_read OR space.visibility = 'public'
        OR (p_member AND space.visibility = 'members')
        OR (space.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
ORDER BY me.last_activity_at DESC, me.thread_id DESC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tagged_threads_v1(text, uuid, boolean,
    boolean, uuid, uuid[], uuid[], integer) FROM PUBLIC;

-- Every tag with how many threads the reader may read under it, the most
-- used first; a tag with none the reader may read is absent.
CREATE FUNCTION api.forum_list_tags_v1(
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (slug text, name text, thread_count bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT tag.slug, tag.name, count(*) AS thread_count
FROM public.thread_tags tt
JOIN public.tags tag ON tag.tag_id = tt.tag_id
JOIN public.threads me ON me.thread_id = tt.thread_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE me.deleted_at IS NULL
    AND me.moderation_state IN ('visible', 'locked')
    AND (p_global_read OR me.visibility = 'public'
        OR (p_member AND me.visibility = 'members')
        OR (me.visibility = 'private' AND p_member
            AND me.author_user_id = p_scope_user_id))
    AND (p_global_read OR category.visibility = 'public'
        OR (p_member AND category.visibility = 'members')
        OR (category.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
    AND (p_global_read OR space.visibility = 'public'
        OR (p_member AND space.visibility = 'members')
        OR (space.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
GROUP BY tag.tag_id, tag.slug, tag.name
ORDER BY count(*) DESC, tag.name, tag.slug
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tags_v1(boolean, boolean, uuid, uuid[],
    uuid[], integer) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.forum_set_thread_tags_v2(
p_thread_id uuid, p_slugs text[], p_names text[]
)
RETURNS TABLE (slug text, name text, tag_position smallint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_set_thread_tags_v1(p_thread_id, p_slugs, p_names);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_set_thread_tags_v2(uuid, text[], text[])
    FROM PUBLIC;

CREATE FUNCTION api.forum_thread_tags_v2(
p_thread_ids uuid[]
)
RETURNS TABLE (thread_id uuid, slug text, name text, tag_position smallint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_tags_v1(p_thread_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_tags_v2(uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_list_tagged_threads_v2(
p_tag_slug text, p_category_id uuid, p_member boolean, p_global_read boolean,
p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[],
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
    category_title text,
    reply_count bigint
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_tagged_threads_v1(p_tag_slug, p_category_id,
    p_member, p_global_read, p_scope_user_id, p_category_ids, p_space_ids,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tagged_threads_v2(text, uuid, boolean,
    boolean, uuid, uuid[], uuid[], integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_tags_v2(
p_member boolean, p_global_read boolean, p_scope_user_id uuid,
p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer
)
RETURNS TABLE (slug text, name text, thread_count bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_list_tags_v1(p_member, p_global_read, p_scope_user_id,
    p_category_ids, p_space_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tags_v2(boolean, boolean, uuid, uuid[],
    uuid[], integer) FROM PUBLIC;

COMMIT;
