-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Reactions on a post (ADR 0145): beside the like (109), a member may give
-- a post one of four reactions -- heart, laugh, celebrate, think -- each
-- once, and take it back; never on their own post. Each reaction is one
-- row, counted when a page is read; giving and taking back are commands
-- on the shape of the like's, with their events. Erasure deletes a
-- member's reactions and the export lists them. The thread page's one
-- read (124) answers the reactions with its other parts.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.post_reactions (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    reaction text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_reactions_pkey PRIMARY KEY (post_id, user_id, reaction),
    CONSTRAINT post_reactions_post_id_fkey FOREIGN KEY (post_id)
        REFERENCES public.posts (post_id),
    CONSTRAINT post_reactions_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES public.users (id),
    CONSTRAINT post_reactions_reaction_check CHECK (
        reaction IN ('heart', 'laugh', 'celebrate', 'think'))
);
CREATE INDEX idx_post_reactions_user ON public.post_reactions (user_id);

-- The reactions on the posts of a page: how many of each, and whether the
-- viewer gave it. A post nobody reacted to is absent.
CREATE FUNCTION api.community_post_reactions_v1(p_post_ids uuid[],
    p_viewer_user_id uuid)
RETURNS TABLE (post_id uuid, reaction text, reaction_count bigint,
    reacted boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.post_id, r.reaction, count(*)::bigint AS reaction_count,
    coalesce(bool_or(r.user_id = p_viewer_user_id), false) AS reacted
FROM public.post_reactions r
WHERE r.post_id = ANY(p_post_ids)
GROUP BY r.post_id, r.reaction
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_reactions_v1(uuid[], uuid)
    FROM PUBLIC;

-- The event a reaction given or taken back records, as the like's
-- (core_community_like_event_v1) with the reaction in the key and payload.
CREATE FUNCTION api.core_community_reaction_event_v1(p_row jsonb, p_event_type text,
    p_thread_id uuid, p_author_user_id uuid)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object(
    'actor_id', p_row -> 'user_id',
    'aggregate_id', p_row -> 'post_id',
    'aggregate_type', 'post',
    'aggregate_version', 1,
    'causation_id', NULL,
    'correlation_id', p_row -> 'correlation_id',
    'created_at', p_row -> 'created_at',
    'event_id', p_row -> 'event_id',
    'event_type', p_event_type,
    'idempotency_key', p_event_type || ':' || (p_row ->> 'post_id') || ':'
        || (p_row ->> 'reaction') || ':' || (p_row ->> 'event_id'),
    'metadata', jsonb_build_object(
        'actor', jsonb_build_object('id', p_row -> 'user_id'),
        'aggregate_id', p_row -> 'post_id',
        'causation_id', NULL,
        'correlation_id', p_row -> 'correlation_id',
        'event_id', p_row -> 'event_id',
        'timestamp', p_row -> 'created_at',
        'transport', jsonb_build_object(
            'listen_notify_channel', 'gpforum_domain_events',
            'minion_job', 'domain_event.dispatch',
            'stream', 'gpforum.domain_events')),
    'payload', jsonb_build_object(
        'author_user_id', p_author_user_id,
        'post_id', p_row -> 'post_id',
        'reaction', p_row -> 'reaction',
        'thread_id', p_thread_id,
        'user_id', p_row -> 'user_id'),
    'schema_version', 1)
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_reaction_event_v1(jsonb, text, uuid, uuid) FROM PUBLIC;

-- Giving a reaction: the post must be there to be read, the reaction one of
-- the four, the member not its author; given twice it is one.
CREATE FUNCTION api.community_react_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
    kind text := p_row ->> 'reaction';
    added integer := 0;
    total bigint;
BEGIN
    SELECT p.post_id, p.thread_id, p.author_user_id INTO target
    FROM public.posts p
    WHERE p.post_id = (p_row ->> 'post_id')::uuid
        AND p.deleted_at IS NULL AND p.moderation_state = 'visible';
    IF target.post_id IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'post not found',
            'ok', 0, 'status', 'not_found');
        RETURN;
    END IF;
    IF kind IS NULL OR kind NOT IN ('heart', 'laugh', 'celebrate', 'think') THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'unknown reaction',
            'ok', 0, 'status', 'invalid');
        RETURN;
    END IF;
    IF target.author_user_id = liker THEN
        RETURN QUERY SELECT jsonb_build_object('error',
            'a post is not reacted to by its author', 'ok', 0,
            'status', 'invalid');
        RETURN;
    END IF;
    INSERT INTO public.post_reactions (post_id, user_id, reaction, created_at)
    VALUES (target.post_id, liker, kind, (p_row ->> 'created_at')::timestamptz)
    ON CONFLICT ON CONSTRAINT post_reactions_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    IF added = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_reaction_event_v1(p_row,
            'post.reacted', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_reactions r
    WHERE r.post_id = target.post_id AND r.reaction = kind;
    RETURN QUERY SELECT jsonb_build_object('changed', added,
        'reaction', kind, 'reaction_count', total, 'reacted', 1, 'ok', 1,
        'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_post_v1(jsonb) FROM PUBLIC;

-- Taking a reaction back always goes through: it adds nothing.
CREATE FUNCTION api.community_unreact_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
    kind text := p_row ->> 'reaction';
    removed integer := 0;
    total bigint;
BEGIN
    SELECT p.post_id, p.thread_id, p.author_user_id INTO target
    FROM public.posts p
    WHERE p.post_id = (p_row ->> 'post_id')::uuid;
    IF target.post_id IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'post not found',
            'ok', 0, 'status', 'not_found');
        RETURN;
    END IF;
    DELETE FROM public.post_reactions r
    WHERE r.post_id = target.post_id AND r.user_id = liker AND r.reaction = kind;
    GET DIAGNOSTICS removed = ROW_COUNT;
    IF removed = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_reaction_event_v1(p_row,
            'post.unreacted', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_reactions r
    WHERE r.post_id = target.post_id AND r.reaction = kind;
    RETURN QUERY SELECT jsonb_build_object('changed', removed,
        'reaction', kind, 'reaction_count', total, 'reacted', 0, 'ok', 1,
        'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_post_v1(jsonb) FROM PUBLIC;

-- The answer a reaction command records, as the like's.
CREATE FUNCTION api.core_community_reaction_answer_v1(p_saved jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE WHEN (p_saved ->> 'ok')::integer = 1 THEN jsonb_build_object(
        'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
        'stored', jsonb_build_object(
            'ok', 1,
            'post_id', p_saved -> 'post_id',
            'reacted', p_saved -> 'reacted',
            'reaction', p_saved -> 'reaction',
            'reaction_count', p_saved -> 'reaction_count',
            'thread_id', p_saved -> 'thread_id',
            'user_id', p_saved -> 'user_id'))
    ELSE jsonb_build_object(
        'error', p_saved -> 'error',
        'errors', CASE WHEN p_saved ->> 'status' = 'invalid'
            THEN jsonb_build_object(CASE WHEN p_saved ->> 'error' = 'unknown reaction' THEN 'reaction' ELSE 'post_id' END, p_saved -> 'error')
            ELSE NULL END,
        'ok', 0, 'status', p_saved -> 'status', 'stored', NULL)
    END
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_reaction_answer_v1(jsonb) FROM PUBLIC;

-- The commands around giving and taking back (ADR 0126 section 5).
CREATE FUNCTION api.community_react_command_v1(p_log jsonb, p_answer jsonb,
    p_row jsonb)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved FROM api.community_react_post_v1(p_row);
        answer := api.core_community_reaction_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_command_v1(jsonb, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unreact_command_v1(p_log jsonb, p_answer jsonb,
    p_row jsonb)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved FROM api.community_unreact_post_v1(p_row);
        answer := api.core_community_reaction_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_command_v1(jsonb, jsonb, jsonb) FROM PUBLIC;

-- Erasure deletes a member's reactions (source PostReaction); every other
-- source goes on to the version before.
CREATE FUNCTION api.privacy_revoke_user_v19(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    amount bigint;
BEGIN
    IF p_source = 'PostReaction' THEN
        DELETE FROM public.post_reactions r WHERE r.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v17(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v19(text, uuid, text)
    FROM PUBLIC;

-- The export lists the member's reactions, post by post, with the rest.
CREATE FUNCTION api.portability_export_parts_v21(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('reactions',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('post_id', r.post_id,
        'reaction', r.reaction, 'created_at', r.created_at)
        ORDER BY r.created_at, r.post_id, r.reaction), '[]'::jsonb)
    FROM public.post_reactions r WHERE r.user_id = p_user_id)))::json
FROM api.portability_export_parts_v19(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v21(uuid) FROM PUBLIC;

-- The thread page's one read (124), answering the reactions too.
CREATE FUNCTION api.forum_thread_page_reads_v3(
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
    reacted boolean
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
    NULL::text, NULL::bigint, NULL::boolean
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
    NULL, NULL, NULL
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
    NULL, NULL, NULL
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
    NULL, NULL,
    NULL, NULL, NULL
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
    NULL, NULL,
    NULL, NULL, NULL
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
    NULL, NULL, NULL
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
    NULL, NULL, NULL
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
    x.reaction, x.reaction_count, x.reacted
FROM (
    SELECT pr.post_id, pr.reaction, count(*)::bigint AS reaction_count,
        coalesce(bool_or(pr.user_id = p_viewer_user_id), false) AS reacted
    FROM public.post_reactions pr
    WHERE pr.post_id = ANY(p_post_ids)
    GROUP BY pr.post_id, pr.reaction
) x
ORDER BY 1, 2
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v3(uuid, uuid[], uuid,
    text, text, uuid[], integer) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.community_post_reactions_v2(
p_post_ids uuid[], p_viewer_user_id uuid
)
RETURNS TABLE (post_id uuid, reaction text, reaction_count bigint,
    reacted boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_post_reactions_v1(p_post_ids, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_reactions_v2(uuid[], uuid)
    FROM PUBLIC;

CREATE FUNCTION api.community_react_post_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_react_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_post_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unreact_post_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unreact_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_post_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_react_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_react_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_command_v2(jsonb, jsonb, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.community_unreact_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unreact_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_command_v2(jsonb, jsonb, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v20(
p_source text, p_user_id uuid, p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v19(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v20(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v22(
p_user_id uuid
)
RETURNS TABLE (document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v21(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v22(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_reads_v4(
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
    last_read_at timestamptz,
    reaction text,
    reaction_count bigint,
    reacted boolean
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_reads_v3(p_thread_id, p_post_ids,
    p_viewer_user_id, p_engagement_target_type, p_link_target_type,
    p_link_post_ids, p_link_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v4(uuid, uuid[], uuid,
    text, text, uuid[], integer) FROM PUBLIC;

COMMIT;
