-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126: notifications filter source visibility before LIMIT, preserving
-- full keyset pages and capped badge counts. A partitioned notification is
-- joined on its id AND timestamp. Payloads remain columns; no ORM inflation.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.notification_list_inbox_v1(
    p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_notification_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    recipient_user_id uuid, notification_id uuid, created_at timestamptz,
    read_at timestamptz, rank_score numeric, source_type text, source_id uuid,
    notification_type text, payload jsonb, source_thread_id uuid, source_thread_title text
)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY
    SELECT i.recipient_user_id, i.notification_id, i.created_at, i.read_at, i.rank_score,
      n.source_type, n.source_id, n.notification_type, n.payload,
      CASE WHEN p_filter_sources THEN CASE n.source_type WHEN 'thread' THEN n.source_id
        WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END END,
      CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id =
        CASE n.source_type WHEN 'thread' THEN n.source_id
          WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END) END
    FROM public.notification_inbox i
    JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_recipient_user_id
      AND (NOT p_filter_sources OR ((n.source_type = 'thread' AND EXISTS (
          SELECT 1 FROM public.threads t
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))))
        OR (n.source_type = 'post' AND EXISTS (
          SELECT 1 FROM public.posts p
          JOIN public.threads t ON t.thread_id = p.thread_id
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
            AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))
            AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
    ORDER BY i.created_at DESC, i.notification_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY
    SELECT i.recipient_user_id, i.notification_id, i.created_at, i.read_at, i.rank_score,
      n.source_type, n.source_id, n.notification_type, n.payload,
      CASE WHEN p_filter_sources THEN CASE n.source_type WHEN 'thread' THEN n.source_id
        WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END END,
      CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id =
        CASE n.source_type WHEN 'thread' THEN n.source_id
          WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END) END
    FROM public.notification_inbox i
    JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_recipient_user_id
      AND (NOT p_filter_sources OR ((n.source_type = 'thread' AND EXISTS (
          SELECT 1 FROM public.threads t
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))))
        OR (n.source_type = 'post' AND EXISTS (
          SELECT 1 FROM public.posts p
          JOIN public.threads t ON t.thread_id = p.thread_id
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
            AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))
            AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND i.created_at <= p_after_created_at
      AND (i.created_at < p_after_created_at OR (i.created_at = p_after_created_at AND i.notification_id < p_after_notification_id))
    ORDER BY i.created_at DESC, i.notification_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_unread_count_v1(
    p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[]
)
RETURNS TABLE (unread_count bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT count(*) FROM (
    SELECT i.notification_id
    FROM public.notification_inbox i
    JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_recipient_user_id
      AND (NOT p_filter_sources OR ((n.source_type = 'thread' AND EXISTS (
          SELECT 1 FROM public.threads t
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))))
        OR (n.source_type = 'post' AND EXISTS (
          SELECT 1 FROM public.posts p
          JOIN public.threads t ON t.thread_id = p.thread_id
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
            AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))
            AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id))))))))))) AND i.read_at IS NULL
    LIMIT 100
) counted
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[]) FROM PUBLIC;

COMMIT;
