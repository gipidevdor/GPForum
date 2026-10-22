-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The outbox and its workers, realtime polling, readiness and metrics,
-- partitions and query budgets.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Stores a command's answer in the command log: its payload, response hash,
-- status and the time it was handled.
CREATE FUNCTION api.ops_command_finish_v1(p_command_id uuid, p_changes jsonb)
RETURNS TABLE (success boolean)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    WITH changed AS (UPDATE public.command_log me SET handled_at = (p_changes->>'handled_at')::timestamptz,
        payload = p_changes->'payload',response_hash = p_changes->>'response_hash',status = p_changes->>'status'
        WHERE me.command_id = p_command_id RETURNING 1)
    SELECT EXISTS(SELECT 1 FROM changed)
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_finish_v1(uuid, jsonb) FROM PUBLIC;

-- Records a command in the command log, recovering a taken command id.
CREATE FUNCTION api.ops_command_insert_v1(p_command jsonb)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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

-- A command log row by idempotency key, or by command id.
CREATE FUNCTION api.ops_command_lookup_v1(p_key text, p_command_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT to_jsonb(me)::json FROM public.command_log me
    WHERE (p_key IS NOT NULL AND me.idempotency_key = p_key)
      OR (p_key IS NULL AND me.command_id = p_command_id) LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.ops_command_lookup_v1(text, uuid) FROM PUBLIC;

-- How many outbox messages wait, how long the oldest has, and how long ago one
-- was last delivered, for gpforum doctor.
CREATE FUNCTION api.ops_doctor_outbox_v1()
RETURNS TABLE (
    waiting bigint,
    oldest_seconds numeric,
    last_sent_seconds numeric
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT count(*),
        EXTRACT(EPOCH FROM now() - min(CASE WHEN o.status = 'running' THEN o.locked_until
            ELSE GREATEST(o.next_attempt_at, COALESCE(o.locked_until, o.next_attempt_at)) END)),
        (SELECT EXTRACT(EPOCH FROM now() - max(done.next_attempt_at))
            FROM public.outbox_messages done WHERE done.status = 'done')
    FROM public.outbox_messages o
    WHERE (o.status IN ('pending', 'failed') AND o.next_attempt_at <= now()
        AND (o.locked_until IS NULL OR o.locked_until <= now()))
        OR (o.status = 'running' AND o.locked_until IS NOT NULL AND o.locked_until <= now());
$$;
REVOKE EXECUTE ON FUNCTION api.ops_doctor_outbox_v1() FROM PUBLIC;

-- A worker's claim on an event (ADR 0126): whether it is done, a claim taken
-- before the side effect, its completion, or its release after a failure.
CREATE FUNCTION api.ops_event_claim_v1(
    p_operation text,
    p_key text,
    p_event_id text,
    p_now text,
    p_expired_before text
)
RETURNS TABLE (claimed boolean)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.ops_event_claim_v1(text, text, text, text, text)
    FROM PUBLIC;

-- Whether an event with this idempotency key is recorded.
CREATE FUNCTION api.ops_event_recorded_v1(p_key text)
RETURNS TABLE (recorded boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT EXISTS(SELECT 1 FROM public.event_log me WHERE me.idempotency_key = p_key) $$;
REVOKE EXECUTE ON FUNCTION api.ops_event_recorded_v1(text) FROM PUBLIC;

-- The outbox gauges /metrics reports: pending, failed, due for retry, and the
-- dead letters.
CREATE FUNCTION api.ops_outbox_metrics_v1(p_now timestamptz)
RETURNS TABLE (
    pending bigint,
    failed bigint,
    retry_backlog bigint,
    dead_letters bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT count(*) FILTER (WHERE m.status='pending'), count(*) FILTER (WHERE m.status='failed'),
 count(*) FILTER (WHERE m.status IN ('pending','failed') AND m.next_attempt_at <= p_now),
 (SELECT count(*) FROM public.dead_letters) FROM public.outbox_messages m;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_outbox_metrics_v1(timestamptz) FROM PUBLIC;

-- For each partitioned log, the end of its last month partition and whether
-- its DEFAULT partition holds rows.
CREATE FUNCTION api.ops_partition_horizon_v1()
RETURNS TABLE (
    table_name text,
    horizon_epoch numeric,
    default_has_rows boolean
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    WITH horizons AS (
        SELECT parent.relname::text AS table_name,
            extract(epoch FROM max(substring(pg_get_expr(child.relpartbound, child.oid)
                FROM 'TO \(''([^'']+)''\)')::timestamptz)) AS horizon_epoch
        FROM pg_catalog.pg_inherits inheritance
        JOIN pg_catalog.pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_catalog.pg_class child ON child.oid = inheritance.inhrelid
        JOIN pg_catalog.pg_namespace space ON space.oid = parent.relnamespace
        WHERE space.nspname = 'public'
            AND parent.relname IN ('audit_log', 'event_log', 'notifications')
        GROUP BY parent.relname
    ), defaults(table_name, default_has_rows) AS (
        VALUES
            ('audit_log'::text, EXISTS(SELECT 1 FROM ONLY public.audit_log_default)),
            ('event_log'::text, EXISTS(SELECT 1 FROM ONLY public.event_log_default)),
            ('notifications'::text, EXISTS(SELECT 1 FROM ONLY public.notifications_default))
    )
    SELECT d.table_name, h.horizon_epoch, d.default_has_rows FROM defaults d
        LEFT JOIN horizons h USING (table_name) ORDER BY d.table_name;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_horizon_v1() FROM PUBLIC;

-- The partition registry.
CREATE FUNCTION api.ops_partition_registry_v1()
RETURNS SETOF api.ops_partition_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT r.table_name, r.partition_name, r.range_start, r.range_end, r.state,
    r.created_at, r.detached_at, r.archived_at
FROM public.partition_registry r;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_registry_v1() FROM PUBLIC;

-- Sends a NOTIFY on a channel, at commit.
CREATE FUNCTION api.ops_publish_notification_v1(
    p_channel text,
    p_payload text
)
RETURNS TABLE (sent boolean)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    PERFORM pg_notify(p_channel,p_payload);
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notification_v1(text, text)
    FROM PUBLIC;

-- The endpoint query budgets, by endpoint.
CREATE FUNCTION api.ops_query_budget_list_v1(p_row_limit integer)
RETURNS SETOF api.ops_query_budget_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT b.endpoint_name, b.max_queries, b.max_transactions, b.notes,
    b.created_at
FROM public.endpoint_query_budgets b ORDER BY b.endpoint_name ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_list_v1(integer) FROM PUBLIC;

-- Brings the endpoint query budgets in line with the code: writes the given
-- rows, removes the endpoints not given. Answers what changed.
CREATE FUNCTION api.ops_query_budget_sync_v1(
    p_rows jsonb,
    p_endpoint_names text[]
)
RETURNS TABLE (written bigint, removed text[])
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY WITH incoming AS (
      SELECT x.* FROM jsonb_populate_recordset(NULL::public.endpoint_query_budgets,p_rows) x
    ), changed AS (
      INSERT INTO public.endpoint_query_budgets AS held (endpoint_name,max_queries,max_transactions,notes)
      SELECT endpoint_name,max_queries,max_transactions,notes FROM incoming
      ON CONFLICT (endpoint_name) DO UPDATE SET max_queries=excluded.max_queries, max_transactions=excluded.max_transactions, notes=excluded.notes
      WHERE held.max_queries IS DISTINCT FROM excluded.max_queries OR held.max_transactions IS DISTINCT FROM excluded.max_transactions
      OR coalesce(held.notes,'') <> coalesce(excluded.notes,'') RETURNING 1
    ), dropped AS (
      DELETE FROM public.endpoint_query_budgets b WHERE NOT(b.endpoint_name = ANY(p_endpoint_names)) RETURNING b.endpoint_name
    ) SELECT (SELECT count(*) FROM changed), coalesce((SELECT array_agg(d.endpoint_name ORDER BY d.endpoint_name) FROM dropped d), ARRAY[]::text[]);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_sync_v1(jsonb, text[])
    FROM PUBLIC;

-- Counts an action in its rate-limit window and answers the bucket's counts,
-- observed and blocked.
CREATE FUNCTION api.ops_rate_limit_check_v1(
    p_scope text,
    p_actor_hash text,
    p_action text,
    p_window_start timestamptz,
    p_window_seconds integer,
    p_limit integer,
    p_now timestamptz,
    p_expires_at timestamptz
)
RETURNS TABLE (
    scope text,
    actor_hash text,
    action text,
    window_started_at timestamptz,
    observed_count integer,
    blocked_count integer
)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO public.rate_limit_buckets AS b (
        scope, actor_hash, action, window_started_at, window_seconds,
        observed_count, blocked_count, first_seen_at, last_seen_at, expires_at)
    VALUES (p_scope, p_actor_hash, p_action, p_window_start, p_window_seconds,
        1, CASE WHEN 1 > p_limit THEN 1 ELSE 0 END, p_now, p_now, p_expires_at)
    ON CONFLICT ON CONSTRAINT rate_limit_buckets_pkey DO UPDATE SET
        observed_count = b.observed_count + 1,
        blocked_count = b.blocked_count
            + CASE WHEN b.observed_count + 1 > p_limit THEN 1 ELSE 0 END,
        last_seen_at = EXCLUDED.last_seen_at,
        expires_at = EXCLUDED.expires_at
    RETURNING b.scope, b.actor_hash, b.action, b.window_started_at,
        b.observed_count, b.blocked_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_check_v1(text, text, text, timestamptz, integer, integer, timestamptz, timestamptz)
    FROM PUBLIC;

-- How many rate-limit buckets are live.
CREATE FUNCTION api.ops_rate_limit_snapshot_v1(p_now timestamptz)
RETURNS TABLE (buckets bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT count(*) FROM public.rate_limit_buckets b
    WHERE b.expires_at > p_now
$$;
REVOKE EXECUTE ON FUNCTION api.ops_rate_limit_snapshot_v1(timestamptz)
    FROM PUBLIC;

-- Whether a table the readiness check names can be read.
CREATE FUNCTION api.ops_readiness_probe_v1(p_source text)
RETURNS TABLE (ready boolean)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    CASE p_source
      WHEN 'EventLog' THEN PERFORM event_id FROM public.event_log LIMIT 1;
      WHEN 'OutboxMessage' THEN PERFORM outbox_id FROM public.outbox_messages LIMIT 1;
      WHEN 'ProjectionGeneration' THEN PERFORM generation_id FROM public.projection_generations LIMIT 1;
      WHEN 'EndpointQueryBudget' THEN PERFORM endpoint_name FROM public.endpoint_query_budgets LIMIT 1;
      ELSE RAISE EXCEPTION 'unknown readiness source';
    END CASE;
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_readiness_probe_v1(text) FROM PUBLIC;

-- The outbox messages delivered since the cursor and settled for
-- p_settle_seconds, for the realtime fallback poll.
CREATE FUNCTION api.ops_realtime_poll_v1(
    p_after_next_at timestamptz,
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_settled_at timestamptz,
    p_settle_seconds integer,
    p_row_limit integer
)
RETURNS SETOF api.outbox_message_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT m.outbox_id, m.event_id, m.queue, m.job_type, m.idempotency_key,
    m.payload, m.available_at, m.created_at, m.locked_at, m.attempts,
    m.status, m.last_error, m.next_attempt_at, m.locked_by, m.locked_until,
    m.attempt_count, m.last_error_class, m.failure_type
FROM public.outbox_messages m WHERE m.status='done'
AND m.next_attempt_at >= p_after_next_at
AND m.next_attempt_at <= coalesce(p_settled_at,clock_timestamp()-make_interval(secs=>p_settle_seconds))
AND (m.next_attempt_at,m.created_at,m.outbox_id) > (p_after_next_at,p_after_created_at,p_after_id)
ORDER BY m.next_attempt_at ASC,m.created_at ASC,m.outbox_id ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_poll_v1(timestamptz, timestamptz, uuid, timestamptz, integer, integer)
    FROM PUBLIC;

-- The instant before which delivered outbox messages have settled.
CREATE FUNCTION api.ops_realtime_settled_v1(p_settle_seconds integer)
RETURNS TABLE (settled_at timestamptz)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT clock_timestamp() - make_interval(secs => p_settle_seconds);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_settled_v1(integer) FROM PUBLIC;

-- Appends a row to the audit chain under the chain's advisory lock, drawing a
-- new id when the given one is taken.
CREATE FUNCTION api.ops_record_audit_v1(p_audit jsonb, p_explicit boolean)
RETURNS TABLE (audit json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.ops_record_audit_v1(jsonb, boolean) FROM PUBLIC;

-- AuditRecord::build and EventRecorder::_insert_audit: the audit row chained
-- to the newest one, its record_hash the SHA-256 of its canonical JSON.
CREATE FUNCTION api.ops_record_event_v1(
    p_event jsonb,
    p_outbox_id text,
    p_outbox_extras jsonb,
    p_explicit boolean
)
RETURNS TABLE (event json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_explicit THEN
        PERFORM pg_advisory_xact_lock(2026100310,hashtext(p_event->>'event_id'));
    END IF;
    RETURN QUERY SELECT api.core_shared_record_event_v1(p_event,p_outbox_id,p_outbox_extras)::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_record_event_v1(jsonb, text, jsonb, boolean)
    FROM PUBLIC;

-- On a standby: how far replay is behind, in time and bytes, and whether WAL
-- is being received.
CREATE FUNCTION api.ops_replication_position_v1()
RETURNS TABLE (
    replay_age_seconds double precision,
    replay_pending_bytes bigint,
    receiving boolean
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT extract(epoch FROM now()-pg_last_xact_replay_timestamp())::float8,
pg_wal_lsn_diff(pg_last_wal_receive_lsn(),pg_last_wal_replay_lsn())::bigint,
EXISTS(SELECT 1 FROM pg_catalog.pg_stat_wal_receiver);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_position_v1() FROM PUBLIC;

-- Whether this server is a standby.
CREATE FUNCTION api.ops_replication_recovery_v1()
RETURNS TABLE (in_recovery boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT pg_is_in_recovery();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_recovery_v1() FROM PUBLIC;

-- The replication slots and the WAL each retains.
CREATE FUNCTION api.ops_replication_slots_v1(p_standby boolean)
RETURNS TABLE (
    slot_name text,
    slot_type text,
    active boolean,
    wal_status text,
    retained_bytes bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT s.slot_name::text,s.slot_type::text,s.active,s.wal_status::text,
pg_wal_lsn_diff(CASE WHEN p_standby THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END,s.restart_lsn)::bigint
FROM pg_catalog.pg_replication_slots s ORDER BY s.slot_name;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_slots_v1(boolean) FROM PUBLIC;

-- The standbys of this primary and their lag, the state shown only to a role
-- that may read the statistics.
CREATE FUNCTION api.ops_replication_standbys_v1()
RETURNS TABLE (
    application_name text,
    state text,
    sync_state text,
    replay_lag_seconds double precision,
    bytes_behind bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT s.application_name::text,
CASE WHEN pg_has_role(session_user,'pg_read_all_stats','USAGE') THEN s.state::text END,
CASE WHEN pg_has_role(session_user,'pg_read_all_stats','USAGE') THEN s.sync_state::text END,
CASE WHEN pg_has_role(session_user,'pg_read_all_stats','USAGE') THEN extract(epoch FROM s.replay_lag)::float8 END,
CASE WHEN pg_has_role(session_user,'pg_read_all_stats','USAGE') THEN pg_wal_lsn_diff(pg_current_wal_lsn(),s.replay_lsn)::bigint END
FROM pg_catalog.pg_stat_replication s ORDER BY s.application_name,s.pid;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_standbys_v1() FROM PUBLIC;

-- Deletes a bounded batch of the rows of one kind past their retention,
-- skipping rows another transaction holds.
CREATE FUNCTION api.ops_retention_purge_v1(
    p_source text,
    p_cutoff timestamptz,
    p_row_limit integer
)
RETURNS TABLE (deleted bigint, ok integer)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    CASE p_source
    WHEN 'Session' THEN
      RETURN QUERY WITH picked AS (
        SELECT a.tableoid AS oid, a.ctid AS tid FROM public.sessions a WHERE a.expires_at <= p_cutoff OR a.revoked_at IS NOT NULL
        ORDER BY a.expires_at ASC LIMIT p_row_limit FOR UPDATE SKIP LOCKED
      ), removed AS (
        DELETE FROM public.sessions a USING picked b WHERE a.tableoid = b.oid AND a.ctid = b.tid RETURNING 1
      ) SELECT count(*), 1 FROM removed;
    WHEN 'IdentityToken' THEN
      RETURN QUERY WITH picked AS (
        SELECT a.tableoid AS oid, a.ctid AS tid FROM public.identity_tokens a WHERE a.expires_at <= p_cutoff OR a.used_at IS NOT NULL
        ORDER BY a.expires_at ASC LIMIT p_row_limit FOR UPDATE SKIP LOCKED
      ), removed AS (
        DELETE FROM public.identity_tokens a USING picked b WHERE a.tableoid = b.oid AND a.ctid = b.tid RETURNING 1
      ) SELECT count(*), 1 FROM removed;
    WHEN 'RateLimitBucket' THEN
      RETURN QUERY WITH picked AS (
        SELECT a.tableoid AS oid, a.ctid AS tid FROM public.rate_limit_buckets a WHERE a.expires_at <= p_cutoff
        ORDER BY a.expires_at ASC LIMIT p_row_limit FOR UPDATE SKIP LOCKED
      ), removed AS (
        DELETE FROM public.rate_limit_buckets a USING picked b WHERE a.tableoid = b.oid AND a.ctid = b.tid RETURNING 1
      ) SELECT count(*), 1 FROM removed;
    WHEN 'OutboxMessage' THEN
      RETURN QUERY WITH picked AS (
        SELECT a.tableoid AS oid, a.ctid AS tid FROM public.outbox_messages a WHERE a.created_at <= p_cutoff AND a.status IN ('done','cancelled')
        ORDER BY a.created_at ASC LIMIT p_row_limit FOR UPDATE SKIP LOCKED
      ), removed AS (
        DELETE FROM public.outbox_messages a USING picked b WHERE a.tableoid = b.oid AND a.ctid = b.tid RETURNING 1
      ) SELECT count(*), 1 FROM removed;
    WHEN 'DeadLetter' THEN
      RETURN QUERY WITH picked AS (
        SELECT a.tableoid AS oid, a.ctid AS tid FROM public.dead_letters a WHERE a.last_failed_at <= p_cutoff
        ORDER BY a.last_failed_at ASC LIMIT p_row_limit FOR UPDATE SKIP LOCKED
      ), removed AS (
        DELETE FROM public.dead_letters a USING picked b WHERE a.tableoid = b.oid AND a.ctid = b.tid RETURNING 1
      ) SELECT count(*), 1 FROM removed;
    ELSE RAISE EXCEPTION 'unknown retention source';
    END CASE;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v1(text, timestamptz, integer)
    FROM PUBLIC;

-- Moves a thread's last activity forward to p_at, never back.
CREATE FUNCTION api.ops_thread_activity_v1(p_thread_id uuid, p_at text)
RETURNS TABLE (bumped bigint)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    WITH changed AS (UPDATE public.threads me
        SET last_activity_at = greatest(me.last_activity_at,p_at::timestamptz)
        WHERE me.thread_id = p_thread_id RETURNING 1)
    SELECT count(*) FROM changed
$$;
REVOKE EXECUTE ON FUNCTION api.ops_thread_activity_v1(uuid, text) FROM PUBLIC;

-- The author and thread of a post or a thread an event names, for a worker.
CREATE FUNCTION api.ops_worker_aggregate_v1(
    p_aggregate_type text,
    p_aggregate_id uuid
)
RETURNS TABLE (author_user_id uuid, thread_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT me.author_user_id,me.thread_id FROM public.posts me
    WHERE p_aggregate_type = 'post' AND me.post_id = p_aggregate_id
    UNION ALL
    SELECT me.author_user_id,me.thread_id FROM public.threads me
    WHERE p_aggregate_type = 'thread' AND me.thread_id = p_aggregate_id
$$;
REVOKE EXECUTE ON FUNCTION api.ops_worker_aggregate_v1(text, uuid) FROM PUBLIC;

-- Claims the next ready outbox messages for a worker, FOR UPDATE SKIP LOCKED,
-- leased until p_locked_until.
CREATE FUNCTION api.outbox_claim_ready_v1(
    p_now text,
    p_locked_until text,
    p_worker_id text,
    p_row_limit integer
)
RETURNS SETOF api.outbox_message_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
    FROM ready WHERE outbox.outbox_id = ready.outbox_id RETURNING
        outbox.outbox_id, outbox.event_id, outbox.queue, outbox.job_type,
        outbox.idempotency_key, outbox.payload, outbox.available_at,
        outbox.created_at, outbox.locked_at, outbox.attempts, outbox.status,
        outbox.last_error, outbox.next_attempt_at, outbox.locked_by,
        outbox.locked_until, outbox.attempt_count, outbox.last_error_class,
        outbox.failure_type
)
SELECT claimed.outbox_id, claimed.event_id, claimed.queue, claimed.job_type,
    claimed.idempotency_key, claimed.payload, claimed.available_at,
    claimed.created_at, claimed.locked_at, claimed.attempts, claimed.status,
    claimed.last_error, claimed.next_attempt_at, claimed.locked_by,
    claimed.locked_until, claimed.attempt_count, claimed.last_error_class,
    claimed.failure_type
FROM claimed JOIN ready ON ready.outbox_id = claimed.outbox_id
ORDER BY ready.next_attempt_at,ready.created_at,ready.outbox_id
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_claim_ready_v1(text, text, text, integer)
    FROM PUBLIC;

-- Records a dead letter once per source.
CREATE FUNCTION api.outbox_dead_letter_v1(p_letter jsonb)
RETURNS TABLE (letter json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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

-- Writes the given fields of an outbox message, only while p_worker_id holds
-- its lease.
CREATE FUNCTION api.outbox_owned_write_v1(
    p_outbox_id uuid,
    p_worker_id text,
    p_changes jsonb
)
RETURNS TABLE (landed boolean)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.outbox_owned_write_v1(uuid, text, jsonb)
    FROM PUBLIC;

-- Replays an outbox dead letter as a new message, once, audited.
CREATE FUNCTION api.outbox_replay_dead_letter_v1(
    p_input jsonb,
    p_ids jsonb,
    p_now text
)
RETURNS TABLE (result json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.outbox_replay_dead_letter_v1(jsonb, jsonb, text)
    FROM PUBLIC;

COMMIT;
