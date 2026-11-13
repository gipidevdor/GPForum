-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- One MVCC snapshot and one client round trip for the ordinary thread page.
-- The existing invoker implementations retain post filtering and ancillary
-- query plans. No authorization or member state is cached by this function.
CREATE FUNCTION api.forum_thread_page_snapshot_v1(
    p_thread_id uuid, p_viewer_user_id uuid, p_member boolean,
    p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[],
    p_after_position bigint, p_after_post_id uuid, p_page_limit integer,
    p_link_target_type text, p_links_per_post integer
)
RETURNS TABLE (thread_head jsonb, posts jsonb, page_reads jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH head AS MATERIALIZED (
    SELECT h.*,
        coalesce(p_global_read OR h.category_id = ANY(p_category_ids)
            OR h.space_id = ANY(p_space_ids), false) AS scoped_grant
    FROM api.forum_thread_page_head_v1(p_thread_id) h
    WHERE h.moderation_state IN ('visible', 'locked')
      AND (h.deleted_at IS NULL OR h.author_user_id = p_viewer_user_id)
      AND (h.space_visibility = 'public'
        OR (p_member AND h.space_visibility = 'members')
        OR (h.space_visibility = 'private' AND (p_global_read
            OR h.category_id = ANY(p_category_ids) OR h.space_id = ANY(p_space_ids))))
      AND (h.category_visibility = 'public'
        OR (p_member AND h.category_visibility = 'members')
        OR (h.category_visibility = 'private' AND (p_global_read
            OR h.category_id = ANY(p_category_ids) OR h.space_id = ANY(p_space_ids))))
      AND (h.visibility = 'public' OR (p_member AND h.visibility = 'members')
        OR (h.visibility = 'private' AND (p_global_read
            OR h.category_id = ANY(p_category_ids) OR h.space_id = ANY(p_space_ids)
            OR (p_member AND h.author_user_id = p_viewer_user_id))))
), limits AS (
    SELECT greatest(1, least(coalesce(p_page_limit, 25), 100)) AS page_limit
), page AS MATERIALIZED (
    SELECT p.* FROM head h CROSS JOIN limits l
    CROSS JOIN LATERAL api.forum_thread_page_posts_v3(
        p_thread_id,
        CASE WHEN h.scoped_grant OR (p_member AND h.visibility = 'private'
                AND h.author_user_id = p_viewer_user_id) THEN 'global'
             WHEN p_member THEN 'member' ELSE 'anonymous' END,
        p_viewer_user_id, p_after_position, p_after_post_id, l.page_limit + 1
    ) p
), shown AS MATERIALIZED (
    SELECT p.* FROM page p ORDER BY p.position, p.post_id
    LIMIT (SELECT page_limit FROM limits)
), ids AS (
    SELECT coalesce(array_agg(p.post_id ORDER BY p.position, p.post_id), '{}') AS post_ids,
        coalesce(array_agg(p.post_id ORDER BY p.post_id), '{}') AS link_ids
    FROM shown p
), reads AS (
    SELECT r.* FROM head h CROSS JOIN ids i
    CROSS JOIN LATERAL api.forum_thread_page_reads_v7(
        p_thread_id, i.post_ids, p_viewer_user_id, 'thread', p_link_target_type,
        i.link_ids, cardinality(i.link_ids) * greatest(0, least(p_links_per_post, 1000))
    ) r
)
SELECT
    (SELECT to_jsonb(h) - 'scoped_grant' || jsonb_build_object(
        'pinned', h.pinned::integer, 'locked_at', h.locked_at::text, 'last_activity_at', h.last_activity_at::text,
        'deleted_at', h.deleted_at::text) FROM head h),
    coalesce((SELECT jsonb_agg(to_jsonb(p) || jsonb_build_object(
        'created_at', p.created_at::text, 'deleted_at', p.deleted_at::text)
        ORDER BY p.position, p.post_id) FROM page p), '[]'::jsonb),
    coalesce((SELECT jsonb_agg(jsonb_strip_nulls(to_jsonb(r) || jsonb_build_object(
        'liked', r.liked::integer, 'reacted', r.reacted::integer,
        'created_at', r.created_at::text, 'deleted_at', r.deleted_at::text,
        'muted_at', r.muted_at::text, 'revoked_at', r.revoked_at::text,
        'last_read_at', r.last_read_at::text, 'file_deleted_at', r.file_deleted_at::text,
        'post_hidden_at', r.post_hidden_at::text, 'post_deleted_at', r.post_deleted_at::text,
        'thread_deleted_at', r.thread_deleted_at::text))
        ORDER BY r.part, r.ordinal) FROM reads r), '[]'::jsonb);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_snapshot_v1(
    uuid,uuid,boolean,boolean,uuid[],uuid[],bigint,uuid,integer,text,integer) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_snapshot_v2(
    p_thread_id uuid, p_viewer_user_id uuid, p_member boolean,
    p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[],
    p_after_position bigint, p_after_post_id uuid, p_page_limit integer,
    p_link_target_type text, p_links_per_post integer
)
RETURNS TABLE (thread_head jsonb, posts jsonb, page_reads jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_snapshot_v1(
    p_thread_id,p_viewer_user_id,p_member,p_global_read,p_category_ids,p_space_ids,
    p_after_position,p_after_post_id,p_page_limit,p_link_target_type,p_links_per_post);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_snapshot_v2(
    uuid,uuid,boolean,boolean,uuid[],uuid[],bigint,uuid,integer,text,integer) FROM PUBLIC;

COMMIT;
