-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- These tables are updated in normal request/dispatch paths. PostgreSQL's
-- default 20% vacuum / 10% analyze thresholds leave a growing amount of
-- dead index entries and stale statistics as the forum grows. Retain the
-- cluster's absolute thresholds, cost limits and worker/memory settings.
-- SET changes storage parameters only: no rewrite or blocking VACUUM FULL.
ALTER TABLE public.threads SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.thread_counters SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.posts SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.search_documents SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.outbox_messages SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.sessions SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.rate_limit_buckets SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.thread_read_state SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);
ALTER TABLE public.user_read_marker_deltas SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_analyze_scale_factor = 0.01
);

COMMIT;
