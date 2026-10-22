-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The row types and the shared steps of api (ADR 0126). Every function of 1011
-- to 1022 runs with its caller's rights (SECURITY INVOKER); only the entry
-- points of 1023 take the owner's. Every function pins search_path =
-- pg_catalog, pg_temp and names every table and function of its own with their
-- schema, so no session setting can redirect a name, and pins plan_cache_mode:
-- force_generic_plan where one plan serves every value (lookups by key, keyset
-- pages, writes by key), force_custom_plan where the best plan depends on the
-- values (search). A read is STABLE and a write VOLATILE; a pure function of
-- its arguments is IMMUTABLE and PARALLEL SAFE. One statement is LANGUAGE sql,
-- branches and writes are plpgsql (ADR 0126, section 3). LEAKPROOF is not
-- used: it matters only behind row security or a security barrier view, which
-- the forum has neither of, and needs a superuser to set. A core_ function is
-- a step other functions share; the application never calls one.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The rows api answers with (ADR 0126, section 2). A function that returns a
-- table's row returns one of these, not the table's own row type: each is the
-- table's columns at 1.0, in their order, so a column the table gains later
-- changes no shipped function, and the prepared calls of the workers that run
-- it stay valid.

CREATE TYPE api.admin_announcement_v1 AS (
    announcement_id uuid,
    message text,
    tone text,
    created_by uuid,
    created_at timestamptz,
    retired_by uuid,
    retired_at timestamptz
);

CREATE TYPE api.admin_audit_entry_v1 AS (
    audit_id uuid,
    action text,
    schema_version integer,
    actor_id uuid,
    target_type text,
    target_id uuid,
    correlation_id uuid,
    previous_hash text,
    record_hash text,
    metadata jsonb,
    created_at timestamptz
);

CREATE TYPE api.admin_permission_v1 AS (
    permission_id uuid,
    name text,
    resource_type text,
    action text,
    created_at timestamptz
);

CREATE TYPE api.admin_role_binding_v1 AS (
    binding_id uuid,
    user_id uuid,
    role_id uuid,
    resource_type text,
    resource_id uuid,
    space_id uuid,
    created_at timestamptz,
    revoked_at timestamptz,
    created_by_user_id uuid
);

CREATE TYPE api.admin_role_permission_v1 AS (
    role_id uuid,
    permission_id uuid,
    created_at timestamptz
);

CREATE TYPE api.admin_role_v1 AS (
    role_id uuid,
    name text,
    description text,
    created_at timestamptz
);

CREATE TYPE api.attachment_file_v1 AS (
    attachment_id uuid,
    owner_user_id uuid,
    object_key text,
    original_filename text,
    media_type text,
    byte_size bigint,
    checksum text,
    state text,
    scan_status text,
    created_at timestamptz,
    uploaded_at timestamptz,
    scanned_at timestamptz,
    quarantined_at timestamptz,
    deleted_at timestamptz,
    scan_engine text,
    scan_signature text,
    scan_attempts integer,
    scan_error text
);

CREATE TYPE api.attachment_link_v1 AS (
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz
);

CREATE TYPE api.attachment_variant_v1 AS (
    attachment_variant_id uuid,
    attachment_id uuid,
    variant_type text,
    object_key text,
    media_type text,
    byte_size bigint,
    created_at timestamptz
);

CREATE TYPE api.community_bookmark_v1 AS (
    bookmark_id uuid,
    user_id uuid,
    target_type text,
    target_id uuid,
    note text,
    created_at timestamptz,
    deleted_at timestamptz
);

CREATE TYPE api.forum_category_v1 AS (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz
);

CREATE TYPE api.forum_post_v1 AS (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    current_revision_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    version bigint,
    visibility_version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    hidden_at timestamptz,
    locked_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid
);

CREATE TYPE api.forum_read_state_v1 AS (
    user_id uuid,
    thread_id uuid,
    last_read_position bigint,
    last_read_at timestamptz
);

CREATE TYPE api.forum_space_v1 AS (
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz
);

CREATE TYPE api.forum_thread_v1 AS (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    version bigint,
    visibility_version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid
);

CREATE TYPE api.identity_credential_v1 AS (
    id uuid,
    user_id uuid,
    type text,
    secret_hash text,
    created_at timestamptz,
    revoked_at timestamptz
);

CREATE TYPE api.identity_session_v1 AS (
    session_id uuid,
    user_id uuid,
    session_hash text,
    created_at timestamptz,
    last_seen_at timestamptz,
    expires_at timestamptz,
    revoked_at timestamptz,
    ip_hash text,
    user_agent_hash text
);

CREATE TYPE api.identity_token_v1 AS (
    token_id uuid,
    user_id uuid,
    token_type text,
    token_hash text,
    email_normalized text,
    created_at timestamptz,
    expires_at timestamptz,
    used_at timestamptz,
    metadata jsonb
);

CREATE TYPE api.identity_trust_snapshot_v1 AS (
    user_id uuid,
    score integer,
    trust_level integer,
    calculated_at timestamptz,
    version bigint
);

CREATE TYPE api.identity_user_v1 AS (
    id uuid,
    username text,
    display_name text,
    email_normalized text,
    password_hash text,
    status text,
    trust_level integer,
    version bigint,
    permission_version bigint,
    email_verified_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    preferred_locale text,
    preferred_theme text,
    preferred_timezone text,
    bio text
);

CREATE TYPE api.moderation_action_v1 AS (
    moderation_action_id uuid,
    actor_user_id uuid,
    action_type text,
    target_type text,
    target_id uuid,
    reason text,
    metadata jsonb,
    created_at timestamptz,
    reversed_at timestamptz,
    reversed_by_user_id uuid,
    command_id uuid
);

CREATE TYPE api.moderation_report_v1 AS (
    report_id uuid,
    reporter_user_id uuid,
    target_type text,
    target_id uuid,
    reason text,
    details text,
    status text,
    assigned_moderator_user_id uuid,
    created_at timestamptz,
    resolved_at timestamptz,
    resolution text
);

CREATE TYPE api.moderation_suspension_v1 AS (
    suspension_id uuid,
    user_id uuid,
    actor_user_id uuid,
    reason text,
    valid_from timestamptz,
    valid_to timestamptz,
    revoked_at timestamptz,
    metadata jsonb
);

CREATE TYPE api.notification_preference_v1 AS (
    user_id uuid,
    channel text,
    enabled boolean,
    digest_frequency text,
    updated_at timestamptz
);

CREATE TYPE api.notification_subscription_v1 AS (
    subscription_id uuid,
    user_id uuid,
    target_type text,
    target_id uuid,
    preference text,
    created_at timestamptz,
    muted_at timestamptz,
    revoked_at timestamptz
);

CREATE TYPE api.ops_partition_v1 AS (
    table_name text,
    partition_name text,
    range_start timestamptz,
    range_end timestamptz,
    state text,
    created_at timestamptz,
    detached_at timestamptz,
    archived_at timestamptz
);

CREATE TYPE api.ops_query_budget_v1 AS (
    endpoint_name text,
    max_queries integer,
    max_transactions integer,
    notes text,
    created_at timestamptz
);

CREATE TYPE api.outbox_message_v1 AS (
    outbox_id uuid,
    event_id uuid,
    queue text,
    job_type text,
    idempotency_key text,
    payload jsonb,
    available_at timestamptz,
    created_at timestamptz,
    locked_at timestamptz,
    attempts integer,
    status text,
    last_error text,
    next_attempt_at timestamptz,
    locked_by text,
    locked_until timestamptz,
    attempt_count integer,
    last_error_class text,
    failure_type text
);

-- A jsonb value as JSON::MaybeXS writes it with canonical => 1, utf8 => 1:
-- keys sorted by code point, no whitespace, strings escaped as
-- Cpanel::JSON::XS escapes them. The command log's response_hash and the audit
-- chain's record_hash are SHA-256 of this text, so a function that records
-- either writes it byte for byte as Perl does
-- (t/integration/postgres-sql-function-canonical-json.t proves it).
CREATE FUNCTION api.core_canonical_json_v1(p_value jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE jsonb_typeof(p_value)
    WHEN 'object' THEN
        '{' || coalesce((
            SELECT string_agg(
                to_jsonb(member.key)::text || ':'
                    || api.core_canonical_json_v1(member.value),
                ',' ORDER BY member.key COLLATE "C")
            FROM jsonb_each(p_value) AS member
        ), '') || '}'
    WHEN 'array' THEN
        '[' || coalesce((
            SELECT string_agg(
                api.core_canonical_json_v1(element.value),
                ',' ORDER BY element.place)
            FROM jsonb_array_elements(p_value)
                WITH ORDINALITY AS element (value, place)
        ), '') || ']'
    ELSE p_value::text
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_canonical_json_v1(jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.core_append_audit_v1(text, text, text, text, text, jsonb, integer, text, text)
    FROM PUBLIC;

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

-- The command log's close: the answer, its canonical hash and the status
-- the Perl path stored (handled for an answer that says ok, rejected
-- otherwise), handled at the command's own time.
CREATE FUNCTION api.core_command_close_v1(
    p_command_id text,
    p_command_at text,
    p_payload jsonb,
    p_answer jsonb
)
RETURNS TABLE (closed boolean)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH changed AS (
    UPDATE public.command_log me
    SET handled_at = p_command_at::timestamptz,
        payload = p_payload || jsonb_build_object('response', p_answer),
        response_hash = encode(sha256(convert_to(
            api.core_canonical_json_v1(p_answer), 'UTF8')), 'hex'),
        status = CASE WHEN api.core_perl_true_v1(p_answer ->> 'ok')
            THEN 'handled' ELSE 'rejected' END
    WHERE me.command_id = p_command_id::uuid
    RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM changed)
$$;
REVOKE EXECUTE ON FUNCTION api.core_command_close_v1(text, text, jsonb, jsonb)
    FROM PUBLIC;

-- CommandIdempotency::_existing_result: a command already in the log is a
-- conflict when its request hash is another, in progress while it has no
-- response, else its response is replayed.
CREATE FUNCTION api.core_command_existing_v1(
    p_payload jsonb,
    p_request_hash text
)
RETURNS TABLE (outcome text, response jsonb)
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
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

-- A UUIDv7 as Infrastructure::Id mints one: the Unix time in milliseconds,
-- then random bits, version 7. gen_random_uuid's version 4 nibble becomes 7
-- with two bits set; PostgreSQL 16 and 17 have no uuidv7().
CREATE FUNCTION api.core_uuid_v7_v1()
RETURNS uuid
LANGUAGE sql
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

-- The command log's opening, as api.forum_create_reply_v1 does it inline:
-- a key already logged replays its response, conflicts on another request
-- hash or is in progress; a new row is inserted, a taken command id is
-- drawn again, and a row of the same key without a response is reused.
-- 'opened' hands back the row's id and payload for the close.
CREATE FUNCTION api.core_command_open_v1(p_log jsonb)
RETURNS TABLE (outcome text, response jsonb, command_id text, payload jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    existing public.command_log;
    held record;
    row_command_id text := p_log ->> 'command_id';
    held_payload jsonb :=
        jsonb_build_object('request_hash', p_log ->> 'request_hash');
    reported text;
BEGIN
    SELECT me.* INTO existing FROM public.command_log me
    WHERE me.idempotency_key = p_log ->> 'idempotency_key'
    LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held FROM api.core_command_existing_v1(
            existing.payload, p_log ->> 'request_hash');
        RETURN QUERY SELECT held.outcome, held.response, NULL::text,
            NULL::jsonb;
        RETURN;
    END IF;
    BEGIN
        INSERT INTO public.command_log (actor_id, command_id, command_type,
            correlation_id, created_at, handled_at, idempotency_key, payload,
            response_hash, status)
        VALUES ((p_log ->> 'actor_id')::uuid, row_command_id::uuid,
            p_log ->> 'command_type',
            (p_log ->> 'command_correlation_id')::uuid,
            (p_log ->> 'command_at')::timestamptz, NULL,
            p_log ->> 'idempotency_key', held_payload, NULL, 'accepted');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF api.core_unique_on_v1(reported, 'command_log_pkey') THEN
            SELECT me.* INTO existing FROM public.command_log me
            WHERE me.command_id = row_command_id::uuid;
            IF NOT FOUND OR existing.idempotency_key IS NULL
                OR existing.idempotency_key <> p_log ->> 'idempotency_key'
            THEN
                row_command_id := api.core_uuid_v7_v1()::text;
                INSERT INTO public.command_log (actor_id, command_id,
                    command_type, correlation_id, created_at, handled_at,
                    idempotency_key, payload, response_hash, status)
                VALUES ((p_log ->> 'actor_id')::uuid, row_command_id::uuid,
                    p_log ->> 'command_type',
                    (p_log ->> 'command_correlation_id')::uuid,
                    (p_log ->> 'command_at')::timestamptz, NULL,
                    p_log ->> 'idempotency_key', held_payload, NULL,
                    'accepted');
            ELSIF jsonb_typeof(existing.payload) = 'object'
                AND existing.payload ? 'response'
            THEN
                SELECT * INTO held FROM api.core_command_existing_v1(
                    existing.payload, p_log ->> 'request_hash');
                RETURN QUERY SELECT held.outcome, held.response, NULL::text,
                    NULL::jsonb;
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
            WHERE me.idempotency_key = p_log ->> 'idempotency_key'
            LIMIT 1;
            IF NOT FOUND THEN
                RAISE;
            END IF;
            SELECT * INTO held FROM api.core_command_existing_v1(
                existing.payload, p_log ->> 'request_hash');
            RETURN QUERY SELECT held.outcome, held.response, NULL::text,
                NULL::jsonb;
            RETURN;
        ELSE
            RAISE;
        END IF;
    END;
    RETURN QUERY SELECT 'opened'::text, NULL::jsonb, row_command_id,
        held_payload;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_command_open_v1(jsonb) FROM PUBLIC;

-- The command's answer as the Perl path records one: the public fields of
-- the like under ok, or the refusal with its status.
CREATE FUNCTION api.core_community_like_answer_v1(p_saved jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
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
REVOKE EXECUTE ON FUNCTION api.core_community_like_answer_v1(jsonb)
    FROM PUBLIC;

-- The event a like or an unlike records, as EventRecorder shapes one: the
-- row carries the ids the store drew (event, outbox, correlation) and the
-- time it stamped.
CREATE FUNCTION api.core_community_like_event_v1(
    p_row jsonb,
    p_event_type text,
    p_thread_id uuid,
    p_author_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
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
REVOKE EXECUTE ON FUNCTION api.core_community_like_event_v1(jsonb, text, uuid, uuid)
    FROM PUBLIC;

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
PARALLEL SAFE
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

-- The event a message records, as EventRecorder shapes one: the row
-- carries the ids the store drew (event, outbox, correlation) and the time
-- it stamped. Ids only: the text never leaves the table.
CREATE FUNCTION api.core_community_message_event_v1(
    p_row jsonb,
    p_conversation_id uuid,
    p_recipient_user_id uuid,
    p_first_unread boolean,
    p_started boolean
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object(
    'actor_id', p_row -> 'sender_user_id',
    'aggregate_id', p_conversation_id,
    'aggregate_type', 'conversation',
    'aggregate_version', 1,
    'causation_id', NULL,
    'correlation_id', p_row -> 'correlation_id',
    'created_at', p_row -> 'created_at',
    'event_id', p_row -> 'event_id',
    'event_type', 'direct_message.sent',
    'idempotency_key', 'direct_message.sent:' || (p_row ->> 'message_id'),
    'metadata', jsonb_build_object(
        'actor', jsonb_build_object('id', p_row -> 'sender_user_id'),
        'aggregate_id', p_conversation_id,
        'causation_id', NULL,
        'correlation_id', p_row -> 'correlation_id',
        'event_id', p_row -> 'event_id',
        'timestamp', p_row -> 'created_at',
        'transport', jsonb_build_object(
            'listen_notify_channel', 'gpforum_domain_events',
            'minion_job', 'domain_event.dispatch',
            'stream', 'gpforum.domain_events')),
    'payload', jsonb_build_object(
        'conversation_id', p_conversation_id,
        'message_id', p_row -> 'message_id',
        'sender_user_id', p_row -> 'sender_user_id',
        'recipient_user_id', p_recipient_user_id,
        'first_unread', p_first_unread,
        'started', p_started),
    'schema_version', 1)
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_event_v1(jsonb, uuid, uuid, boolean, boolean)
    FROM PUBLIC;

-- Appends the message to a conversation whose row the caller holds: the
-- sender has read everything up to it, the recipient has one more unread.
-- A message id already stored is the same message again (replayed) when
-- the sender wrote it in this conversation, and a conflict otherwise.
CREATE FUNCTION api.core_community_message_append_v1(
    p_row jsonb,
    p_conversation_id uuid,
    p_recipient_user_id uuid,
    p_started boolean
)
RETURNS TABLE (status text, first_unread boolean)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    sender uuid := (p_row ->> 'sender_user_id')::uuid;
    message uuid := (p_row ->> 'message_id')::uuid;
    sent_at timestamptz := (p_row ->> 'created_at')::timestamptz;
    unread integer;
    existing record;
BEGIN
    INSERT INTO public.direct_messages (message_id, conversation_id,
        author_user_id, body, created_at)
        VALUES (message, p_conversation_id, sender, p_row ->> 'body', sent_at)
        ON CONFLICT ON CONSTRAINT direct_messages_pkey DO NOTHING;
    IF NOT FOUND THEN
        SELECT d.conversation_id, d.author_user_id INTO existing
            FROM public.direct_messages d WHERE d.message_id = message;
        RETURN QUERY SELECT CASE WHEN existing.author_user_id = sender
            AND existing.conversation_id = p_conversation_id
            THEN 'replayed' ELSE 'conflict' END, false;
        RETURN;
    END IF;
    UPDATE public.direct_conversations c
        SET last_message_at = greatest(c.last_message_at, sent_at)
        WHERE c.conversation_id = p_conversation_id;
    UPDATE public.direct_conversation_members m
        SET last_message_at = greatest(m.last_message_at, sent_at),
            last_read_at = greatest(coalesce(m.last_read_at, sent_at), sent_at),
            unread_count = 0
        WHERE m.conversation_id = p_conversation_id AND m.user_id = sender;
    UPDATE public.direct_conversation_members m
        SET last_message_at = greatest(m.last_message_at, sent_at),
            unread_count = m.unread_count + 1
        WHERE m.conversation_id = p_conversation_id
            AND m.user_id = p_recipient_user_id
        RETURNING m.unread_count INTO unread;
    PERFORM api.core_record_event_v1(api.core_community_message_event_v1(
        p_row, p_conversation_id, p_recipient_user_id,
        coalesce(unread, 0) = 1, p_started), p_row ->> 'outbox_id');
    RETURN QUERY SELECT 'ok'::text, coalesce(unread, 0) = 1;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_append_v1(jsonb, uuid, uuid, boolean)
    FROM PUBLIC;

-- True when either member blocks the other (ADR 0130).
CREATE FUNCTION api.core_community_message_blocked_v1(
    p_one uuid,
    p_other uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (SELECT 1 FROM public.member_relations r
    WHERE r.kind = 'block'
        AND ((r.owner_user_id = p_one AND r.other_user_id = p_other)
            OR (r.owner_user_id = p_other AND r.other_user_id = p_one)));
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_blocked_v1(uuid, uuid)
    FROM PUBLIC;

-- The row a send is written from is complete: the ids, the time, a body
-- of 1 to 5000 characters.
CREATE FUNCTION api.core_community_message_row_valid_v1(p_row jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_row IS NOT NULL
    AND jsonb_typeof(p_row) = 'object'
    AND p_row ->> 'message_id' IS NOT NULL
    AND p_row ->> 'sender_user_id' IS NOT NULL
    AND p_row ->> 'created_at' IS NOT NULL
    AND p_row ->> 'event_id' IS NOT NULL
    AND p_row ->> 'correlation_id' IS NOT NULL
    AND p_row ->> 'outbox_id' IS NOT NULL
    AND coalesce(length(p_row ->> 'body'), 0) BETWEEN 1 AND 5000;
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_row_valid_v1(jsonb)
    FROM PUBLIC;

-- The answer a reaction command records, as the like's.
CREATE FUNCTION api.core_community_reaction_answer_v1(p_saved jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE WHEN (p_saved ->> 'ok')::integer = 1 THEN jsonb_build_object(
        'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
        'stored', jsonb_build_object(
            'ok', 1,
            'post_id', p_saved -> 'post_id',
            'reacted', p_saved -> 'reacted',
            'reaction', p_saved -> 'reaction',
            'reaction_count', p_saved -> 'reaction_count',
            'thread_id', p_saved -> 'thread_id',
            'user_id', p_saved -> 'user_id'))
    ELSE jsonb_build_object(
        'error', p_saved -> 'error',
        'errors', CASE WHEN p_saved ->> 'status' = 'invalid'
            THEN jsonb_build_object(CASE WHEN p_saved ->> 'error' = 'unknown reaction' THEN 'reaction' ELSE 'post_id' END, p_saved -> 'error')
            ELSE NULL END,
        'ok', 0, 'status', p_saved -> 'status', 'stored', NULL)
    END
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_reaction_answer_v1(jsonb)
    FROM PUBLIC;

-- The event a reaction given or taken back records, as the like's
-- (core_community_like_event_v1) with the reaction in the key and payload.
CREATE FUNCTION api.core_community_reaction_event_v1(
    p_row jsonb,
    p_event_type text,
    p_thread_id uuid,
    p_author_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
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
        || (p_row ->> 'reaction') || ':' || (p_row ->> 'event_id'),
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
        'reaction', p_row -> 'reaction',
        'thread_id', p_thread_id,
        'user_id', p_row -> 'user_id'),
    'schema_version', 1)
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_reaction_event_v1(jsonb, text, uuid, uuid)
    FROM PUBLIC;

-- PostStore::_count_replies (ADR 0119): the delta added to the thread's
-- counter row in SQL, never below zero, the row taken after the thread's
-- and the post's. A thread without a row gets one; an insert that loses
-- the race adds the delta to the row that won.
CREATE FUNCTION api.core_forum_count_replies_v1(
    p_thread_id text,
    p_delta integer
)
RETURNS void
LANGUAGE plpgsql
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

-- PostStore::_with_new_id: the command with a new id for its post, body or
-- revision, in every part that carries it.
CREATE FUNCTION api.core_forum_with_new_id_v1(p_command jsonb, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_store_revision_v1(jsonb) FROM PUBLIC;

-- Stores a new thread's opening post and its counter.
CREATE FUNCTION api.core_forum_thread_opening_v1(
    p_command jsonb,
    p_thread jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_thread_opening_v1(jsonb, jsonb)
    FROM PUBLIC;

-- Stores a thread's row from a thread command.
CREATE FUNCTION api.core_forum_insert_thread_v1(p_command jsonb)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_record_audit_v1(text, text, text, text, text, jsonb, integer, text, text)
    FROM PUBLIC;

-- Records the event, outbox message and audit row a forum write leaves, with
-- the fields each kind of write carries.
CREATE FUNCTION api.core_forum_record_write_v1(
    p_type text,
    p_command jsonb,
    p_row jsonb,
    p_record jsonb,
    p_causation text DEFAULT NULL,
    p_audit boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_record_write_v1(text, jsonb, jsonb, jsonb, text, boolean)
    FROM PUBLIC;

-- Stores a new thread with its opening post and counter, drawing a new thread
-- id when the given one is taken by another thread, and records the thread's
-- event, outbox message and audit row.
CREATE FUNCTION api.core_forum_create_thread_v1(
    p_command jsonb,
    p_record jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_create_thread_v1(jsonb, jsonb)
    FROM PUBLIC;

-- Whether the category or thread a draft is for still takes a post from its
-- author.
CREATE FUNCTION api.core_forum_draft_target_v1(
    p_owner_user_id uuid,
    p_kind text,
    p_category_id uuid,
    p_thread_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.core_forum_draft_target_v1(uuid, text, uuid, uuid)
    FROM PUBLIC;

-- Checks, under its row lock, that a draft may be published as the command
-- that publishes it: the author active, the draft unchanged since it was read,
-- its target still there. Answers the refusal, or null.
CREATE FUNCTION api.core_forum_draft_publish_v1(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_kind text,
    p_category_id uuid,
    p_thread_id uuid,
    p_command_id text,
    p_now timestamptz,
    p_prepared boolean
)
RETURNS text
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_draft_publish_v1(uuid, uuid, bigint, text, uuid, uuid, text, timestamptz, boolean)
    FROM PUBLIC;

-- Stores the body and the revision of a post edit, numbering the revision
-- after the post's last when the command does not.
CREATE FUNCTION api.core_forum_insert_edit_v1(p_command jsonb)
RETURNS jsonb
LANGUAGE plpgsql
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

-- PostStore::_record for post.created, through Forum::Event's envelope and
-- audit row: the event (EventEnvelope::record's keys and types) and its
-- outbox row, then the audit row, under the caller's correlation id.
CREATE FUNCTION api.core_forum_record_post_created_v1(
    p_command jsonb,
    p_record jsonb
)
RETURNS void
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_record_post_created_v1(jsonb, jsonb)
    FROM PUBLIC;

-- PostStore::_write_copy and _finish_new_post: the new post's body and
-- revision, its reply count, the post pointed at both (only when an id was
-- given up, as DBIx::Class updates only the columns that changed), and
-- post.created recorded. p_post is the post row as the caller holds it.
-- Returns { command, post }, the command as written and the row.
CREATE FUNCTION api.core_forum_write_copy_v1(
    p_command jsonb,
    p_post jsonb,
    p_record jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
CREATE FUNCTION api.core_forum_insert_reply_v1(
    p_command jsonb,
    p_record jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_store_reply_v1(text, text, text, text, text, bigint, text, text, bigint, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text, text, text, text, integer, text, text, text, text, text, text, text)
    FROM PUBLIC;

-- Edits, deletes or restores a post as a command: the thread row FOR KEY
-- SHARE, then the post FOR UPDATE (ADR 0111), the author's checks, the write
-- and its records.
CREATE FUNCTION api.core_forum_write_post_v1(
    p_type text,
    p_command jsonb,
    p_record jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_write_post_v1(text, jsonb, jsonb)
    FROM PUBLIC;

-- Edits, moves, deletes or restores a thread as a command: the thread FOR
-- UPDATE, the author's checks, the write and its records.
CREATE FUNCTION api.core_forum_write_thread_v1(
    p_type text,
    p_command jsonb,
    p_record jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_forum_write_thread_v1(text, jsonb, jsonb)
    FROM PUBLIC;

-- The wrong answers the member's challenges took in the hour before now.
CREATE FUNCTION api.core_identity_challenge_failures_v1(
    p_user_id uuid,
    p_now timestamptz
)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(sum(c.failed_attempts), 0)::integer
FROM public.second_factor_challenges c
WHERE c.user_id = p_user_id AND c.created_at > p_now - interval '1 hour'
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_challenge_failures_v1(uuid, timestamptz)
    FROM PUBLIC;

-- Staff: a member holding a role that grants anything besides reading a
-- category, which every staff console's permission is.
CREATE FUNCTION api.core_identity_is_staff_v1(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (SELECT 1 FROM public.role_bindings b
    JOIN public.role_permissions rp ON rp.role_id = b.role_id
    JOIN public.permissions p ON p.permission_id = rp.permission_id
    WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
        AND NOT (p.resource_type = 'category' AND p.action = 'read'))
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_is_staff_v1(uuid) FROM PUBLIC;

-- The ten recovery codes are 64 hexadecimal characters each, distinct.
CREATE FUNCTION api.core_identity_recovery_hashes_valid_v1(p_hashes text[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_hashes IS NOT NULL AND cardinality(p_hashes) = 10
    AND (SELECT count(DISTINCT h) FROM unnest(p_hashes) h
        WHERE h ~ '^[0-9a-f]{64}$') = 10
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_recovery_hashes_valid_v1(text[])
    FROM PUBLIC;

-- The hash of an unused recovery code of the member, spent now: true when
-- there was one.
CREATE FUNCTION api.core_identity_recovery_spend_v1(
    p_user_id uuid,
    p_hash text,
    p_now timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_hash IS NULL THEN
        RETURN false;
    END IF;
    UPDATE public.second_factor_recovery_codes c SET used_at = p_now
        WHERE c.user_id = p_user_id AND c.code_hash = p_hash
            AND c.used_at IS NULL;
    RETURN FOUND;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_recovery_spend_v1(uuid, text, timestamptz)
    FROM PUBLIC;

-- The notice mail a change records: an identity.mail.requested event whose
-- outbox message names the kind, and the member's address and language
-- read here, so the caller never needs them.
CREATE FUNCTION api.core_identity_second_factor_mail_v1(
    p_user_id uuid,
    p_mail jsonb
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE member_row record;
BEGIN
    IF p_mail IS NULL THEN
        RETURN;
    END IF;
    SELECT u.email_normalized, u.preferred_locale INTO member_row
        FROM public.users u WHERE u.id = p_user_id;
    IF NOT FOUND OR member_row.email_normalized IS NULL THEN
        RETURN;
    END IF;
    PERFORM api.ops_record_event_v1(p_mail -> 'event',
        p_mail ->> 'outbox_id',
        jsonb_build_object('mail', coalesce(p_mail -> 'outbox_extras' -> 'mail',
            '{}'::jsonb) || jsonb_build_object(
                'to', member_row.email_normalized,
                'locale', member_row.preferred_locale)),
        false);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_second_factor_mail_v1(uuid, jsonb)
    FROM PUBLIC;

-- The policy requires two-step sign-in of staff and this member has none
-- turned on.
CREATE FUNCTION api.core_identity_second_factor_missing_v1(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce((SELECT p.staff_required FROM public.second_factor_policy p),
        false)
    AND NOT EXISTS (SELECT 1 FROM public.second_factors f
        WHERE f.user_id = p_user_id AND f.state = 'active')
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_second_factor_missing_v1(uuid)
    FROM PUBLIC;

-- The password credential as CredentialStore creates it: none when the
-- account already has an active one, the row inserted, or the open row
-- stored under its id with the same secret; a taken id that is another's
-- is drawn again once.
CREATE FUNCTION api.core_identity_store_credential_v1(p_credential jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    row_in jsonb := p_credential;
    stored public.credentials;
    reported text;
BEGIN
    SELECT * INTO stored FROM api.identity_active_password_v1(
        (row_in ->> 'user_id')::uuid);
    IF FOUND THEN
        RETURN to_jsonb(stored);
    END IF;
    FOR attempt IN 1 .. 2 LOOP
        BEGIN
            SELECT * INTO stored
            FROM api.identity_insert_credential_v1(row_in);
            RETURN to_jsonb(stored);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported, 'credentials_pkey') THEN
                RAISE;
            END IF;
            SELECT * INTO stored FROM api.identity_credential_by_id_v1(
                (row_in ->> 'id')::uuid);
            IF FOUND AND stored.revoked_at IS NULL
                AND stored.user_id = (row_in ->> 'user_id')::uuid
                AND stored.type = row_in ->> 'type'
                AND stored.secret_hash = row_in ->> 'secret_hash'
            THEN
                RETURN to_jsonb(stored);
            END IF;
            IF attempt = 2 THEN
                RAISE;
            END IF;
            row_in := row_in || jsonb_build_object('id',
                api.core_uuid_v7_v1()::text);
        END;
    END LOOP;
    RETURN NULL;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_store_credential_v1(jsonb)
    FROM PUBLIC;

-- The verification token as TokenStore issues it: the row inserted, the
-- open row stored under its id with the same hash, or a taken id drawn
-- again once. A taken hash is the caller's to draw again: the raw token
-- is theirs, so the call raises.
CREATE FUNCTION api.core_identity_store_token_v1(p_token jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    row_in jsonb := p_token;
    stored public.identity_tokens;
    reported text;
BEGIN
    FOR attempt IN 1 .. 2 LOOP
        BEGIN
            SELECT * INTO stored FROM api.identity_insert_token_v1(row_in);
            RETURN to_jsonb(stored);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported, 'identity_tokens_pkey') THEN
                RAISE;
            END IF;
            SELECT * INTO stored FROM public.identity_tokens me
            WHERE me.token_id = (row_in ->> 'token_id')::uuid;
            IF FOUND AND stored.used_at IS NULL
                AND stored.token_hash = row_in ->> 'token_hash'
                AND stored.token_type = row_in ->> 'token_type'
                AND stored.user_id IS NOT DISTINCT FROM
                    (row_in ->> 'user_id')::uuid
            THEN
                RETURN to_jsonb(stored);
            END IF;
            IF attempt = 2 THEN
                RAISE;
            END IF;
            row_in := row_in || jsonb_build_object('token_id',
                api.core_uuid_v7_v1()::text);
        END;
    END LOOP;
    RETURN NULL;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_store_token_v1(jsonb) FROM PUBLIC;

-- The user row inserted, or the open row already stored under its id with
-- the same username and email (a retried registration); a taken id that
-- belongs to another account raises, and the caller draws another id.
CREATE FUNCTION api.core_identity_store_user_v1(p_user jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    stored public.users;
    reported text;
BEGIN
    BEGIN
        SELECT * INTO stored FROM api.identity_insert_user_v1(p_user);
        RETURN to_jsonb(stored);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'users_pkey') THEN
            RETURN NULL;
        END IF;
        SELECT * INTO stored FROM api.identity_user_by_id_v1(
            (p_user ->> 'id')::uuid);
        IF NOT FOUND
            OR stored.username IS DISTINCT FROM p_user ->> 'username'
            OR stored.email_normalized IS DISTINCT FROM
                p_user ->> 'email_normalized'
        THEN
            RAISE;
        END IF;
        RETURN to_jsonb(stored);
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_store_user_v1(jsonb) FROM PUBLIC;

-- The last complete period before p_now: the UTC day before, or the UTC
-- week (Monday to Monday) before.
CREATE FUNCTION api.core_notification_digest_period_v1(
    p_frequency text,
    p_now timestamptz
)
RETURNS TABLE (period_start timestamptz, period_end timestamptz)
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT x.period_end - CASE WHEN p_frequency = 'weekly'
        THEN interval '7 days' ELSE interval '1 day' END,
    x.period_end
FROM (SELECT date_trunc(CASE WHEN p_frequency = 'weekly'
        THEN 'week' ELSE 'day' END, p_now AT TIME ZONE 'UTC')
        AT TIME ZONE 'UTC' AS period_end) x;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_digest_period_v1(text, timestamptz)
    FROM PUBLIC;

-- ADR 0078's kinds gain messages: a direct_message notification belongs
-- to the kind message, on in the inbox and by email unless the member
-- turns it off.
CREATE FUNCTION api.core_notification_event_type_v2(p_notification_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE
    WHEN p_notification_type IN ('reply', 'follow') THEN 'reply'
    WHEN p_notification_type = 'mention' THEN 'mention'
    WHEN p_notification_type IN ('review_approved', 'review_rejected')
        THEN 'moderation'
    WHEN p_notification_type = 'direct_message' THEN 'message'
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_event_type_v2(text)
    FROM PUBLIC;

-- Marks a notification read once and copies the time into the inbox. Answers
-- the time it was read.
CREATE FUNCTION api.core_notification_read_v1(
    p_notification_id uuid,
    p_recipient_user_id uuid,
    p_read_at text
)
RETURNS text
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_at text;
BEGIN
  INSERT INTO public.notification_reads (notification_id, recipient_user_id, read_at) VALUES (p_notification_id, p_recipient_user_id, p_read_at::timestamptz)
  ON CONFLICT (notification_id, recipient_user_id) DO NOTHING;
  IF FOUND THEN v_at := p_read_at;
  ELSE SELECT r.read_at::text INTO v_at FROM public.notification_reads r WHERE r.notification_id = p_notification_id AND r.recipient_user_id = p_recipient_user_id; END IF;
  UPDATE public.notification_inbox i SET read_at = v_at::timestamptz WHERE i.notification_id = p_notification_id AND i.recipient_user_id = p_recipient_user_id;
  RETURN v_at;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_read_v1(uuid, uuid, text)
    FROM PUBLIC;

-- Whether a kind of notification is on by default on a channel: in the inbox
-- always, by email for mentions, moderation notices and messages.
CREATE FUNCTION api.core_notification_type_default_v2(
    p_event_type text,
    p_channel text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_channel = 'in_app'
    OR p_event_type IN ('mention', 'moderation', 'message');
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_type_default_v2(text, text)
    FROM PUBLIC;

-- Compares a stored token digest with a presented one in time that does not
-- depend on where they differ.
CREATE FUNCTION api.core_session_digest_equals_v1(
    p_stored text,
    p_presented text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_stored bytea;
    v_presented bytea;
    v_difference integer := 0;
    v_position integer;
BEGIN
    IF p_stored IS NULL OR p_presented IS NULL
       OR length(p_stored) = 0 OR length(p_stored) <> length(p_presented) THEN
        RETURN false;
    END IF;
    v_stored := convert_to(p_stored, 'UTF8');
    v_presented := convert_to(p_presented, 'UTF8');
    IF length(v_stored) <> length(v_presented) THEN
        RETURN false;
    END IF;
    FOR v_position IN 0 .. length(v_stored) - 1 LOOP
        v_difference := v_difference | (get_byte(v_stored, v_position)
            # get_byte(v_presented, v_position));
    END LOOP;
    RETURN v_difference = 0;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_session_digest_equals_v1(text, text)
    FROM PUBLIC;

-- Appends a row to the audit chain: its previous hash is the chain's head, and
-- its record hash the SHA-256 of its canonical JSON.
CREATE FUNCTION api.core_shared_append_audit_v1(p_audit jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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

-- Queues an event's outbox message once, by the event's idempotency key,
-- recovering a taken outbox id.
CREATE FUNCTION api.core_shared_ensure_outbox_v1(
    p_event jsonb,
    p_outbox_id text,
    p_extras jsonb
)
RETURNS void
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_shared_ensure_outbox_v1(jsonb, text, jsonb)
    FROM PUBLIC;

-- Records an event once and queues its outbox message; an event recorded
-- before is answered as it was, marked skipped.
CREATE FUNCTION api.core_shared_record_event_v1(
    p_event jsonb,
    p_outbox_id text,
    p_extras jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.core_shared_record_event_v1(jsonb, text, jsonb)
    FROM PUBLIC;

COMMIT;
