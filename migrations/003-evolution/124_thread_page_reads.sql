-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- What a thread page reads once it has its posts, in one call: the posts'
-- likes (109), the posts they answer (114), the thread's tags (117), the
-- posts' attachment links (067), and for a member their bookmark and their
-- subscription (062) and how far they have read (063). Each was a call of
-- its own; together they were seven of the eleven statements of a
-- signed-in thread page.
--
-- Each part is the query of the function the page called -- the version
-- named beside it -- with the values the page gave that function, so it
-- answers what that call answered. The queries are written here rather
-- than called: a call of each function cost PostgreSQL about as much again
-- as its query (11 to 26 us each, 100 for the seven, where the seven
-- queries in one statement take 40), and those functions never change
-- (ADR 0126): a page whose store calls another version is not answered
-- from this one (GPForum::Service::Forum::ThreadPageReads).
--
-- The rows come back as one table, each tagged with its part and its place
-- in that part's answer; a column is a part's own column, under its own
-- name and type, and NULL in the other parts' rows. A column two parts
-- share -- post_id, thread_id, user_id, target_type, target_id, created_at
-- -- has the same type in both.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_thread_page_reads_v1(
    p_thread_id uuid,
    p_post_ids uuid[],
    p_viewer_user_id uuid,
    p_engagement_target_type text,
    p_link_target_type text,
    p_link_post_ids uuid[],
    p_link_row_limit integer
)
RETURNS TABLE (
    part text,
    ordinal bigint,
    post_id uuid,
    like_count bigint,
    liked boolean,
    reply_to_post_id uuid,
    reply_to_position bigint,
    reply_to_author_username text,
    thread_id uuid,
    slug text,
    name text,
    tag_position smallint,
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    bookmark_id uuid,
    user_id uuid,
    note text,
    deleted_at timestamptz,
    subscription_id uuid,
    preference text,
    muted_at timestamptz,
    revoked_at timestamptz,
    last_read_position bigint,
    last_read_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
-- api.community_post_likes_v1
SELECT 'like'::text, row_number() OVER (), l.post_id, l.like_count, l.liked,
    NULL::uuid, NULL::bigint, NULL::text,
    NULL::uuid, NULL::text, NULL::text, NULL::smallint,
    NULL::uuid, NULL::uuid, NULL::text, NULL::uuid, NULL::timestamptz,
    NULL::uuid, NULL::uuid, NULL::text, NULL::timestamptz,
    NULL::uuid, NULL::text, NULL::timestamptz, NULL::timestamptz,
    NULL::bigint, NULL::timestamptz
FROM (
    SELECT pl.post_id, count(*)::bigint AS like_count,
        coalesce(bool_or(pl.user_id = p_viewer_user_id), false) AS liked
    FROM public.post_likes pl
    WHERE pl.post_id = ANY(p_post_ids)
    GROUP BY pl.post_id
) l
UNION ALL
-- api.forum_reply_targets_v1
SELECT 'reply_target', row_number() OVER (), r.post_id, NULL, NULL,
    r.reply_to_post_id, target.position, author.username,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL
FROM public.post_replies r
JOIN public.posts target ON target.post_id = r.reply_to_post_id
LEFT JOIN public.users author ON author.id = target.author_user_id
WHERE r.post_id = ANY(p_post_ids)
UNION ALL
-- api.forum_thread_tags_v1, for the page's thread
SELECT 'tag', row_number() OVER (ORDER BY tt.thread_id, tt.position), NULL,
    NULL, NULL,
    NULL, NULL, NULL,
    tt.thread_id, t.slug, t.name, tt.position,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL
FROM public.thread_tags tt
JOIN public.tags t ON t.tag_id = tt.tag_id
WHERE tt.thread_id = p_thread_id
UNION ALL
-- api.attachment_links_v1, by the posts' ids
SELECT 'attachment_link', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    a.attachment_link_id, a.attachment_id, a.target_type, a.target_id,
    a.created_at,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL
FROM (
    SELECT al.* FROM public.attachment_links al
    WHERE al.target_type = p_link_target_type
        AND al.target_id = ANY(p_link_post_ids)
    LIMIT p_link_row_limit
) a
UNION ALL
-- api.community_find_bookmark_v1
SELECT 'bookmark', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, b.target_type, b.target_id, b.created_at,
    b.bookmark_id, b.user_id, b.note, b.deleted_at,
    NULL, NULL, NULL, NULL,
    NULL, NULL
FROM public.bookmarks b
WHERE b.user_id = p_viewer_user_id
    AND b.target_type = p_engagement_target_type
    AND b.target_id = p_thread_id
UNION ALL
-- api.notification_find_subscription_v1
SELECT 'subscription', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, s.target_type, s.target_id, s.created_at,
    NULL, s.user_id, NULL, NULL,
    s.subscription_id, s.preference, s.muted_at, s.revoked_at,
    NULL, NULL
FROM public.subscriptions s
WHERE s.user_id = p_viewer_user_id
    AND s.target_type = p_engagement_target_type
    AND s.target_id = p_thread_id
UNION ALL
-- api.forum_read_state_v1
SELECT 'read_state', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    rs.thread_id, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, rs.user_id, NULL, NULL,
    NULL, NULL, NULL, NULL,
    rs.last_read_position, rs.last_read_at
FROM public.thread_read_state rs
WHERE rs.user_id = p_viewer_user_id
    AND rs.thread_id = p_thread_id
ORDER BY 1, 2
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v1(uuid, uuid[], uuid,
    text, text, uuid[], integer) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.forum_thread_page_reads_v2(
p_thread_id uuid, p_post_ids uuid[], p_viewer_user_id uuid,
p_engagement_target_type text, p_link_target_type text,
p_link_post_ids uuid[], p_link_row_limit integer
)
RETURNS TABLE (
    part text,
    ordinal bigint,
    post_id uuid,
    like_count bigint,
    liked boolean,
    reply_to_post_id uuid,
    reply_to_position bigint,
    reply_to_author_username text,
    thread_id uuid,
    slug text,
    name text,
    tag_position smallint,
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    bookmark_id uuid,
    user_id uuid,
    note text,
    deleted_at timestamptz,
    subscription_id uuid,
    preference text,
    muted_at timestamptz,
    revoked_at timestamptz,
    last_read_position bigint,
    last_read_at timestamptz
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_reads_v1(p_thread_id, p_post_ids,
    p_viewer_user_id, p_engagement_target_type, p_link_target_type,
    p_link_post_ids, p_link_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v2(uuid, uuid[], uuid,
    text, text, uuid[], integer) FROM PUBLIC;

COMMIT;
