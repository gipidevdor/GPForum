-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- Two reads planned on every call. A function that forces a custom plan is
-- planned again each time it runs; for these two, point and keyset lookups
-- by id, the plan never changes with the parameters, and the planning was
-- most of the call. Measured with 1,000 correlated calls on the hot-thread
-- seed, per call: forum_find_listed_post 0.142 ms under the custom plan,
-- 0.013 generic; notification_list_inbox 0.288 and 0.070. The bodies are
-- unchanged; the previous boundaries stay for the previous release's
-- workers until a release later (ADR 0126, section 2). The list functions
-- that filter by standing keep their custom plans: a generic plan cannot
-- use the partial indexes whose predicate depends on the parameters.

-- api.forum_find_listed_post_v1, planned once.
CREATE FUNCTION api.forum_find_listed_post_v3(
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
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v3(uuid, uuid, boolean, boolean, uuid, uuid)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.forum_find_listed_post_v4(
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
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_find_listed_post_v3(p_post_id, p_thread_id, p_member, p_global_read, p_scope_user_id, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v4(uuid, uuid, boolean, boolean, uuid, uuid)
    FROM PUBLIC;

-- api.notification_list_inbox_v5, planned once.
CREATE FUNCTION api.notification_list_inbox_v7(
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
    recipient_user_id uuid,
    notification_id uuid,
    created_at timestamptz,
    read_at timestamptz,
    rank_score numeric,
    source_type text,
    source_id uuid,
    notification_type text,
    payload jsonb,
    source_thread_id uuid,
    source_thread_title text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
      AND (NOT p_filter_sources OR (n.source_type = 'message' AND EXISTS (
          SELECT 1 FROM public.direct_messages dm
          JOIN public.direct_conversation_members dmm
            ON dmm.conversation_id = dm.conversation_id
            AND dmm.user_id = p_recipient_user_id
          WHERE dm.message_id = n.source_id))
        OR ((n.source_type = 'thread' AND EXISTS (
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
      AND NOT (n.notification_type IN ('reply', 'mention', 'direct_message') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
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
      AND (NOT p_filter_sources OR (n.source_type = 'message' AND EXISTS (
          SELECT 1 FROM public.direct_messages dm
          JOIN public.direct_conversation_members dmm
            ON dmm.conversation_id = dm.conversation_id
            AND dmm.user_id = p_recipient_user_id
          WHERE dm.message_id = n.source_id))
        OR ((n.source_type = 'thread' AND EXISTS (
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
      AND NOT (n.notification_type IN ('reply', 'mention', 'direct_message') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
    ORDER BY i.created_at DESC, i.notification_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v7(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.notification_list_inbox_v8(
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
    recipient_user_id uuid,
    notification_id uuid,
    created_at timestamptz,
    read_at timestamptz,
    rank_score numeric,
    source_type text,
    source_id uuid,
    notification_type text,
    payload jsonb,
    source_thread_id uuid,
    source_thread_title text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_inbox_v7(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids, p_after_created_at,
    p_after_notification_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v8(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;
