-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0078 (the email digest): a member who turns the digest channel on,
-- daily or weekly, is mailed one summary per period of the posts they have
-- not read in the threads they follow and in the categories they follow.
-- The scheduled-jobs runner queues it: each period of each member is
-- recorded once (notification_digests), with the mail as an event in the
-- event log and outbox, so a run is bounded, a second run of the same
-- period queues nothing and a run cut short is resumed by the next. A
-- period is a UTC day, or a UTC ISO week from Monday, and ends before the
-- run: a digest never names a post written after it was made. The digest
-- needs the email channel on (that is all notification email) and an
-- active account with a verified address; its unsubscribe link turns the
-- digest channel off, audited.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.notification_digests (
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    frequency text NOT NULL,
    period_start timestamptz NOT NULL,
    period_end timestamptz NOT NULL,
    status text NOT NULL,
    thread_count integer NOT NULL,
    event_id uuid,
    created_at timestamptz NOT NULL,
    CONSTRAINT notification_digests_pkey
        PRIMARY KEY (user_id, frequency, period_start),
    CONSTRAINT notification_digests_frequency_check
        CHECK (frequency IN ('daily', 'weekly')),
    CONSTRAINT notification_digests_period_check
        CHECK (period_end > period_start),
    CONSTRAINT notification_digests_status_check
        CHECK (status IN ('queued', 'empty')),
    CONSTRAINT notification_digests_thread_count_check
        CHECK (thread_count >= 0),
    CONSTRAINT notification_digests_queued_check
        CHECK ((status = 'queued') = (event_id IS NOT NULL))
);
CREATE INDEX idx_notification_digests_period_end
    ON public.notification_digests(period_end);

-- The last complete period before p_now: the UTC day before, or the UTC
-- week (Monday to Monday) before.
CREATE FUNCTION api.core_notification_digest_period_v1(p_frequency text,
    p_now timestamptz)
RETURNS TABLE(period_start timestamptz, period_end timestamptz)
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT x.period_end - CASE WHEN p_frequency = 'weekly'
        THEN interval '7 days' ELSE interval '1 day' END,
    x.period_end
FROM (SELECT date_trunc(CASE WHEN p_frequency = 'weekly'
        THEN 'week' ELSE 'day' END, p_now AT TIME ZONE 'UTC')
        AT TIME ZONE 'UTC' AS period_end) x;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_digest_period_v1(text,
    timestamptz) FROM PUBLIC;

-- The members whose digest of the last period is not recorded yet, in id
-- order, at most p_row_limit (1 to 1,000) of them.
CREATE FUNCTION api.notification_digest_due_v1(p_now timestamptz,
    p_row_limit integer)
RETURNS TABLE(user_id uuid, frequency text, period_start timestamptz,
    period_end timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT d.user_id, d.digest_frequency, w.period_start, w.period_end
FROM public.notification_preferences d
JOIN public.users u ON u.id = d.user_id
CROSS JOIN LATERAL api.core_notification_digest_period_v1(
    d.digest_frequency, p_now) w
WHERE d.channel = 'digest' AND d.enabled
    AND d.digest_frequency IN ('daily', 'weekly')
    AND u.status = 'active' AND u.deleted_at IS NULL
    AND u.email_verified_at IS NOT NULL
    AND coalesce((SELECT e.enabled FROM public.notification_preferences e
        WHERE e.user_id = d.user_id AND e.channel = 'email'), true)
    AND NOT EXISTS (SELECT 1 FROM public.notification_digests g
        WHERE g.user_id = d.user_id AND g.frequency = d.digest_frequency
            AND g.period_start = w.period_start)
ORDER BY d.user_id
LIMIT least(greatest(coalesce(p_row_limit, 100), 1), 1000);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_due_v1(timestamptz,
    integer) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_due_v2(
p_now timestamptz, p_row_limit integer
)
RETURNS TABLE(user_id uuid, frequency text, period_start timestamptz,
    period_end timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_due_v1(p_now, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_due_v2(timestamptz,
    integer) FROM PUBLIC;

-- What the digest names: each thread the member follows, or that is in a
-- category they follow, with posts written in the period that they have
-- not read (past their read position), by someone else, not hidden from
-- them and not by a member they ignore or block. Read as the member reads
-- (ADR 0102): the reader's membership, global read and private grants come
-- from the viewer resolver. Latest first, at most p_row_limit (1 to 50),
-- each row with the number of threads there were in all.
CREATE FUNCTION api.notification_digest_items_v1(p_user_id uuid,
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_items_v1(uuid,
    timestamptz, timestamptz, boolean, boolean, uuid[], uuid[], integer)
    FROM PUBLIC;

CREATE FUNCTION api.notification_digest_items_v2(
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
SELECT * FROM api.notification_digest_items_v1(p_user_id, p_period_start,
    p_period_end, p_member, p_global_read, p_category_ids, p_space_ids,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_items_v2(uuid,
    timestamptz, timestamptz, boolean, boolean, uuid[], uuid[], integer)
    FROM PUBLIC;

-- Records a member's digest of a period, once: with threads to name, its
-- mail event (built as api.ops_record_event takes it) goes into the event
-- log and outbox in the same transaction and the answer is queued; with
-- none, empty. A period already recorded answers duplicate and writes
-- nothing, so two runners cannot both queue it.
CREATE FUNCTION api.notification_digest_record_v1(p_user_id uuid,
    p_frequency text, p_period_start timestamptz, p_period_end timestamptz,
    p_thread_count integer, p_now timestamptz, p_event jsonb,
    p_outbox_id text, p_outbox_extras jsonb, p_explicit boolean)
RETURNS TABLE(status text, event_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    amount integer;
    queued_id uuid;
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL
        OR coalesce(p_frequency, '') NOT IN ('daily', 'weekly')
        OR p_period_start IS NULL OR p_period_end IS NULL
        OR p_period_end <= p_period_start
        OR coalesce(p_thread_count, -1) < 0
        OR (p_thread_count > 0) <> (p_event IS NOT NULL)
        OR (p_event IS NOT NULL
            AND coalesce(p_event ->> 'event_id', '') !~
                '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    queued_id := (p_event ->> 'event_id')::uuid;
    INSERT INTO public.notification_digests (user_id, frequency,
        period_start, period_end, status, thread_count, event_id,
        created_at)
    VALUES (p_user_id, p_frequency, p_period_start, p_period_end,
        CASE WHEN queued_id IS NULL THEN 'empty' ELSE 'queued' END,
        p_thread_count, queued_id, p_now)
    ON CONFLICT ON CONSTRAINT notification_digests_pkey DO NOTHING;
    GET DIAGNOSTICS amount = ROW_COUNT;
    IF amount = 0 THEN
        RETURN QUERY SELECT 'duplicate'::text, NULL::uuid;
        RETURN;
    END IF;
    IF queued_id IS NULL THEN
        RETURN QUERY SELECT 'empty'::text, NULL::uuid;
        RETURN;
    END IF;
    PERFORM api.ops_record_event_v1(p_event, p_outbox_id, p_outbox_extras,
        coalesce(p_explicit, false));
    RETURN QUERY SELECT 'queued'::text, queued_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v1(uuid, text,
    timestamptz, timestamptz, integer, timestamptz, jsonb, text, jsonb,
    boolean) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_record_v2(
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
SELECT * FROM api.notification_digest_record_v1(p_user_id, p_frequency,
    p_period_start, p_period_end, p_thread_count, p_now, p_event,
    p_outbox_id, p_outbox_extras, p_explicit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v2(uuid, text,
    timestamptz, timestamptz, integer, timestamptz, jsonb, text, jsonb,
    boolean) FROM PUBLIC;

-- Whether a queued digest is still to be mailed, read as the worker sends
-- it: the digest channel on, daily or weekly, the email channel on, an
-- active account with a verified address. With the address and locale.
CREATE FUNCTION api.notification_digest_plan_v1(p_user_id uuid)
RETURNS TABLE(digest boolean, frequency text, email_address text,
    locale text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(d.enabled, false)
    AND d.digest_frequency IN ('daily', 'weekly')
    AND u.status = 'active' AND u.deleted_at IS NULL
    AND u.email_verified_at IS NOT NULL
    AND coalesce((SELECT e.enabled FROM public.notification_preferences e
        WHERE e.user_id = u.id AND e.channel = 'email'), true),
    d.digest_frequency, u.email_normalized, u.preferred_locale
FROM public.users u
LEFT JOIN public.notification_preferences d
    ON d.user_id = u.id AND d.channel = 'digest'
WHERE u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v1(uuid)
    FROM PUBLIC;

CREATE FUNCTION api.notification_digest_plan_v2(
p_user_id uuid
)
RETURNS TABLE(digest boolean, frequency text, email_address text,
    locale text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_plan_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v2(uuid)
    FROM PUBLIC;

-- The digest mail's unsubscribe link: turns the digest channel off and
-- audits it. Answers ok, unchanged when it was already off, not_found for
-- an account that is gone and invalid without its arguments.
CREATE FUNCTION api.notification_digest_unsubscribe_v1(p_user_id uuid,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u
        WHERE u.id = p_user_id AND u.deleted_at IS NULL
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text;
        RETURN;
    END IF;
    UPDATE public.notification_preferences p
        SET enabled = false, updated_at = p_now
        WHERE p.user_id = p_user_id AND p.channel = 'digest' AND p.enabled;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'unchanged'::text;
        RETURN;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_unsubscribe_v1(uuid,
    timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_unsubscribe_v2(
p_user_id uuid, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_unsubscribe_v1(p_user_id, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_unsubscribe_v2(uuid,
    timestamptz, jsonb) FROM PUBLIC;

-- The record of a period is needed only until the period is past being
-- queued: rows that ended before p_before go, oldest first, at most
-- p_row_limit (1 to 10,000), skipping rows another run holds.
CREATE FUNCTION api.notification_digest_purge_v1(p_before timestamptz,
    p_row_limit integer)
RETURNS TABLE(deleted integer)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount integer;
BEGIN
    IF p_before IS NULL THEN
        RETURN QUERY SELECT 0;
        RETURN;
    END IF;
    WITH doomed AS (
        SELECT g.user_id, g.frequency, g.period_start
        FROM public.notification_digests g
        WHERE g.period_end < p_before
        ORDER BY g.period_end
        LIMIT least(greatest(coalesce(p_row_limit, 100), 1), 10000)
        FOR UPDATE SKIP LOCKED
    )
    DELETE FROM public.notification_digests g
    USING doomed d
    WHERE g.user_id = d.user_id AND g.frequency = d.frequency
        AND g.period_start = d.period_start;
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN QUERY SELECT amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_purge_v1(timestamptz,
    integer) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_purge_v2(
p_before timestamptz, p_row_limit integer
)
RETURNS TABLE(deleted integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_purge_v1(p_before, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_purge_v2(timestamptz,
    integer) FROM PUBLIC;

COMMIT;
