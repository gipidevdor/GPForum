-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.thread_transfers (
    transfer_id uuid PRIMARY KEY,
    actor_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    source_id uuid NOT NULL REFERENCES public.threads(thread_id),
    target_id uuid NOT NULL REFERENCES public.threads(thread_id),
    operation text NOT NULL CHECK (operation IN ('move','split','merge')),
    post_ids uuid[] NOT NULL,
    original_positions bigint[] NOT NULL,
    new_positions bigint[] NOT NULL,
    reply_links jsonb NOT NULL DEFAULT '[]',
    reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
    created_at timestamptz NOT NULL DEFAULT now(),
    undone_at timestamptz,
    CHECK (source_id <> target_id),
    CHECK (cardinality(post_ids) BETWEEN 1 AND 1000),
    CHECK (cardinality(post_ids) = cardinality(original_positions) AND cardinality(post_ids) = cardinality(new_positions))
);
CREATE UNIQUE INDEX idx_thread_transfers_redirect ON public.thread_transfers(source_id) INCLUDE(target_id)
    WHERE operation = 'merge' AND undone_at IS NULL;
CREATE INDEX idx_thread_transfers_created ON public.thread_transfers(created_at DESC,transfer_id DESC);
COMMENT ON TABLE public.thread_transfers IS 'Bounded staff post transfers with original positions and severed reply links for safe reversal.';

CREATE FUNCTION api.core_product_thread_event_v1(p_actor uuid, p_command uuid, p_thread_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE t public.threads; stamp text := clock_timestamp()::text;
BEGIN
    SELECT * INTO t FROM public.threads x WHERE x.thread_id = p_thread_id;
    PERFORM api.core_forum_record_write_v1('thread.updated',jsonb_build_object(
        'idempotency_key',p_command::text || ':' || p_thread_id::text,
        'thread',jsonb_build_object('thread_id',p_thread_id,'editor_user_id',p_actor)),
        to_jsonb(t),jsonb_build_object('correlation_id',p_command,'recorded_at',stamp,
            'event_id',api.core_uuid_v7_v1(),'outbox_id',api.core_uuid_v7_v1()),NULL,false);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_thread_event_v1(uuid, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.core_product_thread_recount_v1(p_thread_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE total bigint; visible bigint; last_id uuid; last_at timestamptz;
BEGIN
    SELECT greatest(count(*)-1,0),count(*) FILTER(WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible' AND p.position <> 1)
        INTO total,visible FROM public.posts p WHERE p.thread_id = p_thread_id;
    SELECT p.post_id,p.created_at INTO last_id,last_at FROM public.posts p
        WHERE p.thread_id = p_thread_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
        ORDER BY p.position DESC LIMIT 1;
    INSERT INTO public.thread_counters(thread_id,reply_count,visible_reply_count,last_post_id,last_activity_at)
        VALUES(p_thread_id,total,visible,last_id,coalesce(last_at,clock_timestamp()))
        ON CONFLICT(thread_id) DO UPDATE SET reply_count = EXCLUDED.reply_count,visible_reply_count = EXCLUDED.visible_reply_count,
            last_post_id = EXCLUDED.last_post_id,last_activity_at = EXCLUDED.last_activity_at,
            version = public.thread_counters.version+1,reconciled_at = clock_timestamp();
    UPDATE public.threads t SET last_activity_at = coalesce(last_at,t.created_at),updated_at = clock_timestamp(),
        version = t.version+1 WHERE t.thread_id = p_thread_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_thread_recount_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_v1(p_actor uuid, p_command uuid, p_source_id uuid, p_target_id uuid, p_operation text, p_post_numbers bigint[], p_title text, p_reason text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; source public.threads; target public.threads; destination uuid := p_target_id;
    selected uuid[]; positions bigint[]; new_positions bigint[]; links jsonb; base bigint; first_author uuid; answer jsonb;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    IF p_source_id IS NULL OR p_operation IS NULL OR p_operation NOT IN ('move','split','merge')
        OR coalesce(length(btrim(p_reason)),0) NOT BETWEEN 1 AND 500
        OR (p_operation <> 'split' AND (p_target_id IS NULL OR p_target_id = p_source_id))
        OR (p_operation = 'split' AND (p_target_id IS NOT NULL OR coalesce(length(btrim(p_title)),0) NOT BETWEEN 1 AND 200)) THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'moderation.thread_transfer',
        jsonb_build_object('source',p_source_id,'target',p_target_id,'operation',p_operation,'posts',p_post_numbers,'title',p_title,'reason',p_reason));
    IF opened.outcome <> 'opened' THEN RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN; END IF;
    -- The reply allocator takes this same row; two-thread commands always lock
    -- UUID order, before touching posts or counters.
    PERFORM 1 FROM public.threads t WHERE t.thread_id IN (p_source_id,p_target_id) ORDER BY t.thread_id FOR UPDATE;
    SELECT * INTO source FROM public.threads t WHERE t.thread_id = p_source_id;
    SELECT * INTO target FROM public.threads t WHERE t.thread_id = p_target_id;
    IF source.thread_id IS NULL OR source.deleted_at IS NOT NULL OR source.moderation_state <> 'visible'
        OR source.visibility NOT IN ('public','members') OR source.locked_at IS NOT NULL
        OR NOT api.core_product_read_thread_v1(p_actor,p_source_id)
        OR (p_operation <> 'split' AND (target.thread_id IS NULL OR target.deleted_at IS NOT NULL
            OR target.moderation_state <> 'visible' OR target.locked_at IS NOT NULL
            OR target.category_id <> source.category_id OR target.visibility <> source.visibility
            OR NOT api.core_product_read_thread_v1(p_actor,p_target_id)))
        OR EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id IN(p_source_id,p_target_id)) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    IF p_operation <> 'merge' AND (coalesce(cardinality(p_post_numbers),0) NOT BETWEEN 1 AND 1000
        OR cardinality(p_post_numbers) <> (SELECT count(DISTINCT x) FROM unnest(p_post_numbers) x)) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
    END IF;
    SELECT array_agg(x.post_id ORDER BY x.position),array_agg(x.position ORDER BY x.position)
        INTO selected,positions FROM (SELECT p.post_id,p.position FROM public.posts p WHERE p.thread_id = p_source_id
        AND (p_operation = 'merge' OR p.position = ANY(p_post_numbers)) ORDER BY p.position LIMIT 1001) x;
    IF coalesce(cardinality(selected),0) NOT BETWEEN 1 AND 1000
        OR (p_operation <> 'merge' AND (cardinality(selected) <> cardinality(p_post_numbers) OR 1 = ANY(positions))) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
    END IF;
    IF EXISTS(SELECT 1 FROM public.posts p WHERE p.post_id = ANY(selected) AND p.visibility = 'private') THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    IF p_operation = 'split' THEN
        destination := api.core_uuid_v7_v1();
        SELECT p.author_user_id INTO first_author FROM public.posts p WHERE p.post_id = selected[1];
        INSERT INTO public.threads(thread_id,category_id,author_user_id,title,slug,visibility)
        VALUES(destination,source.category_id,first_author,btrim(p_title),'discussion-' || destination::text,source.visibility);
    END IF;
    SELECT coalesce(max(p.position),0) INTO base FROM public.posts p WHERE p.thread_id = destination;
    SELECT array_agg(base+x.n ORDER BY x.n) INTO new_positions FROM generate_series(1,cardinality(selected)) x(n);
    WITH map AS (SELECT x.id,x.position FROM unnest(selected,new_positions) x(id,position))
    UPDATE public.posts p SET thread_id = destination,position = map.position,version = p.version+1,
        visibility_version = p.visibility_version+1,permission_version = p.permission_version+1,updated_at = clock_timestamp()
    FROM map WHERE p.post_id = map.id;
    -- Preserve the links that stop being meaningful in one thread, for undo.
    WITH removed AS (DELETE FROM public.post_replies r USING public.posts child,public.posts parent
        WHERE child.post_id = r.post_id AND parent.post_id = r.reply_to_post_id AND child.thread_id <> parent.thread_id
            AND (r.post_id = ANY(selected) OR r.reply_to_post_id = ANY(selected)) RETURNING r.*)
    SELECT coalesce(jsonb_agg(to_jsonb(removed)),'[]'::jsonb) INTO links FROM removed;
    IF p_operation = 'merge' THEN
        UPDATE public.threads SET deleted_at = clock_timestamp(),deleted_by = p_actor,moderation_state = 'deleted',
            visibility_version = visibility_version+1,permission_version = permission_version+1 WHERE thread_id = p_source_id;
    END IF;
    INSERT INTO public.thread_transfers(transfer_id,actor_id,source_id,target_id,operation,post_ids,original_positions,new_positions,reply_links,reason)
    VALUES(p_command,p_actor,p_source_id,destination,p_operation,selected,positions,new_positions,links,btrim(p_reason));
    PERFORM api.core_product_thread_recount_v1(p_source_id);
    PERFORM api.core_product_thread_recount_v1(destination);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,p_source_id);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,destination);
    PERFORM api.core_product_audit_v1(p_actor,p_command,'moderation.thread_transfer',p_source_id,'thread',
        jsonb_build_object('target',destination,'operation',p_operation,'count',cardinality(selected),'transfer',p_command));
    answer := jsonb_build_object('status','ok','target_id',destination,'transfer_id',p_command,'count',cardinality(selected));
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_v1(uuid, uuid, uuid, uuid, text, bigint[], text, text) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_v2(p_actor uuid, p_command uuid, p_source_id uuid, p_target_id uuid, p_operation text, p_post_numbers bigint[], p_title text, p_reason text)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_thread_transfer_v1(p_actor, p_command, p_source_id, p_target_id, p_operation, p_post_numbers, p_title, p_reason);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_v2(uuid, uuid, uuid, uuid, text, bigint[], text, text) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_undo_v1(p_actor uuid, p_command uuid, p_transfer_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; held public.thread_transfers; answer jsonb;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'moderation.thread_transfer_undo',jsonb_build_object('transfer',p_transfer_id));
    IF opened.outcome <> 'opened' THEN RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN; END IF;
    SELECT * INTO held FROM public.thread_transfers x WHERE x.transfer_id = p_transfer_id;
    IF held.transfer_id IS NULL THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','not_found')); RETURN;
    END IF;
    PERFORM 1 FROM public.threads t WHERE t.thread_id IN(held.source_id,held.target_id) ORDER BY t.thread_id FOR UPDATE;
    SELECT * INTO held FROM public.thread_transfers x WHERE x.transfer_id = p_transfer_id FOR UPDATE;
    IF held.undone_at IS NOT NULL THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','ok','target_id',held.source_id)); RETURN;
    END IF;
    IF (SELECT count(DISTINCT (t.category_id,t.visibility)) FROM public.threads t WHERE t.thread_id IN(held.source_id,held.target_id)) <> 1
        OR (held.operation = 'split' AND EXISTS(SELECT 1 FROM public.posts p WHERE p.thread_id = held.target_id AND NOT(p.post_id = ANY(held.post_ids))))
        OR EXISTS(SELECT 1 FROM public.posts p WHERE p.post_id = ANY(held.post_ids) AND p.visibility = 'private')
        OR EXISTS(SELECT 1 FROM public.threads t WHERE t.thread_id IN(held.source_id,held.target_id)
            AND (t.visibility NOT IN('public','members') OR (t.deleted_at IS NOT NULL AND NOT(t.thread_id = held.source_id AND held.operation = 'merge'))))
        OR (SELECT count(*) FROM public.posts p JOIN unnest(held.post_ids,held.new_positions) x(id,position)
            ON p.post_id = x.id AND p.position = x.position WHERE p.thread_id = held.target_id) <> cardinality(held.post_ids)
        OR EXISTS(SELECT 1 FROM public.posts p WHERE p.thread_id = held.source_id AND p.position = ANY(held.original_positions))
        OR EXISTS(SELECT 1 FROM public.post_replies r WHERE r.reply_to_post_id = ANY(held.post_ids) AND NOT(r.post_id = ANY(held.post_ids)))
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(held.reply_links) x
            LEFT JOIN public.posts child ON child.post_id = (x->>'post_id')::uuid
            LEFT JOIN public.posts parent ON parent.post_id = (x->>'reply_to_post_id')::uuid
            WHERE child.post_id IS NULL OR parent.post_id IS NULL
                OR (CASE WHEN child.post_id = ANY(held.post_ids) THEN held.source_id ELSE child.thread_id END)
                    <> (CASE WHEN parent.post_id = ANY(held.post_ids) THEN held.source_id ELSE parent.thread_id END)
                OR EXISTS(SELECT 1 FROM public.post_replies r WHERE r.post_id = child.post_id AND r.reply_to_post_id <> parent.post_id))
        OR EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id IN(held.source_id,held.target_id)) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    UPDATE public.posts p SET thread_id = held.source_id,position = x.position,version = p.version+1,
        visibility_version = p.visibility_version+1,permission_version = p.permission_version+1
    FROM unnest(held.post_ids,held.original_positions) x(id,position) WHERE p.post_id = x.id;
    INSERT INTO public.post_replies(post_id,reply_to_post_id,created_at)
    SELECT (x->>'post_id')::uuid,(x->>'reply_to_post_id')::uuid,(x->>'created_at')::timestamptz
        FROM jsonb_array_elements(held.reply_links) x ON CONFLICT(post_id) DO NOTHING;
    IF held.operation = 'merge' THEN
        UPDATE public.threads SET deleted_at = NULL,deleted_by = NULL,moderation_state = 'visible',
            visibility_version = visibility_version+1,permission_version = permission_version+1 WHERE thread_id = held.source_id;
    ELSIF held.operation = 'split' AND NOT EXISTS(SELECT 1 FROM public.posts p WHERE p.thread_id = held.target_id) THEN
        UPDATE public.threads SET deleted_at = clock_timestamp(),deleted_by = p_actor,moderation_state = 'deleted' WHERE thread_id = held.target_id;
    END IF;
    UPDATE public.thread_transfers SET undone_at = clock_timestamp() WHERE transfer_id = p_transfer_id;
    PERFORM api.core_product_thread_recount_v1(held.source_id);
    PERFORM api.core_product_thread_recount_v1(held.target_id);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,held.source_id);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,held.target_id);
    PERFORM api.core_product_audit_v1(p_actor,p_command,'moderation.thread_transfer_undo',held.source_id,'thread',jsonb_build_object('transfer',p_transfer_id));
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','ok','target_id',held.source_id));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_undo_v1(uuid, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_undo_v2(p_actor uuid, p_command uuid, p_transfer_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_thread_transfer_undo_v1(p_actor, p_command, p_transfer_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_undo_v2(uuid, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfers_v1(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('status','ok','transfers',coalesce((SELECT jsonb_agg(x) FROM (
        SELECT t.transfer_id,t.source_id,t.target_id,t.operation,t.created_at,t.undone_at,cardinality(t.post_ids) AS post_count
        FROM public.thread_transfers t ORDER BY t.created_at DESC,t.transfer_id DESC LIMIT 100) x),'[]'::jsonb));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfers_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfers_v2(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_thread_transfers_v1(p_actor);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfers_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_redirect_v1(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (target_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH RECURSIVE chain(id,depth) AS (
    SELECT p_thread_id,0 UNION ALL
    SELECT x.target_id,c.depth+1 FROM chain c JOIN public.thread_transfers x ON x.source_id = c.id
    WHERE x.operation = 'merge' AND x.undone_at IS NULL AND c.depth < 16
)
SELECT c.id FROM chain c WHERE c.depth > 0 AND api.core_product_read_thread_v1(p_actor,c.id)
ORDER BY c.depth DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_redirect_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_redirect_v2(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (target_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_redirect_v1(p_actor, p_thread_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_redirect_v2(uuid, uuid) FROM PUBLIC;

COMMIT;
