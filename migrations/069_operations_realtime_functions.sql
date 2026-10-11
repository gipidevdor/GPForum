-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.ops_publish_notification_v1(p_channel text, p_payload text)
RETURNS TABLE(sent boolean)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    PERFORM pg_notify(p_channel,p_payload);
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notification_v1(text, text) FROM PUBLIC;

CREATE FUNCTION api.ops_retention_purge_v1(p_source text, p_cutoff timestamptz, p_row_limit integer)
RETURNS TABLE(deleted bigint, ok integer)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
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
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v1(text, timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.ops_outbox_metrics_v1(p_now timestamptz)
RETURNS TABLE(pending bigint, failed bigint, retry_backlog bigint, dead_letters bigint)
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT count(*) FILTER (WHERE m.status='pending'), count(*) FILTER (WHERE m.status='failed'),
 count(*) FILTER (WHERE m.status IN ('pending','failed') AND m.next_attempt_at <= p_now),
 (SELECT count(*) FROM public.dead_letters) FROM public.outbox_messages m;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_outbox_metrics_v1(timestamptz) FROM PUBLIC;

CREATE FUNCTION api.ops_readiness_probe_v1(p_source text)
RETURNS TABLE(ready boolean)
LANGUAGE plpgsql STABLE
SECURITY INVOKER
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

CREATE FUNCTION api.ops_query_budget_list_v1(p_row_limit integer)
RETURNS SETOF public.endpoint_query_budgets
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT b.* FROM public.endpoint_query_budgets b ORDER BY b.endpoint_name ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_list_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.ops_query_budget_sync_v1(p_rows jsonb, p_endpoint_names text[])
RETURNS TABLE(written bigint, removed text[])
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
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
REVOKE EXECUTE ON FUNCTION api.ops_query_budget_sync_v1(jsonb, text[]) FROM PUBLIC;

CREATE FUNCTION api.ops_partition_registry_v1()
RETURNS SETOF public.partition_registry
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT r.* FROM public.partition_registry r;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_partition_registry_v1() FROM PUBLIC;

CREATE FUNCTION api.ops_realtime_settled_v1(p_settle_seconds integer)
RETURNS TABLE(settled_at timestamptz)
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT clock_timestamp() - make_interval(secs => p_settle_seconds);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_settled_v1(integer) FROM PUBLIC;

CREATE FUNCTION api.ops_realtime_poll_v1(p_after_next_at timestamptz, p_after_created_at timestamptz, p_after_id uuid, p_settled_at timestamptz, p_settle_seconds integer, p_row_limit integer)
RETURNS SETOF public.outbox_messages
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT m.* FROM public.outbox_messages m WHERE m.status='done'
AND m.next_attempt_at >= p_after_next_at
AND m.next_attempt_at <= coalesce(p_settled_at,clock_timestamp()-make_interval(secs=>p_settle_seconds))
AND (m.next_attempt_at,m.created_at,m.outbox_id) > (p_after_next_at,p_after_created_at,p_after_id)
ORDER BY m.next_attempt_at ASC,m.created_at ASC,m.outbox_id ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_realtime_poll_v1(timestamptz, timestamptz, uuid, timestamptz, integer, integer) FROM PUBLIC;

CREATE FUNCTION api.ops_replication_recovery_v1()
RETURNS TABLE(in_recovery boolean)
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT pg_is_in_recovery();
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_recovery_v1() FROM PUBLIC;

CREATE FUNCTION api.ops_replication_standbys_v1()
RETURNS TABLE(application_name text, state text, sync_state text, replay_lag_seconds double precision, bytes_behind bigint)
LANGUAGE sql STABLE
SECURITY INVOKER
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

CREATE FUNCTION api.ops_replication_slots_v1(p_standby boolean)
RETURNS TABLE(slot_name text, slot_type text, active boolean, wal_status text, retained_bytes bigint)
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT s.slot_name::text,s.slot_type::text,s.active,s.wal_status::text,
pg_wal_lsn_diff(CASE WHEN p_standby THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END,s.restart_lsn)::bigint
FROM pg_catalog.pg_replication_slots s ORDER BY s.slot_name;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_slots_v1(boolean) FROM PUBLIC;

CREATE FUNCTION api.ops_replication_position_v1()
RETURNS TABLE(replay_age_seconds double precision, replay_pending_bytes bigint, receiving boolean)
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT extract(epoch FROM now()-pg_last_xact_replay_timestamp())::float8,
pg_wal_lsn_diff(pg_last_wal_receive_lsn(),pg_last_wal_replay_lsn())::bigint,
EXISTS(SELECT 1 FROM pg_catalog.pg_stat_wal_receiver);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_replication_position_v1() FROM PUBLIC;

COMMIT;
