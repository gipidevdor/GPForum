-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0078, amendment of 2026-10-17: a digest covers a window, not only
-- the last period. A member's window runs from where their last digest
-- (of either frequency) ended to the end of their frequency's last
-- complete period, but never further back than 14 days: a run missed, a
-- member the runs did not reach in time, or a switch between daily and
-- weekly is caught up in the next digest, once, and never re-reported. A
-- period is complete ten minutes after it ends, past any write still
-- committing a post stamped before its end. The due list is ordered by
-- window start, oldest first, then member, and paged by that key, so the
-- members waiting longest come first and every one is reached. A
-- suspended member is not due and their digest is not sent; a thread the
-- member muted or turned down stays out of a followed category's list.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The members due a digest at p_now, with the window each one covers,
-- oldest window first, after the key (p_after_start, p_after_user_id),
-- at most p_row_limit (1 to 1,000) of them.
CREATE FUNCTION api.notification_digest_due_v3(p_now timestamptz,
    p_after_start timestamptz, p_after_user_id uuid, p_row_limit integer)
RETURNS TABLE(user_id uuid, frequency text, period_start timestamptz,
    period_end timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT w.user_id, w.frequency, w.period_start, w.period_end
FROM (
    SELECT d.user_id, d.digest_frequency AS frequency,
        greatest(coalesce(l.last_end, p.period_start),
            p.period_end - interval '14 days') AS period_start,
        p.period_end
    FROM public.notification_preferences d
    JOIN public.users u ON u.id = d.user_id
    CROSS JOIN LATERAL api.core_notification_digest_period_v1(
        d.digest_frequency, p_now - interval '10 minutes') p
    LEFT JOIN LATERAL (SELECT max(g.period_end) AS last_end
        FROM public.notification_digests g
        WHERE g.user_id = d.user_id) l ON true
    WHERE d.channel = 'digest' AND d.enabled
        AND d.digest_frequency IN ('daily', 'weekly')
        AND u.status = 'active' AND u.deleted_at IS NULL
        AND u.email_verified_at IS NOT NULL
        AND coalesce((SELECT e.enabled FROM public.notification_preferences e
            WHERE e.user_id = d.user_id AND e.channel = 'email'), true)
        AND NOT EXISTS (SELECT 1 FROM public.suspensions s
            WHERE s.user_id = d.user_id AND s.revoked_at IS NULL
                AND s.valid_from <= p_now
                AND (s.valid_to IS NULL OR s.valid_to > p_now))
) w
WHERE w.period_start < w.period_end
    AND (p_after_user_id IS NULL
        OR (w.period_start, w.user_id) > (p_after_start, p_after_user_id))
ORDER BY w.period_start, w.user_id
LIMIT least(greatest(coalesce(p_row_limit, 100), 1), 1000);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_due_v3(timestamptz,
    timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_due_v4(
p_now timestamptz, p_after_start timestamptz, p_after_user_id uuid,
p_row_limit integer
)
RETURNS TABLE(user_id uuid, frequency text, period_start timestamptz,
    period_end timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_due_v3(p_now, p_after_start,
    p_after_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_due_v4(timestamptz,
    timestamptz, uuid, integer) FROM PUBLIC;

-- What the digest names, as version 1 reads it, except that a thread of
-- a followed category is left out when the member's own subscription to
-- the thread mutes it or asks for less than every post.
CREATE FUNCTION api.notification_digest_items_v3(p_user_id uuid,
    p_period_start timestamptz, p_period_end timestamptz,
    p_member boolean, p_global_read boolean, p_category_ids uuid[],
    p_space_ids uuid[], p_row_limit integer)
RETURNS TABLE(thread_id uuid, title text, category_title text,
    new_posts integer, first_unread_position bigint,
    last_post_at timestamptz, thread_total integer)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH followed AS (
    SELECT s.target_id AS thread_id
    FROM public.subscriptions s
    WHERE s.user_id = p_user_id AND s.target_type = 'thread'
        AND s.revoked_at IS NULL AND s.muted_at IS NULL
        AND s.preference = 'all'
    UNION
    SELECT t.thread_id
    FROM public.subscriptions s
    JOIN public.threads t ON t.category_id = s.target_id
    WHERE s.user_id = p_user_id AND s.target_type = 'category'
        AND s.revoked_at IS NULL AND s.muted_at IS NULL
        AND s.preference = 'all'
        AND t.deleted_at IS NULL AND t.last_activity_at >= p_period_start
        AND NOT EXISTS (SELECT 1 FROM public.subscriptions m
            WHERE m.user_id = p_user_id AND m.target_type = 'thread'
                AND m.target_id = t.thread_id AND m.revoked_at IS NULL
                AND (m.muted_at IS NOT NULL OR m.preference <> 'all'))
),
readable AS (
    SELECT t.thread_id, t.title, t.visibility, t.author_user_id,
        c.title AS category_title, c.category_id, c.space_id
    FROM followed f
    JOIN public.threads t ON t.thread_id = f.thread_id
    JOIN public.categories c ON c.category_id = t.category_id
    JOIN public.spaces sp ON sp.space_id = c.space_id
    WHERE t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND sp.deleted_at IS NULL
        AND (p_global_read OR sp.visibility = 'public'
            OR (p_member AND sp.visibility = 'members')
            OR (sp.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids))))
        AND (p_global_read OR c.visibility = 'public'
            OR (p_member AND c.visibility = 'members')
            OR (c.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids))))
        AND (p_global_read OR t.visibility = 'public'
            OR (p_member AND t.visibility = 'members')
            OR (t.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)
                    OR (p_member AND t.author_user_id = p_user_id))))
),
activity AS (
    SELECT r.thread_id, r.title, r.category_title,
        count(*)::integer AS new_posts,
        min(p.position) AS first_unread_position,
        max(p.created_at) AS last_post_at
    FROM readable r
    JOIN public.posts p ON p.thread_id = r.thread_id
    LEFT JOIN public.thread_read_state rs
        ON rs.user_id = p_user_id AND rs.thread_id = r.thread_id
    WHERE p.created_at >= p_period_start AND p.created_at < p_period_end
        AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
        AND p.position > coalesce(rs.last_read_position, 0)
        AND p.author_user_id <> p_user_id
        AND (p_global_read OR p.visibility = 'public'
            OR (p_member AND p.visibility = 'members')
            OR (p.visibility = 'private'
                AND (r.category_id = ANY(p_category_ids)
                    OR r.space_id = ANY(p_space_ids)
                    OR (p_member AND r.visibility = 'private'
                        AND r.author_user_id = p_user_id))))
        AND NOT EXISTS (SELECT 1 FROM public.member_relations m
            WHERE m.owner_user_id = p_user_id
                AND m.other_user_id = p.author_user_id)
    GROUP BY r.thread_id, r.title, r.category_title
)
SELECT a.thread_id, a.title, a.category_title, a.new_posts,
    a.first_unread_position, a.last_post_at,
    (count(*) OVER ())::integer
FROM activity a
ORDER BY a.last_post_at DESC, a.thread_id
LIMIT least(greatest(coalesce(p_row_limit, 20), 1), 50);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_items_v3(uuid,
    timestamptz, timestamptz, boolean, boolean, uuid[], uuid[], integer)
    FROM PUBLIC;

CREATE FUNCTION api.notification_digest_items_v4(
p_user_id uuid, p_period_start timestamptz, p_period_end timestamptz,
p_member boolean, p_global_read boolean, p_category_ids uuid[],
p_space_ids uuid[], p_row_limit integer
)
RETURNS TABLE(thread_id uuid, title text, category_title text,
    new_posts integer, first_unread_position bigint,
    last_post_at timestamptz, thread_total integer)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_items_v3(p_user_id, p_period_start,
    p_period_end, p_member, p_global_read, p_category_ids, p_space_ids,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_items_v4(uuid,
    timestamptz, timestamptz, boolean, boolean, uuid[], uuid[], integer)
    FROM PUBLIC;

-- Records a member's digest of a window, once, as version 1 does; with
-- the member's records serialised, a window that starts before the end of
-- one already recorded, of either frequency, answers duplicate, so two
-- runners, or a frequency switched between them, cannot cover a post
-- twice.
CREATE FUNCTION api.notification_digest_record_v3(p_user_id uuid,
    p_frequency text, p_period_start timestamptz, p_period_end timestamptz,
    p_thread_count integer, p_now timestamptz, p_event jsonb,
    p_outbox_id text, p_outbox_extras jsonb, p_explicit boolean)
RETURNS TABLE(status text, event_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_user_id IS NOT NULL AND p_period_start IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(2026101701,
            hashtext(p_user_id::text));
        IF EXISTS (SELECT 1 FROM public.notification_digests g
            WHERE g.user_id = p_user_id
                AND g.period_end > p_period_start) THEN
            RETURN QUERY SELECT 'duplicate'::text, NULL::uuid;
            RETURN;
        END IF;
    END IF;
    RETURN QUERY SELECT * FROM api.notification_digest_record_v1(p_user_id,
        p_frequency, p_period_start, p_period_end, p_thread_count, p_now,
        p_event, p_outbox_id, p_outbox_extras, p_explicit);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v3(uuid, text,
    timestamptz, timestamptz, integer, timestamptz, jsonb, text, jsonb,
    boolean) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_record_v4(
p_user_id uuid, p_frequency text, p_period_start timestamptz,
p_period_end timestamptz, p_thread_count integer, p_now timestamptz,
p_event jsonb, p_outbox_id text, p_outbox_extras jsonb, p_explicit boolean
)
RETURNS TABLE(status text, event_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_record_v3(p_user_id, p_frequency,
    p_period_start, p_period_end, p_thread_count, p_now, p_event,
    p_outbox_id, p_outbox_extras, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v4(uuid, text,
    timestamptz, timestamptz, integer, timestamptz, jsonb, text, jsonb,
    boolean) FROM PUBLIC;

-- Whether a queued digest is still to be mailed, as version 1 reads it,
-- and not while the member is suspended at p_now.
CREATE FUNCTION api.notification_digest_plan_v3(p_user_id uuid,
    p_now timestamptz)
RETURNS TABLE(digest boolean, frequency text, email_address text,
    locale text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.digest AND NOT EXISTS (SELECT 1 FROM public.suspensions s
        WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
            AND s.valid_from <= p_now
            AND (s.valid_to IS NULL OR s.valid_to > p_now)),
    v.frequency, v.email_address, v.locale
FROM api.notification_digest_plan_v1(p_user_id) v;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v3(uuid,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_plan_v4(
p_user_id uuid, p_now timestamptz
)
RETURNS TABLE(digest boolean, frequency text, email_address text,
    locale text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_plan_v3(p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v4(uuid,
    timestamptz) FROM PUBLIC;

COMMIT;
