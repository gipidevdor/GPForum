-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The inbox, its badge, deliveries, preferences, unsubscribes and digests.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Delivers a notification into a member's inbox once, by its idempotency key,
-- writing the notification itself the first time.
CREATE FUNCTION api.notification_deliver_v1(
    p_notification jsonb,
    p_inbox jsonb,
    p_idempotency_key text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.notification_inbox%ROWTYPE; v_at text; v_notification jsonb; v_inbox jsonb; v_constraint text;
BEGIN
  SELECT i.* INTO v FROM public.notification_inbox i WHERE i.recipient_user_id = (p_inbox->>'recipient_user_id')::uuid AND i.notification_id = (p_inbox->>'notification_id')::uuid;
  IF v.notification_id IS NULL THEN
    BEGIN
      SELECT n.created_at::text INTO v_at FROM public.notifications n WHERE n.notification_id = (p_inbox->>'notification_id')::uuid LIMIT 1;
      v_at := COALESCE(v_at, p_inbox->>'created_at');
      v_notification := p_notification || jsonb_build_object('created_at', v_at);
      v_inbox := p_inbox || jsonb_build_object('created_at', v_at);
      INSERT INTO public.notifications (notification_id, recipient_user_id, source_type, source_id, notification_type, payload, created_at)
      VALUES ((v_notification->>'notification_id')::uuid, (v_notification->>'recipient_user_id')::uuid, v_notification->>'source_type', (v_notification->>'source_id')::uuid, v_notification->>'notification_type', v_notification->'payload', v_at::timestamptz)
      ON CONFLICT (notification_id, created_at) DO NOTHING;
      INSERT INTO public.notification_inbox (recipient_user_id, notification_id, created_at, read_at, rank_score)
      VALUES ((p_inbox->>'recipient_user_id')::uuid, (p_inbox->>'notification_id')::uuid, v_at::timestamptz, NULL, (p_inbox->>'rank_score')::numeric);
      RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', 0, 'idempotency_key', p_idempotency_key, 'notification', v_notification, 'inbox', v_inbox); RETURN;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF NOT api.core_unique_on_v1(v_constraint, 'notification_inbox_pkey') THEN RAISE; END IF;
      SELECT i.* INTO v FROM public.notification_inbox i WHERE i.recipient_user_id = (p_inbox->>'recipient_user_id')::uuid AND i.notification_id = (p_inbox->>'notification_id')::uuid;
      IF v.notification_id IS NULL THEN RAISE; END IF;
    END;
  END IF;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', 1, 'idempotency_key', p_idempotency_key,
    'notification', p_notification || jsonb_build_object('notification_id', v.notification_id, 'created_at', v.created_at::text),
    'inbox', to_jsonb(v) || jsonb_build_object('created_at', v.created_at::text, 'read_at', v.read_at::text));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_deliver_v1(jsonb, jsonb, text)
    FROM PUBLIC;

-- Where a notification of one kind goes for a member: the inbox, email (with
-- the address and locale), both or neither, from their channel and kind
-- preferences.
CREATE FUNCTION api.notification_delivery_plan_v3(
    p_user_id uuid,
    p_notification_type text
)
RETURNS TABLE (
    event_type text,
    in_app boolean,
    email boolean,
    email_address text,
    locale text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH kind AS (
    SELECT api.core_notification_event_type_v2(p_notification_type) AS k
)
SELECT kind.k,
    coalesce((SELECT c.enabled FROM public.notification_preferences c
        WHERE c.user_id = u.id AND c.channel = 'in_app'), true)
    AND (kind.k IS NULL OR coalesce(
        (SELECT t.enabled FROM public.notification_type_preferences t
            WHERE t.user_id = u.id AND t.event_type = kind.k
                AND t.channel = 'in_app'),
        api.core_notification_type_default_v2(kind.k, 'in_app'))),
    kind.k IS NOT NULL
    AND u.status = 'active' AND u.deleted_at IS NULL
    AND u.email_verified_at IS NOT NULL
    AND coalesce((SELECT c.enabled FROM public.notification_preferences c
        WHERE c.user_id = u.id AND c.channel = 'email'), true)
    AND coalesce(
        (SELECT t.enabled FROM public.notification_type_preferences t
            WHERE t.user_id = u.id AND t.event_type = kind.k
                AND t.channel = 'email'),
        api.core_notification_type_default_v2(kind.k, 'email')),
    u.email_normalized, u.preferred_locale
FROM public.users u CROSS JOIN kind
WHERE u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v3(uuid, text)
    FROM PUBLIC;

-- Claims the queued digest p_event_id of the member's window for sending:
-- claimed the first time, sent when it already was, missing when no such
-- queued digest is recorded (or its record is past keeping), and invalid
-- without its arguments.
CREATE FUNCTION api.notification_digest_claim_v1(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_event_id uuid,
    p_now timestamptz
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    held timestamptz;
BEGIN
    IF p_user_id IS NULL OR p_frequency IS NULL OR p_period_start IS NULL
        OR p_event_id IS NULL OR p_now IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    SELECT g.sent_at INTO held FROM public.notification_digests g
        WHERE g.user_id = p_user_id AND g.frequency = p_frequency
            AND g.period_start = p_period_start
            AND g.event_id = p_event_id
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'missing'::text;
        RETURN;
    END IF;
    IF held IS NOT NULL THEN
        RETURN QUERY SELECT 'sent'::text;
        RETURN;
    END IF;
    UPDATE public.notification_digests g SET sent_at = p_now
        WHERE g.user_id = p_user_id AND g.frequency = p_frequency
            AND g.period_start = p_period_start;
    RETURN QUERY SELECT 'claimed'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_claim_v1(uuid, text, timestamptz, uuid, timestamptz)
    FROM PUBLIC;

-- The members due a digest at p_now, with the window each one covers,
-- oldest window first, after the key (p_after_start, p_after_user_id),
-- at most p_row_limit (1 to 1,000) of them.
CREATE FUNCTION api.notification_digest_due_v3(
    p_now timestamptz,
    p_after_start timestamptz,
    p_after_user_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    user_id uuid,
    frequency text,
    period_start timestamptz,
    period_end timestamptz
)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_due_v3(timestamptz, timestamptz, uuid, integer)
    FROM PUBLIC;

-- What the digest names, as version 1 reads it, except that a thread of
-- a followed category is left out when the member's own subscription to
-- the thread mutes it or asks for less than every post.
CREATE FUNCTION api.notification_digest_items_v3(
    p_user_id uuid,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    title text,
    category_title text,
    new_posts integer,
    first_unread_position bigint,
    last_post_at timestamptz,
    thread_total integer
)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_items_v3(uuid, timestamptz, timestamptz, boolean, boolean, uuid[], uuid[], integer)
    FROM PUBLIC;

-- Whether a queued digest is still to be mailed, read as the worker sends
-- it: the digest channel on, daily or weekly, the email channel on, an
-- active account with a verified address. With the address and locale.
CREATE FUNCTION api.notification_digest_plan_v1(p_user_id uuid)
RETURNS TABLE (
    digest boolean,
    frequency text,
    email_address text,
    locale text
)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v1(uuid) FROM PUBLIC;

-- Whether a queued digest is still to be mailed, as version 1 reads it,
-- and not while the member is suspended at p_now.
CREATE FUNCTION api.notification_digest_plan_v3(
    p_user_id uuid,
    p_now timestamptz
)
RETURNS TABLE (
    digest boolean,
    frequency text,
    email_address text,
    locale text
)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_plan_v3(uuid, timestamptz)
    FROM PUBLIC;

-- The record of a period is needed only until the period is past being
-- queued: rows that ended before p_before go, oldest first, at most
-- p_row_limit (1 to 10,000), skipping rows another run holds.
CREATE FUNCTION api.notification_digest_purge_v1(
    p_before timestamptz,
    p_row_limit integer
)
RETURNS TABLE (deleted integer)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_purge_v1(timestamptz, integer)
    FROM PUBLIC;

-- Records a member's digest of a period, once: with threads to name, its
-- mail event (built as api.ops_record_event takes it) goes into the event
-- log and outbox in the same transaction and the answer is queued; with
-- none, empty. A period already recorded answers duplicate and writes
-- nothing, so two runners cannot both queue it.
CREATE FUNCTION api.notification_digest_record_v1(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_thread_count integer,
    p_now timestamptz,
    p_event jsonb,
    p_outbox_id text,
    p_outbox_extras jsonb,
    p_explicit boolean
)
RETURNS TABLE (status text, event_id uuid)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v1(uuid, text, timestamptz, timestamptz, integer, timestamptz, jsonb, text, jsonb, boolean)
    FROM PUBLIC;

-- Records a member's digest of a window, once, as version 1 does; with
-- the member's records serialised, a window that starts before the end of
-- one already recorded, of either frequency, answers duplicate, so two
-- runners, or a frequency switched between them, cannot cover a post
-- twice.
CREATE FUNCTION api.notification_digest_record_v3(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_thread_count integer,
    p_now timestamptz,
    p_event jsonb,
    p_outbox_id text,
    p_outbox_extras jsonb,
    p_explicit boolean
)
RETURNS TABLE (status text, event_id uuid)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_record_v3(uuid, text, timestamptz, timestamptz, integer, timestamptz, jsonb, text, jsonb, boolean)
    FROM PUBLIC;

-- Gives a claim back after the transport refused the mail: released, or
-- unchanged when the digest was not claimed.
CREATE FUNCTION api.notification_digest_release_v1(
    p_user_id uuid,
    p_frequency text,
    p_period_start timestamptz,
    p_event_id uuid
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    UPDATE public.notification_digests g SET sent_at = NULL
        WHERE g.user_id = p_user_id AND g.frequency = p_frequency
            AND g.period_start = p_period_start
            AND g.event_id = p_event_id AND g.sent_at IS NOT NULL;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'unchanged'::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'released'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_release_v1(uuid, text, timestamptz, uuid)
    FROM PUBLIC;

-- The digest mail's unsubscribe link: turns the digest channel off and
-- audits it. Answers ok, unchanged when it was already off, not_found for
-- an account that is gone and invalid without its arguments.
CREATE FUNCTION api.notification_digest_unsubscribe_v1(
    p_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.notification_digest_unsubscribe_v1(uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- A member's subscription to a target, revoked or not.
CREATE FUNCTION api.notification_find_subscription_v1(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF api.notification_subscription_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.subscription_id, b.user_id, b.target_type, b.target_id, b.preference,
    b.created_at, b.muted_at, b.revoked_at
FROM public.subscriptions b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id
$$;
REVOKE EXECUTE ON FUNCTION api.notification_find_subscription_v1(uuid, text, uuid)
    FROM PUBLIC;

-- ADR 0102 and 0130 for the inbox: a direct-message notification stays
-- while its message is in a conversation of the recipient's, and leaves
-- with a member the recipient ignores or blocks, as a reply does.
CREATE FUNCTION api.notification_list_inbox_v5(
    p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_notification_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    recipient_user_id uuid,
    notification_id uuid,
    created_at timestamptz,
    read_at timestamptz,
    rank_score numeric,
    source_type text,
    source_id uuid,
    notification_type text,
    payload jsonb,
    source_thread_id uuid,
    source_thread_title text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY
    SELECT i.recipient_user_id, i.notification_id, i.created_at, i.read_at, i.rank_score,
      n.source_type, n.source_id, n.notification_type, n.payload,
      CASE WHEN p_filter_sources THEN CASE n.source_type WHEN 'thread' THEN n.source_id
        WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END END,
      CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id =
        CASE n.source_type WHEN 'thread' THEN n.source_id
          WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END) END
    FROM public.notification_inbox i
    JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_recipient_user_id
      AND (NOT p_filter_sources OR (n.source_type = 'message' AND EXISTS (
          SELECT 1 FROM public.direct_messages dm
          JOIN public.direct_conversation_members dmm
            ON dmm.conversation_id = dm.conversation_id
            AND dmm.user_id = p_recipient_user_id
          WHERE dm.message_id = n.source_id))
        OR ((n.source_type = 'thread' AND EXISTS (
          SELECT 1 FROM public.threads t
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))))
        OR (n.source_type = 'post' AND EXISTS (
          SELECT 1 FROM public.posts p
          JOIN public.threads t ON t.thread_id = p.thread_id
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
            AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))
            AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND NOT (n.notification_type IN ('reply', 'mention', 'direct_message') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
    ORDER BY i.created_at DESC, i.notification_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY
    SELECT i.recipient_user_id, i.notification_id, i.created_at, i.read_at, i.rank_score,
      n.source_type, n.source_id, n.notification_type, n.payload,
      CASE WHEN p_filter_sources THEN CASE n.source_type WHEN 'thread' THEN n.source_id
        WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END END,
      CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id =
        CASE n.source_type WHEN 'thread' THEN n.source_id
          WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = n.source_id) END) END
    FROM public.notification_inbox i
    JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_recipient_user_id
      AND (NOT p_filter_sources OR (n.source_type = 'message' AND EXISTS (
          SELECT 1 FROM public.direct_messages dm
          JOIN public.direct_conversation_members dmm
            ON dmm.conversation_id = dm.conversation_id
            AND dmm.user_id = p_recipient_user_id
          WHERE dm.message_id = n.source_id))
        OR ((n.source_type = 'thread' AND EXISTS (
          SELECT 1 FROM public.threads t
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))))
        OR (n.source_type = 'post' AND EXISTS (
          SELECT 1 FROM public.posts p
          JOIN public.threads t ON t.thread_id = p.thread_id
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
            AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))
            AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND i.created_at <= p_after_created_at
      AND (i.created_at < p_after_created_at OR (i.created_at = p_after_created_at AND i.notification_id < p_after_notification_id))
      AND NOT (n.notification_type IN ('reply', 'mention', 'direct_message') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
    ORDER BY i.created_at DESC, i.notification_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v5(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- A member's channel preferences.
CREATE FUNCTION api.notification_list_preferences_v1(p_user_id uuid)
RETURNS SETOF api.notification_preference_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p.user_id, p.channel, p.enabled, p.digest_frequency, p.updated_at
FROM public.notification_preferences p WHERE p.user_id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_preferences_v1(uuid)
    FROM PUBLIC;

-- Marks read every unread notification in a member's inbox that the viewer may
-- read.
CREATE FUNCTION api.notification_mark_all_read_v1(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
DECLARE v record; v_count bigint := 0;
BEGIN
  FOR v IN SELECT i.notification_id FROM public.notification_inbox i JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_user_id AND i.read_at IS NULL AND (NOT p_filter_sources OR ((n.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (n.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id))))))))))) FOR UPDATE OF i
  LOOP
    PERFORM api.core_notification_read_v1(v.notification_id, p_user_id, p_read_at);
    v_count := v_count + 1;
  END LOOP;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', CASE WHEN v_count = 0 THEN 1 ELSE 0 END, 'marked_count', v_count, 'read_at', p_read_at, 'recipient_user_id', p_user_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_all_read_v1(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text)
    FROM PUBLIC;

-- Marks one notification in a member's inbox read.
CREATE FUNCTION api.notification_mark_read_v1(
    p_notification_id uuid,
    p_recipient_user_id uuid,
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.notification_inbox%ROWTYPE; v_at text;
BEGIN
  SELECT i.* INTO v FROM public.notification_inbox i WHERE i.notification_id = p_notification_id AND i.recipient_user_id = p_recipient_user_id FOR UPDATE;
  IF v.notification_id IS NULL THEN RETURN QUERY SELECT jsonb_build_object('ok', 0, 'error', 'not_found'); RETURN; END IF;
  v_at := CASE WHEN v.read_at IS NOT NULL THEN v.read_at::text ELSE api.core_notification_read_v1(p_notification_id, p_recipient_user_id, p_read_at) END;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', CASE WHEN v.read_at IS NOT NULL THEN 1 ELSE 0 END, 'notification_id', p_notification_id, 'recipient_user_id', p_recipient_user_id, 'read_at', v_at);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_read_v1(uuid, uuid, text)
    FROM PUBLIC;

-- Stores a member's subscription, or restores the one they revoked when
-- p_restore is true.
CREATE FUNCTION api.notification_save_subscription_v1(
    p_row jsonb,
    p_restore boolean
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.subscriptions%ROWTYPE; v_constraint text; v_skipped boolean;
BEGIN
  IF p_restore THEN SELECT b.* INTO v FROM public.subscriptions b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE; END IF;
  IF v.subscription_id IS NULL THEN
    BEGIN
      INSERT INTO public.subscriptions (subscription_id, user_id, target_type, target_id, preference, created_at, muted_at, revoked_at) VALUES ((p_row->>'subscription_id')::uuid, (p_row->>'user_id')::uuid, p_row->>'target_type', (p_row->>'target_id')::uuid, p_row->>'preference', (p_row->>'created_at')::timestamptz, NULL, NULL);
      RETURN QUERY SELECT p_row; RETURN;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF NOT p_restore THEN RAISE; END IF;
      SELECT b.* INTO v FROM public.subscriptions b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE;
      IF v.subscription_id IS NULL THEN
        IF v_constraint = 'subscriptions_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
        RAISE;
      END IF;
    END;
  END IF;
  v_skipped := v.muted_at IS NULL AND v.revoked_at IS NULL AND v.preference = p_row->>'preference';
  IF NOT v_skipped THEN UPDATE public.subscriptions b SET muted_at = NULL, revoked_at = NULL, preference = p_row->>'preference' WHERE b.subscription_id = v.subscription_id; END IF;
  RETURN QUERY SELECT p_row || jsonb_build_object('subscription_id', v.subscription_id, 'created_at', v.created_at::text) || CASE WHEN v_skipped THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_save_subscription_v1(jsonb, boolean)
    FROM PUBLIC;

-- Writes one of a member's channel preferences.
CREATE FUNCTION api.notification_set_preference_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.notification_preferences%ROWTYPE;
BEGIN
  INSERT INTO public.notification_preferences (user_id, channel, enabled, digest_frequency, updated_at)
  VALUES ((p_row->>'user_id')::uuid, p_row->>'channel', (p_row->>'enabled')::boolean, p_row->>'digest_frequency', (p_row->>'updated_at')::timestamptz)
  ON CONFLICT (user_id, channel) DO NOTHING;
  IF FOUND THEN RETURN QUERY SELECT p_row; RETURN; END IF;
  SELECT p.* INTO v FROM public.notification_preferences p WHERE p.user_id = (p_row->>'user_id')::uuid AND p.channel = p_row->>'channel' FOR UPDATE;
  IF v.enabled = (p_row->>'enabled')::boolean AND v.digest_frequency = p_row->>'digest_frequency' THEN
    RETURN QUERY SELECT p_row || jsonb_build_object('skipped', 1, 'updated_at', v.updated_at::text); RETURN;
  END IF;
  UPDATE public.notification_preferences p SET enabled = (p_row->>'enabled')::boolean, digest_frequency = p_row->>'digest_frequency', updated_at = (p_row->>'updated_at')::timestamptz
  WHERE p.user_id = v.user_id AND p.channel = v.channel;
  RETURN QUERY SELECT p_row;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_preference_v1(jsonb)
    FROM PUBLIC;

-- Writes a member's kind preferences, at most one per kind and channel.
CREATE FUNCTION api.notification_set_type_preferences_v3(
    p_user_id uuid,
    p_preferences jsonb,
    p_now timestamptz
)
RETURNS TABLE (status text, changed integer)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount integer;
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL
        OR jsonb_typeof(p_preferences) IS DISTINCT FROM 'array' THEN
        RETURN QUERY SELECT 'invalid'::text, 0;
        RETURN;
    END IF;
    IF jsonb_array_length(p_preferences) > 8
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_preferences) e(v)
            WHERE jsonb_typeof(e.v) IS DISTINCT FROM 'object'
                OR coalesce(e.v ->> 'event_type', '')
                    NOT IN ('reply', 'mention', 'moderation', 'message')
                OR coalesce(e.v ->> 'channel', '')
                    NOT IN ('in_app', 'email')
                OR jsonb_typeof(e.v -> 'enabled')
                    IS DISTINCT FROM 'boolean') THEN
        RETURN QUERY SELECT 'invalid'::text, 0;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u
        WHERE u.id = p_user_id AND u.deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, 0;
        RETURN;
    END IF;
    INSERT INTO public.notification_type_preferences AS p (user_id,
        event_type, channel, enabled, updated_at)
    SELECT DISTINCT ON (e.v ->> 'event_type', e.v ->> 'channel') p_user_id,
        e.v ->> 'event_type', e.v ->> 'channel',
        (e.v ->> 'enabled')::boolean, p_now
    FROM jsonb_array_elements(p_preferences) WITH ORDINALITY e(v, n)
    ORDER BY e.v ->> 'event_type', e.v ->> 'channel', e.n DESC
    ON CONFLICT ON CONSTRAINT notification_type_preferences_pkey
    DO UPDATE SET enabled = excluded.enabled, updated_at = excluded.updated_at
        WHERE p.enabled IS DISTINCT FROM excluded.enabled;
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN QUERY SELECT CASE WHEN amount > 0 THEN 'ok' ELSE 'unchanged' END,
        amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_type_preferences_v3(uuid, jsonb, timestamptz)
    FROM PUBLIC;

-- Sets one timestamp column of a subscription, found by id or by its member
-- and target.
CREATE FUNCTION api.notification_stamp_subscription_v1(
    p_id uuid,
    p_by_target boolean,
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_column text,
    p_stamped_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.subscriptions%ROWTYPE;
BEGIN
  IF p_by_target THEN SELECT b.* INTO v FROM public.subscriptions b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id FOR UPDATE;
  ELSE SELECT b.* INTO v FROM public.subscriptions b WHERE b.subscription_id = p_id FOR UPDATE; END IF;
  IF v.subscription_id IS NULL THEN RETURN QUERY SELECT jsonb_build_object('ok', 0, 'error', 'not_found'); RETURN; END IF;
  IF p_column = 'muted_at' THEN
    IF v.muted_at IS NULL THEN UPDATE public.subscriptions b SET muted_at = p_stamped_at::timestamptz WHERE b.subscription_id = v.subscription_id; END IF;
    RETURN QUERY SELECT jsonb_build_object('subscription_id', v.subscription_id, 'muted_at', COALESCE(v.muted_at::text, p_stamped_at)) || CASE WHEN v.muted_at IS NOT NULL THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END || jsonb_build_object('ok', 1); RETURN;
  END IF; IF p_column = 'revoked_at' THEN
    IF v.revoked_at IS NULL THEN UPDATE public.subscriptions b SET revoked_at = p_stamped_at::timestamptz WHERE b.subscription_id = v.subscription_id; END IF;
    RETURN QUERY SELECT jsonb_build_object('subscription_id', v.subscription_id, 'revoked_at', COALESCE(v.revoked_at::text, p_stamped_at)) || CASE WHEN v.revoked_at IS NOT NULL THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END || jsonb_build_object('ok', 1); RETURN;
  END IF;
  RAISE EXCEPTION 'invalid stamp column' USING ERRCODE = '22023';
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_stamp_subscription_v1(uuid, boolean, uuid, text, uuid, text, text)
    FROM PUBLIC;

-- The members subscribed to a target who want to hear about a notification of
-- this kind.
CREATE FUNCTION api.notification_subscribers_v1(
    p_target_type text,
    p_target_id uuid,
    p_notification_type text
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.user_id FROM public.subscriptions s WHERE s.target_type = p_target_type AND s.target_id = p_target_id AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none' AND (s.preference = 'all' OR p_notification_type = 'mention')
$$;
REVOKE EXECUTE ON FUNCTION api.notification_subscribers_v1(text, uuid, text)
    FROM PUBLIC;

-- A member's switch for every kind on every channel, the default where they
-- stored none.
CREATE FUNCTION api.notification_type_preferences_v3(p_user_id uuid)
RETURNS TABLE (event_type text, channel text, enabled boolean, stored boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT k.event_type, c.channel,
    coalesce(p.enabled,
        api.core_notification_type_default_v2(k.event_type, c.channel)),
    p.user_id IS NOT NULL
FROM (VALUES ('reply', 1), ('mention', 2), ('moderation', 3), ('message', 4))
    AS k(event_type, rank)
CROSS JOIN (VALUES ('in_app', 1), ('email', 2)) AS c(channel, rank)
LEFT JOIN public.notification_type_preferences p
    ON p.user_id = p_user_id AND p.event_type = k.event_type
    AND p.channel = c.channel
ORDER BY k.rank, c.rank;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_type_preferences_v3(uuid)
    FROM PUBLIC;

-- How many unread notifications a member's inbox holds that the viewer may
-- read, leaving out the members on their list.
CREATE FUNCTION api.notification_unread_count_v5(
    p_recipient_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[]
)
RETURNS TABLE (unread_count bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT count(*) FROM (
    SELECT i.notification_id
    FROM public.notification_inbox i
    JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_recipient_user_id
      AND (NOT p_filter_sources OR (n.source_type = 'message' AND EXISTS (
          SELECT 1 FROM public.direct_messages dm
          JOIN public.direct_conversation_members dmm
            ON dmm.conversation_id = dm.conversation_id
            AND dmm.user_id = p_recipient_user_id
          WHERE dm.message_id = n.source_id))
        OR ((n.source_type = 'thread' AND EXISTS (
          SELECT 1 FROM public.threads t
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL
            AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))))
        OR (n.source_type = 'post' AND EXISTS (
          SELECT 1 FROM public.posts p
          JOIN public.threads t ON t.thread_id = p.thread_id
          JOIN public.categories c ON c.category_id = t.category_id
          JOIN public.spaces s ON s.space_id = c.space_id
          WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible'
            AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL
            AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false))))))
            AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id))))))
            AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id))))))))))) AND i.read_at IS NULL
      AND NOT (n.notification_type IN ('reply', 'mention', 'direct_message') AND EXISTS (
          SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_recipient_user_id
            AND r.other_user_id::text = n.payload->>'actor_id'))
    LIMIT 100
) counted
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v5(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[])
    FROM PUBLIC;

-- Turns off one kind's email, or the whole email channel, from an unsubscribe
-- link, audited.
CREATE FUNCTION api.notification_unsubscribe_v3(
    p_user_id uuid,
    p_scope text,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, scope text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE was_on boolean;
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL OR p_audit IS NULL
        OR coalesce(p_scope, '')
            NOT IN ('reply', 'mention', 'moderation', 'message', 'all') THEN
        RETURN QUERY SELECT 'invalid'::text, p_scope;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u
        WHERE u.id = p_user_id AND u.deleted_at IS NULL
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, p_scope;
        RETURN;
    END IF;
    IF p_scope = 'all' THEN
        was_on := coalesce((SELECT c.enabled
            FROM public.notification_preferences c
            WHERE c.user_id = p_user_id AND c.channel = 'email'), true);
    ELSE
        was_on := coalesce((SELECT t.enabled
            FROM public.notification_type_preferences t
            WHERE t.user_id = p_user_id AND t.event_type = p_scope
                AND t.channel = 'email'),
            api.core_notification_type_default_v2(p_scope, 'email'));
    END IF;
    IF NOT was_on THEN
        RETURN QUERY SELECT 'unchanged'::text, p_scope;
        RETURN;
    END IF;
    IF p_scope = 'all' THEN
        INSERT INTO public.notification_preferences AS p (user_id, channel,
            enabled, digest_frequency, updated_at)
        VALUES (p_user_id, 'email', false, 'daily', p_now)
        ON CONFLICT (user_id, channel)
        DO UPDATE SET enabled = false, updated_at = excluded.updated_at;
    ELSE
        INSERT INTO public.notification_type_preferences AS p (user_id,
            event_type, channel, enabled, updated_at)
        VALUES (p_user_id, p_scope, 'email', false, p_now)
        ON CONFLICT ON CONSTRAINT notification_type_preferences_pkey
        DO UPDATE SET enabled = false, updated_at = excluded.updated_at;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_scope;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unsubscribe_v3(uuid, text, timestamptz, jsonb)
    FROM PUBLIC;

COMMIT;
