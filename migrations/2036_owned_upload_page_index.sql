-- gpforum:no-transaction
-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
-- Latest-first post uploads and their continuation cursor, without sorting
-- a post's complete file history. Build without blocking attachment writes.
DROP INDEX CONCURRENTLY IF EXISTS public.idx_attachment_post_uploads_page;
CREATE INDEX CONCURRENTLY idx_attachment_post_uploads_page
ON public.attachment_links (target_id, created_at DESC, attachment_link_id DESC)
INCLUDE (attachment_id) WHERE target_type = 'post';
