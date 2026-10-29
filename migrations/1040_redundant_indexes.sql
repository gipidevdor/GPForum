-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- Three indexes no statement needs, each a write on every insert and update
-- of its table for nothing. idx_sessions_active (session_id, where not
-- revoked) and idx_sessions_lookup (session_id, expires_at, revoked_at) both
-- lead with session_id, the primary key, which answers the one-row lookup
-- they could serve; a session is found by its hash (unique) or its id.
-- idx_user_feed_items_ranked (user_id, rank_score DESC, created_at DESC)
-- orders by a score no reader orders by: the feed is read newest first,
-- which idx_user_feed_items_user_created serves, with the item columns
-- included.
DROP INDEX IF EXISTS public.idx_sessions_active;
DROP INDEX IF EXISTS public.idx_sessions_lookup;
DROP INDEX IF EXISTS public.idx_user_feed_items_ranked;
