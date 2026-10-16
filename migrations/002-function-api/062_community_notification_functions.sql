-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126: source lists retain their bounded keyset scans; mutations own
-- their locking, duplicate recovery and ledger updates inside PostgreSQL.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.community_list_bookmarks_v1(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_target_type text,
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (bookmark_id uuid, user_id uuid, target_type text, target_id uuid, note text, created_at timestamptz, deleted_at timestamptz, source_thread_id uuid, source_thread_title text)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note, b.created_at, b.deleted_at, CASE WHEN p_filter_sources THEN CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END) END FROM public.bookmarks b  WHERE b.user_id = p_user_id AND b.deleted_at IS NULL AND (p_target_type IS NULL OR b.target_type = p_target_type) AND (NOT p_filter_sources OR ((b.target_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.target_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.target_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
    ORDER BY b.created_at DESC, b.bookmark_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note, b.created_at, b.deleted_at, CASE WHEN p_filter_sources THEN CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END) END FROM public.bookmarks b  WHERE b.user_id = p_user_id AND b.deleted_at IS NULL AND (p_target_type IS NULL OR b.target_type = p_target_type) AND (NOT p_filter_sources OR ((b.target_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.target_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.target_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.bookmark_id < p_after_id))
    ORDER BY b.created_at DESC, b.bookmark_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmarks_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_list_feed_v1(
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
    ORDER BY b.created_at DESC, b.item_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.user_id, b.item_type, b.item_id, b.created_at, b.rank_score, b.visibility_version, b.permission_version, CASE WHEN p_filter_sources THEN CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END) END FROM public.user_feed_items b  WHERE b.user_id = p_user_id AND (NOT p_filter_sources OR ((b.item_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.item_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.item_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.item_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.item_id < p_after_id))
    ORDER BY b.created_at DESC, b.item_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_feed_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_list_mentions_v1(
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
RETURNS TABLE (mention_id uuid, source_type text, source_id uuid, actor_id uuid, mentioned_user_id uuid, mentioned_username text, created_at timestamptz, actor_username text, actor_display_name text, source_thread_id uuid, source_thread_title text)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY SELECT b.mention_id, b.source_type, b.source_id, b.actor_id, b.mentioned_user_id, b.mentioned_username, b.created_at, a.username, a.display_name, CASE WHEN p_filter_sources THEN CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END) END FROM public.mentions b JOIN public.users a ON a.id = b.actor_id WHERE b.mentioned_user_id = p_user_id AND (NOT p_filter_sources OR ((b.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
    ORDER BY b.created_at DESC, b.mention_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.mention_id, b.source_type, b.source_id, b.actor_id, b.mentioned_user_id, b.mentioned_username, b.created_at, a.username, a.display_name, CASE WHEN p_filter_sources THEN CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END) END FROM public.mentions b JOIN public.users a ON a.id = b.actor_id WHERE b.mentioned_user_id = p_user_id AND (NOT p_filter_sources OR ((b.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.mention_id < p_after_id))
    ORDER BY b.created_at DESC, b.mention_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_mentions_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_save_bookmark_v1(
    p_row jsonb,
    p_restore boolean
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.bookmarks%ROWTYPE; v_constraint text; v_skipped boolean;
BEGIN
  IF p_restore THEN SELECT b.* INTO v FROM public.bookmarks b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE; END IF;
  IF v.bookmark_id IS NULL THEN
    BEGIN
      INSERT INTO public.bookmarks (bookmark_id, user_id, target_type, target_id, note, created_at, deleted_at) VALUES ((p_row->>'bookmark_id')::uuid, (p_row->>'user_id')::uuid, p_row->>'target_type', (p_row->>'target_id')::uuid, p_row->>'note', (p_row->>'created_at')::timestamptz, NULL);
      RETURN QUERY SELECT p_row; RETURN;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF NOT p_restore THEN RAISE; END IF;
      SELECT b.* INTO v FROM public.bookmarks b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE;
      IF v.bookmark_id IS NULL THEN
        IF v_constraint = 'bookmarks_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
        RAISE;
      END IF;
    END;
  END IF;
  v_skipped := v.deleted_at IS NULL AND v.note = p_row->>'note';
  IF NOT v_skipped THEN UPDATE public.bookmarks b SET deleted_at = NULL, note = p_row->>'note' WHERE b.bookmark_id = v.bookmark_id; END IF;
  RETURN QUERY SELECT p_row || jsonb_build_object('bookmark_id', v.bookmark_id, 'created_at', v.created_at::text) || CASE WHEN v_skipped THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_save_bookmark_v1(jsonb, boolean) FROM PUBLIC;

CREATE FUNCTION api.community_find_bookmark_v1(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF public.bookmarks
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.* FROM public.bookmarks b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id
$$;
REVOKE EXECUTE ON FUNCTION api.community_find_bookmark_v1(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.community_stamp_bookmark_v1(
    p_id uuid,
    p_by_target boolean,
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_column text,
    p_stamped_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.bookmarks%ROWTYPE;
BEGIN
  IF p_by_target THEN SELECT b.* INTO v FROM public.bookmarks b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id FOR UPDATE;
  ELSE SELECT b.* INTO v FROM public.bookmarks b WHERE b.bookmark_id = p_id FOR UPDATE; END IF;
  IF v.bookmark_id IS NULL THEN RETURN QUERY SELECT jsonb_build_object('ok', 0, 'error', 'not_found'); RETURN; END IF;
  IF p_column = 'deleted_at' THEN
    IF v.deleted_at IS NULL THEN UPDATE public.bookmarks b SET deleted_at = p_stamped_at::timestamptz WHERE b.bookmark_id = v.bookmark_id; END IF;
    RETURN QUERY SELECT jsonb_build_object('bookmark_id', v.bookmark_id, 'deleted_at', COALESCE(v.deleted_at::text, p_stamped_at)) || CASE WHEN v.deleted_at IS NOT NULL THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END || CASE WHEN p_by_target THEN jsonb_build_object('ok', 1) ELSE '{}'::jsonb END; RETURN;
  END IF;
  RAISE EXCEPTION 'invalid stamp column' USING ERRCODE = '22023';
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_stamp_bookmark_v1(uuid, boolean, uuid, text, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.notification_save_subscription_v1(
    p_row jsonb,
    p_restore boolean
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.subscriptions%ROWTYPE; v_constraint text; v_skipped boolean;
BEGIN
  IF p_restore THEN SELECT b.* INTO v FROM public.subscriptions b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE; END IF;
  IF v.subscription_id IS NULL THEN
    BEGIN
      INSERT INTO public.subscriptions (subscription_id, user_id, target_type, target_id, preference, created_at, muted_at, revoked_at) VALUES ((p_row->>'subscription_id')::uuid, (p_row->>'user_id')::uuid, p_row->>'target_type', (p_row->>'target_id')::uuid, p_row->>'preference', (p_row->>'created_at')::timestamptz, NULL, NULL);
      RETURN QUERY SELECT p_row; RETURN;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF NOT p_restore THEN RAISE; END IF;
      SELECT b.* INTO v FROM public.subscriptions b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE;
      IF v.subscription_id IS NULL THEN
        IF v_constraint = 'subscriptions_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
        RAISE;
      END IF;
    END;
  END IF;
  v_skipped := v.muted_at IS NULL AND v.revoked_at IS NULL AND v.preference = p_row->>'preference';
  IF NOT v_skipped THEN UPDATE public.subscriptions b SET muted_at = NULL, revoked_at = NULL, preference = p_row->>'preference' WHERE b.subscription_id = v.subscription_id; END IF;
  RETURN QUERY SELECT p_row || jsonb_build_object('subscription_id', v.subscription_id, 'created_at', v.created_at::text) || CASE WHEN v_skipped THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_save_subscription_v1(jsonb, boolean) FROM PUBLIC;

CREATE FUNCTION api.notification_find_subscription_v1(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF public.subscriptions
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.* FROM public.subscriptions b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id
$$;
REVOKE EXECUTE ON FUNCTION api.notification_find_subscription_v1(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_stamp_subscription_v1(
    p_id uuid,
    p_by_target boolean,
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_column text,
    p_stamped_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.subscriptions%ROWTYPE;
BEGIN
  IF p_by_target THEN SELECT b.* INTO v FROM public.subscriptions b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id FOR UPDATE;
  ELSE SELECT b.* INTO v FROM public.subscriptions b WHERE b.subscription_id = p_id FOR UPDATE; END IF;
  IF v.subscription_id IS NULL THEN RETURN QUERY SELECT jsonb_build_object('ok', 0, 'error', 'not_found'); RETURN; END IF;
  IF p_column = 'muted_at' THEN
    IF v.muted_at IS NULL THEN UPDATE public.subscriptions b SET muted_at = p_stamped_at::timestamptz WHERE b.subscription_id = v.subscription_id; END IF;
    RETURN QUERY SELECT jsonb_build_object('subscription_id', v.subscription_id, 'muted_at', COALESCE(v.muted_at::text, p_stamped_at)) || CASE WHEN v.muted_at IS NOT NULL THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END || jsonb_build_object('ok', 1); RETURN;
  END IF; IF p_column = 'revoked_at' THEN
    IF v.revoked_at IS NULL THEN UPDATE public.subscriptions b SET revoked_at = p_stamped_at::timestamptz WHERE b.subscription_id = v.subscription_id; END IF;
    RETURN QUERY SELECT jsonb_build_object('subscription_id', v.subscription_id, 'revoked_at', COALESCE(v.revoked_at::text, p_stamped_at)) || CASE WHEN v.revoked_at IS NOT NULL THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END || jsonb_build_object('ok', 1); RETURN;
  END IF;
  RAISE EXCEPTION 'invalid stamp column' USING ERRCODE = '22023';
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_stamp_subscription_v1(uuid, boolean, uuid, text, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.notification_subscribers_v1(
    p_target_type text,
    p_target_id uuid,
    p_notification_type text
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.user_id FROM public.subscriptions s WHERE s.target_type = p_target_type AND s.target_id = p_target_id AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none' AND (s.preference = 'all' OR p_notification_type = 'mention')
$$;
REVOKE EXECUTE ON FUNCTION api.notification_subscribers_v1(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_list_preferences_v1(
    p_user_id uuid
)
RETURNS SETOF public.notification_preferences
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p.* FROM public.notification_preferences p WHERE p.user_id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_preferences_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_set_preference_v1(
    p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.notification_preferences%ROWTYPE;
BEGIN
  INSERT INTO public.notification_preferences (user_id, channel, enabled, digest_frequency, updated_at)
  VALUES ((p_row->>'user_id')::uuid, p_row->>'channel', (p_row->>'enabled')::boolean, p_row->>'digest_frequency', (p_row->>'updated_at')::timestamptz)
  ON CONFLICT (user_id, channel) DO NOTHING;
  IF FOUND THEN RETURN QUERY SELECT p_row; RETURN; END IF;
  SELECT p.* INTO v FROM public.notification_preferences p WHERE p.user_id = (p_row->>'user_id')::uuid AND p.channel = p_row->>'channel' FOR UPDATE;
  IF v.enabled = (p_row->>'enabled')::boolean AND v.digest_frequency = p_row->>'digest_frequency' THEN
    RETURN QUERY SELECT p_row || jsonb_build_object('skipped', 1, 'updated_at', v.updated_at::text); RETURN;
  END IF;
  UPDATE public.notification_preferences p SET enabled = (p_row->>'enabled')::boolean, digest_frequency = p_row->>'digest_frequency', updated_at = (p_row->>'updated_at')::timestamptz
  WHERE p.user_id = v.user_id AND p.channel = v.channel;
  RETURN QUERY SELECT p_row;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_preference_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_project_feed_v1(
    p_row jsonb,
    p_user_ids uuid[]
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_written bigint;
BEGIN
  INSERT INTO public.user_feed_items (user_id, item_type, item_id, created_at, rank_score, visibility_version, permission_version)
  SELECT u, p_row->>'item_type', (p_row->>'item_id')::uuid, (p_row->>'created_at')::timestamptz,
    (p_row->>'rank_score')::numeric, (p_row->>'visibility_version')::bigint, (p_row->>'permission_version')::bigint FROM unnest(p_user_ids) u
  ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET created_at = EXCLUDED.created_at, rank_score = EXCLUDED.rank_score, visibility_version = EXCLUDED.visibility_version, permission_version = EXCLUDED.permission_version
  WHERE (public.user_feed_items.created_at, public.user_feed_items.rank_score, public.user_feed_items.visibility_version, public.user_feed_items.permission_version)
    IS DISTINCT FROM (EXCLUDED.created_at, EXCLUDED.rank_score, EXCLUDED.visibility_version, EXCLUDED.permission_version);
  GET DIAGNOSTICS v_written = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'projected', cardinality(p_user_ids), 'written', v_written);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_project_feed_v1(jsonb, uuid[]) FROM PUBLIC;

CREATE FUNCTION api.community_remove_feed_v1(
    p_item_type text,
    p_item_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_removed bigint;
BEGIN
  DELETE FROM public.user_feed_items f WHERE f.item_type = p_item_type AND f.item_id = p_item_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'removed', v_removed);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_feed_v1(text, uuid) FROM PUBLIC;

CREATE FUNCTION api.community_remove_thread_feed_v1(
    p_thread_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_thread bigint; v_posts bigint;
BEGIN
  DELETE FROM public.user_feed_items f WHERE f.item_type = 'thread' AND f.item_id = p_thread_id;
  GET DIAGNOSTICS v_thread = ROW_COUNT;
  DELETE FROM public.user_feed_items f WHERE f.item_type = 'post' AND f.item_id IN (SELECT p.post_id FROM public.posts p WHERE p.thread_id = p_thread_id);
  GET DIAGNOSTICS v_posts = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'posts_removed', v_posts, 'removed', v_thread + v_posts);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_thread_feed_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.community_resolve_mention_users_v1(
    p_usernames text[]
)
RETURNS TABLE (id uuid, username text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id, u.username FROM public.users u WHERE u.username = ANY(p_usernames) AND u.deleted_at IS NULL LIMIT cardinality(p_usernames)
$$;
REVOKE EXECUTE ON FUNCTION api.community_resolve_mention_users_v1(text[]) FROM PUBLIC;

CREATE FUNCTION api.community_create_mention_v1(
    p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_constraint text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.mentions m WHERE m.source_type = p_row->>'source_type' AND m.source_id = (p_row->>'source_id')::uuid AND m.mentioned_user_id = (p_row->>'mentioned_user_id')::uuid) THEN RETURN QUERY SELECT NULL::jsonb; RETURN; END IF;
  BEGIN
    INSERT INTO public.mentions (mention_id, source_type, source_id, actor_id, mentioned_user_id, mentioned_username, created_at)
    VALUES ((p_row->>'mention_id')::uuid, p_row->>'source_type', (p_row->>'source_id')::uuid, (p_row->>'actor_id')::uuid, (p_row->>'mentioned_user_id')::uuid, p_row->>'mentioned_username', (p_row->>'created_at')::timestamptz);
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF EXISTS (SELECT 1 FROM public.mentions m WHERE m.source_type = p_row->>'source_type' AND m.source_id = (p_row->>'source_id')::uuid AND m.mentioned_user_id = (p_row->>'mentioned_user_id')::uuid) THEN RETURN QUERY SELECT NULL::jsonb; RETURN; END IF;
    IF v_constraint = 'mentions_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
    RAISE;
  END;
  RETURN QUERY SELECT p_row;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_create_mention_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_record_reputation_v1(
    p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_event public.reputation_events%ROWTYPE; v_snapshot public.trust_score_snapshots%ROWTYPE;
  v_new boolean := false; v_constraint text; v_at text; v_event_json jsonb; v_score integer; v_trust integer; v_snapshot_json jsonb;
BEGIN
  IF COALESCE(p_row->>'source_type', '') = '' OR COALESCE(p_row->>'source_id', '') = '' THEN
    SELECT s.* INTO v_snapshot FROM public.trust_score_snapshots s WHERE s.user_id = (p_row->>'user_id')::uuid;
    v_snapshot_json := CASE WHEN v_snapshot.user_id IS NULL THEN jsonb_build_object('user_id', p_row->>'user_id', 'score', 0, 'trust_level', 0, 'version', 1)
      ELSE to_jsonb(v_snapshot) || jsonb_build_object('calculated_at', v_snapshot.calculated_at::text) END;
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'reason', 'missing_source', 'skipped', 1, 'snapshot', v_snapshot_json); RETURN;
  END IF;
  SELECT e.* INTO v_event FROM public.reputation_events e WHERE e.user_id = (p_row->>'user_id')::uuid AND e.source_type = p_row->>'source_type' AND e.source_id = (p_row->>'source_id')::uuid;
  IF v_event.reputation_event_id IS NULL THEN
    BEGIN
      INSERT INTO public.reputation_events (reputation_event_id, user_id, actor_id, source_type, source_id, delta, reason, created_at)
      VALUES ((p_row->>'reputation_event_id')::uuid, (p_row->>'user_id')::uuid, (p_row->>'actor_id')::uuid, p_row->>'source_type', (p_row->>'source_id')::uuid, (p_row->>'delta')::integer, p_row->>'reason', (p_row->>'created_at')::timestamptz);
      v_new := true;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      SELECT e.* INTO v_event FROM public.reputation_events e WHERE e.user_id = (p_row->>'user_id')::uuid AND e.source_type = p_row->>'source_type' AND e.source_id = (p_row->>'source_id')::uuid;
      IF v_event.reputation_event_id IS NULL THEN
        IF v_constraint = 'reputation_events_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
        RAISE;
      END IF;
    END;
  END IF;
  v_at := CASE WHEN v_new THEN p_row->>'created_at' ELSE v_event.created_at::text END;
  v_event_json := CASE WHEN v_new THEN jsonb_build_object('actor_id', p_row->'actor_id', 'created_at', p_row->'created_at', 'delta', p_row->'delta', 'reason', p_row->'reason', 'reputation_event_id', p_row->'reputation_event_id', 'source_id', p_row->'source_id', 'source_type', p_row->'source_type', 'user_id', p_row->'user_id') ELSE to_jsonb(v_event) || jsonb_build_object('created_at', v_event.created_at::text) END;
  SELECT s.* INTO v_snapshot FROM public.trust_score_snapshots s WHERE s.user_id = (p_row->>'user_id')::uuid FOR UPDATE;
  IF NOT v_new AND v_snapshot.user_id IS NOT NULL THEN
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'skipped', 1, 'event', v_event_json, 'snapshot', to_jsonb(v_snapshot) || jsonb_build_object('calculated_at', v_snapshot.calculated_at::text)); RETURN;
  END IF;
  IF v_snapshot.user_id IS NULL THEN
    v_score := COALESCE((p_row->>'current_score')::integer, 0) + (p_row->>'delta')::integer;
    v_trust := CASE WHEN v_score >= 500 THEN 4 WHEN v_score >= 150 THEN 3 WHEN v_score >= 50 THEN 2 WHEN v_score >= 10 THEN 1 ELSE 0 END;
    INSERT INTO public.trust_score_snapshots (user_id, score, trust_level, calculated_at, version)
    VALUES ((p_row->>'user_id')::uuid, v_score, v_trust, v_at::timestamptz, 1) ON CONFLICT (user_id) DO NOTHING;
    IF NOT FOUND THEN
      SELECT s.* INTO v_snapshot FROM public.trust_score_snapshots s WHERE s.user_id = (p_row->>'user_id')::uuid FOR UPDATE;
    END IF;
  END IF;
  IF v_snapshot.user_id IS NOT NULL THEN
    v_score := v_snapshot.score + CASE WHEN v_new THEN (p_row->>'delta')::integer ELSE 0 END;
    v_trust := CASE WHEN v_score >= 500 THEN 4 WHEN v_score >= 150 THEN 3 WHEN v_score >= 50 THEN 2 WHEN v_score >= 10 THEN 1 ELSE 0 END;
    IF v_new THEN UPDATE public.trust_score_snapshots s SET score = v_score, trust_level = v_trust, calculated_at = v_at::timestamptz, version = 1 WHERE s.user_id = v_snapshot.user_id;
    ELSE v_at := v_snapshot.calculated_at::text; END IF;
  END IF;
  UPDATE public.users u SET trust_level = v_trust WHERE u.id = (p_row->>'user_id')::uuid AND u.trust_level IS DISTINCT FROM v_trust;
  v_snapshot_json := jsonb_build_object('user_id', p_row->>'user_id', 'score', v_score, 'trust_level', v_trust, 'calculated_at', v_at, 'version', 1);
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'event', v_event_json, 'snapshot', v_snapshot_json) || CASE WHEN NOT v_new THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_record_reputation_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_deliver_v1(
    p_notification jsonb,
    p_inbox jsonb,
    p_idempotency_key text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.notification_inbox%ROWTYPE; v_at text; v_notification jsonb; v_inbox jsonb; v_constraint text;
BEGIN
  SELECT i.* INTO v FROM public.notification_inbox i WHERE i.recipient_user_id = (p_inbox->>'recipient_user_id')::uuid AND i.notification_id = (p_inbox->>'notification_id')::uuid;
  IF v.notification_id IS NULL THEN
    BEGIN
      SELECT n.created_at::text INTO v_at FROM public.notifications n WHERE n.notification_id = (p_inbox->>'notification_id')::uuid LIMIT 1;
      v_at := COALESCE(v_at, p_inbox->>'created_at');
      v_notification := p_notification || jsonb_build_object('created_at', v_at);
      v_inbox := p_inbox || jsonb_build_object('created_at', v_at);
      INSERT INTO public.notifications (notification_id, recipient_user_id, source_type, source_id, notification_type, payload, created_at)
      VALUES ((v_notification->>'notification_id')::uuid, (v_notification->>'recipient_user_id')::uuid, v_notification->>'source_type', (v_notification->>'source_id')::uuid, v_notification->>'notification_type', v_notification->'payload', v_at::timestamptz)
      ON CONFLICT (notification_id, created_at) DO NOTHING;
      INSERT INTO public.notification_inbox (recipient_user_id, notification_id, created_at, read_at, rank_score)
      VALUES ((p_inbox->>'recipient_user_id')::uuid, (p_inbox->>'notification_id')::uuid, v_at::timestamptz, NULL, (p_inbox->>'rank_score')::numeric);
      RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', 0, 'idempotency_key', p_idempotency_key, 'notification', v_notification, 'inbox', v_inbox); RETURN;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF NOT api.core_unique_on_v1(v_constraint, 'notification_inbox_pkey') THEN RAISE; END IF;
      SELECT i.* INTO v FROM public.notification_inbox i WHERE i.recipient_user_id = (p_inbox->>'recipient_user_id')::uuid AND i.notification_id = (p_inbox->>'notification_id')::uuid;
      IF v.notification_id IS NULL THEN RAISE; END IF;
    END;
  END IF;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', 1, 'idempotency_key', p_idempotency_key,
    'notification', p_notification || jsonb_build_object('notification_id', v.notification_id, 'created_at', v.created_at::text),
    'inbox', to_jsonb(v) || jsonb_build_object('created_at', v.created_at::text, 'read_at', v.read_at::text));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_deliver_v1(jsonb, jsonb, text) FROM PUBLIC;

CREATE FUNCTION api.core_notification_read_v1(
    p_notification_id uuid,
    p_recipient_user_id uuid,
    p_read_at text
)
RETURNS text
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_at text;
BEGIN
  INSERT INTO public.notification_reads (notification_id, recipient_user_id, read_at) VALUES (p_notification_id, p_recipient_user_id, p_read_at::timestamptz)
  ON CONFLICT (notification_id, recipient_user_id) DO NOTHING;
  IF FOUND THEN v_at := p_read_at;
  ELSE SELECT r.read_at::text INTO v_at FROM public.notification_reads r WHERE r.notification_id = p_notification_id AND r.recipient_user_id = p_recipient_user_id; END IF;
  UPDATE public.notification_inbox i SET read_at = v_at::timestamptz WHERE i.notification_id = p_notification_id AND i.recipient_user_id = p_recipient_user_id;
  RETURN v_at;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_read_v1(uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_mark_read_v1(
    p_notification_id uuid,
    p_recipient_user_id uuid,
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.notification_inbox%ROWTYPE; v_at text;
BEGIN
  SELECT i.* INTO v FROM public.notification_inbox i WHERE i.notification_id = p_notification_id AND i.recipient_user_id = p_recipient_user_id FOR UPDATE;
  IF v.notification_id IS NULL THEN RETURN QUERY SELECT jsonb_build_object('ok', 0, 'error', 'not_found'); RETURN; END IF;
  v_at := CASE WHEN v.read_at IS NOT NULL THEN v.read_at::text ELSE api.core_notification_read_v1(p_notification_id, p_recipient_user_id, p_read_at) END;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', CASE WHEN v.read_at IS NOT NULL THEN 1 ELSE 0 END, 'notification_id', p_notification_id, 'recipient_user_id', p_recipient_user_id, 'read_at', v_at);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_read_v1(uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_mark_all_read_v1(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
DECLARE v record; v_count bigint := 0;
BEGIN
  FOR v IN SELECT i.notification_id FROM public.notification_inbox i JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_user_id AND i.read_at IS NULL AND (NOT p_filter_sources OR ((n.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (n.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id))))))))))) FOR UPDATE OF i
  LOOP
    PERFORM api.core_notification_read_v1(v.notification_id, p_user_id, p_read_at);
    v_count := v_count + 1;
  END LOOP;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', CASE WHEN v_count = 0 THEN 1 ELSE 0 END, 'marked_count', v_count, 'read_at', p_read_at, 'recipient_user_id', p_user_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_all_read_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text) FROM PUBLIC;

COMMIT;
