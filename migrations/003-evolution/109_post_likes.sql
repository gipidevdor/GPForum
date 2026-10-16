-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A member likes a post, once, and may take the like back (ADR 0129). A
-- like is a row of its own, so the count a page shows is counted from the
-- rows and never drifts; the author of a post cannot like it; a post that
-- is not visible takes no like. Each like and unlike is an event, for the
-- cache of the public pages that show the count. Erasing an account deletes
-- its likes; a member's export lists them. The erasure and the export are
-- new versions, as ADR 0126 section 2 asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.post_likes (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_likes_pkey PRIMARY KEY (post_id, user_id),
    CONSTRAINT post_likes_post_id_fkey FOREIGN KEY (post_id)
        REFERENCES public.posts (post_id),
    CONSTRAINT post_likes_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES public.users (id)
);
CREATE INDEX idx_post_likes_user_created
    ON public.post_likes (user_id, created_at DESC);

-- The likes on the posts of a page, with whether the viewer gave one; a post
-- with none has no row.
CREATE FUNCTION api.community_post_likes_v1(p_post_ids uuid[],
    p_viewer_user_id uuid)
RETURNS TABLE (post_id uuid, like_count bigint, liked boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT l.post_id, count(*)::bigint AS like_count,
    coalesce(bool_or(l.user_id = p_viewer_user_id), false) AS liked
FROM public.post_likes l
WHERE l.post_id = ANY(p_post_ids)
GROUP BY l.post_id
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_likes_v1(uuid[], uuid)
    FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.community_post_likes_v2(
p_post_ids uuid[], p_viewer_user_id uuid
)
RETURNS TABLE (post_id uuid, like_count bigint, liked boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_post_likes_v1(p_post_ids, p_viewer_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_likes_v2(uuid[], uuid)
    FROM PUBLIC;

-- The event a like or an unlike records, as EventRecorder shapes one: the
-- row carries the ids the store drew (event, outbox, correlation) and the
-- time it stamped.
CREATE FUNCTION api.core_community_like_event_v1(p_row jsonb, p_event_type text,
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
        || (p_row ->> 'event_id'),
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
        'thread_id', p_thread_id,
        'user_id', p_row -> 'user_id'),
    'schema_version', 1)
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_like_event_v1(jsonb, text, uuid,
    uuid) FROM PUBLIC;

-- Liking a post: refused when the post is not there to be read, or is the
-- liker's own; a like already given is kept, and no second event is
-- recorded for it. Answers with the count as it then is.
CREATE FUNCTION api.community_like_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
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
    IF target.author_user_id = liker THEN
        RETURN QUERY SELECT jsonb_build_object('error',
            'a post is not liked by its author', 'ok', 0,
            'status', 'invalid');
        RETURN;
    END IF;
    INSERT INTO public.post_likes (post_id, user_id, created_at)
    VALUES (target.post_id, liker, (p_row ->> 'created_at')::timestamptz)
    ON CONFLICT ON CONSTRAINT post_likes_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    IF added = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_like_event_v1(p_row,
            'post.liked', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_likes l
    WHERE l.post_id = target.post_id;
    RETURN QUERY SELECT jsonb_build_object('changed', added,
        'like_count', total, 'liked', 1, 'ok', 1, 'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_post_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_like_post_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_like_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_post_v2(jsonb) FROM PUBLIC;

-- Taking a like back: allowed whatever became of the post, since nothing
-- is added; a like not given is nothing to take back, and no event.
CREATE FUNCTION api.community_unlike_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
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
    DELETE FROM public.post_likes l
    WHERE l.post_id = target.post_id AND l.user_id = liker;
    GET DIAGNOSTICS removed = ROW_COUNT;
    IF removed = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_like_event_v1(p_row,
            'post.unliked', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_likes l
    WHERE l.post_id = target.post_id;
    RETURN QUERY SELECT jsonb_build_object('changed', removed,
        'like_count', total, 'liked', 0, 'ok', 1, 'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_post_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unlike_post_v2(
p_row jsonb
)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unlike_post_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_post_v2(jsonb) FROM PUBLIC;

-- The command's answer as the Perl path records one: the public fields of
-- the like under ok, or the refusal with its status.
CREATE FUNCTION api.core_community_like_answer_v1(p_saved jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE WHEN (p_saved ->> 'ok')::integer = 1 THEN jsonb_build_object(
        'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
        'stored', jsonb_build_object(
            'like_count', p_saved -> 'like_count',
            'liked', p_saved -> 'liked',
            'ok', 1,
            'post_id', p_saved -> 'post_id',
            'thread_id', p_saved -> 'thread_id',
            'user_id', p_saved -> 'user_id'))
    ELSE jsonb_build_object(
        'error', p_saved -> 'error',
        'errors', CASE WHEN p_saved ->> 'status' = 'invalid'
            THEN jsonb_build_object('post_id', p_saved -> 'error')
            ELSE NULL END,
        'ok', 0, 'status', p_saved -> 'status', 'stored', NULL)
    END
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_like_answer_v1(jsonb) FROM PUBLIC;

-- Liking as one command: the command log around api.community_like_post_v1,
-- as api.community_bookmark_command_v1 is around a bookmark.
CREATE FUNCTION api.community_like_command_v1(p_log jsonb, p_answer jsonb,
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
        SELECT result INTO saved FROM api.community_like_post_v1(p_row);
        answer := api.core_community_like_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.community_like_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_like_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_command_v2(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- Taking a like back as one command, the same around
-- api.community_unlike_post_v1.
CREATE FUNCTION api.community_unlike_command_v1(p_log jsonb, p_answer jsonb,
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
        SELECT result INTO saved FROM api.community_unlike_post_v1(p_row);
        answer := api.core_community_like_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_command_v1(jsonb, jsonb,
    jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_unlike_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_unlike_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_command_v2(jsonb, jsonb,
    jsonb) FROM PUBLIC;

-- Erasing an account takes its likes with it (source PostLike); every other
-- source is as it was.
CREATE FUNCTION api.privacy_revoke_user_v5(p_source text, p_user_id uuid,
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
    IF p_source = 'PostLike' THEN
        DELETE FROM public.post_likes l WHERE l.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v3(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v5(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v6(
p_source text, p_user_id uuid, p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v5(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v6(text, uuid, text)
    FROM PUBLIC;

-- A member's export lists the posts they liked and when.
CREATE FUNCTION api.portability_export_parts_v5(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('likes',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('post_id', l.post_id,
        'created_at', l.created_at) ORDER BY l.created_at, l.post_id),
        '[]'::jsonb)
    FROM public.post_likes l WHERE l.user_id = p_user_id)))::json
FROM api.portability_export_parts_v3(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v5(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v6(
p_user_id uuid
)
RETURNS TABLE (document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v5(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v6(uuid) FROM PUBLIC;

COMMIT;
