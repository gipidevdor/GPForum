-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0130: a member ignores or blocks another member. The relation is the
-- owner's private list, at most 500 members; a block is an ignore that also
-- refuses the other member's mentions. The inbox, its unread count and the
-- mentions page leave out the replies and mentions of a member on the
-- reader's list, judged before LIMIT so a page stays full; only member
-- notification types (reply, mention) are filtered, so a staff notice is
-- never ignored. Erasure removes the relations on both sides, and the
-- export carries the owner's own list. The viewer carries the list, so a
-- thread page collapses the listed members' posts at no extra query. New versions, as ADR 0126 section 2
-- asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.member_relations (
    owner_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    other_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('ignore', 'block')),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    PRIMARY KEY (owner_user_id, other_user_id),
    CHECK (owner_user_id <> other_user_id),
    CHECK (updated_at >= created_at)
);
CREATE INDEX idx_member_relations_other
    ON public.member_relations(other_user_id);

-- The owner's row is held while the list is counted, so two requests cannot
-- both take the last place. A member already listed changes kind in place.
CREATE FUNCTION api.community_relation_set_v1(p_owner_user_id uuid,
    p_username text, p_kind text, p_now timestamptz)
RETURNS TABLE(status text, other_user_id uuid, username text, kind text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE target record; held text; amount bigint;
BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('ignore', 'block')
        OR p_username IS NULL OR length(p_username) NOT BETWEEN 1 AND 200
        OR p_now IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u WHERE u.id = p_owner_user_id
        AND u.deleted_at IS NULL AND u.status IN ('active', 'suspended')
        FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'forbidden'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    SELECT u.id, u.username INTO target FROM public.users u
        WHERE u.username = p_username AND u.deleted_at IS NULL
            AND u.status IN ('active', 'suspended');
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    IF target.id = p_owner_user_id THEN
        RETURN QUERY SELECT 'self'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    SELECT r.kind INTO held FROM public.member_relations r
        WHERE r.owner_user_id = p_owner_user_id AND r.other_user_id = target.id
        FOR UPDATE;
    IF FOUND THEN
        IF held = p_kind THEN
            RETURN QUERY SELECT 'unchanged'::text, target.id, target.username, held;
            RETURN;
        END IF;
        UPDATE public.member_relations r SET kind = p_kind,
            updated_at = greatest(p_now, r.created_at)
            WHERE r.owner_user_id = p_owner_user_id
                AND r.other_user_id = target.id;
        RETURN QUERY SELECT 'ok'::text, target.id, target.username, p_kind;
        RETURN;
    END IF;
    SELECT count(*) INTO amount FROM public.member_relations r
        WHERE r.owner_user_id = p_owner_user_id;
    IF amount >= 500 THEN
        RETURN QUERY SELECT 'limit'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    INSERT INTO public.member_relations (owner_user_id, other_user_id, kind,
        created_at, updated_at)
        VALUES (p_owner_user_id, target.id, p_kind, p_now, p_now);
    RETURN QUERY SELECT 'ok'::text, target.id, target.username, p_kind;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_set_v1(uuid, text, text,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.community_relation_set_v2(
p_owner_user_id uuid, p_username text, p_kind text, p_now timestamptz
)
RETURNS TABLE(status text, other_user_id uuid, username text, kind text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_set_v1(p_owner_user_id, p_username,
    p_kind, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_set_v2(uuid, text, text,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.community_relation_remove_v1(p_owner_user_id uuid,
    p_username text)
RETURNS TABLE(removed bigint)
LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH gone AS (
    DELETE FROM public.member_relations r USING public.users u
    WHERE r.owner_user_id = p_owner_user_id AND r.other_user_id = u.id
        AND u.username = p_username
    RETURNING 1
)
SELECT count(*) FROM gone;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_remove_v1(uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.community_relation_remove_v2(
p_owner_user_id uuid, p_username text
)
RETURNS TABLE(removed bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_remove_v1(p_owner_user_id, p_username);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_remove_v2(uuid, text)
    FROM PUBLIC;

-- The owner's list, newest change first, for the settings page.
CREATE FUNCTION api.community_relation_list_v1(p_owner_user_id uuid)
RETURNS TABLE(other_user_id uuid, username text, display_name text,
    kind text, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.other_user_id, u.username, u.display_name, r.kind, r.created_at,
    r.updated_at
FROM public.member_relations r JOIN public.users u ON u.id = r.other_user_id
WHERE r.owner_user_id = p_owner_user_id
ORDER BY r.updated_at DESC, u.username
LIMIT 500;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_list_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.community_relation_list_v2(
p_owner_user_id uuid
)
RETURNS TABLE(other_user_id uuid, username text, display_name text,
    kind text, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_list_v1(p_owner_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_list_v2(uuid) FROM PUBLIC;

-- What the owner holds against one member: the profile page's actions, the
-- notification dispatcher and the mention store ask it.
CREATE FUNCTION api.community_relation_between_v1(p_owner_user_id uuid,
    p_other_user_id uuid)
RETURNS TABLE(kind text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.kind FROM public.member_relations r
WHERE r.owner_user_id = p_owner_user_id AND r.other_user_id = p_other_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_between_v1(uuid, uuid)
    FROM PUBLIC;

CREATE FUNCTION api.community_relation_between_v2(
p_owner_user_id uuid, p_other_user_id uuid
)
RETURNS TABLE(kind text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_relation_between_v1(p_owner_user_id,
    p_other_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_between_v2(uuid, uuid)
    FROM PUBLIC;

-- The reader of a request learns the members on their list with the rest of
-- who they are, in the viewer's one query: a thread page collapses their
-- posts without a second lookup.
CREATE FUNCTION api.forum_resolve_viewer_v5(p_user_id uuid)
RETURNS TABLE (status text, suspended boolean, grants json,
    moderates boolean, listed uuid[])
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.status, v.suspended, v.grants, v.moderates,
    coalesce((SELECT array_agg(r.other_user_id ORDER BY r.other_user_id)
        FROM public.member_relations r WHERE r.owner_user_id = p_user_id),
        '{}'::uuid[]) AS listed
FROM api.forum_resolve_viewer_v3(p_user_id) v
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v5(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v6(
p_user_id uuid
)
RETURNS TABLE (status text, suspended boolean, grants json,
    moderates boolean, listed uuid[])
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_resolve_viewer_v5(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v6(uuid) FROM PUBLIC;

-- The inbox, its badge and the mentions page as versions 1 read them, less
-- the replies and mentions of a member on the reader's list.
CREATE FUNCTION api.notification_list_inbox_v3(
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
      AND NOT (n.notification_type IN ('reply', 'mention') AND EXISTS (
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
      AND NOT (n.notification_type IN ('reply', 'mention') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
    ORDER BY i.created_at DESC, i.notification_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_unread_count_v3(
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
      AND NOT (n.notification_type IN ('reply', 'mention') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
    LIMIT 100
) counted
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[]) FROM PUBLIC;

CREATE FUNCTION api.community_list_mentions_v3(
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
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id AND r.other_user_id = b.actor_id)
    ORDER BY b.created_at DESC, b.mention_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.mention_id, b.source_type, b.source_id, b.actor_id, b.mentioned_user_id, b.mentioned_username, b.created_at, a.username, a.display_name, CASE WHEN p_filter_sources THEN CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END) END FROM public.mentions b JOIN public.users a ON a.id = b.actor_id WHERE b.mentioned_user_id = p_user_id AND (NOT p_filter_sources OR ((b.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.mention_id < p_after_id))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id AND r.other_user_id = b.actor_id)
    ORDER BY b.created_at DESC, b.mention_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_mentions_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_list_inbox_v4(
p_recipient_user_id uuid, p_filter_sources boolean, p_member boolean,
p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[],
p_space_ids uuid[], p_after_created_at timestamptz,
p_after_notification_id uuid, p_row_limit integer
)
RETURNS TABLE (
    recipient_user_id uuid, notification_id uuid, created_at timestamptz,
    read_at timestamptz, rank_score numeric, source_type text, source_id uuid,
    notification_type text, payload jsonb, source_thread_id uuid, source_thread_title text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_inbox_v3(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids, p_after_created_at, p_after_notification_id,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v4(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_unread_count_v4(
p_recipient_user_id uuid, p_filter_sources boolean, p_member boolean,
p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[],
p_space_ids uuid[]
)
RETURNS TABLE (unread_count bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unread_count_v3(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v4(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[]) FROM PUBLIC;

CREATE FUNCTION api.community_list_mentions_v4(
p_user_id uuid, p_filter_sources boolean, p_member boolean,
p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[],
p_space_ids uuid[], p_after_created_at timestamptz, p_after_id uuid,
p_row_limit integer
)
RETURNS TABLE (mention_id uuid, source_type text, source_id uuid, actor_id uuid, mentioned_user_id uuid, mentioned_username text, created_at timestamptz, actor_username text, actor_display_name text, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_mentions_v3(p_user_id, p_filter_sources,
    p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids,
    p_after_created_at, p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_mentions_v4(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

-- Erasure: the erased member leaves every list, theirs and others'.
CREATE FUNCTION api.privacy_revoke_user_v7(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'MemberRelation' THEN
        DELETE FROM public.member_relations r
            WHERE r.owner_user_id = p_user_id OR r.other_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v5(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v7(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v8(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v7(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v8(text, uuid, text)
    FROM PUBLIC;

-- The export: the owner's own list, never who listed them.
CREATE FUNCTION api.portability_export_parts_v9(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('member_relations',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('username', u.username,
        'kind', r.kind, 'created_at', r.created_at,
        'updated_at', r.updated_at) ORDER BY r.created_at, u.username),
        '[]'::jsonb)
     FROM public.member_relations r
     JOIN public.users u ON u.id = r.other_user_id
     WHERE r.owner_user_id = p_user_id)))::json
FROM api.portability_export_parts_v7(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v9(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v10(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v9(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v10(uuid) FROM PUBLIC;

COMMIT;
