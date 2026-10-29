-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- The files a thread page lists under its posts cost four statements each:
-- the page's one statement read the links, then each link looked up its
-- file, the file's links, the post the link names and the post's placement
-- before the listing could decide. Twenty-five posts with a file each were
-- a hundred statements. The page's one statement now reads each link with
-- its file and its post, and the listing decides from that
-- (Service::Attachment::DownloadAccess::listing_payload);
-- api.attachment_post_files_v2 answers the same rows on its own for a page
-- that reads them outside the one statement.

-- The links of some posts, each with its file and the post it names.
CREATE FUNCTION api.attachment_post_files_v1(
    p_target_type text,
    p_post_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT a.attachment_link_id, a.attachment_id, a.target_type, a.target_id,
    a.created_at,
    f.owner_user_id, f.object_key, f.original_filename, f.media_type,
    f.byte_size, f.state, f.scan_status, f.deleted_at,
    p.thread_id, p.author_user_id, p.visibility, p.moderation_state,
    p.hidden_at, p.deleted_at,
    t.author_user_id, t.visibility, t.deleted_at, t.moderation_state,
    c.category_id, c.visibility, c.deleted_at, c.space_id, s.visibility
FROM (
    SELECT al.* FROM public.attachment_links al
    WHERE al.target_type = p_target_type
        AND al.target_id = ANY(p_post_ids)
    ORDER BY al.target_id, al.created_at, al.attachment_link_id
    LIMIT p_row_limit
) a
JOIN public.attachments f ON f.attachment_id = a.attachment_id
JOIN public.posts p ON p.post_id = a.target_id
JOIN public.threads t ON t.thread_id = p.thread_id
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
ORDER BY a.target_id, a.created_at, a.attachment_link_id
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_post_files_v1(text, uuid[], integer)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.attachment_post_files_v2(
    p_target_type text,
    p_post_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_post_files_v1(p_target_type, p_post_ids, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_post_files_v2(text, uuid[], integer)
    FROM PUBLIC;

-- The thread page's reads after its posts, the links' part now carrying each
-- file and its post (the part is named attachment_file, after the call it
-- answers). v3 stays for the previous release's workers.
CREATE FUNCTION api.forum_thread_page_reads_v5(
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
    last_read_at timestamptz,
    reaction text,
    reaction_count bigint,
    reacted boolean,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
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
    NULL::bigint, NULL::timestamptz,
    NULL::text, NULL::bigint, NULL::boolean,
    NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::bigint,
    NULL::text, NULL::text, NULL::timestamptz,
    NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::timestamptz,
    NULL::timestamptz,
    NULL::uuid, NULL::text, NULL::timestamptz, NULL::text,
    NULL::uuid, NULL::text, NULL::timestamptz, NULL::uuid, NULL::text
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
    NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
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
    NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM public.thread_tags tt
JOIN public.tags t ON t.tag_id = tt.tag_id
WHERE tt.thread_id = p_thread_id
UNION ALL
-- api.attachment_post_files_v1, by the posts' ids: each link with its file
-- and its post, so the listing decides without a statement per file
SELECT 'attachment_file', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    a.attachment_link_id, a.attachment_id, a.target_type, a.target_id,
    a.created_at,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL,
    f.owner_user_id, f.object_key, f.original_filename, f.media_type,
    f.byte_size, f.state, f.scan_status, f.deleted_at,
    p.thread_id, p.author_user_id, p.visibility, p.moderation_state,
    p.hidden_at, p.deleted_at,
    t.author_user_id, t.visibility, t.deleted_at, t.moderation_state,
    c.category_id, c.visibility, c.deleted_at, c.space_id, s.visibility
FROM (
    SELECT al.* FROM public.attachment_links al
    WHERE al.target_type = p_link_target_type
        AND al.target_id = ANY(p_link_post_ids)
    ORDER BY al.target_id, al.created_at, al.attachment_link_id
    LIMIT p_link_row_limit
) a
JOIN public.attachments f ON f.attachment_id = a.attachment_id
JOIN public.posts p ON p.post_id = a.target_id
JOIN public.threads t ON t.thread_id = p.thread_id
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
UNION ALL
-- api.community_find_bookmark_v1
SELECT 'bookmark', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, b.target_type, b.target_id, b.created_at,
    b.bookmark_id, b.user_id, b.note, b.deleted_at,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
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
    NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
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
    rs.last_read_position, rs.last_read_at,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM public.thread_read_state rs
WHERE rs.user_id = p_viewer_user_id
    AND rs.thread_id = p_thread_id
UNION ALL
-- api.community_post_reactions_v1 (migration 133)
SELECT 'reaction', row_number() OVER (), x.post_id, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    x.reaction, x.reaction_count, x.reacted,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (
    SELECT pr.post_id, pr.reaction, count(*)::bigint AS reaction_count,
        coalesce(bool_or(pr.user_id = p_viewer_user_id), false) AS reacted
    FROM public.post_reactions pr
    WHERE pr.post_id = ANY(p_post_ids)
    GROUP BY pr.post_id, pr.reaction
) x
ORDER BY 1, 2
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v5(uuid, uuid[], uuid, text, text, uuid[], integer)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.forum_thread_page_reads_v6(
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
    last_read_at timestamptz,
    reaction text,
    reaction_count bigint,
    reacted boolean,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_reads_v5(p_thread_id, p_post_ids, p_viewer_user_id, p_engagement_target_type, p_link_target_type, p_link_post_ids, p_link_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v6(uuid, uuid[], uuid, text, text, uuid[], integer)
    FROM PUBLIC;
