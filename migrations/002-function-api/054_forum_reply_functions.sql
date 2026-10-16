-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126, phase 0: the reply as functions. api.forum_create_reply_v1 is
-- the reply command, CommandIdempotency's command log around the post
-- store's write, api.core_forum_store_reply_v1, which is
-- PostStore::create_post. Perl calls the command; the store step is shared
-- with the commands phase 1 moves (PostStore keeps its Perl create_post for
-- the callers that use it alone until the forum writes move, ADR 0126,
-- section 10).
--
-- Every statement is the one DBIx::Class and the raw DBI code sent for a
-- reply (traced with its bound values against the seed), in the order the
-- trace shows, and every branch is the one the Perl took between them:
--
--   lookup of the command by its key, the command row, the thread FOR NO
--   KEY UPDATE and the check under it, the next position, the post, its
--   body, its revision, the thread's counter row, the event (looked up by
--   id in every partition, ADR 0116) and its outbox row, the audit chain's
--   lock, its tip and the audit row, the command row's response.
--
-- What the boundary changed: the values are parameters; a savepoint that
-- guarded an insert is an exception block, a subtransaction as the
-- savepoint was, without its two round trips; the conflict's constraint is
-- read with GET STACKED DIAGNOSTICS and a partition's index is matched to
-- its parent's constraint as GPForum::X::Conflict->on matches it; a row
-- DBIx::Class read back whole is read for the columns the Perl used. Ids
-- and the clock come from Perl, as they did, except the id a collision
-- makes the Perl draw again, which api.core_uuid_v7_v1 draws here, as
-- Infrastructure::Id would: a UUIDv7.
--
-- The documents are built as Perl built them, with the same keys and the
-- same JSON types: the event, its metadata and the outbox payload of
-- Domain::EventEnvelope, the audit row of Infrastructure::AuditRecord, whose
-- record_hash is SHA-256 of api.core_canonical_json_v1 (proved against
-- JSON::MaybeXS before any use, migration 052), the command log's response
-- of Forum::PostingCommand and its response_hash. The words a refusal is
-- recorded with are Perl's: the caller passes them.
--
-- Two releases run side by side during a deploy: the previous one does not
-- call these, this one calls them only once the migration has run. A
-- change is a new version, never an edit (ADR 0126, section 2).

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A UUIDv7 as Infrastructure::Id mints one: the Unix time in milliseconds,
-- then random bits, version 7. gen_random_uuid's version 4 nibble becomes 7
-- with two bits set; PostgreSQL 16 and 17 have no uuidv7().
CREATE FUNCTION api.core_uuid_v7_v1()
RETURNS uuid
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT encode(
    set_bit(
        set_bit(
            overlay(
                uuid_send(gen_random_uuid())
                PLACING substring(
                    int8send(floor(
                        extract(epoch FROM clock_timestamp()) * 1000
                    )::bigint)
                    FROM 3)
                FROM 1 FOR 6),
            52, 1),
        53, 1),
    'hex')::uuid
$$;
REVOKE EXECUTE ON FUNCTION api.core_uuid_v7_v1() FROM PUBLIC;

-- Whether a unique violation reported on p_reported is one on the
-- constraint p_constraint: its own index, or, on a partitioned table, the
-- index a partition attached to it (pg_inherits, recursively), which is the
-- name PostgreSQL reports (GPForum::X::Conflict->on, ADR 0113 and 0116).
CREATE FUNCTION api.core_unique_on_v1(p_reported text, p_constraint text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_reported = p_constraint OR EXISTS (
    WITH RECURSIVE family (index_oid, index_name) AS (
        SELECT root.oid, root.relname::text
        FROM pg_catalog.pg_class AS root
        WHERE root.oid = to_regclass('public.' || quote_ident(p_constraint))
          AND root.relkind IN ('i', 'I')
        UNION ALL
        SELECT child.oid, child.relname::text
        FROM family
        JOIN pg_catalog.pg_inherits AS link ON link.inhparent = family.index_oid
        JOIN pg_catalog.pg_class AS child ON child.oid = link.inhrelid
    )
    SELECT 1 FROM family WHERE family.index_name = p_reported
)
$$;
REVOKE EXECUTE ON FUNCTION api.core_unique_on_v1(text, text) FROM PUBLIC;

-- Perl's truth of a string: undef, '' and '0' are false.
CREATE FUNCTION api.core_perl_true_v1(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(p_value, '') NOT IN ('', '0')
$$;
REVOKE EXECUTE ON FUNCTION api.core_perl_true_v1(text) FROM PUBLIC;

-- An event_log row as EventRecorder::_existing_event hands it on: every
-- column as DBD::Pg reads it -- the integers as numbers, the rest as text --
-- payload and metadata decoded.
CREATE FUNCTION api.core_event_of_row_v1(p_row public.event_log)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object(
    'actor_id', p_row.actor_id::text,
    'aggregate_id', p_row.aggregate_id::text,
    'aggregate_type', p_row.aggregate_type,
    'aggregate_version', p_row.aggregate_version,
    'causation_id', p_row.causation_id::text,
    'correlation_id', p_row.correlation_id::text,
    'created_at', p_row.created_at::text,
    'event_id', p_row.event_id::text,
    'event_type', p_row.event_type,
    'idempotency_key', p_row.idempotency_key,
    'metadata', p_row.metadata,
    'payload', p_row.payload,
    'schema_version', p_row.schema_version
)
$$;
REVOKE EXECUTE ON FUNCTION api.core_event_of_row_v1(public.event_log)
    FROM PUBLIC;

-- Domain::EventEnvelope::transport_payload: the document the outbox carries
-- for an event, from the event as the recorder holds it (p_event's keys and
-- JSON types are the Perl hash's).
CREATE FUNCTION api.core_transport_payload_v1(p_event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    event_metadata jsonb := CASE
        WHEN jsonb_typeof(p_event -> 'metadata') = 'object'
        THEN p_event -> 'metadata' ELSE '{}'::jsonb END;
    payload jsonb := CASE
        WHEN jsonb_typeof(p_event -> 'payload') = 'object'
        THEN p_event -> 'payload' ELSE '{}'::jsonb END;
    stamp jsonb;
    metadata jsonb;
    document jsonb;
BEGIN
    stamp := CASE
        WHEN api.core_perl_true_v1(p_event ->> 'created_at')
        THEN p_event -> 'created_at' ELSE event_metadata -> 'timestamp' END;
    metadata := event_metadata || jsonb_build_object(
        'actor', jsonb_build_object('id', p_event -> 'actor_id'),
        'aggregate_id', p_event -> 'aggregate_id',
        'causation_id', p_event -> 'causation_id',
        'correlation_id', p_event -> 'correlation_id',
        'event_id', p_event -> 'event_id',
        'transport', jsonb_build_object(
            'listen_notify_channel', 'gpforum_domain_events',
            'minion_job', 'domain_event.dispatch',
            'stream', 'gpforum.domain_events'));
    IF length(coalesce(stamp #>> '{}', '')) > 0 THEN
        metadata := metadata || jsonb_build_object('timestamp', stamp);
    END IF;
    stamp := CASE
        WHEN api.core_perl_true_v1(p_event ->> 'created_at')
        THEN p_event -> 'created_at' ELSE metadata -> 'timestamp' END;

    document := jsonb_build_object(
        'aggregate', jsonb_build_object(
            'id', p_event -> 'aggregate_id',
            'type', p_event -> 'aggregate_type',
            'version', p_event -> 'aggregate_version'),
        'aggregate_id', p_event -> 'aggregate_id',
        'aggregate_type', p_event -> 'aggregate_type',
        'aggregate_version', p_event -> 'aggregate_version',
        'actor', jsonb_build_object('id', p_event -> 'actor_id'),
        'actor_id', p_event -> 'actor_id',
        'causation_id', p_event -> 'causation_id',
        'contract', 'gpforum.domain_event',
        'contract_version', 1,
        'correlation_id', p_event -> 'correlation_id',
        'domain_payload', payload,
        'event_id', p_event -> 'event_id',
        'event_type', p_event -> 'event_type',
        'idempotency_key', p_event -> 'idempotency_key',
        'metadata', metadata,
        'payload', payload,
        'schema_version', p_event -> 'schema_version',
        'transport', jsonb_build_object(
            'kafka_topic', 'gpforum.domain_events',
            'listen_notify_channel', 'gpforum_domain_events',
            'minion_job', 'domain_event.dispatch',
            'nats_subject', 'gpforum.domain_events',
            'partition_key', CASE
                WHEN api.core_perl_true_v1(p_event ->> 'aggregate_id')
                THEN p_event -> 'aggregate_id'
                ELSE p_event -> 'event_id' END));
    IF length(coalesce(stamp #>> '{}', '')) > 0 THEN
        document := document || jsonb_build_object(
            'occurred_at', stamp, 'timestamp', stamp);
    END IF;

    RETURN document;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_transport_payload_v1(jsonb) FROM PUBLIC;

-- EventRecorder::_ensure_outbox: the event's outbox row unless its key is
-- taken. A conflict on the id is a raced write or an id drawn twice, one on
-- the key the same message written first: the stored row is taken when
-- there is one, else an id conflict is tried once more with a new id.
CREATE FUNCTION api.core_ensure_outbox_v1(p_event jsonb, p_outbox_id text)
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
            api.core_transport_payload_v1(p_event), 'events', 'pending');
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
            api.core_transport_payload_v1(p_event), 'events', 'pending');
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_ensure_outbox_v1(jsonb, text) FROM PUBLIC;

-- EventRecorder::record_event for an event whose id the recorder drew: an
-- event of that id is reused (looked up in every partition, ADR 0116), else
-- inserted; a conflict on its key is the same open event when the stored
-- one has the same idempotency key, else an id drawn twice, written once
-- more under a new id. Then its outbox row. Returns the event as recorded,
-- with skipped => 1 when one was reused.
CREATE FUNCTION api.core_record_event_v1(p_event jsonb, p_outbox_id text)
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
        PERFORM api.core_ensure_outbox_v1(stored, p_outbox_id);
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

    PERFORM api.core_ensure_outbox_v1(stored, p_outbox_id);
    RETURN stored;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_record_event_v1(jsonb, text) FROM PUBLIC;

-- AuditRecord::build and EventRecorder::_insert_audit: the audit row chained
-- to the newest one, its record_hash the SHA-256 of its canonical JSON.
CREATE FUNCTION api.core_append_audit_v1(
    p_action text,
    p_actor_id text,
    p_audit_id text,
    p_correlation_id text,
    p_created_at text,
    p_metadata jsonb,
    p_schema_version integer,
    p_target_id text,
    p_target_type text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    tip text;
    previous text;
    audit jsonb;
    chain_hash text;
BEGIN
    SELECT me.record_hash INTO tip FROM public.audit_log me
    ORDER BY me.created_at DESC, me.audit_id DESC
    LIMIT 1;
    previous := CASE WHEN length(coalesce(tip, '')) > 0 THEN tip END;

    audit := jsonb_build_object(
        'action', p_action,
        'actor_id', p_actor_id,
        'audit_id', p_audit_id,
        'correlation_id', p_correlation_id,
        'created_at', p_created_at,
        'metadata', coalesce(p_metadata, '{}'::jsonb),
        'previous_hash', previous,
        'schema_version', p_schema_version,
        'target_id', p_target_id,
        'target_type', p_target_type);
    chain_hash := encode(sha256(convert_to(
        api.core_canonical_json_v1(audit), 'UTF8')), 'hex');

    INSERT INTO public.audit_log (action, actor_id, audit_id, correlation_id,
        created_at, metadata, previous_hash, record_hash, schema_version,
        target_id, target_type)
    VALUES (p_action, p_actor_id::uuid, p_audit_id::uuid,
        p_correlation_id::uuid, p_created_at::timestamptz,
        coalesce(p_metadata, '{}'::jsonb), previous, chain_hash,
        p_schema_version, p_target_id::uuid, p_target_type);

    RETURN audit || jsonb_build_object('record_hash', chain_hash);
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_append_audit_v1(text, text, text, text,
    text, jsonb, integer, text, text) FROM PUBLIC;

-- EventRecorder::record_audit for an audit whose id the record drew: the
-- audit chain's lock, held to the end of the transaction, then the row; an
-- id drawn twice is written once more under a new id.
CREATE FUNCTION api.core_record_audit_v1(
    p_action text,
    p_actor_id text,
    p_audit_id text,
    p_correlation_id text,
    p_created_at text,
    p_metadata jsonb,
    p_schema_version integer,
    p_target_id text,
    p_target_type text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    reported text;
BEGIN
    PERFORM pg_advisory_xact_lock(2026060210);
    BEGIN
        RETURN api.core_append_audit_v1(p_action, p_actor_id, p_audit_id,
            p_correlation_id, p_created_at, p_metadata, p_schema_version,
            p_target_id, p_target_type);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'audit_log_pkey') THEN
            RAISE;
        END IF;
        RETURN api.core_append_audit_v1(p_action, p_actor_id,
            api.core_uuid_v7_v1()::text, p_correlation_id, p_created_at,
            p_metadata, p_schema_version, p_target_id, p_target_type);
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_record_audit_v1(text, text, text, text,
    text, jsonb, integer, text, text) FROM PUBLIC;

-- PostStore::_with_new_id: the command with a new id for its post, body or
-- revision, in every part that carries it.
CREATE FUNCTION api.core_forum_with_new_id_v1(p_command jsonb, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    new_id jsonb := to_jsonb(api.core_uuid_v7_v1()::text);
BEGIN
    IF p_kind = 'post' THEN
        RETURN jsonb_set(jsonb_set(jsonb_set(p_command,
            '{body,post_id}', new_id), '{post,post_id}', new_id),
            '{revision,post_id}', new_id);
    ELSIF p_kind = 'body' THEN
        RETURN jsonb_set(jsonb_set(p_command,
            '{body,body_id}', new_id), '{revision,body_id}', new_id);
    END IF;

    RETURN jsonb_set(p_command, '{revision,revision_id}', new_id);
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_with_new_id_v1(jsonb, text)
    FROM PUBLIC;

-- PostStore::_stored_part for the body: inserted, or, when its id is taken,
-- kept if the row holding it is the same post's, else given up for a new
-- one, once. Any other conflict is the caller's. Returns the command as
-- written.
CREATE FUNCTION api.core_forum_store_body_v1(p_command jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    part jsonb := p_command -> 'body';
    reported text;
    owner text;
    retry jsonb;
BEGIN
    BEGIN
        INSERT INTO public.post_bodies (body_format, body_id,
            body_rendered_safe, body_source, post_id, source_hash)
        VALUES (part ->> 'body_format', (part ->> 'body_id')::uuid,
            part ->> 'body_rendered_safe', part ->> 'body_source',
            (part ->> 'post_id')::uuid, part ->> 'source_hash');
        RETURN p_command;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'post_bodies_pkey') THEN
            RAISE;
        END IF;
        SELECT me.post_id::text INTO owner FROM public.post_bodies me
        WHERE me.body_id = (part ->> 'body_id')::uuid;
        IF FOUND AND coalesce(owner, '') = coalesce(part ->> 'post_id', '')
        THEN
            RETURN p_command;
        END IF;
        retry := api.core_forum_with_new_id_v1(p_command, 'body');
        part := retry -> 'body';
        INSERT INTO public.post_bodies (body_format, body_id,
            body_rendered_safe, body_source, post_id, source_hash)
        VALUES (part ->> 'body_format', (part ->> 'body_id')::uuid,
            part ->> 'body_rendered_safe', part ->> 'body_source',
            (part ->> 'post_id')::uuid, part ->> 'source_hash');
        RETURN retry;
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_store_body_v1(jsonb) FROM PUBLIC;

-- PostStore::_stored_part for the revision, as for the body.
CREATE FUNCTION api.core_forum_store_revision_v1(p_command jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    part jsonb := p_command -> 'revision';
    reported text;
    owner text;
    retry jsonb;
BEGIN
    BEGIN
        INSERT INTO public.post_revisions (body_id, edit_reason,
            editor_user_id, post_id, revision_id, revision_number)
        VALUES ((part ->> 'body_id')::uuid, part ->> 'edit_reason',
            (part ->> 'editor_user_id')::uuid, (part ->> 'post_id')::uuid,
            (part ->> 'revision_id')::uuid,
            (part ->> 'revision_number')::integer);
        RETURN p_command;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'post_revisions_pkey') THEN
            RAISE;
        END IF;
        SELECT me.post_id::text INTO owner FROM public.post_revisions me
        WHERE me.revision_id = (part ->> 'revision_id')::uuid;
        IF FOUND AND coalesce(owner, '') = coalesce(part ->> 'post_id', '')
        THEN
            RETURN p_command;
        END IF;
        retry := api.core_forum_with_new_id_v1(p_command, 'revision');
        part := retry -> 'revision';
        INSERT INTO public.post_revisions (body_id, edit_reason,
            editor_user_id, post_id, revision_id, revision_number)
        VALUES ((part ->> 'body_id')::uuid, part ->> 'edit_reason',
            (part ->> 'editor_user_id')::uuid, (part ->> 'post_id')::uuid,
            (part ->> 'revision_id')::uuid,
            (part ->> 'revision_number')::integer);
        RETURN retry;
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_store_revision_v1(jsonb)
    FROM PUBLIC;

-- PostStore::_count_replies (ADR 0119): the delta added to the thread's
-- counter row in SQL, never below zero, the row taken after the thread's
-- and the post's. A thread without a row gets one; an insert that loses
-- the race adds the delta to the row that won.
CREATE FUNCTION api.core_forum_count_replies_v1(p_thread_id text,
    p_delta integer)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    reported text;
BEGIN
    PERFORM 1 FROM public.thread_counters me
    WHERE me.thread_id = p_thread_id::uuid;
    IF NOT FOUND THEN
        BEGIN
            INSERT INTO public.thread_counters (reply_count, thread_id)
            VALUES (greatest(p_delta, 0), p_thread_id::uuid);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            PERFORM 1 FROM public.thread_counters me
            WHERE me.thread_id = p_thread_id::uuid;
            IF NOT FOUND OR NOT api.core_unique_on_v1(reported,
                'thread_counters_pkey') THEN
                RAISE;
            END IF;
        END;
    END IF;

    UPDATE public.thread_counters me
    SET reply_count = GREATEST(me.reply_count + p_delta, 0)
    WHERE me.thread_id = p_thread_id::uuid;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_count_replies_v1(text, integer)
    FROM PUBLIC;

-- PostStore::_record for post.created, through Forum::Event's envelope and
-- audit row: the event (EventEnvelope::record's keys and types) and its
-- outbox row, then the audit row, under the caller's correlation id.
CREATE FUNCTION api.core_forum_record_post_created_v1(p_command jsonb,
    p_record jsonb)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    post jsonb := p_command -> 'post';
    stamp jsonb := p_record -> 'recorded_at';
    event_key text;
BEGIN
    event_key := CASE
        WHEN length(coalesce(p_command ->> 'idempotency_key', '')) > 0
        THEN 'command:' || (p_command ->> 'idempotency_key')
            || ':post.created'
        ELSE 'post.created:' || coalesce(post ->> 'post_id', '') END;

    PERFORM api.core_record_event_v1(jsonb_build_object(
        'actor_id', post -> 'author_user_id',
        'aggregate_id', post -> 'post_id',
        'aggregate_type', 'post',
        'aggregate_version', 1,
        'causation_id', NULL,
        'correlation_id', p_record -> 'correlation_id',
        'created_at', stamp,
        'event_id', p_record -> 'event_id',
        'event_type', 'post.created',
        'idempotency_key', event_key,
        'metadata', jsonb_build_object(
            'actor', jsonb_build_object('id', post -> 'author_user_id'),
            'aggregate_id', post -> 'post_id',
            'causation_id', NULL,
            'correlation_id', p_record -> 'correlation_id',
            'event_id', p_record -> 'event_id',
            'timestamp', stamp,
            'transport', jsonb_build_object(
                'listen_notify_channel', 'gpforum_domain_events',
                'minion_job', 'domain_event.dispatch',
                'stream', 'gpforum.domain_events')),
        'payload', jsonb_build_object(
            'author_user_id', post -> 'author_user_id',
            'post_id', post -> 'post_id',
            'revision_id', p_command #> '{revision,revision_id}',
            'thread_id', post -> 'thread_id'),
        'schema_version', 1
    ), p_record ->> 'outbox_id');

    PERFORM api.core_record_audit_v1('post.created',
        post ->> 'author_user_id', p_record ->> 'audit_id',
        p_record ->> 'correlation_id', p_record ->> 'recorded_at',
        jsonb_build_object('thread_id', post -> 'thread_id'), 1,
        post ->> 'post_id', 'post');
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_record_post_created_v1(jsonb,
    jsonb) FROM PUBLIC;

-- PostStore::_write_copy and _finish_new_post: the new post's body and
-- revision, its reply count, the post pointed at both (only when an id was
-- given up, as DBIx::Class updates only the columns that changed), and
-- post.created recorded. p_post is the post row as the caller holds it.
-- Returns { command, post }, the command as written and the row.
CREATE FUNCTION api.core_forum_write_copy_v1(p_command jsonb, p_post jsonb,
    p_record jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    command jsonb;
    body_moved boolean;
    revision_moved boolean;
BEGIN
    command := api.core_forum_store_body_v1(p_command);
    command := api.core_forum_store_revision_v1(command);
    PERFORM api.core_forum_count_replies_v1(command #>> '{post,thread_id}',
        1);

    body_moved := (p_post ->> 'current_body_id')
        IS DISTINCT FROM (command #>> '{body,body_id}');
    revision_moved := (p_post ->> 'current_revision_id')
        IS DISTINCT FROM (command #>> '{revision,revision_id}');
    IF body_moved OR revision_moved THEN
        UPDATE public.posts me
        SET current_body_id = CASE WHEN body_moved
                THEN (command #>> '{body,body_id}')::uuid
                ELSE me.current_body_id END,
            current_revision_id = CASE WHEN revision_moved
                THEN (command #>> '{revision,revision_id}')::uuid
                ELSE me.current_revision_id END
        WHERE me.post_id = (p_post ->> 'post_id')::uuid;
    END IF;

    PERFORM api.core_forum_record_post_created_v1(command, p_record);

    RETURN jsonb_build_object('command', command,
        'post', p_post || jsonb_build_object(
            'current_body_id', command #> '{body,body_id}',
            'current_revision_id', command #> '{revision,revision_id}'));
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_write_copy_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- PostStore::_insert_reply: the post at the thread's next position, from 1,
-- unless the command names a positive one, then its copy. Returns
-- { command, post }.
CREATE FUNCTION api.core_forum_insert_reply_v1(p_command jsonb,
    p_record jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    command jsonb := p_command;
    post jsonb;
    latest bigint;
BEGIN
    IF coalesce((command #>> '{post,position}')::bigint, 0) <= 0 THEN
        SELECT me.position INTO latest FROM public.posts me
        WHERE me.thread_id = (command #>> '{post,thread_id}')::uuid
        ORDER BY me.position DESC, me.post_id DESC
        LIMIT 1;
        command := jsonb_set(command, '{post,position}',
            to_jsonb(CASE WHEN FOUND THEN latest + 1 ELSE 1 END));
    END IF;
    post := command -> 'post';

    INSERT INTO public.posts (author_user_id, current_body_id,
        current_revision_id, deleted_at, deleted_by, hidden_at, locked_at,
        moderation_state, permission_version, position, post_id, thread_id,
        version, visibility, visibility_version)
    VALUES ((post ->> 'author_user_id')::uuid,
        (post ->> 'current_body_id')::uuid,
        (post ->> 'current_revision_id')::uuid,
        (post ->> 'deleted_at')::timestamptz, (post ->> 'deleted_by')::uuid,
        (post ->> 'hidden_at')::timestamptz,
        (post ->> 'locked_at')::timestamptz, post ->> 'moderation_state',
        (post ->> 'permission_version')::bigint,
        (post ->> 'position')::bigint, (post ->> 'post_id')::uuid,
        (post ->> 'thread_id')::uuid, (post ->> 'version')::bigint,
        post ->> 'visibility', (post ->> 'visibility_version')::bigint);

    RETURN api.core_forum_write_copy_v1(command, post, p_record);
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_insert_reply_v1(jsonb, jsonb)
    FROM PUBLIC;

-- PostStore::create_post. The thread row is taken FOR NO KEY UPDATE first
-- (ADR 0111): the lock hands out positions in commit order and orders the
-- reply against a moderator's lock or hide and its author's delete, so the
-- thread is checked again as the lock returns it, by Domain::Thread's rule
-- for a writer (shown_to_writer, then reply_refusal). A refusal writes
-- nothing and is answered by its code: thread_not_found or thread_locked.
--
-- Then the post, in a block (PostStore::_insert_post): a post id already
-- taken by a post of the same thread is an earlier run of the same command,
-- finished here -- skipped when its body is stored too, else its body,
-- revision, count and pointers written now; one taken by another thread's
-- post gives its id up for a new one, once. Any other conflict -- a
-- position taken meanwhile -- gets the position allocated again, once.
--
-- Returns one row: the refusal, or the post as the store answers it
-- (skipped, and the post's columns, as given for a new post and as stored
-- for one found).
CREATE FUNCTION api.core_forum_store_reply_v1(
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
    p_idempotency_key text,
    p_correlation_id text,
    p_event_id text,
    p_outbox_id text,
    p_audit_id text,
    p_recorded_at text
)
RETURNS TABLE (
    refusal text,
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
    thread record;
    command jsonb;
    ids jsonb;
    written jsonb;
    found_post public.posts;
    reported text;
    body_owner text;
    row_post jsonb;
BEGIN
    SELECT me.author_user_id, me.deleted_at, me.locked_at, me.moderation_state
    INTO thread
    FROM public.threads me
    WHERE me.thread_id = p_thread_id::uuid
    FOR NO KEY UPDATE;
    IF NOT FOUND
        OR coalesce(thread.moderation_state, '') NOT IN ('locked', 'visible')
        OR ( thread.deleted_at IS NOT NULL
            AND NOT ( length(coalesce(p_author_user_id, '')) > 0
                AND coalesce(thread.author_user_id::text, '')
                    = p_author_user_id ) )
    THEN
        RETURN QUERY SELECT 'thread_not_found'::text, NULL::boolean,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    IF thread.locked_at IS NOT NULL THEN
        RETURN QUERY SELECT 'thread_locked'::text, NULL::boolean,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    command := jsonb_build_object(
        'idempotency_key', p_idempotency_key,
        'post', jsonb_build_object(
            'author_user_id', p_author_user_id,
            'current_body_id', p_current_body_id,
            'current_revision_id', p_current_revision_id,
            'deleted_at', p_deleted_at,
            'deleted_by', p_deleted_by,
            'hidden_at', p_hidden_at,
            'locked_at', p_locked_at,
            'moderation_state', p_moderation_state,
            'permission_version', p_permission_version,
            'position', p_position,
            'post_id', p_post_id,
            'thread_id', p_thread_id,
            'version', p_version,
            'visibility', p_visibility,
            'visibility_version', p_visibility_version),
        'body', jsonb_build_object(
            'body_format', p_body_format,
            'body_id', p_body_id,
            'body_rendered_safe', p_body_rendered_safe,
            'body_source', p_body_source,
            'post_id', p_body_post_id,
            'source_hash', p_source_hash),
        'revision', jsonb_build_object(
            'body_id', p_revision_body_id,
            'edit_reason', p_edit_reason,
            'editor_user_id', p_editor_user_id,
            'post_id', p_revision_post_id,
            'revision_id', p_revision_id,
            'revision_number', p_revision_number));
    ids := jsonb_build_object(
        'audit_id', p_audit_id,
        'correlation_id', p_correlation_id,
        'event_id', p_event_id,
        'outbox_id', p_outbox_id,
        'recorded_at', p_recorded_at);

    BEGIN
        written := api.core_forum_insert_reply_v1(command, ids);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'posts_pkey') THEN
            written := api.core_forum_insert_reply_v1(
                jsonb_set(command, '{post,position}', '0'::jsonb), ids);
        ELSE
            SELECT me.* INTO found_post FROM public.posts me
            WHERE me.post_id = p_post_id::uuid;
            row_post := CASE WHEN FOUND THEN jsonb_build_object(
                'author_user_id', found_post.author_user_id::text,
                'current_body_id', found_post.current_body_id::text,
                'current_revision_id', found_post.current_revision_id::text,
                'deleted_at', found_post.deleted_at::text,
                'deleted_by', found_post.deleted_by::text,
                'hidden_at', found_post.hidden_at::text,
                'locked_at', found_post.locked_at::text,
                'moderation_state', found_post.moderation_state,
                'permission_version', found_post.permission_version::text,
                'position', found_post.position::text,
                'post_id', found_post.post_id::text,
                'thread_id', found_post.thread_id::text,
                'version', found_post.version::text,
                'visibility', found_post.visibility,
                'visibility_version', found_post.visibility_version::text)
            END;
            IF row_post IS NULL
                OR coalesce(row_post ->> 'thread_id', '')
                    <> coalesce(p_thread_id, '')
            THEN
                written := api.core_forum_insert_reply_v1(
                    api.core_forum_with_new_id_v1(command, 'post'), ids);
            ELSE
                SELECT me.post_id::text INTO body_owner
                FROM public.post_bodies me
                WHERE me.body_id = p_body_id::uuid;
                IF FOUND
                    AND coalesce(body_owner, '')
                        = coalesce(p_body_post_id, '')
                THEN
                    written := jsonb_build_object('post', row_post,
                        'skipped', true);
                ELSE
                    written := api.core_forum_write_copy_v1(command,
                        row_post, ids);
                END IF;
            END IF;
        END IF;
    END;

    RETURN QUERY SELECT NULL::text,
        coalesce((written ->> 'skipped')::boolean, false),
        written #>> '{post,post_id}',
        written #>> '{post,thread_id}',
        written #>> '{post,author_user_id}',
        written #>> '{post,current_body_id}',
        written #>> '{post,current_revision_id}',
        written #>> '{post,position}',
        written #>> '{post,visibility}',
        written #>> '{post,moderation_state}',
        written #>> '{post,version}',
        written #>> '{post,visibility_version}',
        written #>> '{post,permission_version}',
        written #>> '{post,hidden_at}',
        written #>> '{post,locked_at}',
        written #>> '{post,deleted_at}',
        written #>> '{post,deleted_by}';
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_store_reply_v1(text, text, text, text,
    text, bigint, text, text, bigint, bigint, bigint, text, text, text, text,
    text, text, text, text, text, text, text, text, text, text, integer, text,
    text, text, text, text, text, text) FROM PUBLIC;

-- CommandIdempotency::_existing_result: a command already in the log is a
-- conflict when its request hash is another, in progress while it has no
-- response, else its response is replayed.
CREATE FUNCTION api.core_command_existing_v1(p_payload jsonb,
    p_request_hash text)
RETURNS TABLE (outcome text, response jsonb)
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE
        WHEN CASE WHEN api.core_perl_true_v1(payload ->> 'request_hash')
                THEN payload ->> 'request_hash' ELSE '' END
            <> p_request_hash THEN 'conflict'
        WHEN NOT payload ? 'response' THEN 'in_progress'
        ELSE 'replayed' END,
    CASE WHEN payload ? 'response'
            AND CASE WHEN api.core_perl_true_v1(payload ->> 'request_hash')
                THEN payload ->> 'request_hash' ELSE '' END = p_request_hash
        THEN payload -> 'response' END
FROM (SELECT CASE WHEN jsonb_typeof(p_payload) = 'object'
        THEN p_payload ELSE '{}'::jsonb END AS payload) AS held
$$;
REVOKE EXECUTE ON FUNCTION api.core_command_existing_v1(jsonb, text)
    FROM PUBLIC;

-- The reply command (PostingWorkflow::create_reply through
-- CommandIdempotency::run): once per command key, the request hash kept
-- with the response. In the order run follows: the key looked up and its
-- answer replayed, or refused as another request's or one in progress; the
-- command row inserted, a taken command id drawn again or the row of the
-- same key reused; then the answer. The workflow's check before the lock
-- and its composer ran in Perl, which hands in their answer as the
-- response to record (p_answer), else the store runs and its answer is
-- recorded: the post, or its refusal, in the words p_store_refusals gives
-- for each code. The response, its hash, the status and handled_at finish
-- the row. A failure raises: nothing is committed, as the abandoned
-- transaction committed nothing.
--
-- Returns one row: outcome (recorded, replayed, conflict or in_progress),
-- the response recorded or replayed, and for a post the store's row.
CREATE FUNCTION api.forum_create_reply_v1(
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
)
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
BEGIN
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
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v1(text, text, text, text,
    text, text, text, jsonb, jsonb, text, text, text, text, text, bigint,
    text, text, bigint, bigint, bigint, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, integer, text, text,
    text, text, text, text) FROM PUBLIC;

COMMIT;
