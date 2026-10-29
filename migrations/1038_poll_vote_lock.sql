-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- A vote on a thread's poll locked the thread's row FOR UPDATE for the length
-- of the vote, so a reply arriving meanwhile -- which updates the thread's
-- activity -- waited for the vote, and the votes of a lively thread queued
-- behind its replies. The vote reads the thread (its author, whether it is
-- locked) and needs it to stay a thread: FOR KEY SHARE keeps it from being
-- deleted under the vote and lets a reply's update through. The poll's own
-- row stays locked FOR UPDATE, which is what keeps two votes from counting
-- over each other. The body is forum_poll_change_v1's; v2, the boundary the
-- previous release's workers call, stays until a release later (ADR 0126,
-- section 2).
CREATE FUNCTION api.forum_poll_change_v3(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb)
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
    SELECT * INTO thread FROM public.threads t WHERE t.thread_id = p_thread_id FOR KEY SHARE;
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
REVOKE EXECUTE ON FUNCTION api.forum_poll_change_v3(uuid, uuid, uuid, text, jsonb) FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.forum_poll_change_v4(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_poll_change_v3(p_actor, p_command, p_thread_id, p_operation, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_change_v4(uuid, uuid, uuid, text, jsonb) FROM PUBLIC;
