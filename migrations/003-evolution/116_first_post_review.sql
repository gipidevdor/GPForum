-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0134: the first-post review queue. A new member's first posts (while
-- they have fewer published posts than the configured count) and, when
-- staff ask for it, the posts the automod rules flag are held for review:
-- kept here, outside threads and posts, until staff approve them (the
-- application then publishes them as their author's command) or reject
-- them. Held content is in no thread, count, feed, search document, event
-- or realtime message. Every hold and decision is audited.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The review rule beside the link rule: 0 posts is the rule off.
ALTER TABLE public.automod_settings
    ADD COLUMN review_first_posts integer NOT NULL DEFAULT 0,
    ADD COLUMN review_flagged boolean NOT NULL DEFAULT false,
    ADD CONSTRAINT automod_settings_review_first_posts_check
        CHECK (review_first_posts BETWEEN 0 AND 20);

CREATE TABLE public.held_posts (
    review_id uuid NOT NULL,
    author_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    command_id text NOT NULL,
    kind text NOT NULL,
    category_id uuid,
    thread_id uuid,
    title text NOT NULL DEFAULT '',
    body_source text NOT NULL,
    body_rendered_safe text NOT NULL,
    visibility text,
    reply_to_post_id uuid,
    reason text NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'pending',
    decided_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    decided_at timestamptz,
    decision_reason text NOT NULL DEFAULT '',
    post_id uuid,
    created_at timestamptz NOT NULL,
    CONSTRAINT held_posts_pkey PRIMARY KEY (review_id),
    CONSTRAINT held_posts_command_key UNIQUE (author_user_id, command_id),
    CONSTRAINT held_posts_command_id_check
        CHECK (length(command_id) BETWEEN 1 AND 200),
    CONSTRAINT held_posts_kind_check CHECK (
        (kind = 'thread' AND category_id IS NOT NULL AND length(title) > 0)
        OR (kind = 'reply' AND thread_id IS NOT NULL)),
    CONSTRAINT held_posts_title_check CHECK (length(title) <= 300),
    CONSTRAINT held_posts_visibility_check
        CHECK (visibility IS NULL
            OR visibility IN ('public', 'members', 'private')),
    CONSTRAINT held_posts_reason_check
        CHECK (reason IN ('first_posts', 'flagged')),
    CONSTRAINT held_posts_status_check
        CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
    CONSTRAINT held_posts_decision_check CHECK (
        (status = 'pending' AND decided_at IS NULL)
        OR (status <> 'pending' AND decided_at IS NOT NULL)),
    CONSTRAINT held_posts_published_check
        CHECK (status <> 'approved' OR post_id IS NOT NULL),
    CONSTRAINT held_posts_decision_reason_check
        CHECK (length(decision_reason) <= 500)
);
CREATE INDEX idx_held_posts_pending
    ON public.held_posts (created_at, review_id) WHERE status = 'pending';
CREATE INDEX idx_held_posts_author
    ON public.held_posts (author_user_id, created_at DESC, review_id DESC);

-- Holds a post. The author's command id keys it: the same submission again
-- answers the entry it made (replayed, with its status). The draft it was
-- written in, at the revision submitted, is gone with the hold, as it is
-- when a post is published.
CREATE FUNCTION api.moderation_review_hold_v1(p_review_id uuid,
    p_author_user_id uuid, p_command_id text, p_kind text,
    p_category_id uuid, p_thread_id uuid, p_title text, p_body_source text,
    p_body_rendered_safe text, p_visibility text, p_reply_to_post_id uuid,
    p_reason text, p_details jsonb, p_draft_id uuid, p_draft_revision bigint,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, review_id uuid, review_status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_review_id IS NULL OR p_author_user_id IS NULL
        OR p_command_id IS NULL OR p_kind IS NULL
        OR p_kind NOT IN ('thread', 'reply') OR p_body_source IS NULL
        OR p_body_rendered_safe IS NULL OR p_reason IS NULL
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    INSERT INTO public.held_posts (review_id, author_user_id, command_id,
        kind, category_id, thread_id, title, body_source,
        body_rendered_safe, visibility, reply_to_post_id, reason, details,
        status, created_at)
        VALUES (p_review_id, p_author_user_id, p_command_id, p_kind,
            CASE WHEN p_kind = 'thread' THEN p_category_id END,
            CASE WHEN p_kind = 'reply' THEN p_thread_id END,
            coalesce(p_title, ''), p_body_source, p_body_rendered_safe,
            p_visibility,
            CASE WHEN p_kind = 'reply' THEN p_reply_to_post_id END,
            p_reason, coalesce(p_details, '{}'::jsonb), 'pending', p_now)
        ON CONFLICT ON CONSTRAINT held_posts_command_key DO NOTHING;
    IF NOT FOUND THEN
        SELECT h.review_id, h.status INTO held FROM public.held_posts h
            WHERE h.author_user_id = p_author_user_id
                AND h.command_id = p_command_id;
        RETURN QUERY SELECT 'replayed'::text, held.review_id, held.status;
        RETURN;
    END IF;
    IF p_draft_id IS NOT NULL THEN
        DELETE FROM public.forum_drafts d WHERE d.draft_id = p_draft_id
            AND d.owner_user_id = p_author_user_id
            AND d.draft_revision = p_draft_revision;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_review_id, 'pending'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_hold_v1(uuid, uuid, text,
    text, uuid, uuid, text, text, text, text, uuid, text, jsonb, uuid, bigint,
    timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_hold_v2(
p_review_id uuid, p_author_user_id uuid, p_command_id text, p_kind text,
p_category_id uuid, p_thread_id uuid, p_title text, p_body_source text,
p_body_rendered_safe text, p_visibility text, p_reply_to_post_id uuid,
p_reason text, p_details jsonb, p_draft_id uuid, p_draft_revision bigint,
p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, review_id uuid, review_status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_hold_v1(p_review_id, p_author_user_id,
    p_command_id, p_kind, p_category_id, p_thread_id, p_title, p_body_source,
    p_body_rendered_safe, p_visibility, p_reply_to_post_id, p_reason,
    p_details, p_draft_id, p_draft_revision, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_hold_v2(uuid, uuid, text,
    text, uuid, uuid, text, text, text, text, uuid, text, jsonb, uuid, bigint,
    timestamptz, jsonb) FROM PUBLIC;

-- The queue staff review: the pending posts, oldest first, with where each
-- was written and by whom, and how many are pending in all.
CREATE FUNCTION api.moderation_review_queue_v1(p_row_limit integer)
RETURNS TABLE(review_id uuid, kind text, author_user_id uuid,
    author_username text, category_id uuid, category_title text,
    thread_id uuid, thread_title text, title text, body_rendered_safe text,
    reason text, details jsonb, created_at timestamptz, pending_total bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.kind, h.author_user_id, u.username,
    coalesce(h.category_id, t.category_id), c.title, h.thread_id, t.title,
    h.title, h.body_rendered_safe, h.reason, h.details, h.created_at,
    (SELECT count(*) FROM public.held_posts p WHERE p.status = 'pending')
FROM public.held_posts h
JOIN public.users u ON u.id = h.author_user_id
LEFT JOIN public.threads t ON t.thread_id = h.thread_id
LEFT JOIN public.categories c
    ON c.category_id = coalesce(h.category_id, t.category_id)
WHERE h.status = 'pending'
ORDER BY h.created_at, h.review_id
LIMIT least(greatest(coalesce(p_row_limit, 50), 1), 200);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_queue_v1(integer)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_review_queue_v2(
p_row_limit integer
)
RETURNS TABLE(review_id uuid, kind text, author_user_id uuid,
    author_username text, category_id uuid, category_title text,
    thread_id uuid, thread_title text, title text, body_rendered_safe text,
    reason text, details jsonb, created_at timestamptz, pending_total bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_queue_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_queue_v2(integer)
    FROM PUBLIC;

-- An author's own held posts: those pending, and those decided in the last
-- 30 days, newest first.
CREATE FUNCTION api.moderation_review_mine_v1(p_user_id uuid,
    p_row_limit integer)
RETURNS TABLE(review_id uuid, kind text, category_id uuid,
    category_title text, thread_id uuid, thread_title text, title text,
    body_rendered_safe text, status text, decision_reason text,
    post_id uuid, created_at timestamptz, decided_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.kind, coalesce(h.category_id, t.category_id), c.title,
    h.thread_id, t.title, h.title, h.body_rendered_safe, h.status,
    h.decision_reason, h.post_id, h.created_at, h.decided_at
FROM public.held_posts h
LEFT JOIN public.threads t ON t.thread_id = h.thread_id
LEFT JOIN public.categories c
    ON c.category_id = coalesce(h.category_id, t.category_id)
WHERE h.author_user_id = p_user_id
    AND (h.status = 'pending' OR h.decided_at > now() - interval '30 days')
ORDER BY h.created_at DESC, h.review_id DESC
LIMIT least(greatest(coalesce(p_row_limit, 50), 1), 200);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v1(uuid, integer)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_review_mine_v2(
p_user_id uuid, p_row_limit integer
)
RETURNS TABLE(review_id uuid, kind text, category_id uuid,
    category_title text, thread_id uuid, thread_title text, title text,
    body_rendered_safe text, status text, decision_reason text,
    post_id uuid, created_at timestamptz, decided_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_mine_v1(p_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v2(uuid, integer)
    FROM PUBLIC;

-- One held post, locked until the transaction ends: an approval publishes
-- it and records the decision under this lock, so two staff approving at
-- once publish it once.
CREATE FUNCTION api.moderation_review_take_v1(p_review_id uuid)
RETURNS TABLE(review_id uuid, author_user_id uuid, command_id text,
    kind text, category_id uuid, thread_id uuid, title text,
    body_source text, visibility text, reply_to_post_id uuid, reason text,
    status text, post_id uuid)
LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.author_user_id, h.command_id, h.kind, h.category_id,
    h.thread_id, h.title, h.body_source, h.visibility, h.reply_to_post_id,
    h.reason, h.status, h.post_id
FROM public.held_posts h
WHERE h.review_id = p_review_id
FOR UPDATE;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_take_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_take_v2(
p_review_id uuid
)
RETURNS TABLE(review_id uuid, author_user_id uuid, command_id text,
    kind text, category_id uuid, thread_id uuid, title text,
    body_source text, visibility text, reply_to_post_id uuid, reason text,
    status text, post_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_take_v1(p_review_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_take_v2(uuid) FROM PUBLIC;

-- Decides a held post: approved (with the post it was published as),
-- rejected (with the staff's reason) or withdrawn by its author. Only a
-- pending post is decided; the same decision again is unchanged, another
-- one is refused as decided. A withdrawal by anyone but the author finds
-- nothing.
CREATE FUNCTION api.moderation_review_decide_v1(p_review_id uuid,
    p_status text, p_actor_user_id uuid, p_reason text, p_post_id uuid,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, review_status text, author_user_id uuid,
    kind text, thread_id uuid, post_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_review_id IS NULL OR p_status IS NULL
        OR p_status NOT IN ('approved', 'rejected', 'withdrawn')
        OR (p_status = 'approved' AND p_post_id IS NULL)
        OR length(coalesce(p_reason, '')) > 500
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::text, NULL::uuid,
            NULL::text, NULL::uuid, NULL::uuid;
        RETURN;
    END IF;
    SELECT h.status, h.author_user_id, h.kind, h.thread_id, h.post_id
        INTO held FROM public.held_posts h
        WHERE h.review_id = p_review_id FOR UPDATE;
    IF NOT FOUND OR (p_status = 'withdrawn'
        AND p_actor_user_id IS DISTINCT FROM held.author_user_id) THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::text, NULL::uuid,
            NULL::text, NULL::uuid, NULL::uuid;
        RETURN;
    END IF;
    IF held.status <> 'pending' THEN
        RETURN QUERY SELECT CASE WHEN held.status = p_status
                THEN 'unchanged' ELSE 'decided' END::text, held.status,
            held.author_user_id, held.kind, held.thread_id, held.post_id;
        RETURN;
    END IF;
    UPDATE public.held_posts h SET status = p_status,
        decided_by_user_id = p_actor_user_id, decided_at = p_now,
        decision_reason = coalesce(p_reason, ''),
        post_id = CASE WHEN p_status = 'approved' THEN p_post_id END
        WHERE h.review_id = p_review_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_status, held.author_user_id, held.kind,
        held.thread_id,
        CASE WHEN p_status = 'approved' THEN p_post_id END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_decide_v1(uuid, text, uuid,
    text, uuid, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_decide_v2(
p_review_id uuid, p_status text, p_actor_user_id uuid, p_reason text,
p_post_id uuid, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, review_status text, author_user_id uuid,
    kind text, thread_id uuid, post_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_decide_v1(p_review_id, p_status,
    p_actor_user_id, p_reason, p_post_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_decide_v2(uuid, text, uuid,
    text, uuid, timestamptz, jsonb) FROM PUBLIC;

-- Sets the review rule. The audit carries the rule before; setting the
-- rule it already is changes nothing.
CREATE FUNCTION api.moderation_review_settings_set_v1(p_first_posts integer,
    p_flagged boolean, p_actor_user_id uuid, p_now timestamptz,
    p_audit jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record; before jsonb;
BEGIN
    IF p_first_posts IS NULL OR p_first_posts NOT BETWEEN 0 AND 20
        OR p_flagged IS NULL OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026101501, 2);
    SELECT s.review_first_posts, s.review_flagged INTO held
        FROM public.automod_settings s WHERE s.singleton;
    IF FOUND AND held.review_first_posts = p_first_posts
        AND held.review_flagged = p_flagged THEN
        RETURN QUERY SELECT 'unchanged'::text;
        RETURN;
    END IF;
    before := jsonb_build_object(
        'review_first_posts', coalesce(held.review_first_posts, 0),
        'review_flagged', coalesce(held.review_flagged, false));
    INSERT INTO public.automod_settings (singleton, review_first_posts,
        review_flagged, updated_by_user_id, updated_at)
        VALUES (true, p_first_posts, p_flagged, p_actor_user_id, p_now)
        ON CONFLICT (singleton) DO UPDATE SET
            review_first_posts = EXCLUDED.review_first_posts,
            review_flagged = EXCLUDED.review_flagged,
            updated_by_user_id = EXCLUDED.updated_by_user_id,
            updated_at = EXCLUDED.updated_at;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object('metadata',
        coalesce(p_audit -> 'metadata', '{}'::jsonb)
        || jsonb_build_object('before', before)), false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_settings_set_v1(integer,
    boolean, uuid, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_settings_set_v2(
p_first_posts integer, p_flagged boolean, p_actor_user_id uuid,
p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_review_settings_set_v1(p_first_posts,
    p_flagged, p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_settings_set_v2(integer,
    boolean, uuid, timestamptz, jsonb) FROM PUBLIC;

-- The rules a write is screened by, now with the review rule and, while
-- that rule is on, how many of the author's posts are published and not
-- hidden or deleted (counted up to 20, the rule's largest number).
CREATE FUNCTION api.moderation_automod_rules_v3(p_user_id uuid)
RETURNS TABLE(document json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'review_first_posts', coalesce(s.review_first_posts, 0),
    'review_flagged', coalesce(s.review_flagged, false),
    'published_posts', CASE WHEN coalesce(s.review_first_posts, 0) > 0
        AND p_user_id IS NOT NULL THEN (SELECT count(*) FROM (
            SELECT 1 FROM public.posts p
            WHERE p.author_user_id = p_user_id AND p.deleted_at IS NULL
                AND p.moderation_state IN ('visible', 'locked')
            LIMIT 20) published) END))::json
FROM api.moderation_automod_rules_v1(p_user_id) previous
LEFT JOIN public.automod_settings s ON s.singleton;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v3(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_rules_v4(
p_user_id uuid
)
RETURNS TABLE(document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_rules_v3(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v4(uuid) FROM PUBLIC;

-- An erased member's held posts go with them.
CREATE FUNCTION api.privacy_revoke_user_v9(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'HeldPost' THEN
        DELETE FROM public.held_posts h WHERE h.author_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v7(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v9(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v10(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v9(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v10(text, uuid, text)
    FROM PUBLIC;

-- The export: the member's own held posts, as written, with their
-- decisions; never who decided.
CREATE FUNCTION api.portability_export_parts_v11(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('held_posts',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', h.kind,
        'category_id', h.category_id, 'thread_id', h.thread_id,
        'title', h.title, 'body_source', h.body_source,
        'status', h.status, 'decision_reason', h.decision_reason,
        'post_id', h.post_id, 'created_at', h.created_at,
        'decided_at', h.decided_at) ORDER BY h.created_at, h.review_id),
        '[]'::jsonb)
     FROM public.held_posts h
     WHERE h.author_user_id = p_user_id)))::json
FROM api.portability_export_parts_v9(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v11(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v12(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v11(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v12(uuid) FROM PUBLIC;

COMMIT;
