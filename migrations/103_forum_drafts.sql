-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.forum_drafts (
    draft_id uuid PRIMARY KEY,
    owner_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('thread','reply')),
    category_id uuid,
    thread_id uuid,
    title text NOT NULL DEFAULT '' CHECK (length(title) <= 300),
    body_source text NOT NULL DEFAULT '' CHECK (length(body_source) <= 50000),
    visibility text CHECK (visibility IN ('public','members','private')),
    command_id text NOT NULL CHECK (length(command_id) BETWEEN 1 AND 200),
    draft_revision bigint NOT NULL CHECK (draft_revision > 0),
    save_base_revision bigint NOT NULL,
    save_command_id text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    CHECK ((kind = 'thread' AND thread_id IS NULL)
        OR (kind = 'reply' AND thread_id IS NOT NULL AND category_id IS NULL)),
    CHECK (updated_at >= created_at AND expires_at > updated_at)
);
CREATE INDEX idx_forum_drafts_owner_updated
    ON public.forum_drafts(owner_user_id, updated_at DESC, draft_id DESC);
CREATE INDEX idx_forum_drafts_expires ON public.forum_drafts(expires_at);

CREATE FUNCTION api.core_forum_draft_target_v1(p_owner_user_id uuid,
    p_kind text, p_category_id uuid, p_thread_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE target record; viewer record; granted boolean;
BEGIN
    SELECT * INTO viewer FROM api.forum_resolve_viewer_v1(p_owner_user_id);
    IF NOT FOUND OR viewer.status <> 'active' OR viewer.suspended THEN RETURN false; END IF;
    IF p_kind = 'thread' AND p_category_id IS NULL AND p_thread_id IS NULL THEN RETURN true; END IF;
    IF p_kind = 'thread' AND p_thread_id IS NULL THEN
        SELECT c.category_id, c.space_id, c.visibility AS category_visibility,
            s.visibility AS space_visibility, NULL::text AS thread_visibility,
            NULL::uuid AS author_user_id INTO target
        FROM public.categories c JOIN public.spaces s ON s.space_id = c.space_id
        WHERE c.category_id = p_category_id AND c.deleted_at IS NULL;
    ELSIF p_kind = 'reply' AND p_category_id IS NULL THEN
        SELECT c.category_id, c.space_id, c.visibility AS category_visibility,
            s.visibility AS space_visibility, t.visibility AS thread_visibility,
            t.author_user_id INTO target
        FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        WHERE t.thread_id = p_thread_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible','locked') AND c.deleted_at IS NULL;
    ELSE RETURN false;
    END IF;
    IF NOT FOUND THEN RETURN false; END IF;
    SELECT EXISTS (SELECT 1 FROM json_array_elements(viewer.grants) g WHERE
        (g->>'resource_type' = 'global' AND g->>'resource_id' IS NULL AND g->>'space_id' IS NULL)
        OR (g->>'resource_type' = 'category' AND (g->>'resource_id')::uuid = target.category_id)
        OR (g->>'resource_type' = 'space'
            AND coalesce(g->>'resource_id',g->>'space_id')::uuid = target.space_id)) INTO granted;
    RETURN target.space_visibility IN ('public','members','private')
        AND target.category_visibility IN ('public','members','private')
        AND (target.space_visibility <> 'private' OR granted)
        AND (target.category_visibility <> 'private' OR granted)
        AND (target.thread_visibility IS NULL
            OR target.thread_visibility IN ('public','members')
            OR (target.thread_visibility = 'private'
                AND (granted OR target.author_user_id = p_owner_user_id)));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_draft_target_v1(uuid,text,uuid,uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_find_v1(p_owner_user_id uuid, p_draft_id uuid, p_now timestamptz)
RETURNS TABLE(draft json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT to_json(d) FROM public.forum_drafts d
JOIN public.users u ON u.id = d.owner_user_id
WHERE d.owner_user_id = p_owner_user_id AND d.draft_id = p_draft_id
    AND d.expires_at > p_now AND u.deleted_at IS NULL AND u.status = 'active';
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_find_v1(uuid,uuid,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_list_v1(p_owner_user_id uuid, p_now timestamptz)
RETURNS TABLE(draft json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (to_jsonb(d) - 'body_source' - 'save_base_revision' - 'save_command_id')::json FROM public.forum_drafts d
JOIN public.users u ON u.id = d.owner_user_id
WHERE d.owner_user_id = p_owner_user_id AND d.expires_at > p_now
    AND u.deleted_at IS NULL AND u.status = 'active'
ORDER BY d.updated_at DESC, d.draft_id DESC LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_list_v1(uuid,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_save_v1(p_owner_user_id uuid, p_draft_id uuid,
    p_draft_revision bigint, p_kind text, p_category_id uuid, p_thread_id uuid,
    p_title text, p_body_source text, p_visibility text, p_command_id text,
    p_now timestamptz)
RETURNS TABLE(status text, draft json, error text) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.forum_drafts; nonce text := p_command_id; amount bigint;
BEGIN
    IF p_draft_id IS NULL OR p_draft_revision IS NULL OR p_draft_revision < 0
        OR p_kind IS NULL OR p_kind NOT IN ('thread','reply')
        OR p_title IS NULL OR length(p_title) > 300
        OR p_body_source IS NULL OR length(p_body_source) > 50000
        OR p_command_id IS NULL OR length(p_command_id) NOT BETWEEN 1 AND 200
        OR (p_visibility IS NOT NULL AND p_visibility NOT IN ('public','members','private'))
        OR (p_kind = 'thread' AND p_thread_id IS NOT NULL)
        OR (p_kind = 'reply' AND (p_thread_id IS NULL OR p_category_id IS NOT NULL)) THEN
        RETURN QUERY SELECT 'invalid'::text,NULL::json,'invalid draft'::text; RETURN;
    END IF;
    -- One account lock serializes quota checks and prevents save after erasure.
    PERFORM 1 FROM public.users u WHERE u.id = p_owner_user_id
        AND u.status = 'active' AND u.deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'forbidden'::text,NULL::json,'account unavailable'::text; RETURN; END IF;
    DELETE FROM public.forum_drafts d WHERE d.owner_user_id = p_owner_user_id AND d.expires_at <= p_now;
    SELECT d.* INTO held FROM public.forum_drafts d WHERE d.draft_id = p_draft_id FOR UPDATE;
    IF FOUND AND held.owner_user_id <> p_owner_user_id THEN
        RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft not found'::text; RETURN;
    END IF;
    IF held.draft_id IS NOT NULL THEN
        IF (held.save_base_revision = p_draft_revision AND held.save_command_id = p_command_id)
            AND held.kind = p_kind AND held.category_id IS NOT DISTINCT FROM p_category_id
            AND held.thread_id IS NOT DISTINCT FROM p_thread_id AND held.title = p_title
            AND held.body_source = p_body_source AND held.visibility IS NOT DISTINCT FROM p_visibility THEN
            RETURN QUERY SELECT 'ok'::text,to_json(held),NULL::text; RETURN;
        END IF;
        IF held.draft_revision = p_draft_revision AND held.command_id = p_command_id
            AND held.kind = p_kind AND held.category_id IS NOT DISTINCT FROM p_category_id
            AND held.thread_id IS NOT DISTINCT FROM p_thread_id AND held.title = p_title
            AND held.body_source = p_body_source AND held.visibility IS NOT DISTINCT FROM p_visibility
            AND NOT EXISTS (SELECT 1 FROM public.command_log c WHERE c.idempotency_key=held.command_id) THEN
            UPDATE public.forum_drafts d SET updated_at=greatest(p_now,d.updated_at),
                expires_at=greatest(p_now,d.updated_at)+interval '30 days'
            WHERE d.draft_id=p_draft_id RETURNING d.* INTO held;
            RETURN QUERY SELECT 'ok'::text,to_json(held),NULL::text; RETURN;
        END IF;
        IF held.draft_revision <> p_draft_revision THEN
            RETURN QUERY SELECT 'conflict'::text,NULL::json,'draft changed'::text; RETURN;
        END IF;
        IF held.kind <> p_kind OR held.thread_id IS DISTINCT FROM p_thread_id THEN
            RETURN QUERY SELECT 'invalid'::text,NULL::json,'draft context changed'::text; RETURN;
        END IF;
        -- The server's publish nonce survives refreshes and ordinary saves.
        nonce := held.command_id;
    ELSIF EXISTS (SELECT 1 FROM public.command_log c WHERE c.idempotency_key=p_command_id)
        OR p_draft_revision <> 0 THEN
        RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft not found'::text; RETURN;
    ELSE
        SELECT count(*) INTO amount FROM public.forum_drafts d WHERE d.owner_user_id = p_owner_user_id;
        IF amount >= 100 THEN RETURN QUERY SELECT 'limit'::text,NULL::json,'draft limit reached'::text; RETURN; END IF;
    END IF;
    IF NOT api.core_forum_draft_target_v1(p_owner_user_id,p_kind,p_category_id,p_thread_id) THEN
        RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft target unavailable'::text; RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM public.command_log c WHERE c.idempotency_key = nonce) THEN
        nonce := api.core_uuid_v7_v1()::text;
    END IF;
    IF held.draft_id IS NULL THEN
        INSERT INTO public.forum_drafts(draft_id,owner_user_id,kind,category_id,thread_id,
            title,body_source,visibility,command_id,draft_revision,save_base_revision,
            save_command_id,created_at,updated_at,expires_at)
        VALUES (p_draft_id,p_owner_user_id,p_kind,p_category_id,p_thread_id,p_title,
            p_body_source,p_visibility,nonce,1,p_draft_revision,p_command_id,p_now,p_now,
            p_now + interval '30 days') RETURNING * INTO held;
    ELSE
        UPDATE public.forum_drafts d SET category_id=p_category_id,title=p_title,
            body_source=p_body_source,visibility=p_visibility,command_id=nonce,
            draft_revision=d.draft_revision+1,save_base_revision=p_draft_revision,
            save_command_id=p_command_id,updated_at=greatest(p_now,d.updated_at),
            expires_at=greatest(p_now,d.updated_at)+interval '30 days'
        WHERE d.draft_id=p_draft_id RETURNING d.* INTO held;
    END IF;
    RETURN QUERY SELECT 'ok'::text,to_json(held),NULL::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_save_v1(uuid,uuid,bigint,text,uuid,uuid,text,text,text,text,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_remove_v1(p_owner_user_id uuid, p_draft_id uuid,
    p_draft_revision bigint, p_now timestamptz)
RETURNS TABLE(status text, draft json, error text) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.forum_drafts;
BEGIN
    SELECT d.* INTO held FROM public.forum_drafts d
        WHERE d.draft_id=p_draft_id AND d.owner_user_id=p_owner_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft not found'::text; RETURN; END IF;
    IF p_draft_revision IS NULL OR held.draft_revision <> p_draft_revision THEN
        RETURN QUERY SELECT 'conflict'::text,NULL::json,'draft changed'::text; RETURN;
    END IF;
    DELETE FROM public.forum_drafts d WHERE d.draft_id=p_draft_id;
    RETURN QUERY SELECT 'ok'::text,NULL::json,NULL::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_remove_v1(uuid,uuid,bigint,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_purge_v1(p_now timestamptz,p_row_limit integer)
RETURNS TABLE(deleted bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    DELETE FROM public.forum_drafts d WHERE d.draft_id IN (
        SELECT expired.draft_id FROM public.forum_drafts expired
        WHERE expired.expires_at <= p_now ORDER BY expired.expires_at,expired.draft_id
        LIMIT least(greatest(coalesce(p_row_limit,100),1),1000)
        FOR UPDATE SKIP LOCKED);
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN QUERY SELECT amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_purge_v1(timestamptz,integer) FROM PUBLIC;

CREATE FUNCTION api.core_forum_draft_publish_v1(p_owner_user_id uuid,p_draft_id uuid,
    p_draft_revision bigint,p_kind text,p_category_id uuid,p_thread_id uuid,
    p_command_id text,p_now timestamptz,p_prepared boolean)
RETURNS text LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.forum_drafts;
BEGIN
    PERFORM 1 FROM public.users u WHERE u.id=p_owner_user_id
        AND u.status='active' AND u.deleted_at IS NULL FOR KEY SHARE;
    IF NOT FOUND THEN RETURN 'account unavailable'; END IF;
    SELECT d.* INTO held FROM public.forum_drafts d
        WHERE d.draft_id=p_draft_id AND d.owner_user_id=p_owner_user_id FOR UPDATE;
    IF NOT FOUND OR held.expires_at <= p_now THEN RETURN 'draft not found'; END IF;
    IF held.draft_revision IS DISTINCT FROM p_draft_revision
        OR held.command_id IS DISTINCT FROM p_command_id THEN RETURN 'draft changed'; END IF;
    IF held.kind IS DISTINCT FROM p_kind OR (p_prepared AND
        (held.category_id IS DISTINCT FROM p_category_id
            OR held.thread_id IS DISTINCT FROM p_thread_id)) THEN RETURN 'draft context changed'; END IF;
    IF NOT api.core_forum_draft_target_v1(p_owner_user_id,held.kind,held.category_id,held.thread_id) THEN
        RETURN 'draft target unavailable'; END IF;
    RETURN NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_draft_publish_v1(uuid,uuid,bigint,text,uuid,uuid,text,timestamptz,boolean) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_find_v2(p_owner_user_id uuid, p_draft_id uuid, p_now timestamptz)
RETURNS TABLE(draft json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_find_v1(p_owner_user_id, p_draft_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_find_v2(uuid,uuid,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_list_v2(p_owner_user_id uuid, p_now timestamptz)
RETURNS TABLE(draft json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_list_v1(p_owner_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_list_v2(uuid,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_save_v2(p_owner_user_id uuid, p_draft_id uuid,
    p_draft_revision bigint, p_kind text, p_category_id uuid, p_thread_id uuid,
    p_title text, p_body_source text, p_visibility text, p_command_id text,
    p_now timestamptz)
RETURNS TABLE(status text, draft json, error text) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_save_v1(p_owner_user_id, p_draft_id, p_draft_revision, p_kind, p_category_id, p_thread_id, p_title, p_body_source, p_visibility, p_command_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_save_v2(uuid,uuid,bigint,text,uuid,uuid,text,text,text,text,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_remove_v2(p_owner_user_id uuid, p_draft_id uuid,
    p_draft_revision bigint, p_now timestamptz)
RETURNS TABLE(status text, draft json, error text) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_remove_v1(p_owner_user_id, p_draft_id, p_draft_revision, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_remove_v2(uuid,uuid,bigint,timestamptz) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_purge_v2(p_now timestamptz,p_row_limit integer)
RETURNS TABLE(deleted bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_draft_purge_v1(p_now,p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_purge_v2(timestamptz,integer) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v3(p_log jsonb,p_answer jsonb,p_store_type text,p_command jsonb,p_record jsonb, p_draft_id uuid, p_draft_revision bigint)
RETURNS TABLE(outcome text,response json,stored json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE existing public.command_log; held record; reported text;
    command_id text := p_log->>'command_id';
    payload jsonb := jsonb_build_object('request_hash',p_log->>'request_hash');
    answer jsonb := p_answer; written jsonb; message text; status text; draft_error text;
BEGIN
    IF p_draft_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('forum.draft.publish:' || (p_log->>'idempotency_key'),0));
    END IF;
    SELECT me.* INTO existing FROM public.command_log me
        WHERE me.idempotency_key = p_log->>'idempotency_key' LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
        RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
    END IF;
    IF p_draft_id IS NOT NULL THEN
        draft_error := api.core_forum_draft_publish_v1((p_log->>'actor_id')::uuid,
            p_draft_id,p_draft_revision,
            CASE WHEN p_store_type='thread.created' THEN 'thread' ELSE 'invalid' END,
            (p_command #>> '{thread,category_id}')::uuid,NULL,
            p_log->>'idempotency_key',(p_log->>'command_at')::timestamptz,p_answer IS NULL);
        IF draft_error IS NOT NULL THEN
            RETURN QUERY SELECT 'recorded'::text,
                json_build_object('ok',0,'status','conflict','error',draft_error),NULL::json;
            RETURN;
        END IF;
    END IF;
    BEGIN
        INSERT INTO public.command_log(actor_id,command_id,command_type,correlation_id,
            created_at,handled_at,idempotency_key,payload,response_hash,status)
        VALUES ((p_log->>'actor_id')::uuid,command_id::uuid,p_log->>'command_type',
            (p_log->>'command_correlation_id')::uuid,(p_log->>'command_at')::timestamptz,
            NULL,p_log->>'idempotency_key',payload,NULL,'accepted');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF api.core_unique_on_v1(reported,'command_log_pkey') THEN
            SELECT me.* INTO existing FROM public.command_log me WHERE me.command_id = command_id::uuid;
            IF NOT FOUND OR existing.idempotency_key IS NULL OR existing.idempotency_key <> p_log->>'idempotency_key' THEN
                command_id := api.core_uuid_v7_v1()::text;
                INSERT INTO public.command_log(actor_id,command_id,command_type,correlation_id,
                    created_at,handled_at,idempotency_key,payload,response_hash,status)
                VALUES ((p_log->>'actor_id')::uuid,command_id::uuid,p_log->>'command_type',
                    (p_log->>'command_correlation_id')::uuid,(p_log->>'command_at')::timestamptz,
                    NULL,p_log->>'idempotency_key',payload,NULL,'accepted');
            ELSIF jsonb_typeof(existing.payload) = 'object' AND existing.payload ? 'response' THEN
                SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
                RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
            ELSE command_id := existing.command_id::text; payload := coalesce(existing.payload,'{}'::jsonb);
            END IF;
        ELSIF api.core_unique_on_v1(reported,'command_log_idempotency_key_key') THEN
            SELECT me.* INTO existing FROM public.command_log me WHERE me.idempotency_key = p_log->>'idempotency_key' LIMIT 1;
            IF NOT FOUND THEN RAISE; END IF;
            SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
            RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
        ELSE RAISE;
        END IF;
    END;
    IF answer IS NULL THEN
        SELECT result.stored::jsonb INTO written FROM api.forum_store_write_v1(p_store_type,p_command,p_record) result;
        IF api.core_perl_true_v1(written->>'ok') THEN
            answer := jsonb_build_object('ok',1,'status','ok');
            IF written ? 'post' THEN answer := answer || jsonb_build_object('post_id',written #> '{post,post_id}'); END IF;
            IF written ? 'thread' THEN
                answer := answer || jsonb_build_object('thread_id',written #> '{thread,thread_id}');
                IF p_log->>'command_type' = 'thread.edit' THEN
                    answer := answer || jsonb_build_object('slug',written #> '{thread,slug}','title',written #> '{thread,title}');
                ELSIF p_log->>'command_type' = 'thread.move' THEN
                    answer := answer || jsonb_build_object('category_id',written #> '{thread,category_id}');
                END IF;
            ELSIF written ? 'post' THEN answer := answer || jsonb_build_object('thread_id',written #> '{post,thread_id}'); END IF;
        ELSE
            message := written->>'error';
            status := CASE WHEN message IN ('thread not found','post not found') THEN 'not_found' ELSE 'forbidden' END;
            answer := jsonb_build_object('ok',0,'status',status,'error',message);
        END IF;
    END IF;
    UPDATE public.command_log me SET handled_at = (p_log->>'command_at')::timestamptz,
        payload = payload || jsonb_build_object('response',answer),
        response_hash = encode(sha256(convert_to(api.core_canonical_json_v1(answer),'UTF8')),'hex'),
        status = CASE WHEN api.core_perl_true_v1(answer->>'ok') THEN 'handled' ELSE 'rejected' END
        WHERE me.command_id = command_id::uuid;
    IF p_draft_id IS NOT NULL AND api.core_perl_true_v1(answer->>'ok') THEN
        DELETE FROM public.forum_drafts d WHERE d.draft_id=p_draft_id;
    END IF;
    RETURN QUERY SELECT 'recorded'::text,answer::json,written::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v3(jsonb,jsonb,text,jsonb,jsonb,uuid,bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v4(p_log jsonb,p_answer jsonb,p_store_type text,p_command jsonb,p_record jsonb, p_draft_id uuid, p_draft_revision bigint)
RETURNS TABLE(outcome text,response json,stored json) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_write_command_v3(p_log, p_answer, p_store_type, p_command, p_record, p_draft_id, p_draft_revision);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v4(jsonb,jsonb,text,jsonb,jsonb,uuid,bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v3(
    p_idempotency_key text,
    p_command_type text,
    p_actor_id text,
    p_request_hash text,
    p_command_id text,
    p_command_correlation_id text,
    p_command_at text,
    p_answer jsonb,
    p_store_refusals jsonb,
    p_post_id text,
    p_thread_id text,
    p_author_user_id text,
    p_current_body_id text,
    p_current_revision_id text,
    p_position bigint,
    p_visibility text,
    p_moderation_state text,
    p_version bigint,
    p_visibility_version bigint,
    p_permission_version bigint,
    p_hidden_at text,
    p_locked_at text,
    p_deleted_at text,
    p_deleted_by text,
    p_body_id text,
    p_body_post_id text,
    p_body_format text,
    p_body_source text,
    p_body_rendered_safe text,
    p_source_hash text,
    p_revision_id text,
    p_revision_post_id text,
    p_revision_body_id text,
    p_editor_user_id text,
    p_revision_number integer,
    p_edit_reason text,
    p_correlation_id text,
    p_event_id text,
    p_outbox_id text,
    p_audit_id text,
    p_recorded_at text
, p_draft_id uuid, p_draft_revision bigint)
RETURNS TABLE (
    outcome text,
    response json,
    skipped boolean,
    post_id text,
    thread_id text,
    author_user_id text,
    current_body_id text,
    current_revision_id text,
    "position" text,
    visibility text,
    moderation_state text,
    version text,
    visibility_version text,
    permission_version text,
    hidden_at text,
    locked_at text,
    deleted_at text,
    deleted_by text
)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    existing public.command_log;
    held record;
    row_command_id text := p_command_id;
    held_payload jsonb := jsonb_build_object('request_hash', p_request_hash);
    from_store boolean := false;
    reported text;
    answer jsonb;
    stored record;
    draft_error text;
BEGIN
    IF p_draft_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('forum.draft.publish:' || p_idempotency_key,0));
    END IF;
    SELECT me.* INTO existing FROM public.command_log me
    WHERE me.idempotency_key = p_idempotency_key
    LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held
        FROM api.core_command_existing_v1(existing.payload, p_request_hash);
        RETURN QUERY SELECT held.outcome, held.response::json,
            NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text;
        RETURN;
    END IF;

    IF p_draft_id IS NOT NULL THEN
        draft_error := api.core_forum_draft_publish_v1(p_actor_id::uuid,p_draft_id,
            p_draft_revision,'reply',NULL,p_thread_id::uuid,p_idempotency_key,
            p_command_at::timestamptz,p_answer IS NULL);
        IF draft_error IS NOT NULL THEN
            RETURN QUERY SELECT 'recorded'::text,
                json_build_object('ok',0,'status','conflict','error',draft_error),
                NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text;
            RETURN;
        END IF;
    END IF;
    BEGIN
        INSERT INTO public.command_log (actor_id, command_id, command_type,
            correlation_id, created_at, handled_at, idempotency_key, payload,
            response_hash, status)
        VALUES (p_actor_id::uuid, p_command_id::uuid, p_command_type,
            p_command_correlation_id::uuid, p_command_at::timestamptz, NULL,
            p_idempotency_key, held_payload, NULL, 'accepted');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF api.core_unique_on_v1(reported, 'command_log_pkey') THEN
            SELECT me.* INTO existing FROM public.command_log me
            WHERE me.command_id = p_command_id::uuid;
            IF NOT FOUND OR existing.idempotency_key IS NULL
                OR existing.idempotency_key <> p_idempotency_key
            THEN
                row_command_id := api.core_uuid_v7_v1()::text;
                INSERT INTO public.command_log (actor_id, command_id,
                    command_type, correlation_id, created_at, handled_at,
                    idempotency_key, payload, response_hash, status)
                VALUES (p_actor_id::uuid, row_command_id::uuid,
                    p_command_type, p_command_correlation_id::uuid,
                    p_command_at::timestamptz, NULL, p_idempotency_key,
                    held_payload, NULL, 'accepted');
            ELSIF jsonb_typeof(existing.payload) = 'object'
                AND existing.payload ? 'response'
            THEN
                SELECT * INTO held FROM api.core_command_existing_v1(
                    existing.payload, p_request_hash);
                RETURN QUERY SELECT held.outcome, held.response::json,
                    NULL::boolean, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::text, NULL::text;
                RETURN;
            ELSE
                row_command_id := existing.command_id::text;
                held_payload := CASE
                    WHEN jsonb_typeof(existing.payload) = 'object'
                    THEN existing.payload ELSE '{}'::jsonb END;
            END IF;
        ELSIF api.core_unique_on_v1(reported,
            'command_log_idempotency_key_key') THEN
            SELECT me.* INTO existing FROM public.command_log me
            WHERE me.idempotency_key = p_idempotency_key
            LIMIT 1;
            IF NOT FOUND THEN
                RAISE;
            END IF;
            SELECT * INTO held
            FROM api.core_command_existing_v1(existing.payload,
                p_request_hash);
            RETURN QUERY SELECT held.outcome, held.response::json,
                NULL::boolean, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text;
            RETURN;
        ELSE
            RAISE;
        END IF;
    END;

    IF p_answer IS NOT NULL THEN
        answer := p_answer;
    ELSE
        from_store := true;
        SELECT * INTO stored FROM api.core_forum_store_reply_v1(p_post_id,
            p_thread_id, p_author_user_id, p_current_body_id,
            p_current_revision_id, p_position, p_visibility,
            p_moderation_state, p_version, p_visibility_version,
            p_permission_version, p_hidden_at, p_locked_at, p_deleted_at,
            p_deleted_by, p_body_id, p_body_post_id, p_body_format,
            p_body_source, p_body_rendered_safe, p_source_hash,
            p_revision_id, p_revision_post_id, p_revision_body_id,
            p_editor_user_id, p_revision_number, p_edit_reason,
            p_idempotency_key, p_correlation_id, p_event_id, p_outbox_id,
            p_audit_id, p_recorded_at);
        answer := CASE WHEN stored.refusal IS NOT NULL
            THEN p_store_refusals -> stored.refusal
            ELSE jsonb_build_object('ok', 1,
                'post_id', stored.post_id,
                'status', 'ok',
                'thread_id', stored.thread_id) END;
        IF answer IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'invalid_parameter_value',
                MESSAGE = 'p_store_refusals has no words for '
                    || stored.refusal;
        END IF;
    END IF;

    UPDATE public.command_log me
    SET handled_at = p_command_at::timestamptz,
        payload = held_payload || jsonb_build_object('response', answer),
        response_hash = encode(sha256(convert_to(
            api.core_canonical_json_v1(answer), 'UTF8')), 'hex'),
        status = CASE WHEN api.core_perl_true_v1(answer ->> 'ok')
            THEN 'handled' ELSE 'rejected' END
    WHERE me.command_id = row_command_id::uuid;

    IF p_draft_id IS NOT NULL AND api.core_perl_true_v1(answer->>'ok') THEN
        DELETE FROM public.forum_drafts d WHERE d.draft_id=p_draft_id;
    END IF;

    IF NOT from_store THEN
        RETURN QUERY SELECT 'recorded'::text, answer::json, NULL::boolean,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'recorded'::text, answer::json, stored.skipped,
        stored.post_id, stored.thread_id, stored.author_user_id,
        stored.current_body_id, stored.current_revision_id, stored.position,
        stored.visibility, stored.moderation_state, stored.version,
        stored.visibility_version, stored.permission_version,
        stored.hidden_at, stored.locked_at, stored.deleted_at,
        stored.deleted_by;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v3(text,text,text,text,text,text,text,jsonb,jsonb,text,text,text,text,text,bigint,text,text,bigint,bigint,bigint,text,text,text,text,text,text,text,text,text,text,text,text,text,text,integer,text,text,text,text,text,text,uuid,bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v4(
    p_idempotency_key text,
    p_command_type text,
    p_actor_id text,
    p_request_hash text,
    p_command_id text,
    p_command_correlation_id text,
    p_command_at text,
    p_answer jsonb,
    p_store_refusals jsonb,
    p_post_id text,
    p_thread_id text,
    p_author_user_id text,
    p_current_body_id text,
    p_current_revision_id text,
    p_position bigint,
    p_visibility text,
    p_moderation_state text,
    p_version bigint,
    p_visibility_version bigint,
    p_permission_version bigint,
    p_hidden_at text,
    p_locked_at text,
    p_deleted_at text,
    p_deleted_by text,
    p_body_id text,
    p_body_post_id text,
    p_body_format text,
    p_body_source text,
    p_body_rendered_safe text,
    p_source_hash text,
    p_revision_id text,
    p_revision_post_id text,
    p_revision_body_id text,
    p_editor_user_id text,
    p_revision_number integer,
    p_edit_reason text,
    p_correlation_id text,
    p_event_id text,
    p_outbox_id text,
    p_audit_id text,
    p_recorded_at text
, p_draft_id uuid, p_draft_revision bigint)
RETURNS TABLE (
    outcome text,
    response json,
    skipped boolean,
    post_id text,
    thread_id text,
    author_user_id text,
    current_body_id text,
    current_revision_id text,
    "position" text,
    visibility text,
    moderation_state text,
    version text,
    visibility_version text,
    permission_version text,
    hidden_at text,
    locked_at text,
    deleted_at text,
    deleted_by text
)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_create_reply_v3(p_idempotency_key, p_command_type, p_actor_id, p_request_hash, p_command_id, p_command_correlation_id, p_command_at, p_answer, p_store_refusals, p_post_id, p_thread_id, p_author_user_id, p_current_body_id, p_current_revision_id, p_position, p_visibility, p_moderation_state, p_version, p_visibility_version, p_permission_version, p_hidden_at, p_locked_at, p_deleted_at, p_deleted_by, p_body_id, p_body_post_id, p_body_format, p_body_source, p_body_rendered_safe, p_source_hash, p_revision_id, p_revision_post_id, p_revision_body_id, p_editor_user_id, p_revision_number, p_edit_reason, p_correlation_id, p_event_id, p_outbox_id, p_audit_id, p_recorded_at, p_draft_id, p_draft_revision);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v4(text,text,text,text,text,text,text,jsonb,jsonb,text,text,text,text,text,bigint,text,text,bigint,bigint,bigint,text,text,text,text,text,text,text,text,text,text,text,text,text,text,integer,text,text,text,text,text,text,uuid,bigint) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v3(p_source text,p_user_id uuid,p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source='ForumDraft' THEN
        DELETE FROM public.forum_drafts d WHERE d.owner_user_id=p_user_id;
        GET DIAGNOSTICS amount=ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE RETURN QUERY SELECT * FROM api.privacy_revoke_user_v1(p_source,p_user_id,p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v3(text,uuid,text) FROM PUBLIC;
CREATE FUNCTION api.privacy_revoke_user_v4(p_source text,p_user_id uuid,p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v3(p_source,p_user_id,p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v4(text,uuid,text) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v3(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('drafts',
    (SELECT coalesce(jsonb_agg(to_jsonb(d) - 'save_base_revision' - 'save_command_id'),'[]'::jsonb)
        FROM public.forum_drafts d WHERE d.owner_user_id=p_user_id AND d.expires_at>now())))::json
FROM api.portability_export_parts_v1(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v3(uuid) FROM PUBLIC;
CREATE FUNCTION api.portability_export_parts_v4(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v3(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v4(uuid) FROM PUBLIC;

COMMIT;
