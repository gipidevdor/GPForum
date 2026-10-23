-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- The claim read every ready row before taking its page: its WHERE is an OR
-- of the two predicates the partial indexes idx_outbox_messages_claim_ready
-- (pending and failed) and idx_outbox_messages_stale_locks (running) each
-- serve, which no index can serve in order, so PostgreSQL scanned the table
-- and sorted every ready row for a page of 100 -- 104 ms and a 14 MB
-- external sort on 300,000 ready rows, growing with the backlog it was there
-- to drain. Each half is read in order from its own index and cut at the
-- page; the page is the first p_row_limit of the two, locked FOR UPDATE SKIP
-- LOCKED with the readiness predicate restated on the locked row, so a row
-- another worker claimed and committed between the read and the lock is
-- judged again and left out, as the one scan did. Under contention a claim
-- may hold fewer rows than asked; the next poll takes the rest. 0.9 ms on the
-- same 300,000 rows. v1 stays for workers of the previous release.
CREATE FUNCTION api.outbox_claim_ready_v3(
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
WITH due AS (
    (SELECT outbox_id, next_attempt_at, created_at FROM public.outbox_messages
      WHERE status IN ('pending', 'failed')
        AND next_attempt_at <= p_now::timestamptz
        AND (locked_until IS NULL OR locked_until <= p_now::timestamptz)
      ORDER BY next_attempt_at, created_at, outbox_id
      LIMIT p_row_limit)
    UNION ALL
    (SELECT outbox_id, next_attempt_at, created_at FROM public.outbox_messages
      WHERE status = 'running'
        AND locked_until IS NOT NULL
        AND locked_until <= p_now::timestamptz
      ORDER BY next_attempt_at, created_at, outbox_id
      LIMIT p_row_limit)
), ready AS (
    SELECT me.outbox_id, me.next_attempt_at, me.created_at
    FROM due JOIN public.outbox_messages me ON me.outbox_id = due.outbox_id
    WHERE (me.status IN ('pending', 'failed')
        AND me.next_attempt_at <= p_now::timestamptz
        AND (me.locked_until IS NULL OR me.locked_until <= p_now::timestamptz))
      OR (me.status = 'running'
        AND me.locked_until IS NOT NULL
        AND me.locked_until <= p_now::timestamptz)
    ORDER BY due.next_attempt_at, due.created_at, due.outbox_id
    LIMIT p_row_limit
    FOR UPDATE OF me SKIP LOCKED
), claimed AS (
    UPDATE public.outbox_messages outbox SET status = 'running',
        locked_at = p_now::timestamptz,
        locked_by = p_worker_id,
        locked_until = p_locked_until::timestamptz
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
ORDER BY ready.next_attempt_at, ready.created_at, ready.outbox_id
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_claim_ready_v3(text, text, text, integer)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.outbox_claim_ready_v4(
    p_now text,
    p_locked_until text,
    p_worker_id text,
    p_row_limit integer
)
RETURNS SETOF api.outbox_message_v1
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.outbox_claim_ready_v3(p_now, p_locked_until, p_worker_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.outbox_claim_ready_v4(text, text, text, integer)
    FROM PUBLIC;
