-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause
-- ADR 0126: shared durable records, command log primitives, worker claims,
-- outbox leases, dead letters and projection coordination. Fixed statements
-- and bound JSON documents, without runtime SQL construction.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.core_shared_ensure_outbox_v1(p_event jsonb, p_outbox_id text, p_extras jsonb)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    outbox_key text := 'outbox:' || coalesce(p_event ->> 'event_type', '')
        || ':' || coalesce(p_event ->> 'event_id', '');
    reported text;
    on_id boolean;
BEGIN
    PERFORM 1 FROM public.outbox_messages me
    WHERE me.idempotency_key = outbox_key LIMIT 1;
    IF FOUND THEN
        RETURN;
    END IF;

    BEGIN
        INSERT INTO public.outbox_messages (event_id, idempotency_key,
            job_type, outbox_id, payload, queue, status)
        VALUES ((p_event ->> 'event_id')::uuid, outbox_key,
            'domain_event.dispatch', p_outbox_id::uuid,
            api.core_transport_payload_v1(p_event) || coalesce(p_extras,'{}'::jsonb), 'events', 'pending');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        on_id := api.core_unique_on_v1(reported, 'outbox_messages_pkey');
        IF NOT on_id AND NOT api.core_unique_on_v1(reported,
            'outbox_messages_idempotency_key_key') THEN
            RAISE;
        END IF;
        PERFORM 1 FROM public.outbox_messages me
        WHERE me.idempotency_key = outbox_key LIMIT 1;
        IF FOUND THEN
            RETURN;
        END IF;
        IF NOT on_id THEN
            RAISE;
        END IF;
        INSERT INTO public.outbox_messages (event_id, idempotency_key,
            job_type, outbox_id, payload, queue, status)
        VALUES ((p_event ->> 'event_id')::uuid, outbox_key,
            'domain_event.dispatch', api.core_uuid_v7_v1(),
            api.core_transport_payload_v1(p_event) || coalesce(p_extras,'{}'::jsonb), 'events', 'pending');
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_shared_ensure_outbox_v1(jsonb, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_shared_record_event_v1(p_event jsonb, p_outbox_id text, p_extras jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    stored_row public.event_log;
    stored jsonb;
    reported text;
    new_id text;
BEGIN
    SELECT me.* INTO stored_row FROM public.event_log me
    WHERE me.event_id = (p_event ->> 'event_id')::uuid;
    IF FOUND THEN
        stored := api.core_event_of_row_v1(stored_row)
            || '{"skipped": 1}'::jsonb;
        PERFORM api.core_shared_ensure_outbox_v1(stored, p_outbox_id, p_extras);
        RETURN stored;
    END IF;

    BEGIN
        INSERT INTO public.event_log (actor_id, aggregate_id, aggregate_type,
            aggregate_version, causation_id, correlation_id, created_at,
            event_id, event_type, idempotency_key, metadata, payload,
            schema_version)
        VALUES ((p_event ->> 'actor_id')::uuid,
            (p_event ->> 'aggregate_id')::uuid, p_event ->> 'aggregate_type',
            (p_event ->> 'aggregate_version')::bigint,
            (p_event ->> 'causation_id')::uuid,
            (p_event ->> 'correlation_id')::uuid,
            CASE WHEN p_event ? 'created_at'
                THEN (p_event ->> 'created_at')::timestamptz ELSE now() END,
            (p_event ->> 'event_id')::uuid, p_event ->> 'event_type',
            p_event ->> 'idempotency_key', p_event -> 'metadata',
            p_event -> 'payload', (p_event ->> 'schema_version')::integer);
        stored := p_event;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'event_log_pkey') THEN
            RAISE;
        END IF;
        SELECT me.* INTO stored_row FROM public.event_log me
        WHERE me.event_id = (p_event ->> 'event_id')::uuid;
        IF FOUND
            AND stored_row.idempotency_key IS NOT NULL
            AND p_event ->> 'idempotency_key' IS NOT NULL
            AND stored_row.idempotency_key = p_event ->> 'idempotency_key'
        THEN
            stored := api.core_event_of_row_v1(stored_row)
                || '{"skipped": 1}'::jsonb;
        ELSE
            new_id := api.core_uuid_v7_v1()::text;
            stored := p_event || jsonb_build_object(
                'event_id', new_id,
                'metadata', CASE
                    WHEN jsonb_typeof(p_event -> 'metadata') = 'object'
                    THEN p_event -> 'metadata' ELSE '{}'::jsonb END
                    || jsonb_build_object('event_id', new_id));
            INSERT INTO public.event_log (actor_id, aggregate_id,
                aggregate_type, aggregate_version, causation_id,
                correlation_id, created_at, event_id, event_type,
                idempotency_key, metadata, payload, schema_version)
            VALUES ((stored ->> 'actor_id')::uuid,
                (stored ->> 'aggregate_id')::uuid, stored ->> 'aggregate_type',
                (stored ->> 'aggregate_version')::bigint,
                (stored ->> 'causation_id')::uuid,
                (stored ->> 'correlation_id')::uuid,
                CASE WHEN stored ? 'created_at'
                    THEN (stored ->> 'created_at')::timestamptz
                    ELSE now() END,
                (stored ->> 'event_id')::uuid, stored ->> 'event_type',
                stored ->> 'idempotency_key', stored -> 'metadata',
                stored -> 'payload', (stored ->> 'schema_version')::integer);
        END IF;
    END;

    PERFORM api.core_shared_ensure_outbox_v1(stored, p_outbox_id, p_extras);
    RETURN stored;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_shared_record_event_v1(jsonb, text, jsonb) FROM PUBLIC;

-- AuditRecord::build and EventRecorder::_insert_audit: the audit row chained
-- to the newest one, its record_hash the SHA-256 of its canonical JSON.
CREATE FUNCTION api.ops_record_event_v1(p_event jsonb,p_outbox_id text,p_outbox_extras jsonb,p_explicit boolean)
RETURNS TABLE(event json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_explicit THEN
        PERFORM pg_advisory_xact_lock(2026100310,hashtext(p_event->>'event_id'));
    END IF;
    RETURN QUERY SELECT api.core_shared_record_event_v1(p_event,p_outbox_id,p_outbox_extras)::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_record_event_v1(jsonb,text,jsonb,boolean) FROM PUBLIC;

CREATE FUNCTION api.core_shared_append_audit_v1(p_audit jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE audit jsonb := p_audit - 'record_hash'; tip text; chain_hash text;
BEGIN
    SELECT me.record_hash INTO tip FROM public.audit_log me
        ORDER BY me.created_at DESC,me.audit_id DESC LIMIT 1;
    audit := audit || jsonb_build_object('previous_hash',CASE
        WHEN length(coalesce(audit->>'previous_hash','')) > 0 THEN audit->>'previous_hash'
        ELSE nullif(tip,'') END);
    chain_hash := encode(sha256(convert_to(api.core_canonical_json_v1(audit),'UTF8')),'hex');
    INSERT INTO public.audit_log(action,actor_id,audit_id,correlation_id,created_at,metadata,
        previous_hash,record_hash,schema_version,target_id,target_type)
    VALUES (audit->>'action',(audit->>'actor_id')::uuid,(audit->>'audit_id')::uuid,
        (audit->>'correlation_id')::uuid,(audit->>'created_at')::timestamptz,
        audit->'metadata',audit->>'previous_hash',chain_hash,(audit->>'schema_version')::integer,
        (audit->>'target_id')::uuid,audit->>'target_type');
    RETURN audit || jsonb_build_object('record_hash',chain_hash);
END $$;
REVOKE EXECUTE ON FUNCTION api.core_shared_append_audit_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_record_audit_v1(p_audit jsonb,p_explicit boolean)
RETURNS TABLE(audit json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE document jsonb := p_audit; reported text;
BEGIN
    PERFORM pg_advisory_xact_lock(2026060210);
    IF p_explicit AND EXISTS (SELECT 1 FROM public.audit_log me
        WHERE me.audit_id = (document->>'audit_id')::uuid) THEN
        document := document || jsonb_build_object('audit_id',api.core_uuid_v7_v1()::text);
    END IF;
    BEGIN
        RETURN QUERY SELECT api.core_shared_append_audit_v1(document)::json;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'audit_log_pkey') THEN RAISE; END IF;
        document := document || jsonb_build_object('audit_id',api.core_uuid_v7_v1()::text);
        RETURN QUERY SELECT api.core_shared_append_audit_v1(document)::json;
    END;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_record_audit_v1(jsonb,boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_event_recorded_v1(p_key text)
RETURNS TABLE(recorded boolean) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT EXISTS(SELECT 1 FROM public.event_log me WHERE me.idempotency_key = p_key) $$;
REVOKE EXECUTE ON FUNCTION api.ops_event_recorded_v1(text) FROM PUBLIC;

CREATE FUNCTION api.ops_command_lookup_v1(p_key text,p_command_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
    SELECT to_jsonb(me)::json FROM public.command_log me
    WHERE (p_key IS NOT NULL AND me.idempotency_key = p_key)
      OR (p_key IS NULL AND me.command_id = p_command_id) LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_lookup_v1(text,uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_command_insert_v1(p_command jsonb)
RETURNS TABLE(document json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    INSERT INTO public.command_log(actor_id,command_id,command_type,correlation_id,created_at,
        handled_at,idempotency_key,payload,response_hash,status)
    VALUES ((p_command->>'actor_id')::uuid,(p_command->>'command_id')::uuid,p_command->>'command_type',
        (p_command->>'correlation_id')::uuid,(p_command->>'created_at')::timestamptz,
        (p_command->>'handled_at')::timestamptz,p_command->>'idempotency_key',p_command->'payload',
        p_command->>'response_hash',p_command->>'status');
    RETURN QUERY SELECT p_command::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_command_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_command_finish_v1(p_command_id uuid,p_changes jsonb)
RETURNS TABLE(success boolean) LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
    WITH changed AS (UPDATE public.command_log me SET handled_at = (p_changes->>'handled_at')::timestamptz,
        payload = p_changes->'payload',response_hash = p_changes->>'response_hash',status = p_changes->>'status'
        WHERE me.command_id = p_command_id RETURNING 1)
    SELECT EXISTS(SELECT 1 FROM changed)
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_finish_v1(uuid,jsonb) FROM PUBLIC;

CREATE FUNCTION api.ops_event_claim_v1(p_operation text,p_key text,p_event_id text,p_now text,p_expired_before text)
RETURNS TABLE(claimed boolean) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE reported text; affected integer;
BEGIN
    IF p_operation = 'is_done' THEN
        RETURN QUERY SELECT EXISTS(SELECT 1 FROM public.event_idempotency_keys me
            WHERE me.idempotency_key = p_key AND me.completed_at IS NOT NULL); RETURN;
    ELSIF p_operation = 'failed' THEN
        DELETE FROM public.event_idempotency_keys me WHERE me.idempotency_key = p_key AND me.completed_at IS NULL;
        RETURN QUERY SELECT true; RETURN;
    ELSIF p_operation = 'done' THEN
        UPDATE public.event_idempotency_keys me SET completed_at = p_now::timestamptz WHERE me.idempotency_key = p_key;
        IF FOUND THEN RETURN QUERY SELECT true; RETURN; END IF;
        BEGIN
            INSERT INTO public.event_idempotency_keys(idempotency_key,event_id,created_at,completed_at)
            VALUES (p_key,p_event_id::uuid,p_now::timestamptz,p_now::timestamptz);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported,'event_idempotency_keys_pkey') THEN RAISE; END IF;
        END;
        RETURN QUERY SELECT true; RETURN;
    ELSIF p_operation <> 'begin' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',MESSAGE = 'unknown event claim operation';
    END IF;
    BEGIN
        INSERT INTO public.event_idempotency_keys(idempotency_key,event_id,created_at,completed_at)
        VALUES (p_key,p_event_id::uuid,p_now::timestamptz,NULL);
        RETURN QUERY SELECT true; RETURN;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'event_idempotency_keys_pkey') THEN RAISE; END IF;
    END;
    UPDATE public.event_idempotency_keys me SET created_at = p_now::timestamptz
        WHERE me.idempotency_key = p_key AND me.completed_at IS NULL AND me.created_at < p_expired_before::timestamptz;
    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN QUERY SELECT affected > 0;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_event_claim_v1(text,text,text,text,text) FROM PUBLIC;

CREATE FUNCTION api.outbox_claim_ready_v1(p_now text,p_locked_until text,p_worker_id text,p_row_limit integer)
RETURNS SETOF public.outbox_messages LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
WITH ready AS (
    SELECT outbox_id,next_attempt_at,created_at FROM public.outbox_messages
    WHERE (status IN ('pending','failed') AND next_attempt_at <= p_now::timestamptz
        AND (locked_until IS NULL OR locked_until <= p_now::timestamptz))
      OR (status = 'running' AND locked_until IS NOT NULL AND locked_until <= p_now::timestamptz)
    ORDER BY next_attempt_at,created_at,outbox_id LIMIT p_row_limit FOR UPDATE SKIP LOCKED
), claimed AS (
    UPDATE public.outbox_messages outbox SET status = 'running',locked_at = p_now::timestamptz,
        locked_by = p_worker_id,locked_until = p_locked_until::timestamptz
    FROM ready WHERE outbox.outbox_id = ready.outbox_id RETURNING outbox.*
)
SELECT claimed.* FROM claimed JOIN ready ON ready.outbox_id = claimed.outbox_id
ORDER BY ready.next_attempt_at,ready.created_at,ready.outbox_id
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_claim_ready_v1(text,text,text,integer) FROM PUBLIC;

CREATE FUNCTION api.outbox_owned_write_v1(p_outbox_id uuid,p_worker_id text,p_changes jsonb)
RETURNS TABLE(landed boolean) LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
WITH changed AS (
    UPDATE public.outbox_messages me SET
        status = CASE WHEN p_changes ? 'status' THEN p_changes->>'status' ELSE me.status END,
        locked_at = CASE WHEN p_changes ? 'locked_at' THEN (p_changes->>'locked_at')::timestamptz ELSE me.locked_at END,
        locked_by = CASE WHEN p_changes ? 'locked_by' THEN p_changes->>'locked_by' ELSE me.locked_by END,
        locked_until = CASE WHEN p_changes ? 'locked_until' THEN (p_changes->>'locked_until')::timestamptz ELSE me.locked_until END,
        next_attempt_at = CASE WHEN p_changes ? 'next_attempt_at' THEN (p_changes->>'next_attempt_at')::timestamptz ELSE me.next_attempt_at END,
        attempt_count = CASE WHEN p_changes ? 'attempt_count' THEN (p_changes->>'attempt_count')::integer ELSE me.attempt_count END,
        attempts = CASE WHEN p_changes ? 'attempts' THEN (p_changes->>'attempts')::integer ELSE me.attempts END,
        failure_type = CASE WHEN p_changes ? 'failure_type' THEN p_changes->>'failure_type' ELSE me.failure_type END,
        last_error = CASE WHEN p_changes ? 'last_error' THEN p_changes->>'last_error' ELSE me.last_error END,
        last_error_class = CASE WHEN p_changes ? 'last_error_class' THEN p_changes->>'last_error_class' ELSE me.last_error_class END
    WHERE me.outbox_id = p_outbox_id AND me.locked_by = p_worker_id AND me.status = 'running' RETURNING 1
) SELECT EXISTS(SELECT 1 FROM changed)
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_owned_write_v1(uuid,text,jsonb) FROM PUBLIC;

CREATE FUNCTION api.outbox_dead_letter_v1(p_letter jsonb)
RETURNS TABLE(letter json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE document jsonb := p_letter; reported text;
BEGIN
    IF EXISTS (SELECT 1 FROM public.dead_letters me WHERE me.source_table = document->>'source_table'
        AND me.source_id = (document->>'source_id')::uuid) THEN
        RETURN QUERY SELECT '{"skipped":1}'::json; RETURN;
    END IF;
    BEGIN
        INSERT INTO public.dead_letters(dead_letter_id,source_table,source_id,payload,error_class,error_message,
            failure_type,retry_count,first_failed_at,last_failed_at)
        VALUES ((document->>'dead_letter_id')::uuid,document->>'source_table',(document->>'source_id')::uuid,
            document->'payload',document->>'error_class',document->>'error_message',document->>'failure_type',
            (document->>'retry_count')::integer,(document->>'first_failed_at')::timestamptz,(document->>'last_failed_at')::timestamptz);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'dead_letters_pkey')
            AND NOT api.core_unique_on_v1(reported,'idx_dead_letters_source_unique') THEN RAISE; END IF;
        IF EXISTS (SELECT 1 FROM public.dead_letters me WHERE me.source_table = document->>'source_table'
            AND me.source_id = (document->>'source_id')::uuid) THEN
            RETURN QUERY SELECT '{"skipped":1}'::json; RETURN;
        END IF;
        IF NOT api.core_unique_on_v1(reported,'dead_letters_pkey') THEN RAISE; END IF;
        document := document || jsonb_build_object('dead_letter_id',api.core_uuid_v7_v1()::text);
        INSERT INTO public.dead_letters(dead_letter_id,source_table,source_id,payload,error_class,error_message,
            failure_type,retry_count,first_failed_at,last_failed_at)
        VALUES ((document->>'dead_letter_id')::uuid,document->>'source_table',(document->>'source_id')::uuid,
            document->'payload',document->>'error_class',document->>'error_message',document->>'failure_type',
            (document->>'retry_count')::integer,(document->>'first_failed_at')::timestamptz,(document->>'last_failed_at')::timestamptz);
    END;
    RETURN QUERY SELECT document::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.outbox_dead_letter_v1(jsonb) FROM PUBLIC;
CREATE FUNCTION api.outbox_replay_dead_letter_v1(p_input jsonb,p_ids jsonb,p_now text)
RETURNS TABLE(result json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE letter public.dead_letters; earlier public.audit_log; replayed jsonb;
    envelope jsonb; audit jsonb; via text;
BEGIN
    SELECT me.* INTO letter FROM public.dead_letters me WHERE me.dead_letter_id = (p_input->>'dead_letter_id')::uuid FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT '{"status":"not_found","error":"dead letter not found"}'::json; RETURN; END IF;
    IF letter.source_table <> 'outbox_messages' THEN
        RETURN QUERY SELECT '{"status":"conflict","error":"only outbox dead letters can be replayed"}'::json; RETURN;
    END IF;
    envelope := letter.payload;
    IF jsonb_typeof(envelope) <> 'object' OR NOT coalesce((envelope->>'event_id') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false) THEN
        RETURN QUERY SELECT '{"status":"conflict","error":"the dead letter does not name its event; emit the work again from its source"}'::json; RETURN;
    END IF;
    SELECT me.* INTO earlier FROM public.audit_log me
        WHERE me.action = 'outbox.dead_letter_replayed' AND me.target_type = 'dead_letter'
          AND me.target_id = letter.dead_letter_id LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT jsonb_build_object('status','conflict','error','already replayed at '
            || earlier.created_at::text || ' as outbox ' || coalesce(earlier.metadata->>'outbox_id','unknown'))::json; RETURN;
    END IF;
    INSERT INTO public.outbox_messages(outbox_id,event_id,queue,job_type,idempotency_key,payload,status,next_attempt_at)
    VALUES ((p_ids->>'outbox_id')::uuid,(envelope->>'event_id')::uuid,'events','domain_event.dispatch',
        'dead-letter-replay:' || letter.dead_letter_id::text,envelope,'pending',p_now::timestamptz);
    replayed := jsonb_build_object('dead_letter_id',letter.dead_letter_id::text,'event_id',envelope->>'event_id',
        'outbox_id',p_ids->>'outbox_id','source_id',letter.source_id::text);
    via := CASE WHEN api.core_perl_true_v1(p_input->>'via') THEN p_input->>'via' ELSE 'web' END;
    audit := jsonb_build_object('action','outbox.dead_letter_replayed','actor_id',p_input->>'actor_user_id',
        'audit_id',p_ids->>'audit_id','correlation_id',p_ids->>'correlation_id','created_at',p_now,
        'metadata',replayed || jsonb_build_object('error_class',letter.error_class,'failure_type',letter.failure_type,
            'retry_count',letter.retry_count,'via',via),'previous_hash',NULL,'schema_version',1,
        'target_id',letter.dead_letter_id::text,'target_type','dead_letter');
    PERFORM api.ops_record_audit_v1(audit,false);
    RETURN QUERY SELECT jsonb_build_object('status','replayed','replayed',replayed)::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.outbox_replay_dead_letter_v1(jsonb,jsonb,text) FROM PUBLIC;

CREATE FUNCTION api.projection_offset_get_v1(p_projection_name text)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$ SELECT jsonb_build_object('projection_name',me.projection_name,'lag_seconds',me.lag_seconds,
    'status',me.status,'updated_at',me.updated_at::text)::json FROM public.projection_offsets me
    WHERE me.projection_name = p_projection_name $$;
REVOKE EXECUTE ON FUNCTION api.projection_offset_get_v1(text) FROM PUBLIC;

CREATE FUNCTION api.projection_offset_write_v1(p_row jsonb)
RETURNS TABLE(document json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE stored public.projection_offsets; reported text;
BEGIN
    SELECT me.* INTO stored FROM public.projection_offsets me WHERE me.projection_name = p_row->>'projection_name';
    IF FOUND AND ((p_row->>'status' = 'failed' AND stored.status = 'failed')
        OR (length(coalesce(p_row->>'last_event_id','')) > 0 AND stored.last_event_id::text = p_row->>'last_event_id')) THEN
        RETURN QUERY SELECT (to_jsonb(stored) || jsonb_build_object('last_event_created_at',stored.last_event_created_at::text,
            'updated_at',stored.updated_at::text,'skipped',1))::json; RETURN;
    END IF;
    INSERT INTO public.projection_offsets(projection_name,last_event_id,last_event_created_at,lag_seconds,status,updated_at)
    VALUES (p_row->>'projection_name',(p_row->>'last_event_id')::uuid,(p_row->>'last_event_created_at')::timestamptz,
        (p_row->>'lag_seconds')::integer,p_row->>'status',(p_row->>'updated_at')::timestamptz)
    ON CONFLICT (projection_name) DO UPDATE SET
        last_event_id = CASE WHEN p_row ? 'last_event_id' THEN EXCLUDED.last_event_id ELSE projection_offsets.last_event_id END,
        last_event_created_at = CASE WHEN p_row ? 'last_event_created_at' THEN EXCLUDED.last_event_created_at ELSE projection_offsets.last_event_created_at END,
        lag_seconds = EXCLUDED.lag_seconds,status = EXCLUDED.status,updated_at = EXCLUDED.updated_at
    WHERE NOT ((p_row->>'status' = 'failed' AND projection_offsets.status = 'failed')
        OR (length(coalesce(p_row->>'last_event_id','')) > 0
            AND projection_offsets.last_event_id::text = p_row->>'last_event_id'))
    RETURNING projection_offsets.* INTO stored;
    IF NOT FOUND THEN
        SELECT me.* INTO stored FROM public.projection_offsets me WHERE me.projection_name = p_row->>'projection_name';
        RETURN QUERY SELECT (to_jsonb(stored) || jsonb_build_object('last_event_created_at',stored.last_event_created_at::text,
            'updated_at',stored.updated_at::text,'skipped',1))::json; RETURN;
    END IF;
    RETURN QUERY SELECT p_row::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.projection_offset_write_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.projection_generation_start_v1(p_row jsonb)
RETURNS TABLE(document json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE stored public.projection_generations; document jsonb := p_row; reported text;
BEGIN
    SELECT me.* INTO stored FROM public.projection_generations me
        WHERE me.projection_name = document->>'projection_name'
          AND me.built_from_event_id IS NOT DISTINCT FROM (document->>'built_from_event_id')::uuid LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT (to_jsonb(stored) || jsonb_build_object('is_active',CASE WHEN stored.is_active THEN 1 ELSE 0 END,
            'activated_at',stored.activated_at::text,'created_at',stored.created_at::text,
            'built_from_event_created_at',stored.built_from_event_created_at::text,'skipped',1))::json; RETURN;
    END IF;
    BEGIN
        INSERT INTO public.projection_generations(generation_id,projection_name,built_from_event_id,
            built_from_event_created_at,is_active,status,created_at,activated_at)
        VALUES ((document->>'generation_id')::uuid,document->>'projection_name',(document->>'built_from_event_id')::uuid,
            (document->>'built_from_event_created_at')::timestamptz,(document->>'is_active')::boolean,
            document->>'status',(document->>'created_at')::timestamptz,(document->>'activated_at')::timestamptz);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'projection_generations_pkey')
            AND NOT api.core_unique_on_v1(reported,'idx_projection_generations_source_unique') THEN RAISE; END IF;
        SELECT me.* INTO stored FROM public.projection_generations me
            WHERE me.projection_name = document->>'projection_name'
              AND me.built_from_event_id IS NOT DISTINCT FROM (document->>'built_from_event_id')::uuid LIMIT 1;
        IF FOUND THEN
            RETURN QUERY SELECT (to_jsonb(stored) || jsonb_build_object('is_active',CASE WHEN stored.is_active THEN 1 ELSE 0 END,
                'activated_at',stored.activated_at::text,'created_at',stored.created_at::text,
                'built_from_event_created_at',stored.built_from_event_created_at::text,'skipped',1))::json; RETURN;
        END IF;
        IF NOT api.core_unique_on_v1(reported,'projection_generations_pkey') THEN RAISE; END IF;
        document := document || jsonb_build_object('generation_id',api.core_uuid_v7_v1()::text);
        INSERT INTO public.projection_generations(generation_id,projection_name,built_from_event_id,
            built_from_event_created_at,is_active,status,created_at,activated_at)
        VALUES ((document->>'generation_id')::uuid,document->>'projection_name',(document->>'built_from_event_id')::uuid,
            (document->>'built_from_event_created_at')::timestamptz,(document->>'is_active')::boolean,
            document->>'status',(document->>'created_at')::timestamptz,(document->>'activated_at')::timestamptz);
    END;
    RETURN QUERY SELECT document::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.projection_generation_start_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.projection_generation_update_v1(p_generation_id uuid,p_status text)
RETURNS TABLE(document json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE stored public.projection_generations;
BEGIN
    IF p_status NOT IN ('ready','failed') THEN RAISE EXCEPTION USING ERRCODE = '22023',MESSAGE = 'invalid generation status'; END IF;
    SELECT me.* INTO stored FROM public.projection_generations me WHERE me.generation_id = p_generation_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = '22023',MESSAGE = 'generation not found'; END IF;
    IF stored.status = p_status THEN
        RETURN QUERY SELECT jsonb_build_object('generation_id',p_generation_id::text,'status',p_status,'skipped',1)::json; RETURN;
    END IF;
    UPDATE public.projection_generations me SET status = p_status WHERE me.generation_id = p_generation_id;
    RETURN QUERY SELECT jsonb_build_object('generation_id',p_generation_id::text,'status',p_status)::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.projection_generation_update_v1(uuid,text) FROM PUBLIC;

CREATE FUNCTION api.projection_generation_activate_v1(p_generation_id uuid,p_now text)
RETURNS TABLE(document json) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
DECLARE stored public.projection_generations; retired integer;
BEGIN
    SELECT me.* INTO stored FROM public.projection_generations me WHERE me.generation_id = p_generation_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = '22023',MESSAGE = 'generation not found'; END IF;
    PERFORM pg_advisory_xact_lock(2026101111,hashtext(stored.projection_name));
    SELECT me.* INTO stored FROM public.projection_generations me WHERE me.generation_id = p_generation_id;
    IF stored.is_active AND stored.status = 'active' THEN
        RETURN QUERY SELECT jsonb_build_object('generation_id',p_generation_id::text,
            'projection_name',stored.projection_name,'retired_generations',0,'status','active','skipped',1)::json; RETURN;
    END IF;
    UPDATE public.projection_generations me SET is_active = false,status = 'retired'
        WHERE me.projection_name = stored.projection_name AND me.is_active;
    GET DIAGNOSTICS retired = ROW_COUNT;
    UPDATE public.projection_generations me SET is_active = true,status = 'active',activated_at = p_now::timestamptz
        WHERE me.generation_id = p_generation_id;
    RETURN QUERY SELECT jsonb_build_object('generation_id',p_generation_id::text,
        'projection_name',stored.projection_name,'retired_generations',retired,'status','active')::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.projection_generation_activate_v1(uuid,text) FROM PUBLIC;
CREATE FUNCTION api.ops_worker_aggregate_v1(p_aggregate_type text,p_aggregate_id uuid)
RETURNS TABLE(author_user_id uuid,thread_id uuid) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
    SELECT me.author_user_id,me.thread_id FROM public.posts me
    WHERE p_aggregate_type = 'post' AND me.post_id = p_aggregate_id
    UNION ALL
    SELECT me.author_user_id,me.thread_id FROM public.threads me
    WHERE p_aggregate_type = 'thread' AND me.thread_id = p_aggregate_id
$$;
REVOKE EXECUTE ON FUNCTION api.ops_worker_aggregate_v1(text,uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_thread_activity_v1(p_thread_id uuid,p_at text)
RETURNS TABLE(bumped bigint) LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp SET plan_cache_mode = force_generic_plan
AS $$
    WITH changed AS (UPDATE public.threads me
        SET last_activity_at = greatest(me.last_activity_at,p_at::timestamptz)
        WHERE me.thread_id = p_thread_id RETURNING 1)
    SELECT count(*) FROM changed
$$;
REVOKE EXECUTE ON FUNCTION api.ops_thread_activity_v1(uuid,text) FROM PUBLIC;
COMMIT;
