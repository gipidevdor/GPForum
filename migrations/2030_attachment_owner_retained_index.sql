-- gpforum:no-transaction
-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- The existing owner index excludes soft-deleted rows; quota includes them.
-- Retrying after an interrupted concurrent build removes its invalid index.
DROP INDEX CONCURRENTLY IF EXISTS public.idx_attachments_owner_retained;
CREATE INDEX CONCURRENTLY idx_attachments_owner_retained ON public.attachments (owner_user_id)
    INCLUDE (byte_size, scan_status, deleted_at);
