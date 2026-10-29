-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- A reply's notifications went out one recipient at a time: for each
-- subscriber the worker resolved the viewer, read the delivery plan, read
-- the relation to the actor, wrote the two rows in a transaction of their
-- own, counted the unread inbox and sent the badge -- eight or nine round
-- trips per recipient, so a thread with a thousand followers was some nine
-- thousand statements inside one outbox message, which outlived its lease
-- and was claimed again by the next worker while the first was still at it.
--
-- The fan-out is now four statements however many the recipients: the
-- candidates with everything the screening reads (the first function), where
-- the source sits (the readability's own read, as before), the deliveries in
-- one call (the second function, in pages of a few hundred), and the badges
-- in one NOTIFY statement (the third). Every rule stays where it was.
-- The subscribers, the delivery plan, the relation and the viewer are the
-- functions those stores call, composed here; the readability of the source
-- (ADR 0102) is judged in Perl from the viewers these rows describe, as it
-- was, with no statement per recipient; a delivery, a queued mail and an
-- unread count are the functions the dispatcher called one at a time, the
-- count now planned once (below).

-- The subscribers of a target for one kind of notification, less the one
-- excluded (the actor), each with the delivery plan of that kind, whether a
-- relation of theirs to the actor exists (ADR 0130), and the account's
-- viewer row as api.forum_resolve_viewer answers it, in user id order. A
-- subscriber whose account is gone has a plan of the inbox alone and no
-- viewer row, as the stores answer for one.
CREATE FUNCTION api.notification_fanout_candidates_v1(
    p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid
)
RETURNS TABLE (
    user_id uuid,
    in_app boolean,
    email boolean,
    email_address text,
    locale text,
    event_type text,
    silenced boolean,
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.user_id,
    coalesce(plan.in_app, true),
    coalesce(plan.email, false),
    plan.email_address,
    plan.locale,
    plan.event_type,
    p_actor_id IS NOT NULL AND s.user_id <> p_actor_id AND EXISTS (
        SELECT 1 FROM api.community_relation_between_v1(s.user_id, p_actor_id)),
    viewer.status,
    viewer.suspended,
    viewer.grants,
    viewer.moderates,
    viewer.listed,
    viewer.trust_level
FROM api.notification_subscribers_v3(p_target_type, p_target_id, p_notification_type) s
LEFT JOIN LATERAL api.notification_delivery_plan_v3(s.user_id, p_notification_type) plan
    ON true
LEFT JOIN LATERAL api.forum_resolve_viewer_v7(s.user_id) viewer ON true
WHERE p_excluded_user_id IS NULL OR s.user_id <> p_excluded_user_id
ORDER BY s.user_id
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_candidates_v1(text, uuid, text, uuid, uuid)
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.notification_fanout_candidates_v2(
    p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid
)
RETURNS TABLE (
    user_id uuid,
    in_app boolean,
    email boolean,
    email_address text,
    locale text,
    event_type text,
    silenced boolean,
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_candidates_v1(p_target_type, p_target_id, p_notification_type, p_actor_id, p_excluded_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_candidates_v2(text, uuid, text, uuid, uuid)
    FROM PUBLIC;

-- The unread count a badge carries, planned once. api.notification_unread_count_v5
-- forces a custom plan, so every call plans its three readability subqueries
-- again: 1.4 ms of planning for a count that runs in 0.05 ms (1,000 calls:
-- 1,416 ms, against 55 ms with a generic plan), which was most of what a
-- fan-out of a thousand still cost once its round trips were gone, and 1.4 ms
-- of every delivery's and every mark-read's badge. The body is v5's, the plan
-- generic; v6, the boundary the previous release's workers call, stays until a
-- release later (ADR 0126, section 2).
CREATE FUNCTION api.notification_unread_count_v7(
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
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v7(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[])
    FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.notification_unread_count_v8(
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
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unread_count_v7(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v8(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[])
    FROM PUBLIC;

-- The deliveries of one fan-out, each drawn by the dispatcher as
-- api.notification_deliver takes one. p_recipients is a JSON array of
-- objects: recipient_user_id; in_app and email, the plan; idempotency_key,
-- notification and inbox, the delivery; email_event, email_outbox_id,
-- email_outbox_extras and email_explicit, the mail event as
-- api.ops_record_event takes it, read when email is set; filter_sources,
-- member, global_read, viewer_user_id, category_ids and space_ids, the
-- recipient as api.notification_unread_count sees them. One row per
-- recipient: outcome created, duplicate (the inbox already held it), skipped
-- (the inbox channel is off and the mail alone was queued) or failed, with
-- the delivery's result, the unread count once delivered, whether the mail
-- was queued, and the failure's message: the recipient's when the outcome is
-- failed, the count's when a delivered recipient's count failed (the badge
-- is not sent, and the delivery stands). A recipient that fails fails alone,
-- in a savepoint of their own, as a delivery of their own did; the others
-- are delivered all the same.
CREATE FUNCTION api.notification_fanout_deliver_v1(p_recipients jsonb)
RETURNS TABLE (
    recipient_user_id uuid,
    outcome text,
    result jsonb,
    unread_count bigint,
    email_queued boolean,
    error text
)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    recipient jsonb;
    v_user uuid;
    v_outcome text;
    v_result jsonb;
    v_count bigint;
    v_uncounted text;
    v_mailed boolean;
BEGIN
    FOR recipient IN SELECT * FROM jsonb_array_elements(p_recipients) LOOP
        v_user := (recipient ->> 'recipient_user_id')::uuid;
        v_result := NULL;
        v_count := NULL;
        v_uncounted := NULL;
        v_mailed := false;
        BEGIN
            IF coalesce((recipient ->> 'in_app')::boolean, false) THEN
                SELECT d.result INTO v_result
                FROM api.notification_deliver_v1(recipient -> 'notification',
                    recipient -> 'inbox', recipient ->> 'idempotency_key') d;
                v_outcome := CASE WHEN (v_result ->> 'duplicate')::integer = 1
                    THEN 'duplicate' ELSE 'created' END;
            ELSE
                v_outcome := 'skipped';
            END IF;
            IF coalesce((recipient ->> 'email')::boolean, false) THEN
                PERFORM api.ops_record_event_v1(recipient -> 'email_event',
                    recipient ->> 'email_outbox_id',
                    CASE WHEN jsonb_typeof(recipient -> 'email_outbox_extras') = 'object'
                        THEN recipient -> 'email_outbox_extras' END,
                    coalesce((recipient ->> 'email_explicit')::boolean, false));
                v_mailed := true;
            END IF;
            -- The count after the rows, in a savepoint of its own: a count
            -- that fails (a lock it waited for) leaves the delivery made, as
            -- it did when the count was a statement after the commit, and is
            -- answered as the badge's failure, not the recipient's.
            IF v_outcome <> 'skipped' THEN
                BEGIN
                    SELECT c.unread_count INTO v_count
                    FROM api.notification_unread_count_v7(v_user,
                        coalesce((recipient ->> 'filter_sources')::boolean, false),
                        coalesce((recipient ->> 'member')::boolean, false),
                        coalesce((recipient ->> 'global_read')::boolean, false),
                        (recipient ->> 'viewer_user_id')::uuid,
                        ARRAY(SELECT jsonb_array_elements_text(
                            coalesce(recipient -> 'category_ids', '[]'::jsonb)))::uuid[],
                        ARRAY(SELECT jsonb_array_elements_text(
                            coalesce(recipient -> 'space_ids', '[]'::jsonb)))::uuid[]) c;
                EXCEPTION WHEN OTHERS THEN
                    v_count := NULL;
                    v_uncounted := SQLERRM;
                END;
            END IF;
            RETURN QUERY SELECT v_user, v_outcome, v_result, v_count, v_mailed, v_uncounted;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT v_user, 'failed'::text, NULL::jsonb, NULL::bigint, false, SQLERRM;
        END;
    END LOOP;
    RETURN;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_deliver_v1(jsonb) FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.notification_fanout_deliver_v2(p_recipients jsonb)
RETURNS TABLE (
    recipient_user_id uuid,
    outcome text,
    result jsonb,
    unread_count bigint,
    email_queued boolean,
    error text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_deliver_v1(p_recipients);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_deliver_v2(jsonb) FROM PUBLIC;

-- Several realtime events on one channel in one statement: a fan-out's
-- badges, which went out one NOTIFY statement per recipient. Answers how
-- many went.
CREATE FUNCTION api.ops_publish_notifications_v1(p_channel text, p_payloads text[])
RETURNS TABLE (sent integer)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM pg_notify(p_channel, payload) FROM unnest(p_payloads) AS payload;
    RETURN QUERY SELECT coalesce(array_length(p_payloads, 1), 0);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notifications_v1(text, text[]) FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.ops_publish_notifications_v2(p_channel text, p_payloads text[])
RETURNS TABLE (sent integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_publish_notifications_v1(p_channel, p_payloads);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_publish_notifications_v2(text, text[]) FROM PUBLIC;
