-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Readiness inspects the three known partitioned tables in one fixed call.
-- Partition creation, attachment and retention remain administrative DDL.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.ops_partition_horizon_v1()
RETURNS TABLE(table_name text, horizon_epoch numeric, default_has_rows boolean)
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

CREATE FUNCTION api.ops_doctor_outbox_v1()
RETURNS TABLE(waiting bigint, oldest_seconds numeric, last_sent_seconds numeric)
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

COMMIT;
