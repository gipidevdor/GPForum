-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0138: private staff notes on members. Staff holding the
-- member_note permissions write, edit and delete notes about a member;
-- they are read on the member's admin page and beside the reports about
-- the member (their profile, their posts, their threads), never by the
-- member, and never through a thread, feed, search document, event,
-- outbox message or realtime message. Every add, edit and delete is
-- audited, without the note's text. The erasure of a member deletes the
-- notes about them; the export leaves notes out (ADR 0074).

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.member_notes (
    note_id uuid NOT NULL,
    subject_user_id uuid NOT NULL,
    author_user_id uuid,
    body text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz,
    updated_by_user_id uuid,
    CONSTRAINT member_notes_pkey PRIMARY KEY (note_id),
    CONSTRAINT member_notes_subject_user_id_fkey FOREIGN KEY (subject_user_id)
        REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT member_notes_author_user_id_fkey FOREIGN KEY (author_user_id)
        REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT member_notes_updated_by_user_id_fkey
        FOREIGN KEY (updated_by_user_id)
        REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT member_notes_body_check CHECK (length(body) BETWEEN 1 AND 2000)
);
CREATE INDEX idx_member_notes_subject
    ON public.member_notes (subject_user_id, created_at DESC, note_id DESC);
CREATE INDEX idx_member_notes_author ON public.member_notes (author_user_id);
CREATE INDEX idx_member_notes_updated_by
    ON public.member_notes (updated_by_user_id);

-- Adds a note about a member who has not been erased. The note id is the
-- form's command id: the same submission again answers replayed, and an
-- id another note holds is a conflict.
CREATE FUNCTION api.moderation_member_note_add_v1(p_note_id uuid,
    p_subject_user_id uuid, p_author_user_id uuid, p_body text,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, note_id uuid)
LANGUAGE plpgsql VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_add_v1(uuid, uuid, uuid,
    text, timestamptz, jsonb) FROM PUBLIC;

-- Replaces a note's text, recording who edited it and when. The same text
-- again changes nothing and audits nothing.
CREATE FUNCTION api.moderation_member_note_edit_v1(p_note_id uuid,
    p_subject_user_id uuid, p_editor_user_id uuid, p_body text,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, note_id uuid)
LANGUAGE plpgsql VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_edit_v1(uuid, uuid, uuid,
    text, timestamptz, jsonb) FROM PUBLIC;

-- Deletes a note about the member named. Nothing of its text is kept.
CREATE FUNCTION api.moderation_member_note_delete_v1(p_note_id uuid,
    p_subject_user_id uuid, p_audit jsonb)
RETURNS TABLE(status text, note_id uuid)
LANGUAGE plpgsql VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_delete_v1(uuid, uuid,
    jsonb) FROM PUBLIC;

-- The notes about a member, newest first, with who wrote and last edited
-- each, and how many there are in all.
CREATE FUNCTION api.moderation_member_notes_v1(p_subject_user_id uuid,
    p_row_limit integer)
RETURNS TABLE(note_id uuid, subject_user_id uuid, author_user_id uuid,
    author_username text, body text, created_at timestamptz,
    updated_at timestamptz, updated_by_user_id uuid,
    updated_by_username text, note_total bigint)
LANGUAGE sql STABLE
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

-- Beside each report, the member it is about -- the profile reported, or
-- the author of the post or thread reported -- with their newest notes
-- (at most p_per_member) and how many there are in all. A report whose
-- member is erased or unknown answers no row; a member without notes
-- answers one row with no note.
CREATE FUNCTION api.moderation_member_notes_for_reports_v1(
    p_report_ids uuid[], p_per_member integer)
RETURNS TABLE(report_id uuid, subject_user_id uuid, subject_username text,
    note_total bigint, note_id uuid, author_username text, body text,
    created_at timestamptz, updated_at timestamptz,
    updated_by_username text)
LANGUAGE sql STABLE
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
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_for_reports_v1(uuid[],
    integer) FROM PUBLIC;

-- An erased member's notes go with them; notes an erased staff member
-- wrote about others stay, under the anonymized account.
CREATE FUNCTION api.privacy_revoke_user_v11(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'MemberNote' THEN
        DELETE FROM public.member_notes n WHERE n.subject_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v9(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v11(text, uuid, text)
    FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.moderation_member_note_add_v2(
p_note_id uuid, p_subject_user_id uuid, p_author_user_id uuid, p_body text,
p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, note_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_note_add_v1(p_note_id, p_subject_user_id,
    p_author_user_id, p_body, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_add_v2(uuid, uuid, uuid,
    text, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_note_edit_v2(
p_note_id uuid, p_subject_user_id uuid, p_editor_user_id uuid, p_body text,
p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, note_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_note_edit_v1(p_note_id,
    p_subject_user_id, p_editor_user_id, p_body, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_edit_v2(uuid, uuid, uuid,
    text, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_note_delete_v2(
p_note_id uuid, p_subject_user_id uuid, p_audit jsonb
)
RETURNS TABLE(status text, note_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_note_delete_v1(p_note_id,
    p_subject_user_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_note_delete_v2(uuid, uuid,
    jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_member_notes_v2(
p_subject_user_id uuid, p_row_limit integer
)
RETURNS TABLE(note_id uuid, subject_user_id uuid, author_user_id uuid,
    author_username text, body text, created_at timestamptz,
    updated_at timestamptz, updated_by_user_id uuid,
    updated_by_username text, note_total bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_notes_v1(p_subject_user_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_v2(uuid, integer)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_member_notes_for_reports_v2(
p_report_ids uuid[], p_per_member integer
)
RETURNS TABLE(report_id uuid, subject_user_id uuid, subject_username text,
    note_total bigint, note_id uuid, author_username text, body text,
    created_at timestamptz, updated_at timestamptz,
    updated_by_username text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_member_notes_for_reports_v1(p_report_ids,
    p_per_member);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_member_notes_for_reports_v2(uuid[],
    integer) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v12(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v11(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v12(text, uuid, text)
    FROM PUBLIC;

COMMIT;
