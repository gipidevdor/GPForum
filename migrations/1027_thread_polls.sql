-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.thread_polls (
    thread_id uuid PRIMARY KEY REFERENCES public.threads(thread_id),
    question text NOT NULL CHECK (length(btrim(question)) BETWEEN 1 AND 200),
    created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    closes_at timestamptz NOT NULL,
    closed_at timestamptz,
    CHECK (closes_at > created_at)
);
COMMENT ON TABLE public.thread_polls IS 'One single-choice poll per thread; options never change after publication.';
CREATE TABLE public.poll_options (
    thread_id uuid NOT NULL REFERENCES public.thread_polls(thread_id),
    option_number integer NOT NULL CHECK (option_number BETWEEN 1 AND 10),
    label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
    votes bigint NOT NULL DEFAULT 0 CHECK (votes >= 0),
    PRIMARY KEY(thread_id,option_number),
    UNIQUE(thread_id,label)
);
COMMENT ON TABLE public.poll_options IS 'Immutable ordered poll options with transactionally maintained vote counts.';
CREATE TABLE public.poll_ballots (
    thread_id uuid NOT NULL,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    option_number integer NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(thread_id,user_id),
    FOREIGN KEY(thread_id,option_number) REFERENCES public.poll_options(thread_id,option_number)
);
CREATE INDEX idx_poll_ballots_user ON public.poll_ballots(user_id,thread_id);
COMMENT ON TABLE public.poll_ballots IS 'One mutable single-choice ballot per member and poll, never exposed in aggregate results.';

CREATE FUNCTION api.core_product_read_thread_v1(p_actor uuid, p_thread_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE target record; viewer record; granted boolean := false; member boolean := false;
BEGIN
    SELECT t.author_user_id,t.visibility,c.category_id,c.space_id,c.visibility AS category_visibility,
        s.visibility AS space_visibility INTO target FROM public.threads t
        JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id
        WHERE t.thread_id = p_thread_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')
            AND c.deleted_at IS NULL AND s.deleted_at IS NULL;
    IF NOT FOUND THEN RETURN false; END IF;
    IF p_actor IS NOT NULL THEN
        SELECT * INTO viewer FROM api.forum_resolve_viewer_v5(p_actor);
        member := FOUND AND viewer.status = 'active' AND NOT viewer.suspended;
        IF member THEN
            SELECT EXISTS(SELECT 1 FROM json_array_elements(viewer.grants) g WHERE
                (g->>'resource_type' = 'global' AND g->>'resource_id' IS NULL AND g->>'space_id' IS NULL)
                OR (g->>'resource_type' = 'category' AND (g->>'resource_id')::uuid = target.category_id)
                OR (g->>'resource_type' = 'space' AND coalesce(g->>'resource_id',g->>'space_id')::uuid = target.space_id)) INTO granted;
        END IF;
    END IF;
    RETURN (target.space_visibility = 'public' OR (member AND target.space_visibility = 'members') OR granted)
       AND (target.category_visibility = 'public' OR (member AND target.category_visibility = 'members') OR granted)
       AND (target.visibility = 'public' OR (member AND target.visibility = 'members') OR granted
            OR (member AND target.author_user_id = p_actor));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_read_thread_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_read_v1(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_read_thread_v1(p_actor,p_thread_id) THEN
        RETURN QUERY SELECT jsonb_build_object('status','not_found'); RETURN;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('status','ok','poll',
        (SELECT jsonb_build_object('question',p.question,'closes_at',p.closes_at,
            'closed',p.closed_at IS NOT NULL OR p.closes_at <= statement_timestamp(),
            'options',(SELECT jsonb_agg(jsonb_build_object('number',o.option_number,'label',o.label,'votes',o.votes)
                ORDER BY o.option_number) FROM public.poll_options o WHERE o.thread_id = p_thread_id),
            'choice',(SELECT b.option_number FROM public.poll_ballots b WHERE b.thread_id = p_thread_id AND b.user_id = p_actor))
        FROM public.thread_polls p WHERE p.thread_id = p_thread_id),
        'can_create',EXISTS(SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id AND t.author_user_id = p_actor AND t.locked_at IS NULL),
        'can_close',EXISTS(SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id AND t.author_user_id = p_actor)
            OR api.core_product_staff_v1(p_actor,'thread','moderate'));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_read_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_read_v2(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_poll_read_v1(p_actor, p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_read_v2(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_change_v1(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; answer jsonb; thread public.threads; poll public.thread_polls;
    old_choice integer; choice integer; n integer; labels text[];
BEGIN
    IF p_operation IS NULL OR p_operation NOT IN ('create','vote','close') OR p_values IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    PERFORM 1 FROM public.users u WHERE u.id = p_actor AND u.status = 'active' FOR SHARE;
    IF NOT FOUND THEN RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN; END IF;
    IF NOT api.core_product_read_thread_v1(p_actor,p_thread_id)
        OR NOT api.core_forum_draft_target_v1(p_actor,'reply',NULL,p_thread_id) THEN
        RETURN QUERY SELECT jsonb_build_object('status','not_found'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'forum.poll.' || p_operation,
        jsonb_build_object('thread',p_thread_id,'values',p_values));
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    SELECT * INTO thread FROM public.threads t WHERE t.thread_id = p_thread_id FOR UPDATE;
    SELECT * INTO poll FROM public.thread_polls p WHERE p.thread_id = p_thread_id FOR UPDATE;
    answer := jsonb_build_object('status','ok');
    IF p_operation = 'create' THEN
        IF thread.author_user_id <> p_actor THEN answer := jsonb_build_object('status','forbidden');
        ELSIF thread.locked_at IS NOT NULL OR poll.thread_id IS NOT NULL THEN answer := jsonb_build_object('status','conflict');
        ELSIF coalesce(length(btrim(p_values->>'question')),0) NOT BETWEEN 1 AND 200
            OR jsonb_typeof(p_values->'options') IS DISTINCT FROM 'array' THEN answer := jsonb_build_object('status','invalid');
        ELSE
            IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_values->'options') x WHERE jsonb_typeof(x) <> 'string') THEN
                RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
            END IF;
            SELECT array_agg(btrim(x.label) ORDER BY x.n) INTO labels
                FROM jsonb_array_elements_text(p_values->'options') WITH ORDINALITY x(label,n);
            n := cardinality(labels);
            IF n IS NULL OR n NOT BETWEEN 2 AND 10 OR EXISTS(SELECT 1 FROM unnest(labels) x WHERE x IS NULL OR length(x) NOT BETWEEN 1 AND 120)
                OR (SELECT count(DISTINCT x) FROM unnest(labels) x) <> n THEN answer := jsonb_build_object('status','invalid');
            ELSE
                INSERT INTO public.thread_polls(thread_id,question,created_by,closes_at)
                VALUES (p_thread_id,btrim(p_values->>'question'),p_actor,clock_timestamp()+interval '30 days');
                INSERT INTO public.poll_options(thread_id,option_number,label)
                SELECT p_thread_id,x.n::integer,x.label FROM unnest(labels) WITH ORDINALITY x(label,n);
            END IF;
        END IF;
    ELSIF poll.thread_id IS NULL THEN answer := jsonb_build_object('status','not_found');
    ELSIF p_operation = 'close' THEN
        IF thread.author_user_id <> p_actor AND NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN answer := jsonb_build_object('status','forbidden');
        ELSE UPDATE public.thread_polls SET closed_at = coalesce(closed_at,clock_timestamp()) WHERE thread_id = p_thread_id; END IF;
    ELSIF thread.locked_at IS NOT NULL OR poll.closed_at IS NOT NULL OR poll.closes_at <= clock_timestamp() THEN answer := jsonb_build_object('status','closed');
    ELSIF coalesce(p_values->>'choice','') !~ '^[1-9][0-9]?$' THEN answer := jsonb_build_object('status','invalid');
    ELSE
        choice := (p_values->>'choice')::integer;
        IF NOT EXISTS(SELECT 1 FROM public.poll_options o WHERE o.thread_id = p_thread_id AND o.option_number = choice) THEN
            answer := jsonb_build_object('status','invalid');
        ELSE
            SELECT b.option_number INTO old_choice FROM public.poll_ballots b WHERE b.thread_id = p_thread_id AND b.user_id = p_actor;
            IF old_choice IS DISTINCT FROM choice THEN
                UPDATE public.poll_options o SET votes = o.votes - 1 WHERE o.thread_id = p_thread_id AND o.option_number = old_choice;
                INSERT INTO public.poll_ballots(thread_id,user_id,option_number) VALUES(p_thread_id,p_actor,choice)
                ON CONFLICT(thread_id,user_id) DO UPDATE SET option_number = EXCLUDED.option_number,updated_at = clock_timestamp();
                UPDATE public.poll_options o SET votes = o.votes + 1 WHERE o.thread_id = p_thread_id AND o.option_number = choice;
            END IF;
        END IF;
    END IF;
    IF answer->>'status' = 'ok' THEN
        PERFORM api.core_product_audit_v1(p_actor,p_command,'forum.poll.' || p_operation,p_thread_id,'thread','{}'::jsonb);
    END IF;
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_change_v1(uuid, uuid, uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_change_v2(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_poll_change_v1(p_actor, p_command, p_thread_id, p_operation, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_change_v2(uuid, uuid, uuid, text, jsonb) FROM PUBLIC;

COMMIT;
