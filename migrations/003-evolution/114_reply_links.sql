-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A reply may answer one post in particular (ADR 0132): the link is a row
-- of its own, written after the reply, so the reply command is as it was.
-- A link holds only when both posts are in the same thread and the post
-- answered is there to be read; a link written twice is one. The page
-- reads, for its posts, which post each answers, with its position and
-- its author's name, in one call.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.post_replies (
    post_id uuid NOT NULL,
    reply_to_post_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_replies_pkey PRIMARY KEY (post_id),
    CONSTRAINT post_replies_post_id_fkey FOREIGN KEY (post_id)
        REFERENCES public.posts (post_id),
    CONSTRAINT post_replies_reply_to_post_id_fkey FOREIGN KEY (reply_to_post_id)
        REFERENCES public.posts (post_id),
    CONSTRAINT post_replies_not_self_check CHECK (post_id <> reply_to_post_id)
);
CREATE INDEX idx_post_replies_target ON public.post_replies (reply_to_post_id);

CREATE FUNCTION api.forum_link_reply_v1(p_post_id uuid, p_reply_to_post_id uuid)
RETURNS TABLE (linked boolean)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    added integer := 0;
BEGIN
    INSERT INTO public.post_replies (post_id, reply_to_post_id)
    SELECT reply.post_id, target.post_id
    FROM public.posts reply
    JOIN public.posts target ON target.thread_id = reply.thread_id
    WHERE reply.post_id = p_post_id
        AND target.post_id = p_reply_to_post_id
        AND target.post_id <> reply.post_id
        AND target.deleted_at IS NULL
        AND target.moderation_state = 'visible'
    ON CONFLICT ON CONSTRAINT post_replies_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    RETURN QUERY SELECT added = 1
        OR EXISTS (SELECT 1 FROM public.post_replies r
            WHERE r.post_id = p_post_id
                AND r.reply_to_post_id = p_reply_to_post_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_link_reply_v1(uuid, uuid) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.forum_link_reply_v2(
p_post_id uuid, p_reply_to_post_id uuid
)
RETURNS TABLE (linked boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_link_reply_v1(p_post_id, p_reply_to_post_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_link_reply_v2(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_reply_targets_v1(p_post_ids uuid[])
RETURNS TABLE (post_id uuid, reply_to_post_id uuid, reply_to_position bigint,
    reply_to_author_username text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.post_id, r.reply_to_post_id, target.position, author.username
FROM public.post_replies r
JOIN public.posts target ON target.post_id = r.reply_to_post_id
LEFT JOIN public.users author ON author.id = target.author_user_id
WHERE r.post_id = ANY(p_post_ids)
$$;
REVOKE EXECUTE ON FUNCTION api.forum_reply_targets_v1(uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_reply_targets_v2(
p_post_ids uuid[]
)
RETURNS TABLE (post_id uuid, reply_to_post_id uuid, reply_to_position bigint,
    reply_to_author_username text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_reply_targets_v1(p_post_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_reply_targets_v2(uuid[]) FROM PUBLIC;

COMMIT;
