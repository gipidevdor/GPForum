-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Reports, staff actions, suspensions, automod, the review queue and staff
-- notes.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A moderation action by id, by command, or the latest of a kind on a target.
CREATE FUNCTION api.moderation_action_find_v1(
    p_action_id uuid,
    p_command_id uuid,
    p_action_type text,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_action_id IS NOT NULL THEN
        RETURN QUERY SELECT a.moderation_action_id, a.actor_user_id,
            a.action_type, a.target_type, a.target_id, a.reason, a.metadata,
            a.created_at, a.reversed_at, a.reversed_by_user_id, a.command_id
        FROM public.moderation_actions a WHERE a.moderation_action_id = p_action_id;
    ELSIF p_command_id IS NOT NULL THEN
        RETURN QUERY SELECT a.moderation_action_id, a.actor_user_id,
            a.action_type, a.target_type, a.target_id, a.reason, a.metadata,
            a.created_at, a.reversed_at, a.reversed_by_user_id, a.command_id
        FROM public.moderation_actions a WHERE a.command_id = p_command_id LIMIT 1;
    ELSE
        RETURN QUERY SELECT a.moderation_action_id, a.actor_user_id,
            a.action_type, a.target_type, a.target_id, a.reason, a.metadata,
            a.created_at, a.reversed_at, a.reversed_by_user_id, a.command_id
        FROM public.moderation_actions a WHERE a.action_type = p_action_type
        AND a.target_type = p_target_type AND a.target_id = p_target_id AND a.reversed_at IS NULL
        ORDER BY a.created_at DESC LIMIT 1;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_find_v1(uuid, uuid, text, text, uuid)
    FROM PUBLIC;

-- Stores a moderation action and answers it.
CREATE FUNCTION api.moderation_action_insert_v1(p_values jsonb)
RETURNS SETOF api.moderation_action_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.moderation_actions (moderation_action_id, actor_user_id, action_type, target_type, target_id, reason, metadata, created_at, reversed_at, reversed_by_user_id, command_id)
    SELECT r.moderation_action_id, r.actor_user_id, r.action_type, r.target_type, r.target_id, r.reason, r.metadata, r.created_at, r.reversed_at, r.reversed_by_user_id, r.command_id FROM jsonb_populate_record(NULL::public.moderation_actions, p_values) r RETURNING
        moderation_action_id, actor_user_id, action_type, target_type,
        target_id, reason, metadata, created_at, reversed_at,
        reversed_by_user_id, command_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_insert_v1(jsonb) FROM PUBLIC;

-- A page of the actions on a target, newest first after the cursor.
CREATE FUNCTION api.moderation_action_list_v1(
    p_target_type text,
    p_target_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_after_at IS NULL THEN
        RETURN QUERY SELECT a.moderation_action_id, a.actor_user_id,
            a.action_type, a.target_type, a.target_id, a.reason, a.metadata,
            a.created_at, a.reversed_at, a.reversed_by_user_id, a.command_id
        FROM public.moderation_actions a WHERE (p_target_type IS NULL OR a.target_type = p_target_type) AND (p_target_id IS NULL OR a.target_id = p_target_id)
        ORDER BY a.created_at DESC, a.moderation_action_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.moderation_action_id, a.actor_user_id,
            a.action_type, a.target_type, a.target_id, a.reason, a.metadata,
            a.created_at, a.reversed_at, a.reversed_by_user_id, a.command_id
        FROM public.moderation_actions a WHERE (p_target_type IS NULL OR a.target_type = p_target_type) AND (p_target_id IS NULL OR a.target_id = p_target_id)
        AND (a.created_at, a.moderation_action_id) < (p_after_at, p_after_id)
        ORDER BY a.created_at DESC, a.moderation_action_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_list_v1(text, uuid, timestamptz, uuid, integer)
    FROM PUBLIC;

-- Records the reversal of a moderation action and answers it.
CREATE FUNCTION api.moderation_action_update_v1(
    p_action_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.moderation_actions a SET
      reversed_at = (p_changes->>'reversed_at')::timestamptz,
      reversed_by_user_id = (p_changes->>'reversed_by_user_id')::uuid
    WHERE a.moderation_action_id = p_action_id RETURNING
        a.moderation_action_id, a.actor_user_id, a.action_type, a.target_type,
        a.target_id, a.reason, a.metadata, a.created_at, a.reversed_at,
        a.reversed_by_user_id, a.command_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_update_v1(uuid, jsonb)
    FROM PUBLIC;

-- A member's suspension in force at p_now, if any.
CREATE FUNCTION api.moderation_active_suspension_v1(
    p_user_id uuid,
    p_now text
)
RETURNS TABLE (
    suspension_id uuid,
    user_id uuid,
    actor_user_id uuid,
    reason text,
    valid_from timestamptz,
    valid_to timestamptz,
    revoked_at timestamptz,
    metadata jsonb
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT recent.* FROM (
    SELECT s.* FROM public.suspensions s
        WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
        ORDER BY s.valid_from DESC, s.suspension_id DESC LIMIT 10
) recent
-- The original policy compares the timestamp's text with the supplied
-- clock and examines only these ten rows. Preserve both during migration.
WHERE recent.valid_to IS NULL OR recent.valid_to::text >= p_now
ORDER BY recent.valid_from DESC, recent.suspension_id DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v1(uuid, text)
    FROM PUBLIC;

-- ADR 0133 screens a message as it screens a reply: a flag opens a system
-- report on the message.
CREATE FUNCTION api.moderation_automod_record_v3(
    p_report jsonb,
    p_event jsonb,
    p_event_outbox_id text,
    p_report_audit jsonb,
    p_audits jsonb
)
RETURNS TABLE (report_id uuid, flagged boolean)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v3(jsonb, jsonb, text, jsonb, jsonb)
    FROM PUBLIC;

-- The rules a write is screened by, in one call: the watched words, the
-- link rule and the author's trust level (NULL for an unknown author).
CREATE FUNCTION api.moderation_automod_rules_v1(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT json_build_object(
    'words', coalesce((SELECT json_agg(json_build_object(
            'word_id', w.word_id, 'phrase', w.phrase, 'action', w.action,
            'replacement', w.replacement) ORDER BY w.phrase, w.word_id)
        FROM public.watched_words w), '[]'::json),
    'link_limit', s.link_limit,
    'link_trust_below', coalesce(s.link_trust_below, 1),
    'link_action', coalesce(s.link_action, 'block'),
    'updated_at', s.updated_at,
    'trust_level', (SELECT u.trust_level FROM public.users u
        WHERE u.id = p_user_id))
FROM (SELECT true AS singleton) one
LEFT JOIN public.automod_settings s ON s.singleton = one.singleton;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v1(uuid) FROM PUBLIC;

-- The rules a write is screened by, now with the review rule and, while
-- that rule is on, how many of the author's posts are published and not
-- hidden or deleted (counted up to 20, the rule's largest number).
CREATE FUNCTION api.moderation_automod_rules_v3(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'review_first_posts', coalesce(s.review_first_posts, 0),
    'review_flagged', coalesce(s.review_flagged, false),
    'published_posts', CASE WHEN coalesce(s.review_first_posts, 0) > 0
        AND p_user_id IS NOT NULL THEN (SELECT count(*) FROM (
            SELECT 1 FROM public.posts p
            WHERE p.author_user_id = p_user_id AND p.deleted_at IS NULL
                AND p.moderation_state IN ('visible', 'locked')
            LIMIT 20) published) END))::json
FROM api.moderation_automod_rules_v1(p_user_id) previous
LEFT JOIN public.automod_settings s ON s.singleton;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v3(uuid) FROM PUBLIC;

-- Sets the link rule: a NULL limit turns it off. The audit carries the
-- rule before and after; setting the rule it already is changes nothing.
CREATE FUNCTION api.moderation_automod_settings_set_v1(
    p_link_limit integer,
    p_link_trust_below integer,
    p_link_action text,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record; before jsonb;
BEGIN
    IF (p_link_limit IS NOT NULL AND p_link_limit NOT BETWEEN 0 AND 100)
        OR p_link_trust_below IS NULL
        OR p_link_trust_below NOT BETWEEN 0 AND 100
        OR p_link_action IS NULL OR p_link_action NOT IN ('block', 'flag')
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026101501, 2);
    SELECT s.link_limit, s.link_trust_below, s.link_action INTO held
        FROM public.automod_settings s WHERE s.singleton;
    IF FOUND THEN
        IF held.link_limit IS NOT DISTINCT FROM p_link_limit
            AND held.link_trust_below = p_link_trust_below
            AND held.link_action = p_link_action THEN
            RETURN QUERY SELECT 'unchanged'::text;
            RETURN;
        END IF;
        before := jsonb_build_object('link_limit', held.link_limit,
            'link_trust_below', held.link_trust_below,
            'link_action', held.link_action);
    ELSE
        before := jsonb_build_object('link_limit', NULL,
            'link_trust_below', 1, 'link_action', 'block');
    END IF;
    INSERT INTO public.automod_settings (singleton, link_limit,
        link_trust_below, link_action, updated_by_user_id, updated_at)
        VALUES (true, p_link_limit, p_link_trust_below, p_link_action,
            p_actor_user_id, p_now)
        ON CONFLICT (singleton) DO UPDATE SET
            link_limit = EXCLUDED.link_limit,
            link_trust_below = EXCLUDED.link_trust_below,
            link_action = EXCLUDED.link_action,
            updated_by_user_id = EXCLUDED.updated_by_user_id,
            updated_at = EXCLUDED.updated_at;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object('metadata',
        coalesce(p_audit -> 'metadata', '{}'::jsonb)
        || jsonb_build_object('before', before)), false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_settings_set_v1(integer, integer, text, uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- Whether a member may write: not deleted, not suspended by status or by a
-- suspension in force.
CREATE FUNCTION api.moderation_can_participate_v1(p_user_id uuid, p_now text)
RETURNS TABLE (ok integer, reason text, suspension_id uuid)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_status text;
    v_suspension uuid;
BEGIN
    SELECT u.status INTO v_status FROM public.users u WHERE u.id = p_user_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 0, 'user_not_found'::text, NULL::uuid;
    ELSIF v_status = 'deleted' THEN
        RETURN QUERY SELECT 0, 'user_deleted'::text, NULL::uuid;
    ELSIF v_status = 'suspended' THEN
        RETURN QUERY SELECT 0, 'suspended'::text, NULL::uuid;
    ELSE
        SELECT s.suspension_id INTO v_suspension
            FROM api.moderation_active_suspension_v1(p_user_id, p_now) s;
        IF FOUND THEN
            RETURN QUERY SELECT 0, 'suspended'::text, v_suspension;
        ELSE
            RETURN QUERY SELECT 1, NULL::text, NULL::uuid;
        END IF;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v1(uuid, text)
    FROM PUBLIC;

-- Adds a note about a member who has not been erased. The note id is the
-- form's command id: the same submission again answers replayed, and an
-- id another note holds is a conflict.
CREATE FUNCTION api.moderation_member_note_add_v1(
    p_note_id uuid,
    p_subject_user_id uuid,
    p_author_user_id uuid,
    p_body text,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, note_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE existing record;
BEGIN
    IF p_note_id IS NULL OR p_subject_user_id IS NULL
        OR p_author_user_id IS NULL OR p_body IS NULL
        OR length(p_body) NOT BETWEEN 1 AND 2000
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.users u
        WHERE u.id = p_subject_user_id AND u.status <> 'deleted'
            AND u.deleted_at IS NULL)
    THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    INSERT INTO public.member_notes (note_id, subject_user_id,
        author_user_id, body, created_at)
        VALUES (p_note_id, p_subject_user_id, p_author_user_id, p_body,
            p_now)
        ON CONFLICT ON CONSTRAINT member_notes_pkey DO NOTHING;
    IF NOT FOUND THEN
        SELECT n.subject_user_id, n.author_user_id INTO existing
            FROM public.member_notes n WHERE n.note_id = p_note_id;
        IF existing.subject_user_id = p_subject_user_id
            AND existing.author_user_id = p_author_user_id THEN
            RETURN QUERY SELECT 'replayed'::text, p_note_id;
        ELSE
            RETURN QUERY SELECT 'conflict'::text, NULL::uuid;
        END IF;
        RETURN;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_note_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_add_v1(uuid, uuid, uuid, text, timestamptz, jsonb)
    FROM PUBLIC;

-- Deletes a note about the member named. Nothing of its text is kept.
CREATE FUNCTION api.moderation_member_note_delete_v1(
    p_note_id uuid,
    p_subject_user_id uuid,
    p_audit jsonb
)
RETURNS TABLE (status text, note_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_note_id IS NULL OR p_subject_user_id IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    DELETE FROM public.member_notes n
        WHERE n.note_id = p_note_id AND n.subject_user_id = p_subject_user_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_note_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_delete_v1(uuid, uuid, jsonb)
    FROM PUBLIC;

-- Replaces a note's text, recording who edited it and when. The same text
-- again changes nothing and audits nothing.
CREATE FUNCTION api.moderation_member_note_edit_v1(
    p_note_id uuid,
    p_subject_user_id uuid,
    p_editor_user_id uuid,
    p_body text,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, note_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE current_body text;
BEGIN
    IF p_note_id IS NULL OR p_subject_user_id IS NULL
        OR p_editor_user_id IS NULL OR p_body IS NULL
        OR length(p_body) NOT BETWEEN 1 AND 2000
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT n.body INTO current_body FROM public.member_notes n
        WHERE n.note_id = p_note_id AND n.subject_user_id = p_subject_user_id
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    IF current_body = p_body THEN
        RETURN QUERY SELECT 'unchanged'::text, p_note_id;
        RETURN;
    END IF;
    UPDATE public.member_notes n
        SET body = p_body, updated_at = p_now,
            updated_by_user_id = p_editor_user_id
        WHERE n.note_id = p_note_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_note_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_edit_v1(uuid, uuid, uuid, text, timestamptz, jsonb)
    FROM PUBLIC;

-- Beside each report, the member it is about -- the profile reported, or
-- the author of the post or thread reported -- with their newest notes
-- (at most p_per_member) and how many there are in all. A report whose
-- member is erased or unknown answers no row; a member without notes
-- answers one row with no note.
CREATE FUNCTION api.moderation_member_notes_for_reports_v1(
    p_report_ids uuid[],
    p_per_member integer
)
RETURNS TABLE (
    report_id uuid,
    subject_user_id uuid,
    subject_username text,
    note_total bigint,
    note_id uuid,
    author_username text,
    body text,
    created_at timestamptz,
    updated_at timestamptz,
    updated_by_username text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH subjects AS (
    SELECT r.report_id,
        CASE r.target_type
            WHEN 'user' THEN r.target_id
            WHEN 'post' THEN (SELECT p.author_user_id FROM public.posts p
                WHERE p.post_id = r.target_id)
            WHEN 'thread' THEN (SELECT t.author_user_id FROM public.threads t
                WHERE t.thread_id = r.target_id)
        END AS subject_user_id
    FROM public.reports r
    WHERE r.report_id = ANY (p_report_ids)
)
SELECT s.report_id, s.subject_user_id, u.username,
    (SELECT count(*) FROM public.member_notes c
        WHERE c.subject_user_id = s.subject_user_id),
    n.note_id, a.username, n.body, n.created_at, n.updated_at, e.username
FROM subjects s
JOIN public.users u ON u.id = s.subject_user_id AND u.status <> 'deleted'
LEFT JOIN LATERAL (
    SELECT m.note_id, m.author_user_id, m.body, m.created_at, m.updated_at,
        m.updated_by_user_id
    FROM public.member_notes m
    WHERE m.subject_user_id = s.subject_user_id
    ORDER BY m.created_at DESC, m.note_id DESC
    LIMIT p_per_member
) n ON true
LEFT JOIN public.users a ON a.id = n.author_user_id
LEFT JOIN public.users e ON e.id = n.updated_by_user_id
ORDER BY s.report_id, n.created_at DESC, n.note_id DESC
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_for_reports_v1(uuid[], integer)
    FROM PUBLIC;

-- The notes about a member, newest first, with who wrote and last edited
-- each, and how many there are in all.
CREATE FUNCTION api.moderation_member_notes_v1(
    p_subject_user_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    note_id uuid,
    subject_user_id uuid,
    author_user_id uuid,
    author_username text,
    body text,
    created_at timestamptz,
    updated_at timestamptz,
    updated_by_user_id uuid,
    updated_by_username text,
    note_total bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT n.note_id, n.subject_user_id, n.author_user_id, a.username, n.body,
    n.created_at, n.updated_at, n.updated_by_user_id, e.username,
    count(*) OVER ()
FROM public.member_notes n
LEFT JOIN public.users a ON a.id = n.author_user_id
LEFT JOIN public.users e ON e.id = n.updated_by_user_id
WHERE n.subject_user_id = p_subject_user_id
ORDER BY n.created_at DESC, n.note_id DESC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_v1(uuid, integer)
    FROM PUBLIC;

-- A report by id, or the open one of a reporter on a target, locked FOR UPDATE
-- when p_hold is true.
CREATE FUNCTION api.moderation_report_find_v1(
    p_report_id uuid,
    p_reporter_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_hold boolean
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_report_id IS NOT NULL THEN
        IF p_hold THEN
            RETURN QUERY SELECT r.report_id, r.reporter_user_id,
                r.target_type, r.target_id, r.reason, r.details, r.status,
                r.assigned_moderator_user_id, r.created_at, r.resolved_at,
                r.resolution
            FROM public.reports r WHERE r.report_id = p_report_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT r.report_id, r.reporter_user_id,
                r.target_type, r.target_id, r.reason, r.details, r.status,
                r.assigned_moderator_user_id, r.created_at, r.resolved_at,
                r.resolution
            FROM public.reports r WHERE r.report_id = p_report_id;
        END IF;
    ELSE
        RETURN QUERY SELECT r.report_id, r.reporter_user_id, r.target_type,
            r.target_id, r.reason, r.details, r.status,
            r.assigned_moderator_user_id, r.created_at, r.resolved_at,
            r.resolution
        FROM public.reports r WHERE r.reporter_user_id = p_reporter_user_id
        AND r.target_type = p_target_type AND r.target_id = p_target_id AND r.status IN ('open','triaged')
        ORDER BY r.created_at DESC LIMIT 1;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_find_v1(uuid, uuid, text, uuid, boolean)
    FROM PUBLIC;

-- Stores a report and answers it.
CREATE FUNCTION api.moderation_report_insert_v1(p_values jsonb)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.reports (report_id, reporter_user_id, target_type, target_id, reason, details, status, assigned_moderator_user_id, created_at, resolved_at, resolution)
    SELECT r.report_id, r.reporter_user_id, r.target_type, r.target_id, r.reason, r.details, r.status, r.assigned_moderator_user_id, r.created_at, r.resolved_at, r.resolution FROM jsonb_populate_record(NULL::public.reports, p_values) r RETURNING
        report_id, reporter_user_id, target_type, target_id, reason, details,
        status, assigned_moderator_user_id, created_at, resolved_at,
        resolution;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_insert_v1(jsonb) FROM PUBLIC;

-- The reports of one status, oldest first.
CREATE FUNCTION api.moderation_report_queue_v1(
    p_status text,
    p_row_limit integer
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT r.report_id, r.reporter_user_id, r.target_type,
        r.target_id, r.reason, r.details, r.status,
        r.assigned_moderator_user_id, r.created_at, r.resolved_at,
        r.resolution FROM public.reports r WHERE r.status = p_status
    ORDER BY r.created_at ASC, r.report_id ASC LIMIT p_row_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_queue_v1(text, integer)
    FROM PUBLIC;

-- Writes the given fields of a report (assignment, status, resolution) and
-- answers it.
CREATE FUNCTION api.moderation_report_update_v1(
    p_report_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.reports r SET
      assigned_moderator_user_id = CASE WHEN p_changes ? 'assigned_moderator_user_id' THEN (p_changes->>'assigned_moderator_user_id')::uuid ELSE r.assigned_moderator_user_id END,
      status = CASE WHEN p_changes ? 'status' THEN p_changes->>'status' ELSE r.status END,
      resolved_at = CASE WHEN p_changes ? 'resolved_at' THEN (p_changes->>'resolved_at')::timestamptz ELSE r.resolved_at END,
      resolution = CASE WHEN p_changes ? 'resolution' THEN p_changes->>'resolution' ELSE r.resolution END
    WHERE r.report_id = p_report_id RETURNING r.report_id, r.reporter_user_id,
        r.target_type, r.target_id, r.reason, r.details, r.status,
        r.assigned_moderator_user_id, r.created_at, r.resolved_at,
        r.resolution;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_update_v1(uuid, jsonb)
    FROM PUBLIC;

-- The one way staff read a member's message: the message a report names,
-- with the audit of the reading recorded in the same call. not_found for a
-- report that is not about a message, gone when the message was erased.
CREATE FUNCTION api.moderation_reported_message_v1(
    p_report_id uuid,
    p_audit jsonb
)
RETURNS TABLE (
    status text,
    report_id uuid,
    message_id uuid,
    author_user_id uuid,
    author_username text,
    body text,
    created_at timestamptz
)
LANGUAGE plpgsql
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

-- Decides a held post: approved (with the post it was published as),
-- rejected (with the staff's reason) or withdrawn by its author. Only a
-- pending post is decided; the same decision again is unchanged, another
-- one is refused as decided. A withdrawal by anyone but the author finds
-- nothing.
CREATE FUNCTION api.moderation_review_decide_v1(
    p_review_id uuid,
    p_status text,
    p_actor_user_id uuid,
    p_reason text,
    p_post_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (
    status text,
    review_status text,
    author_user_id uuid,
    kind text,
    thread_id uuid,
    post_id uuid
)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_review_id IS NULL OR p_status IS NULL
        OR p_status NOT IN ('approved', 'rejected', 'withdrawn')
        OR (p_status = 'approved' AND p_post_id IS NULL)
        OR length(coalesce(p_reason, '')) > 500
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::text, NULL::uuid,
            NULL::text, NULL::uuid, NULL::uuid;
        RETURN;
    END IF;
    SELECT h.status, h.author_user_id, h.kind, h.thread_id, h.post_id
        INTO held FROM public.held_posts h
        WHERE h.review_id = p_review_id FOR UPDATE;
    IF NOT FOUND OR (p_status = 'withdrawn'
        AND p_actor_user_id IS DISTINCT FROM held.author_user_id) THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::text, NULL::uuid,
            NULL::text, NULL::uuid, NULL::uuid;
        RETURN;
    END IF;
    IF held.status <> 'pending' THEN
        RETURN QUERY SELECT CASE WHEN held.status = p_status
                THEN 'unchanged' ELSE 'decided' END::text, held.status,
            held.author_user_id, held.kind, held.thread_id, held.post_id;
        RETURN;
    END IF;
    UPDATE public.held_posts h SET status = p_status,
        decided_by_user_id = p_actor_user_id, decided_at = p_now,
        decision_reason = coalesce(p_reason, ''),
        post_id = CASE WHEN p_status = 'approved' THEN p_post_id END
        WHERE h.review_id = p_review_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_status, held.author_user_id, held.kind,
        held.thread_id,
        CASE WHEN p_status = 'approved' THEN p_post_id END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_decide_v1(uuid, text, uuid, text, uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- Holds a post. The author's command id keys it: the same submission again
-- answers the entry it made (replayed, with its status). The draft it was
-- written in, at the revision submitted, is gone with the hold, as it is
-- when a post is published.
CREATE FUNCTION api.moderation_review_hold_v1(
    p_review_id uuid,
    p_author_user_id uuid,
    p_command_id text,
    p_kind text,
    p_category_id uuid,
    p_thread_id uuid,
    p_title text,
    p_body_source text,
    p_body_rendered_safe text,
    p_visibility text,
    p_reply_to_post_id uuid,
    p_reason text,
    p_details jsonb,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, review_id uuid, review_status text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_review_id IS NULL OR p_author_user_id IS NULL
        OR p_command_id IS NULL OR p_kind IS NULL
        OR p_kind NOT IN ('thread', 'reply') OR p_body_source IS NULL
        OR p_body_rendered_safe IS NULL OR p_reason IS NULL
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text;
        RETURN;
    END IF;
    INSERT INTO public.held_posts (review_id, author_user_id, command_id,
        kind, category_id, thread_id, title, body_source,
        body_rendered_safe, visibility, reply_to_post_id, reason, details,
        status, created_at)
        VALUES (p_review_id, p_author_user_id, p_command_id, p_kind,
            CASE WHEN p_kind = 'thread' THEN p_category_id END,
            CASE WHEN p_kind = 'reply' THEN p_thread_id END,
            coalesce(p_title, ''), p_body_source, p_body_rendered_safe,
            p_visibility,
            CASE WHEN p_kind = 'reply' THEN p_reply_to_post_id END,
            p_reason, coalesce(p_details, '{}'::jsonb), 'pending', p_now)
        ON CONFLICT ON CONSTRAINT held_posts_command_key DO NOTHING;
    IF NOT FOUND THEN
        SELECT h.review_id, h.status INTO held FROM public.held_posts h
            WHERE h.author_user_id = p_author_user_id
                AND h.command_id = p_command_id;
        RETURN QUERY SELECT 'replayed'::text, held.review_id, held.status;
        RETURN;
    END IF;
    IF p_draft_id IS NOT NULL THEN
        DELETE FROM public.forum_drafts d WHERE d.draft_id = p_draft_id
            AND d.owner_user_id = p_author_user_id
            AND d.draft_revision = p_draft_revision;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_review_id, 'pending'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_hold_v1(uuid, uuid, text, text, uuid, uuid, text, text, text, text, uuid, text, jsonb, uuid, bigint, timestamptz, jsonb)
    FROM PUBLIC;

-- A member's own held posts, newest first, with the category and thread each
-- is for when the member may still read them.
CREATE FUNCTION api.moderation_review_mine_v3(
    p_user_id uuid,
    p_row_limit integer,
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[]
)
RETURNS TABLE (
    review_id uuid,
    kind text,
    category_id uuid,
    category_title text,
    thread_id uuid,
    thread_title text,
    title text,
    body_rendered_safe text,
    status text,
    decision_reason text,
    post_id uuid,
    created_at timestamptz,
    decided_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.kind,
    CASE WHEN place.category THEN c.category_id END,
    CASE WHEN place.category THEN c.title END,
    CASE WHEN place.thread THEN t.thread_id END,
    CASE WHEN place.thread THEN t.title END,
    h.title, h.body_rendered_safe, h.status, h.decision_reason,
    CASE WHEN place.post THEN h.post_id END,
    h.created_at, h.decided_at
FROM public.held_posts h
LEFT JOIN public.posts p ON p.post_id = h.post_id
LEFT JOIN public.threads t ON t.thread_id = coalesce(h.thread_id, p.thread_id)
LEFT JOIN public.categories c
    ON c.category_id = coalesce(t.category_id, h.category_id)
LEFT JOIN public.spaces sp ON sp.space_id = c.space_id
CROSS JOIN LATERAL (
    SELECT c.category_id IS NOT NULL AND c.deleted_at IS NULL
        AND sp.deleted_at IS NULL
        AND (p_global_read OR sp.visibility = 'public'
            OR (p_member AND sp.visibility = 'members')
            OR (sp.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids))))
        AND (p_global_read OR c.visibility = 'public'
            OR (p_member AND c.visibility = 'members')
            OR (c.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)))) AS category
) area
CROSS JOIN LATERAL (
    SELECT area.category AND t.thread_id IS NOT NULL
        AND t.deleted_at IS NULL
        AND t.moderation_state IN ('visible', 'locked')
        AND (p_global_read OR t.visibility = 'public'
            OR (p_member AND t.visibility = 'members')
            OR (t.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)
                    OR (p_member AND t.author_user_id = p_user_id))))
        AS thread
) way
CROSS JOIN LATERAL (
    SELECT area.category AS category, way.thread AS thread,
        way.thread AND p.post_id IS NOT NULL AND p.deleted_at IS NULL
        AND p.moderation_state = 'visible'
        AND (p_global_read OR p.visibility = 'public'
            OR (p_member AND p.visibility = 'members')
            OR (p.visibility = 'private'
                AND (c.category_id = ANY(p_category_ids)
                    OR c.space_id = ANY(p_space_ids)
                    OR (p_member AND p.author_user_id = p_user_id))))
        AS post
) place
WHERE h.author_user_id = p_user_id
    AND (h.status = 'pending' OR h.decided_at > now() - interval '30 days')
ORDER BY h.created_at DESC, h.review_id DESC
LIMIT least(greatest(coalesce(p_row_limit, 50), 1), 200);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v3(uuid, integer, boolean, boolean, uuid[], uuid[])
    FROM PUBLIC;

-- The queue staff review: the pending posts, oldest first, with where each
-- was written and by whom, and how many are pending in all.
CREATE FUNCTION api.moderation_review_queue_v1(p_row_limit integer)
RETURNS TABLE (
    review_id uuid,
    kind text,
    author_user_id uuid,
    author_username text,
    category_id uuid,
    category_title text,
    thread_id uuid,
    thread_title text,
    title text,
    body_rendered_safe text,
    reason text,
    details jsonb,
    created_at timestamptz,
    pending_total bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.kind, h.author_user_id, u.username,
    coalesce(h.category_id, t.category_id), c.title, h.thread_id, t.title,
    h.title, h.body_rendered_safe, h.reason, h.details, h.created_at,
    (SELECT count(*) FROM public.held_posts p WHERE p.status = 'pending')
FROM public.held_posts h
JOIN public.users u ON u.id = h.author_user_id
LEFT JOIN public.threads t ON t.thread_id = h.thread_id
LEFT JOIN public.categories c
    ON c.category_id = coalesce(h.category_id, t.category_id)
WHERE h.status = 'pending'
ORDER BY h.created_at, h.review_id
LIMIT least(greatest(coalesce(p_row_limit, 50), 1), 200);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_queue_v1(integer) FROM PUBLIC;

-- Sets the review rule. The audit carries the rule before; setting the
-- rule it already is changes nothing.
CREATE FUNCTION api.moderation_review_settings_set_v1(
    p_first_posts integer,
    p_flagged boolean,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record; before jsonb;
BEGIN
    IF p_first_posts IS NULL OR p_first_posts NOT BETWEEN 0 AND 20
        OR p_flagged IS NULL OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026101501, 2);
    SELECT s.review_first_posts, s.review_flagged INTO held
        FROM public.automod_settings s WHERE s.singleton;
    IF FOUND AND held.review_first_posts = p_first_posts
        AND held.review_flagged = p_flagged THEN
        RETURN QUERY SELECT 'unchanged'::text;
        RETURN;
    END IF;
    before := jsonb_build_object(
        'review_first_posts', coalesce(held.review_first_posts, 0),
        'review_flagged', coalesce(held.review_flagged, false));
    INSERT INTO public.automod_settings (singleton, review_first_posts,
        review_flagged, updated_by_user_id, updated_at)
        VALUES (true, p_first_posts, p_flagged, p_actor_user_id, p_now)
        ON CONFLICT (singleton) DO UPDATE SET
            review_first_posts = EXCLUDED.review_first_posts,
            review_flagged = EXCLUDED.review_flagged,
            updated_by_user_id = EXCLUDED.updated_by_user_id,
            updated_at = EXCLUDED.updated_at;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object('metadata',
        coalesce(p_audit -> 'metadata', '{}'::jsonb)
        || jsonb_build_object('before', before)), false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_settings_set_v1(integer, boolean, uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- One held post, locked until the transaction ends: an approval publishes
-- it and records the decision under this lock, so two staff approving at
-- once publish it once.
CREATE FUNCTION api.moderation_review_take_v1(p_review_id uuid)
RETURNS TABLE (
    review_id uuid,
    author_user_id uuid,
    command_id text,
    kind text,
    category_id uuid,
    thread_id uuid,
    title text,
    body_source text,
    visibility text,
    reply_to_post_id uuid,
    reason text,
    status text,
    post_id uuid
)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.author_user_id, h.command_id, h.kind, h.category_id,
    h.thread_id, h.title, h.body_source, h.visibility, h.reply_to_post_id,
    h.reason, h.status, h.post_id
FROM public.held_posts h
WHERE h.review_id = p_review_id
FOR UPDATE;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_take_v1(uuid) FROM PUBLIC;

-- The suspension with this id.
CREATE FUNCTION api.moderation_suspension_find_v1(p_suspension_id uuid)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT s.suspension_id, s.user_id, s.actor_user_id, s.reason,
        s.valid_from, s.valid_to, s.revoked_at, s.metadata
    FROM public.suspensions s WHERE s.suspension_id = p_suspension_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_find_v1(uuid) FROM PUBLIC;

-- Stores a suspension and answers it.
CREATE FUNCTION api.moderation_suspension_insert_v1(p_values jsonb)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.suspensions (suspension_id, user_id, actor_user_id, reason, valid_from, valid_to, revoked_at, metadata)
    SELECT r.suspension_id, r.user_id, r.actor_user_id, r.reason, r.valid_from, r.valid_to, r.revoked_at, r.metadata FROM jsonb_populate_record(NULL::public.suspensions, p_values) r RETURNING
        suspension_id, user_id, actor_user_id, reason, valid_from, valid_to,
        revoked_at, metadata;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_insert_v1(jsonb)
    FROM PUBLIC;

-- A page of a member's suspensions, all or those in force, newest first after
-- the cursor.
CREATE FUNCTION api.moderation_suspension_list_v1(
    p_user_id uuid,
    p_active_only boolean,
    p_now timestamptz,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_after_at IS NULL THEN
        RETURN QUERY SELECT a.suspension_id, a.user_id, a.actor_user_id,
            a.reason, a.valid_from, a.valid_to, a.revoked_at, a.metadata
        FROM public.suspensions a WHERE (p_user_id IS NULL OR a.user_id = p_user_id) AND (NOT p_active_only OR (a.revoked_at IS NULL AND (a.valid_to IS NULL OR a.valid_to >= p_now)))
        ORDER BY a.valid_from DESC, a.suspension_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.suspension_id, a.user_id, a.actor_user_id,
            a.reason, a.valid_from, a.valid_to, a.revoked_at, a.metadata
        FROM public.suspensions a WHERE (p_user_id IS NULL OR a.user_id = p_user_id) AND (NOT p_active_only OR (a.revoked_at IS NULL AND (a.valid_to IS NULL OR a.valid_to >= p_now)))
        AND (a.valid_from, a.suspension_id) < (p_after_at, p_after_id)
        ORDER BY a.valid_from DESC, a.suspension_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_list_v1(uuid, boolean, timestamptz, timestamptz, uuid, integer)
    FROM PUBLIC;

-- Revokes a suspension at p_revoked_at and answers it.
CREATE FUNCTION api.moderation_suspension_update_v1(
    p_suspension_id uuid,
    p_revoked_at timestamptz
)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.suspensions s SET revoked_at = p_revoked_at WHERE s.suspension_id = p_suspension_id RETURNING
        s.suspension_id, s.user_id, s.actor_user_id, s.reason, s.valid_from,
        s.valid_to, s.revoked_at, s.metadata;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_update_v1(uuid, timestamptz)
    FROM PUBLIC;

-- Writes the moderation state of a post or a thread (hidden, locked, pinned).
-- Answers how many rows changed.
CREATE FUNCTION api.moderation_target_update_v3(
    p_kind text,
    p_target_id uuid,
    p_changes jsonb
)
RETURNS TABLE (changed_count bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_kind = 'post' THEN
        UPDATE public.posts p SET
          moderation_state = CASE WHEN p_changes ? 'moderation_state'
              THEN p_changes->>'moderation_state'
              ELSE p.moderation_state END,
          hidden_at = CASE WHEN p_changes ? 'hidden_at'
              THEN (p_changes->>'hidden_at')::timestamptz
              ELSE p.hidden_at END,
          locked_at = CASE WHEN p_changes ? 'locked_at'
              THEN (p_changes->>'locked_at')::timestamptz
              ELSE p.locked_at END
        WHERE p.post_id = p_target_id;
    ELSIF p_kind = 'thread' THEN
        UPDATE public.threads t SET
          moderation_state = CASE WHEN p_changes ? 'moderation_state'
              THEN p_changes->>'moderation_state'
              ELSE t.moderation_state END,
          locked_at = CASE WHEN p_changes ? 'locked_at'
              THEN (p_changes->>'locked_at')::timestamptz
              ELSE t.locked_at END,
          pinned = CASE WHEN p_changes ? 'pinned'
              THEN (p_changes->>'pinned')::boolean
              ELSE t.pinned END
        WHERE t.thread_id = p_target_id;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
    RETURN QUERY SELECT 1::bigint;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v3(text, uuid, jsonb)
    FROM PUBLIC;

-- The moderation state of a post or a thread, locked FOR UPDATE when p_hold is
-- true.
CREATE FUNCTION api.moderation_target_v3(
    p_kind text,
    p_target_id uuid,
    p_hold boolean
)
RETURNS TABLE (
    target_id uuid,
    moderation_state text,
    locked_at timestamptz,
    hidden_at timestamptz,
    pinned boolean
)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_kind = 'post' THEN
        IF p_hold THEN
            RETURN QUERY SELECT p.post_id, p.moderation_state, p.locked_at,
                p.hidden_at, NULL::boolean
                FROM public.posts p WHERE p.post_id = p_target_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT p.post_id, p.moderation_state, p.locked_at,
                p.hidden_at, NULL::boolean
                FROM public.posts p WHERE p.post_id = p_target_id;
        END IF;
    ELSIF p_kind = 'thread' THEN
        IF p_hold THEN
            RETURN QUERY SELECT t.thread_id, t.moderation_state, t.locked_at,
                NULL::timestamptz, t.pinned
                FROM public.threads t WHERE t.thread_id = p_target_id
                FOR UPDATE;
        ELSE
            RETURN QUERY SELECT t.thread_id, t.moderation_state, t.locked_at,
                NULL::timestamptz, t.pinned
                FROM public.threads t WHERE t.thread_id = p_target_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_v3(text, uuid, boolean)
    FROM PUBLIC;

-- Adds a watched word. The list is held while counted, so two staff cannot
-- both take the last place; a phrase already listed is a duplicate.
CREATE FUNCTION api.moderation_watched_word_add_v1(
    p_word_id uuid,
    p_phrase text,
    p_action text,
    p_replacement text,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, word_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_word_id IS NULL OR p_phrase IS NULL
        OR length(p_phrase) NOT BETWEEN 1 AND 100
        OR p_action IS NULL OR p_action NOT IN ('block', 'flag', 'replace')
        OR length(coalesce(p_replacement, '')) > 100
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026101501, 1);
    IF EXISTS (SELECT 1 FROM public.watched_words w
        WHERE w.phrase = p_phrase) THEN
        RETURN QUERY SELECT 'duplicate'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT count(*) INTO amount FROM public.watched_words;
    IF amount >= 500 THEN
        RETURN QUERY SELECT 'limit'::text, NULL::uuid;
        RETURN;
    END IF;
    INSERT INTO public.watched_words (word_id, phrase, action, replacement,
        created_by_user_id, created_at)
        VALUES (p_word_id, p_phrase, p_action, coalesce(p_replacement, ''),
            p_actor_user_id, p_now);
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_word_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_add_v1(uuid, text, text, text, uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- The list as the admin console shows it, in phrase order, with who added
-- each word.
CREATE FUNCTION api.moderation_watched_word_list_v1()
RETURNS TABLE (
    word_id uuid,
    phrase text,
    action text,
    replacement text,
    created_by_user_id uuid,
    created_by_username text,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT w.word_id, w.phrase, w.action, w.replacement, w.created_by_user_id,
    u.username, w.created_at
FROM public.watched_words w
LEFT JOIN public.users u ON u.id = w.created_by_user_id
ORDER BY w.phrase, w.word_id
LIMIT 500;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_list_v1() FROM PUBLIC;

-- Removes a watched word; the audit carries the phrase and action removed.
-- Removing one not listed is no error (removed is 0) and is not audited.
CREATE FUNCTION api.moderation_watched_word_remove_v1(
    p_word_id uuid,
    p_audit jsonb
)
RETURNS TABLE (removed bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE gone record;
BEGIN
    DELETE FROM public.watched_words w WHERE w.word_id = p_word_id
        RETURNING w.phrase, w.action INTO gone;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 0::bigint;
        RETURN;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object('metadata',
        coalesce(p_audit -> 'metadata', '{}'::jsonb)
        || jsonb_build_object('phrase', gone.phrase, 'action', gone.action)),
        false);
    RETURN QUERY SELECT 1::bigint;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_remove_v1(uuid, jsonb)
    FROM PUBLIC;

COMMIT;
