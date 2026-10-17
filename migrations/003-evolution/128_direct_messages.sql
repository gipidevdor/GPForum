-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0139: direct messages. Two members hold one private conversation,
-- started from a profile and continued from the conversation's page. Each
-- side keeps its own read state and unread count; the inbox lists a
-- member's conversations by their latest message. A block either way
-- refuses a message (ADR 0130); a new member starts at most a few
-- conversations a day. Every message records a direct_message.sent event,
-- whose outbox message notifies the recipient (the first unread message
-- of a run) and reaches both members' own realtime channels; the event
-- carries ids, never the text. A participant reports a message to the
-- staff queue; staff read a reported message only through an audited
-- request, and no other. Erasure deletes the erased member's messages and
-- their side of each conversation; the export holds their conversations
-- and the messages they wrote. New versions, as ADR 0126 section 2 asks:
-- the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.direct_conversations (
    conversation_id uuid NOT NULL,
    first_user_id uuid NOT NULL,
    second_user_id uuid NOT NULL,
    started_by_user_id uuid,
    created_at timestamptz NOT NULL,
    last_message_at timestamptz NOT NULL,
    CONSTRAINT direct_conversations_pkey PRIMARY KEY (conversation_id),
    CONSTRAINT direct_conversations_pair_key
        UNIQUE (first_user_id, second_user_id),
    CONSTRAINT direct_conversations_first_user_id_fkey
        FOREIGN KEY (first_user_id) REFERENCES public.users (id)
        ON DELETE CASCADE,
    CONSTRAINT direct_conversations_second_user_id_fkey
        FOREIGN KEY (second_user_id) REFERENCES public.users (id)
        ON DELETE CASCADE,
    CONSTRAINT direct_conversations_started_by_user_id_fkey
        FOREIGN KEY (started_by_user_id) REFERENCES public.users (id)
        ON DELETE SET NULL,
    CONSTRAINT direct_conversations_pair_order_check
        CHECK (first_user_id < second_user_id)
);
CREATE INDEX idx_direct_conversations_second
    ON public.direct_conversations (second_user_id);
CREATE INDEX idx_direct_conversations_started
    ON public.direct_conversations (started_by_user_id, created_at);

-- One row per member of a conversation: whom it is with, when it last
-- moved (the inbox's order), when the member last read it and how many
-- messages wait for them.
CREATE TABLE public.direct_conversation_members (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    other_user_id uuid NOT NULL,
    last_message_at timestamptz NOT NULL,
    last_read_at timestamptz,
    unread_count integer NOT NULL DEFAULT 0,
    CONSTRAINT direct_conversation_members_pkey
        PRIMARY KEY (conversation_id, user_id),
    CONSTRAINT direct_conversation_members_conversation_id_fkey
        FOREIGN KEY (conversation_id)
        REFERENCES public.direct_conversations (conversation_id)
        ON DELETE CASCADE,
    CONSTRAINT direct_conversation_members_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT direct_conversation_members_other_user_id_fkey
        FOREIGN KEY (other_user_id) REFERENCES public.users (id)
        ON DELETE CASCADE,
    CONSTRAINT direct_conversation_members_unread_count_check
        CHECK (unread_count >= 0)
);
CREATE INDEX idx_direct_conversation_members_inbox
    ON public.direct_conversation_members
    (user_id, last_message_at DESC, conversation_id DESC);
CREATE INDEX idx_direct_conversation_members_other
    ON public.direct_conversation_members (other_user_id);

CREATE TABLE public.direct_messages (
    message_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    author_user_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL,
    position bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT direct_messages_pkey PRIMARY KEY (message_id),
    CONSTRAINT direct_messages_conversation_id_fkey
        FOREIGN KEY (conversation_id)
        REFERENCES public.direct_conversations (conversation_id)
        ON DELETE CASCADE,
    CONSTRAINT direct_messages_author_user_id_fkey
        FOREIGN KEY (author_user_id) REFERENCES public.users (id)
        ON DELETE CASCADE,
    CONSTRAINT direct_messages_body_check
        CHECK (length(body) BETWEEN 1 AND 5000)
);
CREATE INDEX idx_direct_messages_conversation
    ON public.direct_messages (conversation_id, position DESC);
CREATE INDEX idx_direct_messages_author
    ON public.direct_messages (author_user_id);

-- A message is reported like a post, a thread or a profile; the kind of
-- notification about messages has its own switches.
ALTER TABLE public.reports
    DROP CONSTRAINT reports_target_type_check,
    ADD CONSTRAINT reports_target_type_check
        CHECK (target_type IN ('thread', 'post', 'user', 'message'));
ALTER TABLE public.notification_type_preferences
    DROP CONSTRAINT notification_type_preferences_event_type_check,
    ADD CONSTRAINT notification_type_preferences_event_type_check
        CHECK (event_type IN ('reply', 'mention', 'moderation', 'message'));

-- The event a message records, as EventRecorder shapes one: the row
-- carries the ids the store drew (event, outbox, correlation) and the time
-- it stamped. Ids only: the text never leaves the table.
CREATE FUNCTION api.core_community_message_event_v1(p_row jsonb,
    p_conversation_id uuid, p_recipient_user_id uuid, p_first_unread boolean,
    p_started boolean)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object(
    'actor_id', p_row -> 'sender_user_id',
    'aggregate_id', p_conversation_id,
    'aggregate_type', 'conversation',
    'aggregate_version', 1,
    'causation_id', NULL,
    'correlation_id', p_row -> 'correlation_id',
    'created_at', p_row -> 'created_at',
    'event_id', p_row -> 'event_id',
    'event_type', 'direct_message.sent',
    'idempotency_key', 'direct_message.sent:' || (p_row ->> 'message_id'),
    'metadata', jsonb_build_object(
        'actor', jsonb_build_object('id', p_row -> 'sender_user_id'),
        'aggregate_id', p_conversation_id,
        'causation_id', NULL,
        'correlation_id', p_row -> 'correlation_id',
        'event_id', p_row -> 'event_id',
        'timestamp', p_row -> 'created_at',
        'transport', jsonb_build_object(
            'listen_notify_channel', 'gpforum_domain_events',
            'minion_job', 'domain_event.dispatch',
            'stream', 'gpforum.domain_events')),
    'payload', jsonb_build_object(
        'conversation_id', p_conversation_id,
        'message_id', p_row -> 'message_id',
        'sender_user_id', p_row -> 'sender_user_id',
        'recipient_user_id', p_recipient_user_id,
        'first_unread', p_first_unread,
        'started', p_started),
    'schema_version', 1)
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_event_v1(jsonb, uuid,
    uuid, boolean, boolean) FROM PUBLIC;

-- Appends the message to a conversation whose row the caller holds: the
-- sender has read everything up to it, the recipient has one more unread.
-- A message id already stored is the same message again (replayed) when
-- the sender wrote it in this conversation, and a conflict otherwise.
CREATE FUNCTION api.core_community_message_append_v1(p_row jsonb,
    p_conversation_id uuid, p_recipient_user_id uuid, p_started boolean)
RETURNS TABLE(status text, first_unread boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    sender uuid := (p_row ->> 'sender_user_id')::uuid;
    message uuid := (p_row ->> 'message_id')::uuid;
    sent_at timestamptz := (p_row ->> 'created_at')::timestamptz;
    unread integer;
    existing record;
BEGIN
    INSERT INTO public.direct_messages (message_id, conversation_id,
        author_user_id, body, created_at)
        VALUES (message, p_conversation_id, sender, p_row ->> 'body', sent_at)
        ON CONFLICT ON CONSTRAINT direct_messages_pkey DO NOTHING;
    IF NOT FOUND THEN
        SELECT d.conversation_id, d.author_user_id INTO existing
            FROM public.direct_messages d WHERE d.message_id = message;
        RETURN QUERY SELECT CASE WHEN existing.author_user_id = sender
            AND existing.conversation_id = p_conversation_id
            THEN 'replayed' ELSE 'conflict' END, false;
        RETURN;
    END IF;
    UPDATE public.direct_conversations c
        SET last_message_at = greatest(c.last_message_at, sent_at)
        WHERE c.conversation_id = p_conversation_id;
    UPDATE public.direct_conversation_members m
        SET last_message_at = greatest(m.last_message_at, sent_at),
            last_read_at = greatest(coalesce(m.last_read_at, sent_at), sent_at),
            unread_count = 0
        WHERE m.conversation_id = p_conversation_id AND m.user_id = sender;
    UPDATE public.direct_conversation_members m
        SET last_message_at = greatest(m.last_message_at, sent_at),
            unread_count = m.unread_count + 1
        WHERE m.conversation_id = p_conversation_id
            AND m.user_id = p_recipient_user_id
        RETURNING m.unread_count INTO unread;
    PERFORM api.core_record_event_v1(api.core_community_message_event_v1(
        p_row, p_conversation_id, p_recipient_user_id,
        coalesce(unread, 0) = 1, p_started), p_row ->> 'outbox_id');
    RETURN QUERY SELECT 'ok'::text, coalesce(unread, 0) = 1;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_append_v1(jsonb, uuid,
    uuid, boolean) FROM PUBLIC;

-- True when either member blocks the other (ADR 0130).
CREATE FUNCTION api.core_community_message_blocked_v1(p_one uuid, p_other uuid)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (SELECT 1 FROM public.member_relations r
    WHERE r.kind = 'block'
        AND ((r.owner_user_id = p_one AND r.other_user_id = p_other)
            OR (r.owner_user_id = p_other AND r.other_user_id = p_one)));
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_blocked_v1(uuid, uuid)
    FROM PUBLIC;

-- The row a send is written from is complete: the ids, the time, a body
-- of 1 to 5000 characters.
CREATE FUNCTION api.core_community_message_row_valid_v1(p_row jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_row IS NOT NULL
    AND jsonb_typeof(p_row) = 'object'
    AND p_row ->> 'message_id' IS NOT NULL
    AND p_row ->> 'sender_user_id' IS NOT NULL
    AND p_row ->> 'created_at' IS NOT NULL
    AND p_row ->> 'event_id' IS NOT NULL
    AND p_row ->> 'correlation_id' IS NOT NULL
    AND p_row ->> 'outbox_id' IS NOT NULL
    AND coalesce(length(p_row ->> 'body'), 0) BETWEEN 1 AND 5000;
$$;
REVOKE EXECUTE ON FUNCTION api.core_community_message_row_valid_v1(jsonb)
    FROM PUBLIC;

-- Sends a message to the member named, in the one conversation the two
-- hold, starting it when there is none. Refusals: invalid, forbidden (the
-- sender cannot write), not_found (no such member to write to), self,
-- blocked (either blocks the other), limit (the sender started as many
-- conversations in the last day as their trust allows), conflict (the
-- message id is another message). The same message again is replayed.
CREATE FUNCTION api.community_message_start_v1(p_row jsonb)
RETURNS TABLE(status text, conversation_id uuid, message_id uuid,
    recipient_user_id uuid, started boolean, first_unread boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    sender uuid;
    message uuid;
    sent_at timestamptz;
    writer record;
    recipient uuid;
    existing record;
    conversation uuid;
    is_new boolean := false;
    recent bigint;
    allowed integer;
    outcome record;
BEGIN
    IF NOT api.core_community_message_row_valid_v1(p_row)
        OR p_row ->> 'new_conversation_id' IS NULL
        OR coalesce(length(p_row ->> 'username'), 0) NOT BETWEEN 1 AND 200
        OR (p_row ->> 'daily_limit') IS NULL
        OR (p_row ->> 'new_member_daily_limit') IS NULL
        OR (p_row ->> 'new_member_trust_below') IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    sender := (p_row ->> 'sender_user_id')::uuid;
    message := (p_row ->> 'message_id')::uuid;
    sent_at := (p_row ->> 'created_at')::timestamptz;
    SELECT d.conversation_id, d.author_user_id INTO existing
        FROM public.direct_messages d WHERE d.message_id = message;
    IF FOUND THEN
        RETURN QUERY SELECT CASE WHEN existing.author_user_id = sender
            THEN 'replayed' ELSE 'conflict' END,
            CASE WHEN existing.author_user_id = sender
            THEN existing.conversation_id END,
            message, NULL::uuid, false, false;
        RETURN;
    END IF;
    SELECT u.status, u.trust_level INTO writer FROM public.users u
        WHERE u.id = sender AND u.deleted_at IS NULL;
    IF NOT FOUND OR writer.status <> 'active' THEN
        RETURN QUERY SELECT 'forbidden'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    SELECT u.id INTO recipient FROM public.users u
        WHERE u.username = p_row ->> 'username' AND u.deleted_at IS NULL
            AND u.status IN ('active', 'suspended');
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    IF recipient = sender THEN
        RETURN QUERY SELECT 'self'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    IF api.core_community_message_blocked_v1(sender, recipient) THEN
        RETURN QUERY SELECT 'blocked'::text, NULL::uuid, NULL::uuid,
            recipient, false, false;
        RETURN;
    END IF;
    SELECT c.conversation_id INTO conversation
        FROM public.direct_conversations c
        WHERE c.first_user_id = least(sender, recipient)
            AND c.second_user_id = greatest(sender, recipient)
        FOR UPDATE;
    IF NOT FOUND THEN
        -- The sender's new conversations are counted one request at a
        -- time, so two cannot both take the last place of the day.
        PERFORM pg_advisory_xact_lock(2026101701, hashtext(sender::text));
        SELECT count(*) INTO recent FROM public.direct_conversations c
            WHERE c.started_by_user_id = sender
                AND c.created_at > sent_at - interval '1 day';
        allowed := CASE
            WHEN writer.trust_level < (p_row ->> 'new_member_trust_below')::integer
            THEN (p_row ->> 'new_member_daily_limit')::integer
            ELSE (p_row ->> 'daily_limit')::integer END;
        IF recent >= allowed THEN
            RETURN QUERY SELECT 'limit'::text, NULL::uuid, NULL::uuid,
                recipient, false, false;
            RETURN;
        END IF;
        INSERT INTO public.direct_conversations (conversation_id,
            first_user_id, second_user_id, started_by_user_id, created_at,
            last_message_at)
            VALUES ((p_row ->> 'new_conversation_id')::uuid,
                least(sender, recipient), greatest(sender, recipient), sender,
                sent_at, sent_at)
            ON CONFLICT ON CONSTRAINT direct_conversations_pair_key
            DO NOTHING;
        IF FOUND THEN
            conversation := (p_row ->> 'new_conversation_id')::uuid;
            is_new := true;
            INSERT INTO public.direct_conversation_members (conversation_id,
                user_id, other_user_id, last_message_at, last_read_at,
                unread_count)
                VALUES (conversation, sender, recipient, sent_at, sent_at, 0),
                    (conversation, recipient, sender, sent_at, NULL, 0);
        ELSE
            SELECT c.conversation_id INTO conversation
                FROM public.direct_conversations c
                WHERE c.first_user_id = least(sender, recipient)
                    AND c.second_user_id = greatest(sender, recipient)
                FOR UPDATE;
        END IF;
    END IF;
    SELECT * INTO outcome FROM api.core_community_message_append_v1(p_row,
        conversation, recipient, is_new);
    IF outcome.status <> 'ok' THEN
        RETURN QUERY SELECT outcome.status, CASE WHEN outcome.status
            = 'replayed' THEN conversation END, message, NULL::uuid, false,
            false;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'ok'::text, conversation, message, recipient, is_new,
        outcome.first_unread;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_start_v1(jsonb) FROM PUBLIC;

-- Sends a message in a conversation the sender is a member of. Refusals:
-- invalid, forbidden, not_found (no such conversation of the sender's),
-- gone (the other member's account was erased), blocked, conflict.
CREATE FUNCTION api.community_message_reply_v1(p_row jsonb)
RETURNS TABLE(status text, conversation_id uuid, message_id uuid,
    recipient_user_id uuid, started boolean, first_unread boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    sender uuid;
    message uuid;
    conversation uuid;
    other uuid;
    existing record;
    outcome record;
BEGIN
    IF NOT api.core_community_message_row_valid_v1(p_row)
        OR p_row ->> 'conversation_id' IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    sender := (p_row ->> 'sender_user_id')::uuid;
    message := (p_row ->> 'message_id')::uuid;
    conversation := (p_row ->> 'conversation_id')::uuid;
    SELECT d.conversation_id, d.author_user_id INTO existing
        FROM public.direct_messages d WHERE d.message_id = message;
    IF FOUND THEN
        RETURN QUERY SELECT CASE WHEN existing.author_user_id = sender
            AND existing.conversation_id = conversation
            THEN 'replayed' ELSE 'conflict' END,
            conversation, message, NULL::uuid, false, false;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u
        WHERE u.id = sender AND u.deleted_at IS NULL AND u.status = 'active';
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'forbidden'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    SELECT m.other_user_id INTO other
        FROM public.direct_conversation_members m
        WHERE m.conversation_id = conversation AND m.user_id = sender;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, false, false;
        RETURN;
    END IF;
    PERFORM 1 FROM public.direct_conversation_members m
        JOIN public.users u ON u.id = m.user_id
        WHERE m.conversation_id = conversation AND m.user_id = other
            AND u.deleted_at IS NULL AND u.status IN ('active', 'suspended');
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'gone'::text, conversation, NULL::uuid, other,
            false, false;
        RETURN;
    END IF;
    IF api.core_community_message_blocked_v1(sender, other) THEN
        RETURN QUERY SELECT 'blocked'::text, conversation, NULL::uuid, other,
            false, false;
        RETURN;
    END IF;
    PERFORM 1 FROM public.direct_conversations c
        WHERE c.conversation_id = conversation FOR UPDATE;
    SELECT * INTO outcome FROM api.core_community_message_append_v1(p_row,
        conversation, other, false);
    IF outcome.status <> 'ok' THEN
        RETURN QUERY SELECT outcome.status, conversation, message, NULL::uuid,
            false, false;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'ok'::text, conversation, message, other, false,
        outcome.first_unread;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_reply_v1(jsonb) FROM PUBLIC;

-- The member's conversations, the one moved last first, each with whom
-- it is held, how many messages wait and the start of the latest one.
CREATE FUNCTION api.community_message_inbox_v1(p_user_id uuid,
    p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS TABLE(conversation_id uuid, other_user_id uuid,
    other_username text, other_display_name text, other_gone boolean,
    last_message_at timestamptz, unread_count integer,
    last_author_user_id uuid, last_excerpt text)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_after_at IS NULL OR p_after_id IS NULL THEN
        RETURN QUERY
        SELECT m.conversation_id, m.other_user_id, u.username,
            u.display_name, (u.deleted_at IS NOT NULL OR u.status = 'deleted'),
            m.last_message_at, m.unread_count, latest.author_user_id,
            left(latest.body, 140)
        FROM public.direct_conversation_members m
        JOIN public.users u ON u.id = m.other_user_id
        LEFT JOIN LATERAL (
            SELECT d.author_user_id, d.body FROM public.direct_messages d
            WHERE d.conversation_id = m.conversation_id
            ORDER BY d.position DESC LIMIT 1
        ) latest ON true
        WHERE m.user_id = p_user_id
        ORDER BY m.last_message_at DESC, m.conversation_id DESC
        LIMIT p_row_limit;
    ELSE
        RETURN QUERY
        SELECT m.conversation_id, m.other_user_id, u.username,
            u.display_name, (u.deleted_at IS NOT NULL OR u.status = 'deleted'),
            m.last_message_at, m.unread_count, latest.author_user_id,
            left(latest.body, 140)
        FROM public.direct_conversation_members m
        JOIN public.users u ON u.id = m.other_user_id
        LEFT JOIN LATERAL (
            SELECT d.author_user_id, d.body FROM public.direct_messages d
            WHERE d.conversation_id = m.conversation_id
            ORDER BY d.position DESC LIMIT 1
        ) latest ON true
        WHERE m.user_id = p_user_id
            AND m.last_message_at <= p_after_at
            AND (m.last_message_at < p_after_at
                OR m.conversation_id < p_after_id)
        ORDER BY m.last_message_at DESC, m.conversation_id DESC
        LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_inbox_v1(uuid, timestamptz,
    uuid, integer) FROM PUBLIC;

-- A conversation as one of its members reads it, or no row for anyone
-- else: with whom, whether that account is gone, the reader's unread
-- count and whether the reader blocks the other member.
CREATE FUNCTION api.community_message_conversation_v1(p_conversation_id uuid,
    p_user_id uuid)
RETURNS TABLE(conversation_id uuid, other_user_id uuid,
    other_username text, other_display_name text, other_gone boolean,
    unread_count integer, last_read_at timestamptz, created_at timestamptz,
    reader_blocks boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT m.conversation_id, m.other_user_id, u.username, u.display_name,
    (u.deleted_at IS NOT NULL OR u.status = 'deleted'
        OR NOT EXISTS (SELECT 1 FROM public.direct_conversation_members o
            WHERE o.conversation_id = m.conversation_id
                AND o.user_id = m.other_user_id)),
    m.unread_count, m.last_read_at, c.created_at,
    EXISTS (SELECT 1 FROM public.member_relations r
        WHERE r.owner_user_id = p_user_id
            AND r.other_user_id = m.other_user_id AND r.kind = 'block')
FROM public.direct_conversation_members m
JOIN public.direct_conversations c ON c.conversation_id = m.conversation_id
JOIN public.users u ON u.id = m.other_user_id
WHERE m.conversation_id = p_conversation_id AND m.user_id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_v1(uuid, uuid)
    FROM PUBLIC;

-- A page of a conversation's messages, newest first, for one of its
-- members only, in the order they were stored; before a message's
-- position for the older ones.
CREATE FUNCTION api.community_message_list_v1(p_conversation_id uuid,
    p_user_id uuid, p_before_position bigint, p_row_limit integer)
RETURNS TABLE(message_id uuid, author_user_id uuid, author_username text,
    author_display_name text, body text, created_at timestamptz,
    message_position bigint)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.direct_conversation_members m
        WHERE m.conversation_id = p_conversation_id
            AND m.user_id = p_user_id) THEN
        RETURN;
    END IF;
    IF p_before_position IS NULL THEN
        RETURN QUERY
        SELECT d.message_id, d.author_user_id, a.username, a.display_name,
            d.body, d.created_at, d.position
        FROM public.direct_messages d
        JOIN public.users a ON a.id = d.author_user_id
        WHERE d.conversation_id = p_conversation_id
        ORDER BY d.position DESC
        LIMIT p_row_limit;
    ELSE
        RETURN QUERY
        SELECT d.message_id, d.author_user_id, a.username, a.display_name,
            d.body, d.created_at, d.position
        FROM public.direct_messages d
        JOIN public.users a ON a.id = d.author_user_id
        WHERE d.conversation_id = p_conversation_id
            AND d.position < p_before_position
        ORDER BY d.position DESC
        LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_list_v1(uuid, uuid,
    bigint, integer) FROM PUBLIC;

-- The member has read the conversation: nothing waits, and the inbox's
-- notifications of its messages are read as well. Answers unchanged when
-- nothing waited and not_found for anyone not a member.
CREATE FUNCTION api.community_message_mark_read_v1(p_conversation_id uuid,
    p_user_id uuid, p_now timestamptz)
RETURNS TABLE(status text, notifications_read integer)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE waiting integer; amount integer;
BEGIN
    SELECT m.unread_count INTO waiting
        FROM public.direct_conversation_members m
        WHERE m.conversation_id = p_conversation_id AND m.user_id = p_user_id
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, 0;
        RETURN;
    END IF;
    IF waiting = 0 THEN
        RETURN QUERY SELECT 'unchanged'::text, 0;
        RETURN;
    END IF;
    UPDATE public.direct_conversation_members m
        SET unread_count = 0,
            last_read_at = greatest(coalesce(m.last_read_at, p_now), p_now)
        WHERE m.conversation_id = p_conversation_id
            AND m.user_id = p_user_id;
    UPDATE public.notification_inbox i SET read_at = p_now
        FROM public.notifications n
        WHERE i.recipient_user_id = p_user_id AND i.read_at IS NULL
            AND n.notification_id = i.notification_id
            AND n.created_at = i.created_at
            AND n.notification_type = 'direct_message'
            AND n.payload ->> 'conversation_id' = p_conversation_id::text;
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN QUERY SELECT 'ok'::text, amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_mark_read_v1(uuid, uuid,
    timestamptz) FROM PUBLIC;

-- Whom the member would write to by that name, and the conversation the
-- two already hold, if any: no row for a member who is not there to
-- write to.
CREATE FUNCTION api.community_message_conversation_with_v1(p_user_id uuid,
    p_username text)
RETURNS TABLE(other_user_id uuid, other_username text,
    other_display_name text, conversation_id uuid)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id, u.username, u.display_name,
    (SELECT c.conversation_id FROM public.direct_conversations c
        WHERE c.first_user_id = least(p_user_id, u.id)
            AND c.second_user_id = greatest(p_user_id, u.id))
FROM public.users u
WHERE u.username = p_username AND u.deleted_at IS NULL
    AND u.status IN ('active', 'suspended');
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_with_v1(uuid,
    text) FROM PUBLIC;

-- A message the member may report: one in a conversation of theirs that
-- another member wrote. No row otherwise.
CREATE FUNCTION api.community_message_for_report_v1(p_message_id uuid,
    p_user_id uuid)
RETURNS TABLE(message_id uuid, conversation_id uuid, author_user_id uuid)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT d.message_id, d.conversation_id, d.author_user_id
FROM public.direct_messages d
JOIN public.direct_conversation_members m
    ON m.conversation_id = d.conversation_id AND m.user_id = p_user_id
WHERE d.message_id = p_message_id AND d.author_user_id <> p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_for_report_v1(uuid, uuid)
    FROM PUBLIC;

-- Whether the member takes part in the conversation of the message: who
-- may be notified about it.
CREATE FUNCTION api.community_message_participant_v1(p_message_id uuid,
    p_user_id uuid)
RETURNS TABLE(participant boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (SELECT 1 FROM public.direct_messages d
    JOIN public.direct_conversation_members m
        ON m.conversation_id = d.conversation_id AND m.user_id = p_user_id
    WHERE d.message_id = p_message_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_participant_v1(uuid, uuid)
    FROM PUBLIC;

-- The one way staff read a member's message: the message a report names,
-- with the audit of the reading recorded in the same call. not_found for a
-- report that is not about a message, gone when the message was erased.
CREATE FUNCTION api.moderation_reported_message_v1(p_report_id uuid,
    p_audit jsonb)
RETURNS TABLE(status text, report_id uuid, message_id uuid,
    author_user_id uuid, author_username text, body text,
    created_at timestamptz)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE target uuid; held_message record;
BEGIN
    IF p_report_id IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, NULL::text, NULL::text, NULL::timestamptz;
        RETURN;
    END IF;
    SELECT r.target_id INTO target FROM public.reports r
        WHERE r.report_id = p_report_id AND r.target_type = 'message';
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid,
            NULL::uuid, NULL::text, NULL::text, NULL::timestamptz;
        RETURN;
    END IF;
    SELECT d.message_id, d.author_user_id, a.username, d.body, d.created_at
        INTO held_message
        FROM public.direct_messages d
        JOIN public.users a ON a.id = d.author_user_id
        WHERE d.message_id = target;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'gone'::text, p_report_id, target, NULL::uuid,
            NULL::text, NULL::text, NULL::timestamptz;
        RETURN;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
        'target_id', target), false);
    RETURN QUERY SELECT 'ok'::text, p_report_id, held_message.message_id,
        held_message.author_user_id, held_message.username, held_message.body, held_message.created_at;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_reported_message_v1(uuid, jsonb)
    FROM PUBLIC;

-- An erased member's messages go, with their side of every conversation;
-- the other member keeps their own messages, and a conversation nobody is
-- left in goes too.
CREATE FUNCTION api.privacy_revoke_user_v13(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'DirectMessage' THEN
        DELETE FROM public.direct_messages d WHERE d.author_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        UPDATE public.direct_conversation_members m
            SET unread_count = (SELECT count(*)
                FROM public.direct_messages d
                WHERE d.conversation_id = m.conversation_id
                    AND d.author_user_id <> m.user_id
                    AND (m.last_read_at IS NULL
                        OR d.created_at > m.last_read_at))
            WHERE m.other_user_id = p_user_id;
        DELETE FROM public.direct_conversation_members m
            WHERE m.user_id = p_user_id;
        DELETE FROM public.direct_conversations c
            WHERE (c.first_user_id = p_user_id OR c.second_user_id = p_user_id)
                AND NOT EXISTS (SELECT 1
                    FROM public.direct_conversation_members m
                    WHERE m.conversation_id = c.conversation_id);
        UPDATE public.direct_conversations c SET started_by_user_id = NULL
            WHERE c.started_by_user_id = p_user_id;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v11(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v13(text, uuid, text)
    FROM PUBLIC;

-- The export: the member's conversations, with whom, and the messages
-- they wrote; never the other member's messages (ADR 0074).
CREATE FUNCTION api.portability_export_parts_v15(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'direct_messages',
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'conversation_id', m.conversation_id,
        'with_username', u.username,
        'started_at', c.created_at,
        'messages', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                'message_id', d.message_id, 'body', d.body,
                'created_at', d.created_at)
                ORDER BY d.position), '[]'::jsonb)
            FROM public.direct_messages d
            WHERE d.conversation_id = m.conversation_id
                AND d.author_user_id = p_user_id))
        ORDER BY c.created_at, m.conversation_id), '[]'::jsonb)
     FROM public.direct_conversation_members m
     JOIN public.direct_conversations c
        ON c.conversation_id = m.conversation_id
     JOIN public.users u ON u.id = m.other_user_id
     WHERE m.user_id = p_user_id)))::json
FROM api.portability_export_parts_v13(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v15(uuid) FROM PUBLIC;

-- ADR 0078's kinds gain messages: a direct_message notification belongs
-- to the kind message, on in the inbox and by email unless the member
-- turns it off.
CREATE FUNCTION api.core_notification_event_type_v2(p_notification_type text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE
    WHEN p_notification_type IN ('reply', 'follow') THEN 'reply'
    WHEN p_notification_type = 'mention' THEN 'mention'
    WHEN p_notification_type IN ('review_approved', 'review_rejected')
        THEN 'moderation'
    WHEN p_notification_type = 'direct_message' THEN 'message'
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_event_type_v2(text)
    FROM PUBLIC;

CREATE FUNCTION api.core_notification_type_default_v2(p_event_type text,
    p_channel text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_channel = 'in_app'
    OR p_event_type IN ('mention', 'moderation', 'message');
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_type_default_v2(text, text)
    FROM PUBLIC;

CREATE FUNCTION api.notification_type_preferences_v3(p_user_id uuid)
RETURNS TABLE(event_type text, channel text, enabled boolean,
    stored boolean)
LANGUAGE sql STABLE
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

CREATE FUNCTION api.notification_set_type_preferences_v3(p_user_id uuid,
    p_preferences jsonb, p_now timestamptz)
RETURNS TABLE(status text, changed integer)
LANGUAGE plpgsql VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.notification_set_type_preferences_v3(uuid,
    jsonb, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.notification_delivery_plan_v3(p_user_id uuid,
    p_notification_type text)
RETURNS TABLE(event_type text, in_app boolean, email boolean,
    email_address text, locale text)
LANGUAGE sql STABLE
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

CREATE FUNCTION api.notification_unsubscribe_v3(p_user_id uuid,
    p_scope text, p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, scope text)
LANGUAGE plpgsql VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.notification_unsubscribe_v3(uuid, text,
    timestamptz, jsonb) FROM PUBLIC;

-- ADR 0133 screens a message as it screens a reply: a flag opens a system
-- report on the message.
CREATE FUNCTION api.moderation_automod_record_v3(p_report jsonb,
    p_event jsonb, p_event_outbox_id text, p_report_audit jsonb,
    p_audits jsonb)
RETURNS TABLE(report_id uuid, flagged boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held uuid; created boolean := false; item jsonb;
BEGIN
    IF p_report IS NOT NULL THEN
        IF p_report ->> 'target_type' NOT IN ('thread', 'post', 'user',
                'message')
            OR p_event IS NULL OR p_report_audit IS NULL THEN
            RAISE EXCEPTION 'an automod report needs its target, event and audit'
                USING ERRCODE = '22023';
        END IF;
        PERFORM pg_advisory_xact_lock(2026101502, hashtext(
            (p_report ->> 'target_type') || ':' || (p_report ->> 'target_id')));
        SELECT r.report_id INTO held FROM public.reports r
            WHERE r.reporter_user_id IS NULL
                AND r.target_type = p_report ->> 'target_type'
                AND r.target_id = (p_report ->> 'target_id')::uuid
                AND r.status IN ('open', 'triaged')
            ORDER BY r.created_at, r.report_id LIMIT 1;
        IF NOT FOUND THEN
            INSERT INTO public.reports (report_id, reporter_user_id,
                target_type, target_id, reason, details, status, created_at)
                VALUES ((p_report ->> 'report_id')::uuid, NULL,
                    p_report ->> 'target_type',
                    (p_report ->> 'target_id')::uuid, p_report ->> 'reason',
                    coalesce(p_report ->> 'details', ''), 'open',
                    (p_report ->> 'created_at')::timestamptz);
            held := (p_report ->> 'report_id')::uuid;
            created := true;
            PERFORM api.ops_record_event_v1(p_event, p_event_outbox_id, NULL,
                false);
            PERFORM api.ops_record_audit_v1(p_report_audit, false);
        END IF;
    END IF;
    FOR item IN SELECT a.value FROM jsonb_array_elements(
        coalesce(p_audits, '[]'::jsonb)) a LOOP
        PERFORM api.ops_record_audit_v1(item, false);
    END LOOP;
    RETURN QUERY SELECT held, created;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v3(jsonb, jsonb,
    text, jsonb, jsonb) FROM PUBLIC;

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
    recipient_user_id uuid, notification_id uuid, created_at timestamptz,
    read_at timestamptz, rank_score numeric, source_type text, source_id uuid,
    notification_type text, payload jsonb, source_thread_id uuid, source_thread_title text
)
LANGUAGE plpgsql STABLE
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
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v5(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

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
LANGUAGE sql STABLE
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
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v5(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[]) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.community_message_start_v2(
p_row jsonb
)
RETURNS TABLE(status text, conversation_id uuid, message_id uuid,
    recipient_user_id uuid, started boolean, first_unread boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_start_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_start_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_message_reply_v2(
p_row jsonb
)
RETURNS TABLE(status text, conversation_id uuid, message_id uuid,
    recipient_user_id uuid, started boolean, first_unread boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_reply_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_reply_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_message_inbox_v2(
p_user_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer
)
RETURNS TABLE(conversation_id uuid, other_user_id uuid,
    other_username text, other_display_name text, other_gone boolean,
    last_message_at timestamptz, unread_count integer,
    last_author_user_id uuid, last_excerpt text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_inbox_v1(p_user_id, p_after_at,
    p_after_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_inbox_v2(uuid, timestamptz,
    uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.community_message_conversation_v2(
p_conversation_id uuid, p_user_id uuid
)
RETURNS TABLE(conversation_id uuid, other_user_id uuid,
    other_username text, other_display_name text, other_gone boolean,
    unread_count integer, last_read_at timestamptz, created_at timestamptz,
    reader_blocks boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_conversation_v1(p_conversation_id,
    p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_v2(uuid, uuid)
    FROM PUBLIC;

CREATE FUNCTION api.community_message_list_v2(
p_conversation_id uuid, p_user_id uuid, p_before_position bigint,
p_row_limit integer
)
RETURNS TABLE(message_id uuid, author_user_id uuid, author_username text,
    author_display_name text, body text, created_at timestamptz,
    message_position bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_list_v1(p_conversation_id, p_user_id,
    p_before_position, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_list_v2(uuid, uuid,
    bigint, integer) FROM PUBLIC;

CREATE FUNCTION api.community_message_mark_read_v2(
p_conversation_id uuid, p_user_id uuid, p_now timestamptz
)
RETURNS TABLE(status text, notifications_read integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_mark_read_v1(p_conversation_id,
    p_user_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_mark_read_v2(uuid, uuid,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.community_message_conversation_with_v2(
p_user_id uuid, p_username text
)
RETURNS TABLE(other_user_id uuid, other_username text,
    other_display_name text, conversation_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_conversation_with_v1(p_user_id,
    p_username);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_with_v2(uuid,
    text) FROM PUBLIC;

CREATE FUNCTION api.community_message_for_report_v2(
p_message_id uuid, p_user_id uuid
)
RETURNS TABLE(message_id uuid, conversation_id uuid, author_user_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_for_report_v1(p_message_id, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_for_report_v2(uuid, uuid)
    FROM PUBLIC;

CREATE FUNCTION api.community_message_participant_v2(
p_message_id uuid, p_user_id uuid
)
RETURNS TABLE(participant boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_message_participant_v1(p_message_id, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_message_participant_v2(uuid, uuid)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_reported_message_v2(
p_report_id uuid, p_audit jsonb
)
RETURNS TABLE(status text, report_id uuid, message_id uuid,
    author_user_id uuid, author_username text, body text,
    created_at timestamptz)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_reported_message_v1(p_report_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_reported_message_v2(uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v14(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v13(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v14(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v16(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v15(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v16(uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_type_preferences_v4(
p_user_id uuid
)
RETURNS TABLE(event_type text, channel text, enabled boolean,
    stored boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_type_preferences_v3(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_type_preferences_v4(uuid)
    FROM PUBLIC;

CREATE FUNCTION api.notification_set_type_preferences_v4(
p_user_id uuid, p_preferences jsonb, p_now timestamptz
)
RETURNS TABLE(status text, changed integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_set_type_preferences_v3(p_user_id,
    p_preferences, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_type_preferences_v4(uuid,
    jsonb, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.notification_delivery_plan_v4(
p_user_id uuid, p_notification_type text
)
RETURNS TABLE(event_type text, in_app boolean, email boolean,
    email_address text, locale text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_delivery_plan_v3(p_user_id,
    p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v4(uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.notification_unsubscribe_v4(
p_user_id uuid, p_scope text, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, scope text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unsubscribe_v3(p_user_id, p_scope, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unsubscribe_v4(uuid, text,
    timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_record_v4(
p_report jsonb, p_event jsonb, p_event_outbox_id text, p_report_audit jsonb,
p_audits jsonb
)
RETURNS TABLE(report_id uuid, flagged boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_record_v3(p_report, p_event,
    p_event_outbox_id, p_report_audit, p_audits);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v4(jsonb, jsonb,
    text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_list_inbox_v6(
p_recipient_user_id uuid, p_filter_sources boolean, p_member boolean,
p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[],
p_space_ids uuid[], p_after_created_at timestamptz,
p_after_notification_id uuid, p_row_limit integer
)
RETURNS TABLE (
    recipient_user_id uuid, notification_id uuid, created_at timestamptz,
    read_at timestamptz, rank_score numeric, source_type text, source_id uuid,
    notification_type text, payload jsonb, source_thread_id uuid, source_thread_title text
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_list_inbox_v5(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids, p_after_created_at, p_after_notification_id,
    p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_list_inbox_v6(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.notification_unread_count_v6(
p_recipient_user_id uuid, p_filter_sources boolean, p_member boolean,
p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[],
p_space_ids uuid[]
)
RETURNS TABLE (unread_count bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unread_count_v5(p_recipient_user_id,
    p_filter_sources, p_member, p_global_read, p_viewer_user_id,
    p_category_ids, p_space_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unread_count_v6(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[]) FROM PUBLIC;

COMMIT;
