-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0130, amendment of 2026-10-17: the personal feed leaves out the
-- threads and posts of a member on the reader's ignore or block list, as
-- the inbox, the mentions page and the digest already do, judged before
-- LIMIT so a page stays full. Taking the member off the list brings their
-- items back. A new version, as ADR 0126 section 2 asks: the shipped ones
-- stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.community_list_feed_v3(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (user_id uuid, item_type text, item_id uuid, created_at timestamptz, rank_score numeric, visibility_version bigint, permission_version bigint, source_thread_id uuid, source_thread_title text)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY SELECT b.user_id, b.item_type, b.item_id, b.created_at, b.rank_score, b.visibility_version, b.permission_version, CASE WHEN p_filter_sources THEN CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END) END FROM public.user_feed_items b  WHERE b.user_id = p_user_id AND (NOT p_filter_sources OR ((b.item_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.item_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.item_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.item_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id
              AND r.other_user_id = CASE b.item_type
                  WHEN 'thread' THEN (SELECT t.author_user_id
                      FROM public.threads t WHERE t.thread_id = b.item_id)
                  WHEN 'post' THEN (SELECT p.author_user_id
                      FROM public.posts p WHERE p.post_id = b.item_id)
              END)
    ORDER BY b.created_at DESC, b.item_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.user_id, b.item_type, b.item_id, b.created_at, b.rank_score, b.visibility_version, b.permission_version, CASE WHEN p_filter_sources THEN CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END) END FROM public.user_feed_items b  WHERE b.user_id = p_user_id AND (NOT p_filter_sources OR ((b.item_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.item_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.item_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.item_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.item_id < p_after_id))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id
              AND r.other_user_id = CASE b.item_type
                  WHEN 'thread' THEN (SELECT t.author_user_id
                      FROM public.threads t WHERE t.thread_id = b.item_id)
                  WHEN 'post' THEN (SELECT p.author_user_id
                      FROM public.posts p WHERE p.post_id = b.item_id)
              END)
    ORDER BY b.created_at DESC, b.item_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_feed_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.community_list_feed_v4(
p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (user_id uuid, item_type text, item_id uuid, created_at timestamptz, rank_score numeric, visibility_version bigint, permission_version bigint, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_feed_v3(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_feed_v4(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

COMMIT;
