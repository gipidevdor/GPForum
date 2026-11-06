-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: api moderation.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

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
REVOKE EXECUTE ON FUNCTION api.moderation_action_list_v1(p_target_type text, p_target_id uuid, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v3(p_report jsonb, p_event jsonb, p_event_outbox_id text, p_report_audit jsonb, p_audits jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v1(p_user_id uuid) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_automod_settings_set_v1(p_link_limit integer, p_link_trust_below integer, p_link_action text, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_add_v1(p_note_id uuid, p_subject_user_id uuid, p_author_user_id uuid, p_body text, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_delete_v1(p_note_id uuid, p_subject_user_id uuid, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_edit_v1(p_note_id uuid, p_subject_user_id uuid, p_editor_user_id uuid, p_body text, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_for_reports_v1(p_report_ids uuid[], p_per_member integer) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_v1(p_subject_user_id uuid, p_row_limit integer) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_reported_message_v1(p_report_id uuid, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_review_decide_v1(p_review_id uuid, p_status text, p_actor_user_id uuid, p_reason text, p_post_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_review_mine_v3(p_user_id uuid, p_row_limit integer, p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[]) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_review_queue_v1(p_row_limit integer) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_review_settings_set_v1(p_first_posts integer, p_flagged boolean, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_list_v1(p_user_id uuid, p_active_only boolean, p_now timestamp with time zone, p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_add_v1(p_word_id uuid, p_phrase text, p_action text, p_replacement text, p_actor_user_id uuid, p_now timestamp with time zone, p_audit jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_remove_v1(p_word_id uuid, p_audit jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_active_suspension_v3(p_user_id uuid, p_now timestamptz)
RETURNS TABLE (suspension_id uuid, user_id uuid, actor_user_id uuid, reason text,
    valid_from timestamptz, valid_to timestamptz, revoked_at timestamptz,
    metadata jsonb)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.suspension_id, s.user_id, s.actor_user_id, s.reason,
    s.valid_from, s.valid_to, s.revoked_at, s.metadata
FROM public.suspensions s
WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
    AND (s.valid_to IS NULL OR s.valid_to >= p_now)
ORDER BY s.valid_from DESC, s.suspension_id DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_active_suspension_v3(p_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.moderation_can_participate_v3(p_user_id uuid, p_now timestamptz)
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
            FROM api.moderation_active_suspension_v3(p_user_id, p_now) s;
        IF FOUND THEN
            RETURN QUERY SELECT 0, 'suspended'::text, v_suspension;
        ELSE
            RETURN QUERY SELECT 1, NULL::text, NULL::uuid;
        END IF;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_can_participate_v3(p_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfers_v1(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('status','ok','transfers',coalesce((SELECT jsonb_agg(x) FROM (
        SELECT t.transfer_id,t.source_id,t.target_id,t.operation,t.created_at,t.undone_at,cardinality(t.post_ids) AS post_count
        FROM public.thread_transfers t ORDER BY t.created_at DESC,t.transfer_id DESC LIMIT 100) x),'[]'::jsonb));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfers_v1(p_actor uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_hold_v3(
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
    p_audit jsonb,
    p_tags text
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
        status, created_at, tags)
        VALUES (p_review_id, p_author_user_id, p_command_id, p_kind,
            CASE WHEN p_kind = 'thread' THEN p_category_id END,
            CASE WHEN p_kind = 'reply' THEN p_thread_id END,
            coalesce(p_title, ''), p_body_source, p_body_rendered_safe,
            p_visibility,
            CASE WHEN p_kind = 'reply' THEN p_reply_to_post_id END,
            p_reason, coalesce(p_details, '{}'::jsonb), 'pending', p_now,
            CASE WHEN p_kind = 'thread' THEN coalesce(p_tags, '') ELSE '' END)
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
REVOKE EXECUTE ON FUNCTION api.moderation_review_hold_v3(p_review_id uuid, p_author_user_id uuid, p_command_id text, p_kind text, p_category_id uuid, p_thread_id uuid, p_title text, p_body_source text, p_body_rendered_safe text, p_visibility text, p_reply_to_post_id uuid, p_reason text, p_details jsonb, p_draft_id uuid, p_draft_revision bigint, p_now timestamp with time zone, p_audit jsonb, p_tags text) FROM PUBLIC;

CREATE FUNCTION api.moderation_review_take_v3(p_review_id uuid)
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
    post_id uuid,
    tags text
)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT h.review_id, h.author_user_id, h.command_id, h.kind, h.category_id,
    h.thread_id, h.title, h.body_source, h.visibility, h.reply_to_post_id,
    h.reason, h.status, h.post_id, h.tags
FROM public.held_posts h
WHERE h.review_id = p_review_id
FOR UPDATE;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_review_take_v3(p_review_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_update_v3(
    p_action_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.moderation_action_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
UPDATE public.moderation_actions a SET
  reversed_at = (p_changes->>'reversed_at')::timestamptz,
  reversed_by_user_id = (p_changes->>'reversed_by_user_id')::uuid
WHERE a.moderation_action_id = p_action_id AND a.reversed_at IS NULL
RETURNING a.moderation_action_id, a.actor_user_id, a.action_type,
    a.target_type, a.target_id, a.reason, a.metadata, a.created_at,
    a.reversed_at, a.reversed_by_user_id, a.command_id;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_update_v3(p_action_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_update_v5(
    p_kind text,
    p_target_id uuid,
    p_changes jsonb
)
RETURNS TABLE (changed_count bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE changed bigint;
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
        GET DIAGNOSTICS changed = ROW_COUNT;
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
        GET DIAGNOSTICS changed = ROW_COUNT;
    ELSE
        RAISE EXCEPTION 'unknown moderation target kind';
    END IF;
    RETURN QUERY SELECT changed;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_target_update_v5(p_kind text, p_target_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_find_v3(
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
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.moderation_action_find_v3(p_action_id uuid, p_command_id uuid, p_action_type text, p_target_type text, p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_action_insert_v3(p_values jsonb)
RETURNS SETOF api.moderation_action_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.moderation_actions (moderation_action_id, actor_user_id, action_type, target_type, target_id, reason, metadata, created_at, reversed_at, reversed_by_user_id, command_id)
    SELECT r.moderation_action_id, r.actor_user_id, r.action_type, r.target_type, r.target_id, r.reason, r.metadata, r.created_at, r.reversed_at, r.reversed_by_user_id, r.command_id FROM jsonb_populate_record(NULL::public.moderation_actions, p_values) r RETURNING
        moderation_action_id, actor_user_id, action_type, target_type,
        target_id, reason, metadata, created_at, reversed_at,
        reversed_by_user_id, command_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_action_insert_v3(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_find_v3(
    p_report_id uuid,
    p_reporter_user_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_hold boolean
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.moderation_report_find_v3(p_report_id uuid, p_reporter_user_id uuid, p_target_type text, p_target_id uuid, p_hold boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_insert_v3(p_values jsonb)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.reports (report_id, reporter_user_id, target_type, target_id, reason, details, status, assigned_moderator_user_id, created_at, resolved_at, resolution)
    SELECT r.report_id, r.reporter_user_id, r.target_type, r.target_id, r.reason, r.details, r.status, r.assigned_moderator_user_id, r.created_at, r.resolved_at, r.resolution FROM jsonb_populate_record(NULL::public.reports, p_values) r RETURNING
        report_id, reporter_user_id, target_type, target_id, reason, details,
        status, assigned_moderator_user_id, created_at, resolved_at,
        resolution;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_insert_v3(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_queue_v3(
    p_status text,
    p_row_limit integer
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY SELECT r.report_id, r.reporter_user_id, r.target_type,
        r.target_id, r.reason, r.details, r.status,
        r.assigned_moderator_user_id, r.created_at, r.resolved_at,
        r.resolution FROM public.reports r WHERE r.status = p_status
    ORDER BY r.created_at ASC, r.report_id ASC LIMIT p_row_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_report_queue_v3(p_status text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.moderation_report_update_v3(
    p_report_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.moderation_report_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.moderation_report_update_v3(p_report_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_find_v3(p_suspension_id uuid)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY SELECT s.suspension_id, s.user_id, s.actor_user_id, s.reason,
        s.valid_from, s.valid_to, s.revoked_at, s.metadata
    FROM public.suspensions s WHERE s.suspension_id = p_suspension_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_find_v3(p_suspension_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_update_v3(
    p_suspension_id uuid,
    p_revoked_at timestamptz
)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.suspensions s SET revoked_at = p_revoked_at WHERE s.suspension_id = p_suspension_id RETURNING
        s.suspension_id, s.user_id, s.actor_user_id, s.reason, s.valid_from,
        s.valid_to, s.revoked_at, s.metadata;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_update_v3(p_suspension_id uuid, p_revoked_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.moderation_target_v5(
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
SET plan_cache_mode = force_generic_plan
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
REVOKE EXECUTE ON FUNCTION api.moderation_target_v5(p_kind text, p_target_id uuid, p_hold boolean) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_v5(p_actor uuid, p_command uuid, p_source_id uuid, p_target_id uuid, p_operation text, p_post_numbers bigint[], p_title text, p_reason text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; source public.threads; target public.threads; destination uuid := p_target_id;
    selected uuid[]; positions bigint[]; new_positions bigint[]; links jsonb; base bigint; first_author uuid; answer jsonb;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    IF p_source_id IS NULL OR p_operation IS NULL OR p_operation NOT IN ('move','split','merge')
        OR coalesce(length(btrim(p_reason)),0) NOT BETWEEN 1 AND 500
        OR (p_operation <> 'split' AND (p_target_id IS NULL OR p_target_id = p_source_id))
        OR (p_operation = 'split' AND (p_target_id IS NOT NULL OR coalesce(length(btrim(p_title)),0) NOT BETWEEN 1 AND 200)) THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'moderation.thread_transfer',
        jsonb_build_object('source',p_source_id,'target',p_target_id,'operation',p_operation,'posts',p_post_numbers,'title',p_title,'reason',p_reason));
    IF opened.outcome <> 'opened' THEN RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN; END IF;
    -- The reply allocator takes this same row; two-thread commands always lock
    -- UUID order, before touching posts or counters.
    PERFORM 1 FROM public.threads t WHERE t.thread_id IN (p_source_id,p_target_id) ORDER BY t.thread_id FOR UPDATE;
    SELECT * INTO source FROM public.threads t WHERE t.thread_id = p_source_id;
    SELECT * INTO target FROM public.threads t WHERE t.thread_id = p_target_id;
    IF source.thread_id IS NULL OR source.deleted_at IS NOT NULL OR source.moderation_state <> 'visible'
        OR source.visibility NOT IN ('public','members') OR source.locked_at IS NOT NULL
        OR NOT api.core_product_read_thread_v1(p_actor,p_source_id)
        OR (p_operation <> 'split' AND (target.thread_id IS NULL OR target.deleted_at IS NOT NULL
            OR target.moderation_state <> 'visible' OR target.locked_at IS NOT NULL
            OR target.category_id <> source.category_id OR target.visibility <> source.visibility
            OR NOT api.core_product_read_thread_v1(p_actor,p_target_id)))
        OR EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id IN(p_source_id,p_target_id)) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    IF p_operation <> 'merge' AND (coalesce(cardinality(p_post_numbers),0) NOT BETWEEN 1 AND 1000
        OR cardinality(p_post_numbers) <> (SELECT count(DISTINCT x) FROM unnest(p_post_numbers) x)) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
    END IF;
    SELECT array_agg(x.post_id ORDER BY x.position),array_agg(x.position ORDER BY x.position)
        INTO selected,positions FROM (SELECT p.post_id,p.position FROM public.posts p WHERE p.thread_id = p_source_id
        AND (p_operation = 'merge' OR p.position = ANY(p_post_numbers)) ORDER BY p.position LIMIT 1001) x;
    IF coalesce(cardinality(selected),0) NOT BETWEEN 1 AND 1000
        OR (p_operation <> 'merge' AND (cardinality(selected) <> cardinality(p_post_numbers) OR 1 = ANY(positions))) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
    END IF;
    IF EXISTS(SELECT 1 FROM public.posts p WHERE p.post_id = ANY(selected) AND p.visibility = 'private') THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    IF p_operation = 'split' THEN
        destination := api.core_uuid_v7_v1();
        SELECT p.author_user_id INTO first_author FROM public.posts p WHERE p.post_id = selected[1];
        INSERT INTO public.threads(thread_id,category_id,author_user_id,title,slug,visibility)
        VALUES(destination,source.category_id,first_author,btrim(p_title),'discussion-' || destination::text,source.visibility);
    END IF;
    SELECT coalesce(max(p.position),0) INTO base FROM public.posts p WHERE p.thread_id = destination;
    SELECT array_agg(base+x.n ORDER BY x.n) INTO new_positions FROM generate_series(1,cardinality(selected)) x(n);
    WITH map AS (SELECT x.id,x.position FROM unnest(selected,new_positions) x(id,position))
    UPDATE public.posts p SET thread_id = destination,position = map.position,version = p.version+1,
        visibility_version = p.visibility_version+1,permission_version = p.permission_version+1,updated_at = clock_timestamp()
    FROM map WHERE p.post_id = map.id;
    -- Preserve the links that stop being meaningful in one thread, for undo.
    WITH removed AS (DELETE FROM public.post_replies r USING public.posts child,public.posts parent
        WHERE child.post_id = r.post_id AND parent.post_id = r.reply_to_post_id AND child.thread_id <> parent.thread_id
            AND (r.post_id = ANY(selected) OR r.reply_to_post_id = ANY(selected)) RETURNING r.*)
    SELECT coalesce(jsonb_agg(to_jsonb(removed)),'[]'::jsonb) INTO links FROM removed;
    IF p_operation = 'merge' THEN
        UPDATE public.threads SET deleted_at = clock_timestamp(),deleted_by = p_actor,moderation_state = 'deleted',
            visibility_version = visibility_version+1,permission_version = permission_version+1 WHERE thread_id = p_source_id;
    END IF;
    INSERT INTO public.thread_transfers(transfer_id,actor_id,source_id,target_id,operation,post_ids,original_positions,new_positions,reply_links,reason)
    VALUES(p_command,p_actor,p_source_id,destination,p_operation,selected,positions,new_positions,links,btrim(p_reason));
    PERFORM api.core_product_thread_recount_v3(p_source_id);
    PERFORM api.core_product_thread_recount_v3(destination);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,p_source_id);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,destination);
    PERFORM api.core_product_audit_v1(p_actor,p_command,'moderation.thread_transfer',p_source_id,'thread',
        jsonb_build_object('target',destination,'operation',p_operation,'count',cardinality(selected),'transfer',p_command));
    answer := jsonb_build_object('status','ok','target_id',destination,'transfer_id',p_command,'count',cardinality(selected));
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_v5(p_actor uuid, p_command uuid, p_source_id uuid, p_target_id uuid, p_operation text, p_post_numbers bigint[], p_title text, p_reason text) FROM PUBLIC;

CREATE FUNCTION api.moderation_thread_transfer_undo_v5(p_actor uuid, p_command uuid, p_transfer_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; held public.thread_transfers; answer jsonb;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'moderation.thread_transfer_undo',jsonb_build_object('transfer',p_transfer_id));
    IF opened.outcome <> 'opened' THEN RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN; END IF;
    SELECT * INTO held FROM public.thread_transfers x WHERE x.transfer_id = p_transfer_id;
    IF held.transfer_id IS NULL THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','not_found')); RETURN;
    END IF;
    PERFORM 1 FROM public.threads t WHERE t.thread_id IN(held.source_id,held.target_id) ORDER BY t.thread_id FOR UPDATE;
    SELECT * INTO held FROM public.thread_transfers x WHERE x.transfer_id = p_transfer_id FOR UPDATE;
    IF held.undone_at IS NOT NULL THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','ok','target_id',held.source_id)); RETURN;
    END IF;
    IF (SELECT count(DISTINCT (t.category_id,t.visibility)) FROM public.threads t WHERE t.thread_id IN(held.source_id,held.target_id)) <> 1
        OR (held.operation = 'split' AND EXISTS(SELECT 1 FROM public.posts p WHERE p.thread_id = held.target_id AND NOT(p.post_id = ANY(held.post_ids))))
        OR EXISTS(SELECT 1 FROM public.posts p WHERE p.post_id = ANY(held.post_ids) AND p.visibility = 'private')
        OR EXISTS(SELECT 1 FROM public.threads t WHERE t.thread_id IN(held.source_id,held.target_id)
            AND (t.visibility NOT IN('public','members') OR (t.deleted_at IS NOT NULL AND NOT(t.thread_id = held.source_id AND held.operation = 'merge'))))
        OR (SELECT count(*) FROM public.posts p JOIN unnest(held.post_ids,held.new_positions) x(id,position)
            ON p.post_id = x.id AND p.position = x.position WHERE p.thread_id = held.target_id) <> cardinality(held.post_ids)
        OR EXISTS(SELECT 1 FROM public.posts p WHERE p.thread_id = held.source_id AND p.position = ANY(held.original_positions))
        OR EXISTS(SELECT 1 FROM public.post_replies r WHERE r.reply_to_post_id = ANY(held.post_ids) AND NOT(r.post_id = ANY(held.post_ids)))
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(held.reply_links) x
            LEFT JOIN public.posts child ON child.post_id = (x->>'post_id')::uuid
            LEFT JOIN public.posts parent ON parent.post_id = (x->>'reply_to_post_id')::uuid
            WHERE child.post_id IS NULL OR parent.post_id IS NULL
                OR (CASE WHEN child.post_id = ANY(held.post_ids) THEN held.source_id ELSE child.thread_id END)
                    <> (CASE WHEN parent.post_id = ANY(held.post_ids) THEN held.source_id ELSE parent.thread_id END)
                OR EXISTS(SELECT 1 FROM public.post_replies r WHERE r.post_id = child.post_id AND r.reply_to_post_id <> parent.post_id))
        OR EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id IN(held.source_id,held.target_id)) THEN
        RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    UPDATE public.posts p SET thread_id = held.source_id,position = x.position,version = p.version+1,
        visibility_version = p.visibility_version+1,permission_version = p.permission_version+1
    FROM unnest(held.post_ids,held.original_positions) x(id,position) WHERE p.post_id = x.id;
    INSERT INTO public.post_replies(post_id,reply_to_post_id,created_at)
    SELECT (x->>'post_id')::uuid,(x->>'reply_to_post_id')::uuid,(x->>'created_at')::timestamptz
        FROM jsonb_array_elements(held.reply_links) x ON CONFLICT(post_id) DO NOTHING;
    IF held.operation = 'merge' THEN
        UPDATE public.threads SET deleted_at = NULL,deleted_by = NULL,moderation_state = 'visible',
            visibility_version = visibility_version+1,permission_version = permission_version+1 WHERE thread_id = held.source_id;
    ELSIF held.operation = 'split' AND NOT EXISTS(SELECT 1 FROM public.posts p WHERE p.thread_id = held.target_id) THEN
        UPDATE public.threads SET deleted_at = clock_timestamp(),deleted_by = p_actor,moderation_state = 'deleted' WHERE thread_id = held.target_id;
    END IF;
    UPDATE public.thread_transfers SET undone_at = clock_timestamp() WHERE transfer_id = p_transfer_id;
    PERFORM api.core_product_thread_recount_v3(held.source_id);
    PERFORM api.core_product_thread_recount_v3(held.target_id);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,held.source_id);
    PERFORM api.core_product_thread_event_v1(p_actor,p_command,held.target_id);
    PERFORM api.core_product_audit_v1(p_actor,p_command,'moderation.thread_transfer_undo',held.source_id,'thread',jsonb_build_object('transfer',p_transfer_id));
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','ok','target_id',held.source_id));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_thread_transfer_undo_v5(p_actor uuid, p_command uuid, p_transfer_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_lock_member_v1(p_user_id uuid)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id FROM public.users u WHERE u.id = p_user_id FOR NO KEY UPDATE;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_lock_member_v1(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_insert_v5(p_values jsonb)
RETURNS SETOF api.moderation_suspension_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE stored api.moderation_suspension_v1;
BEGIN
    INSERT INTO public.suspensions (suspension_id, user_id, actor_user_id, reason, valid_from, valid_to, revoked_at, metadata)
    SELECT r.suspension_id, r.user_id, r.actor_user_id, r.reason, r.valid_from, r.valid_to, r.revoked_at, r.metadata FROM jsonb_populate_record(NULL::public.suspensions, p_values) r RETURNING
        suspension_id, user_id, actor_user_id, reason, valid_from, valid_to,
        revoked_at, metadata
    INTO stored;
    PERFORM api.core_moderation_queue_suspension_end_v1(stored.suspension_id);
    RETURN NEXT stored;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_insert_v5(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_queue_suspension_ends_v1(
    p_now timestamptz,
    p_row_limit integer
)
RETURNS TABLE (queued bigint)
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(sum(api.core_moderation_queue_suspension_end_v1(due.suspension_id)), 0)::bigint
FROM (
    SELECT s.suspension_id FROM public.suspensions s
    JOIN public.users u ON u.id = s.user_id
    WHERE s.revoked_at IS NULL AND s.valid_to IS NOT NULL
        AND u.status = 'suspended'
        AND NOT EXISTS (SELECT 1 FROM public.outbox_messages o
            WHERE o.idempotency_key = 'suspension-end:' || s.suspension_id)
        AND (s.valid_to >= p_now OR NOT EXISTS (
            SELECT 1 FROM public.suspensions other
            WHERE other.user_id = s.user_id AND other.revoked_at IS NULL
                AND other.valid_from <= p_now
                AND (other.valid_to IS NULL OR other.valid_to >= p_now)))
    ORDER BY s.valid_to, s.suspension_id
    LIMIT p_row_limit
) due;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_queue_suspension_ends_v1(p_now timestamp with time zone, p_row_limit integer) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v3(p_user_id uuid) FROM PUBLIC;

COMMIT;
