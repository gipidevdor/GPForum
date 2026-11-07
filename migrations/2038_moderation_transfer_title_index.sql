-- gpforum:no-transaction
-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
-- Title lookup for the bounded staff picker, including freshly created threads.
DROP INDEX CONCURRENTLY IF EXISTS public.idx_threads_transfer_title;
CREATE INDEX CONCURRENTLY idx_threads_transfer_title ON public.threads
USING gin (title public.gin_trgm_ops)
WHERE deleted_at IS NULL AND moderation_state='visible' AND locked_at IS NULL
  AND visibility IN ('public','members');
