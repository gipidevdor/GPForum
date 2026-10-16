-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause
-- ADR 0126: the remaining author writes, their command log and durable
-- event/audit/outbox records. Dispatch selects fixed statements; no SQL text
-- comes from callers. Helpers are private, versioned and plan-pinned.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.core_forum_record_write_v1(p_type text, p_command jsonb,
    p_row jsonb, p_record jsonb, p_causation text DEFAULT NULL,
    p_audit boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE
    aggregate text := split_part(p_type, '.', 1);
    part jsonb := p_command -> aggregate;
    actor text;
    fields text[];
    audit_fields text[];
    name text;
    value jsonb;
    payload jsonb := '{}'::jsonb;
    audit_metadata jsonb := '{}'::jsonb;
    stamp jsonb := p_record -> 'recorded_at';
    event_key text;
    event jsonb;
BEGIN
    CASE p_type
      WHEN 'thread.created' THEN
        actor := 'author_user_id';
        fields := ARRAY['author_user_id','category_id','thread_id','title','visibility'];
        audit_fields := ARRAY['title'];
      WHEN 'thread.updated' THEN
        actor := 'editor_user_id'; fields := ARRAY['editor_user_id','slug','thread_id','title'];
        audit_fields := ARRAY['slug','title'];
      WHEN 'thread.moved' THEN
        actor := 'editor_user_id'; fields := ARRAY['category_id','editor_user_id','previous_category_id','thread_id'];
        audit_fields := ARRAY['category_id','previous_category_id'];
      WHEN 'thread.deleted' THEN
        actor := 'deleted_by'; fields := ARRAY['category_id','deleted_by','thread_id'];
        audit_fields := ARRAY['category_id'];
      WHEN 'thread.undeleted' THEN
        actor := 'restored_by'; fields := ARRAY['author_user_id','category_id','restored_by','thread_id'];
        audit_fields := ARRAY['category_id'];
      WHEN 'post.created' THEN
        actor := 'author_user_id'; fields := ARRAY['author_user_id','post_id','revision_id','thread_id'];
        audit_fields := ARRAY['thread_id'];
      WHEN 'post.updated' THEN
        actor := 'editor_user_id'; fields := ARRAY['editor_user_id','post_id','revision_id','thread_id'];
        audit_fields := ARRAY['revision_id','thread_id'];
      WHEN 'post.deleted' THEN
        actor := 'deleted_by'; fields := ARRAY['deleted_by','post_id','thread_id'];
        audit_fields := ARRAY['thread_id'];
      WHEN 'post.undeleted' THEN
        actor := 'restored_by'; fields := ARRAY['author_user_id','post_id','restored_by','thread_id'];
        audit_fields := ARRAY['thread_id'];
      ELSE RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'unknown forum event type';
    END CASE;
    FOREACH name IN ARRAY fields || audit_fields LOOP
        value := CASE WHEN name = 'revision_id' THEN p_command #> '{revision,revision_id}'
            WHEN ((aggregate = 'thread' AND name = ANY(ARRAY['author_user_id','category_id','slug','title']))
                OR (aggregate = 'post' AND name = ANY(ARRAY['author_user_id','thread_id'])))
                AND api.core_perl_true_v1(p_row ->> name) THEN p_row -> name
            ELSE part -> name END;
        IF name = ANY(fields) THEN
            payload := payload || jsonb_build_object(name, value);
        END IF;
        IF name = ANY(audit_fields) THEN
            audit_metadata := audit_metadata || jsonb_build_object(name, value);
        END IF;
    END LOOP;
    event_key := CASE WHEN length(coalesce(p_command ->> 'idempotency_key','')) > 0
        THEN 'command:' || (p_command ->> 'idempotency_key') || ':' || p_type
        ELSE p_type || ':' || (part ->> (aggregate || '_id')) END;
    event := api.core_record_event_v1(jsonb_build_object(
        'actor_id', part -> actor, 'aggregate_id', part -> (aggregate || '_id'),
        'aggregate_type', aggregate, 'aggregate_version', 1,
        'causation_id', p_causation, 'correlation_id', p_record -> 'correlation_id',
        'created_at', stamp, 'event_id', p_record -> 'event_id',
        'event_type', p_type, 'idempotency_key', event_key,
        'metadata', jsonb_build_object('actor', jsonb_build_object('id', part -> actor),
            'aggregate_id', part -> (aggregate || '_id'), 'causation_id', p_causation,
            'correlation_id', p_record -> 'correlation_id', 'event_id', p_record -> 'event_id',
            'timestamp', stamp, 'transport', jsonb_build_object(
                'listen_notify_channel','gpforum_domain_events',
                'minion_job','domain_event.dispatch', 'stream','gpforum.domain_events')),
        'payload', payload, 'schema_version', 1), p_record ->> 'outbox_id');
    IF p_audit THEN
        PERFORM api.core_record_audit_v1(p_type, part ->> actor,
            p_record ->> 'audit_id', p_record ->> 'correlation_id',
            p_record ->> 'recorded_at', audit_metadata, 1,
            part ->> (aggregate || '_id'), aggregate);
    END IF;
    RETURN event;
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_record_write_v1(text,jsonb,jsonb,jsonb,text,boolean) FROM PUBLIC;

CREATE FUNCTION api.core_forum_thread_opening_v1(p_command jsonb, p_thread jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE
    command jsonb := p_command;
    post jsonb := command -> 'post';
    counter jsonb := command -> 'counter';
    stored public.posts;
    reported text;
    owner text;
BEGIN
    BEGIN
        INSERT INTO public.posts(author_user_id,current_body_id,current_revision_id,
            deleted_at,deleted_by,hidden_at,locked_at,moderation_state,permission_version,
            position,post_id,thread_id,version,visibility,visibility_version)
        VALUES ((post->>'author_user_id')::uuid,(post->>'current_body_id')::uuid,
            (post->>'current_revision_id')::uuid,(post->>'deleted_at')::timestamptz,
            (post->>'deleted_by')::uuid,(post->>'hidden_at')::timestamptz,
            (post->>'locked_at')::timestamptz,post->>'moderation_state',
            (post->>'permission_version')::bigint,(post->>'position')::bigint,
            (post->>'post_id')::uuid,(post->>'thread_id')::uuid,(post->>'version')::bigint,
            post->>'visibility',(post->>'visibility_version')::bigint);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'posts_pkey') THEN RAISE; END IF;
        SELECT me.* INTO stored FROM public.posts me WHERE me.post_id = (post->>'post_id')::uuid;
        IF NOT FOUND OR stored.thread_id::text <> post->>'thread_id' THEN
            command := api.core_forum_with_new_id_v1(command,'post');
            post := command -> 'post';
            INSERT INTO public.posts(author_user_id,current_body_id,current_revision_id,
                deleted_at,deleted_by,hidden_at,locked_at,moderation_state,permission_version,
                position,post_id,thread_id,version,visibility,visibility_version)
            VALUES ((post->>'author_user_id')::uuid,(post->>'current_body_id')::uuid,
                (post->>'current_revision_id')::uuid,(post->>'deleted_at')::timestamptz,
                (post->>'deleted_by')::uuid,(post->>'hidden_at')::timestamptz,
                (post->>'locked_at')::timestamptz,post->>'moderation_state',
                (post->>'permission_version')::bigint,(post->>'position')::bigint,
                (post->>'post_id')::uuid,(post->>'thread_id')::uuid,(post->>'version')::bigint,
                post->>'visibility',(post->>'visibility_version')::bigint);
        ELSE
            post := to_jsonb(stored);
            SELECT me.post_id::text INTO owner FROM public.post_bodies me
                WHERE me.body_id = (command #>> '{body,body_id}')::uuid;
            IF FOUND AND owner = command #>> '{body,post_id}' THEN
                RETURN jsonb_build_object('command',command,'post',post,'thread',p_thread,'skipped',true);
            END IF;
        END IF;
    END;
    command := api.core_forum_store_body_v1(command);
    command := api.core_forum_store_revision_v1(command);
    BEGIN
        INSERT INTO public.thread_counters(thread_id,reply_count,visible_reply_count,
            last_post_id,version,reconciled_at)
        VALUES ((counter->>'thread_id')::uuid,(counter->>'reply_count')::bigint,
            (counter->>'visible_reply_count')::bigint,(counter->>'last_post_id')::uuid,
            (counter->>'version')::bigint,(counter->>'reconciled_at')::timestamptz);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'thread_counters_pkey') THEN RAISE; END IF;
    END;
    UPDATE public.posts me SET current_body_id = (command #>> '{body,body_id}')::uuid,
        current_revision_id = (command #>> '{revision,revision_id}')::uuid
    WHERE me.post_id = (post->>'post_id')::uuid
      AND (me.current_body_id IS DISTINCT FROM (command #>> '{body,body_id}')::uuid
        OR me.current_revision_id IS DISTINCT FROM (command #>> '{revision,revision_id}')::uuid);
    RETURN jsonb_build_object('command',command,'thread',p_thread,'post',post ||
        jsonb_build_object('current_body_id',command #> '{body,body_id}',
            'current_revision_id',command #> '{revision,revision_id}'));
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_thread_opening_v1(jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_forum_insert_thread_v1(p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE part jsonb := p_command -> 'thread';
BEGIN
    INSERT INTO public.threads(thread_id,category_id,author_user_id,title,slug,pinned,
        visibility,moderation_state,locked_at,version,visibility_version,permission_version,
        deleted_at,deleted_by)
    VALUES ((part->>'thread_id')::uuid,(part->>'category_id')::uuid,
        (part->>'author_user_id')::uuid,part->>'title',part->>'slug',
        (part->>'pinned')::boolean,part->>'visibility',part->>'moderation_state',
        (part->>'locked_at')::timestamptz,(part->>'version')::bigint,
        (part->>'visibility_version')::bigint,(part->>'permission_version')::bigint,
        (part->>'deleted_at')::timestamptz,(part->>'deleted_by')::uuid);
    RETURN api.core_forum_thread_opening_v1(p_command,part);
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_insert_thread_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_forum_create_thread_v1(p_command jsonb, p_record jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE command jsonb := p_command; written jsonb; stored public.threads;
    post public.posts; reported text; new_id jsonb; event jsonb; opening_record jsonb;
BEGIN
    BEGIN
        written := api.core_forum_insert_thread_v1(command);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'threads_pkey') THEN RAISE; END IF;
        SELECT me.* INTO stored FROM public.threads me
            WHERE me.thread_id = (command #>> '{thread,thread_id}')::uuid;
        IF NOT FOUND OR stored.category_id::text <> command #>> '{thread,category_id}'
            OR stored.slug <> command #>> '{thread,slug}' THEN
            new_id := to_jsonb(api.core_uuid_v7_v1()::text);
            command := jsonb_set(jsonb_set(jsonb_set(command,'{thread,thread_id}',new_id),
                '{post,thread_id}',new_id),'{counter,thread_id}',new_id);
            written := api.core_forum_insert_thread_v1(command);
        ELSE
            SELECT me.* INTO post FROM public.posts me
                WHERE me.post_id = (command #>> '{post,post_id}')::uuid;
            IF FOUND AND post.thread_id::text = command #>> '{post,thread_id}' THEN
                RETURN jsonb_build_object('ok',1,'post',to_jsonb(post),'thread',to_jsonb(stored),'skipped',true);
            END IF;
            written := api.core_forum_thread_opening_v1(command,to_jsonb(stored));
            RETURN (written - 'command') || jsonb_build_object('ok',1,'skipped',written->'skipped');
        END IF;
    END;
    IF NOT coalesce((written->>'skipped')::boolean,false) THEN
        command := written -> 'command';
        event := api.core_forum_record_write_v1('thread.created',command,
            written->'thread',p_record,NULL,false);
        opening_record := p_record || jsonb_build_object('event_id',p_record->'post_event_id',
            'outbox_id',p_record->'post_outbox_id');
        PERFORM api.core_forum_record_write_v1('post.created',command,
            written->'post',opening_record,event->>'event_id',false);
        PERFORM api.core_record_audit_v1('thread.created',command #>> '{thread,author_user_id}',
            p_record->>'audit_id',p_record->>'correlation_id',p_record->>'recorded_at',
            jsonb_build_object('title',command #> '{thread,title}'),1,
            command #>> '{thread,thread_id}','thread');
    END IF;
    RETURN (written - 'command') || jsonb_build_object('ok',1,'skipped',written->'skipped');
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_create_thread_v1(jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_forum_write_thread_v1(p_type text,p_command jsonb,p_record jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE command jsonb := p_command; part jsonb := command->'thread';
    writer text; stored public.threads; refusal text; row jsonb;
BEGIN
    writer := part ->> CASE p_type WHEN 'thread.deleted' THEN 'deleted_by'
        WHEN 'thread.undeleted' THEN 'restored_by' ELSE 'editor_user_id' END;
    SELECT me.* INTO stored FROM public.threads me
        WHERE me.thread_id = (part->>'thread_id')::uuid FOR UPDATE;
    IF NOT FOUND OR stored.moderation_state NOT IN ('visible','locked')
        OR (stored.deleted_at IS NOT NULL AND (length(coalesce(writer,'')) = 0
            OR stored.author_user_id::text <> writer))
        OR (p_type = 'thread.undeleted' AND stored.deleted_at IS NULL)
        OR (p_type <> 'thread.undeleted' AND stored.deleted_at IS NOT NULL) THEN
        refusal := 'thread not found';
    ELSIF coalesce(stored.author_user_id::text,'') <> coalesce(writer,'') THEN
        refusal := 'not the thread author';
    ELSIF stored.locked_at IS NOT NULL THEN refusal := 'thread is locked';
    END IF;
    IF refusal IS NOT NULL THEN RETURN jsonb_build_object('ok',0,'error',refusal); END IF;
    IF (p_type = 'thread.updated' AND stored.title = part->>'title' AND stored.slug = part->>'slug')
        OR (p_type = 'thread.moved' AND stored.category_id::text = part->>'category_id') THEN
        RETURN jsonb_build_object('ok',1,'thread',to_jsonb(stored),'skipped',true);
    END IF;
    IF p_type = 'thread.moved' THEN
        command := jsonb_set(command,'{thread,previous_category_id}',to_jsonb(stored.category_id::text));
    END IF;
    UPDATE public.threads me SET
        title = CASE WHEN p_type = 'thread.updated' THEN part->>'title' ELSE me.title END,
        slug = CASE WHEN p_type = 'thread.updated' THEN part->>'slug' ELSE me.slug END,
        category_id = CASE WHEN p_type = 'thread.moved' THEN (part->>'category_id')::uuid ELSE me.category_id END,
        deleted_at = CASE WHEN p_type = 'thread.deleted' THEN (p_record->>'deleted_at')::timestamptz
            WHEN p_type = 'thread.undeleted' THEN NULL ELSE me.deleted_at END,
        deleted_by = CASE WHEN p_type = 'thread.deleted' THEN writer::uuid
            WHEN p_type = 'thread.undeleted' THEN NULL ELSE me.deleted_by END,
        version = me.version + 1
    WHERE me.thread_id = stored.thread_id RETURNING me.* INTO stored;
    row := to_jsonb(stored);
    PERFORM api.core_forum_record_write_v1(p_type,command,row,p_record);
    RETURN jsonb_build_object('ok',1,'thread',row);
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_write_thread_v1(text,jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_forum_insert_edit_v1(p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE command jsonb := p_command; part jsonb; latest integer;
BEGIN
    IF coalesce((command #>> '{revision,revision_number}')::integer,0) <= 0 THEN
        SELECT coalesce(max(me.revision_number),0) INTO latest FROM public.post_revisions me
            WHERE me.post_id = (command #>> '{revision,post_id}')::uuid;
        command := jsonb_set(command,'{revision,revision_number}',to_jsonb(latest + 1));
    END IF;
    command := api.core_forum_store_body_v1(command);
    part := command -> 'revision';
    INSERT INTO public.post_revisions(body_id,edit_reason,editor_user_id,post_id,revision_id,revision_number)
    VALUES ((part->>'body_id')::uuid,part->>'edit_reason',(part->>'editor_user_id')::uuid,
        (part->>'post_id')::uuid,(part->>'revision_id')::uuid,(part->>'revision_number')::integer);
    RETURN command;
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_insert_edit_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_forum_write_post_v1(p_type text,p_command jsonb,p_record jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE command jsonb := p_command; part jsonb := command->'post';
    stored public.posts; thread public.threads; revision public.post_revisions;
    writer text; thread_id uuid; refusal text; reported text; row jsonb;
BEGIN
    writer := part ->> CASE p_type WHEN 'post.deleted' THEN 'deleted_by'
        WHEN 'post.undeleted' THEN 'restored_by' ELSE 'editor_user_id' END;
    thread_id := (part->>'thread_id')::uuid;
    IF thread_id IS NULL THEN
        SELECT me.thread_id INTO thread_id FROM public.posts me WHERE me.post_id = (part->>'post_id')::uuid;
    END IF;
    SELECT me.* INTO thread FROM public.threads me WHERE me.thread_id = thread_id FOR KEY SHARE;
    SELECT me.* INTO stored FROM public.posts me WHERE me.post_id = (part->>'post_id')::uuid FOR UPDATE;
    IF NOT FOUND OR (p_type = 'post.undeleted' AND stored.deleted_at IS NULL)
        OR (p_type <> 'post.undeleted' AND stored.deleted_at IS NOT NULL) THEN refusal := 'post not found';
    ELSIF thread.thread_id IS NULL OR thread.moderation_state NOT IN ('visible','locked')
        OR (thread.deleted_at IS NOT NULL AND (length(coalesce(writer,'')) = 0
            OR thread.author_user_id::text <> writer)) THEN refusal := 'thread not found';
    ELSIF coalesce(stored.author_user_id::text,'') <> coalesce(writer,'') THEN refusal := 'not the post author';
    ELSIF stored.hidden_at IS NOT NULL OR stored.moderation_state = 'hidden' THEN refusal := 'post is hidden';
    ELSIF thread.locked_at IS NOT NULL THEN refusal := 'thread is locked';
    END IF;
    IF refusal IS NOT NULL THEN RETURN jsonb_build_object('ok',0,'error',refusal); END IF;
    IF p_type = 'post.updated' THEN
        IF EXISTS (SELECT 1 FROM public.post_bodies me WHERE me.body_id = stored.current_body_id
            AND coalesce(me.source_hash,'') = coalesce(command #>> '{body,source_hash}','')) THEN
            RETURN jsonb_build_object('ok',1,'post',to_jsonb(stored),'skipped',true);
        END IF;
        BEGIN
            command := api.core_forum_insert_edit_v1(command);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported,'post_revisions_pkey') THEN
                command := api.core_forum_insert_edit_v1(jsonb_set(command,'{revision,revision_number}','0'::jsonb));
            ELSE
                SELECT me.* INTO revision FROM public.post_revisions me
                    WHERE me.revision_id = (command #>> '{revision,revision_id}')::uuid;
                IF NOT FOUND OR revision.post_id::text <> command #>> '{revision,post_id}' THEN
                    command := api.core_forum_insert_edit_v1(api.core_forum_with_new_id_v1(command,'revision'));
                ELSIF stored.current_revision_id::text = command #>> '{revision,revision_id}' THEN
                    RETURN jsonb_build_object('ok',1,'post',to_jsonb(stored),'skipped',true);
                END IF;
            END IF;
        END;
        UPDATE public.posts me SET current_body_id = (command #>> '{body,body_id}')::uuid,
            current_revision_id = (command #>> '{revision,revision_id}')::uuid,version = me.version + 1
            WHERE me.post_id = stored.post_id RETURNING me.* INTO stored;
    ELSE
        UPDATE public.posts me SET
            deleted_at = CASE WHEN p_type = 'post.deleted' THEN (p_record->>'deleted_at')::timestamptz END,
            deleted_by = CASE WHEN p_type = 'post.deleted' THEN writer::uuid END,
            version = me.version + 1 WHERE me.post_id = stored.post_id RETURNING me.* INTO stored;
        IF stored.position <> 1 THEN
            PERFORM api.core_forum_count_replies_v1(stored.thread_id::text,
                CASE WHEN p_type = 'post.deleted' THEN -1 ELSE 1 END);
        END IF;
    END IF;
    row := to_jsonb(stored);
    PERFORM api.core_forum_record_write_v1(p_type,command,row,p_record);
    RETURN jsonb_build_object('ok',1,'post',row);
END $$;
REVOKE EXECUTE ON FUNCTION api.core_forum_write_post_v1(text,jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_store_write_v1(p_store_type text,p_command jsonb,p_record jsonb)
RETURNS TABLE(stored json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE answer jsonb;
BEGIN
    CASE p_store_type
      WHEN 'post.created' THEN
        SELECT CASE WHEN reply.refusal IS NOT NULL THEN
            jsonb_build_object('ok',0,'error',CASE reply.refusal
                WHEN 'thread_not_found' THEN 'thread not found' ELSE 'thread is locked' END)
            ELSE jsonb_build_object('ok',1,'skipped',reply.skipped,
                'post',to_jsonb(reply) - 'refusal' - 'skipped') END
        INTO answer FROM api.core_forum_store_reply_v1(
            (p_command #>> '{post,post_id}'),
            (p_command #>> '{post,thread_id}'),
            (p_command #>> '{post,author_user_id}'),
            (p_command #>> '{post,current_body_id}'),
            (p_command #>> '{post,current_revision_id}'),
            (p_command #>> '{post,position}')::bigint,
            (p_command #>> '{post,visibility}'),
            (p_command #>> '{post,moderation_state}'),
            (p_command #>> '{post,version}')::bigint,
            (p_command #>> '{post,visibility_version}')::bigint,
            (p_command #>> '{post,permission_version}')::bigint,
            (p_command #>> '{post,hidden_at}'),
            (p_command #>> '{post,locked_at}'),
            (p_command #>> '{post,deleted_at}'),
            (p_command #>> '{post,deleted_by}'),
            (p_command #>> '{body,body_id}'),
            (p_command #>> '{body,post_id}'),
            (p_command #>> '{body,body_format}'),
            (p_command #>> '{body,body_source}'),
            (p_command #>> '{body,body_rendered_safe}'),
            (p_command #>> '{body,source_hash}'),
            (p_command #>> '{revision,revision_id}'),
            (p_command #>> '{revision,post_id}'),
            (p_command #>> '{revision,body_id}'),
            (p_command #>> '{revision,editor_user_id}'),
            (p_command #>> '{revision,revision_number}')::integer,
            (p_command #>> '{revision,edit_reason}'),
            p_command->>'idempotency_key',
            p_record->>'correlation_id',
            p_record->>'event_id',
            p_record->>'outbox_id',
            p_record->>'audit_id',
            p_record->>'recorded_at') reply;
      WHEN 'thread.created' THEN answer := api.core_forum_create_thread_v1(p_command,p_record);
      WHEN 'thread.updated','thread.moved','thread.deleted','thread.undeleted' THEN
        answer := api.core_forum_write_thread_v1(p_store_type,p_command,p_record);
      WHEN 'post.updated','post.deleted','post.undeleted' THEN
        answer := api.core_forum_write_post_v1(p_store_type,p_command,p_record);
      ELSE RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'unknown forum store type';
    END CASE;
    RETURN QUERY SELECT answer::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v1(text,jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v1(p_log jsonb,p_answer jsonb,p_store_type text,p_command jsonb,p_record jsonb)
RETURNS TABLE(outcome text,response json,stored json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE existing public.command_log; held record; reported text;
    command_id text := p_log->>'command_id';
    payload jsonb := jsonb_build_object('request_hash',p_log->>'request_hash');
    answer jsonb := p_answer; written jsonb; message text; status text;
BEGIN
    SELECT me.* INTO existing FROM public.command_log me
        WHERE me.idempotency_key = p_log->>'idempotency_key' LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
        RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
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
    RETURN QUERY SELECT 'recorded'::text,answer::json,written::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v1(jsonb,jsonb,text,jsonb,jsonb) FROM PUBLIC;
COMMIT;
