-- gpforum:no-transaction
-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
-- The completed handler claims in the order the retention purge deletes them
-- (2052). Build without blocking the workers' claims.
DROP INDEX CONCURRENTLY IF EXISTS public.idx_event_idempotency_keys_completed;
CREATE INDEX CONCURRENTLY idx_event_idempotency_keys_completed
ON public.event_idempotency_keys (completed_at) WHERE completed_at IS NOT NULL;
