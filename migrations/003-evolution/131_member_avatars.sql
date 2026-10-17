-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0144: a member's profile picture. The picture is an attachment the
-- member owns, linked to their profile, validated and scanned as every
-- upload is; the media pipeline crops it to a square and keeps it at 64,
-- 128 and 256 pixels as variants avatar_64, avatar_128 and avatar_256.
-- member_avatars says which attachment a member shows and which one is
-- waiting: an upload is offered (checking), then settled (shown, or
-- unreadable when the image tool could not read it); the picture shown
-- stays until the new one is ready. The member removes theirs; staff
-- holding avatar.moderate remove one, audited. Thread pages read the
-- author's picture with the posts (new versions of the two post reads,
-- wrapping the shipped ones); erasure deletes the row and the pictures;
-- the export says what the member shows. New versions, as ADR 0126
-- section 2 asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.member_avatars (
    user_id uuid NOT NULL,
    attachment_id uuid,
    shown_at timestamptz,
    pending_attachment_id uuid,
    pending_state text,
    pending_at timestamptz,
    CONSTRAINT member_avatars_pkey PRIMARY KEY (user_id),
    CONSTRAINT member_avatars_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT member_avatars_attachment_id_fkey FOREIGN KEY (attachment_id)
        REFERENCES public.attachments (attachment_id),
    CONSTRAINT member_avatars_pending_attachment_id_fkey
        FOREIGN KEY (pending_attachment_id)
        REFERENCES public.attachments (attachment_id),
    CONSTRAINT member_avatars_pending_state_check
        CHECK (pending_state IN ('checking', 'unreadable')),
    CONSTRAINT member_avatars_pending_check
        CHECK ((pending_attachment_id IS NULL) = (pending_state IS NULL)),
    CONSTRAINT member_avatars_shown_check
        CHECK ((attachment_id IS NULL) = (shown_at IS NULL))
);
CREATE INDEX idx_member_avatars_attachment
    ON public.member_avatars (attachment_id)
    WHERE attachment_id IS NOT NULL;
CREATE INDEX idx_member_avatars_pending_attachment
    ON public.member_avatars (pending_attachment_id)
    WHERE pending_attachment_id IS NOT NULL;

-- The upload a member offers as their picture: an attachment they own,
-- linked to their profile and not deleted. It waits (checking) while the
-- picture shown, if any, stays; the upload it replaces as the waiting one
-- comes back, for the caller to discard. The same upload again is a
-- replay.
CREATE FUNCTION api.community_avatar_offer_v1(p_user_id uuid,
    p_attachment_id uuid, p_now timestamptz)
RETURNS TABLE(status text, replaced_attachment_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE previous uuid;
BEGIN
    IF p_user_id IS NULL OR p_attachment_id IS NULL OR p_now IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.users u
            WHERE u.id = p_user_id AND u.status <> 'deleted'
                AND u.deleted_at IS NULL)
        OR NOT EXISTS (SELECT 1 FROM public.attachments a
            JOIN public.attachment_links l
                ON l.attachment_id = a.attachment_id
                AND l.target_type = 'profile' AND l.target_id = p_user_id
            WHERE a.attachment_id = p_attachment_id
                AND a.owner_user_id = p_user_id
                AND a.state <> 'deleted' AND a.deleted_at IS NULL)
    THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    INSERT INTO public.member_avatars (user_id) VALUES (p_user_id)
        ON CONFLICT ON CONSTRAINT member_avatars_pkey DO NOTHING;
    SELECT m.pending_attachment_id INTO previous FROM public.member_avatars m
        WHERE m.user_id = p_user_id FOR UPDATE;
    IF previous = p_attachment_id THEN
        RETURN QUERY SELECT 'replayed'::text, NULL::uuid;
        RETURN;
    END IF;
    UPDATE public.member_avatars m
        SET pending_attachment_id = p_attachment_id,
            pending_state = 'checking', pending_at = p_now
        WHERE m.user_id = p_user_id;
    RETURN QUERY SELECT 'ok'::text, previous;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_offer_v1(uuid, uuid,
    timestamptz) FROM PUBLIC;

-- What became of the waiting upload. ready, once its squares are stored
-- and while it is available and clean: it is shown from now on, and the
-- picture it replaces comes back for the caller to discard. unreadable:
-- it stays waiting with that state, so the member is told. An upload that
-- is already the one shown answers shown; one that is neither shown nor
-- waiting, stale.
CREATE FUNCTION api.community_avatar_settle_v1(p_user_id uuid,
    p_attachment_id uuid, p_outcome text, p_now timestamptz)
RETURNS TABLE(status text, replaced_attachment_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_user_id IS NULL OR p_attachment_id IS NULL OR p_now IS NULL
        OR p_outcome IS NULL OR p_outcome NOT IN ('ready', 'unreadable') THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT m.attachment_id, m.pending_attachment_id INTO held
        FROM public.member_avatars m WHERE m.user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'stale'::text, NULL::uuid;
        RETURN;
    END IF;
    IF held.attachment_id = p_attachment_id THEN
        RETURN QUERY SELECT 'shown'::text, NULL::uuid;
        RETURN;
    END IF;
    IF held.pending_attachment_id IS DISTINCT FROM p_attachment_id THEN
        RETURN QUERY SELECT 'stale'::text, NULL::uuid;
        RETURN;
    END IF;
    IF p_outcome = 'unreadable' THEN
        UPDATE public.member_avatars m SET pending_state = 'unreadable'
            WHERE m.user_id = p_user_id;
        RETURN QUERY SELECT 'ok'::text, NULL::uuid;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.attachments a
        WHERE a.attachment_id = p_attachment_id AND a.state = 'available'
            AND a.scan_status = 'clean' AND a.deleted_at IS NULL)
    THEN
        RETURN QUERY SELECT 'stale'::text, NULL::uuid;
        RETURN;
    END IF;
    UPDATE public.member_avatars m
        SET attachment_id = p_attachment_id, shown_at = p_now,
            pending_attachment_id = NULL, pending_state = NULL,
            pending_at = NULL
        WHERE m.user_id = p_user_id;
    RETURN QUERY SELECT 'ok'::text, held.attachment_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_settle_v1(uuid, uuid, text,
    timestamptz) FROM PUBLIC;

-- Takes a member's picture away. Without an attachment id (the member's
-- own removal) the picture shown and the one waiting both go; with one
-- (staff), only that picture, and only while it is the one shown. With an
-- audit row, the removal is audited. One row per upload removed, for the
-- caller to discard; not_found when there was none.
CREATE FUNCTION api.community_avatar_remove_v1(p_user_id uuid,
    p_attachment_id uuid, p_audit jsonb)
RETURNS TABLE(status text, attachment_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE held record;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT m.attachment_id AS shown, m.pending_attachment_id AS pending
        INTO held
        FROM public.member_avatars m WHERE m.user_id = p_user_id FOR UPDATE;
    IF NOT FOUND
        OR (p_attachment_id IS NULL AND held.shown IS NULL
            AND held.pending IS NULL)
        OR (p_attachment_id IS NOT NULL
            AND held.shown IS DISTINCT FROM p_attachment_id)
    THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    IF p_attachment_id IS NULL THEN
        UPDATE public.member_avatars m
            SET attachment_id = NULL, shown_at = NULL,
                pending_attachment_id = NULL, pending_state = NULL,
                pending_at = NULL
            WHERE m.user_id = p_user_id;
    ELSE
        UPDATE public.member_avatars m
            SET attachment_id = NULL, shown_at = NULL
            WHERE m.user_id = p_user_id;
    END IF;
    IF p_audit IS NOT NULL THEN
        PERFORM api.ops_record_audit_v1(p_audit, false);
    END IF;
    RETURN QUERY
        SELECT 'ok'::text, removed.id
        FROM (VALUES (held.shown), (CASE WHEN p_attachment_id IS NULL
            THEN held.pending END)) AS removed(id)
        WHERE removed.id IS NOT NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_remove_v1(uuid, uuid, jsonb)
    FROM PUBLIC;

-- A member's picture as the settings page and the profile read it: the
-- one shown, while its attachment is available and clean, and the one
-- waiting, refused once its scan found it infected or failed it.
CREATE FUNCTION api.community_avatar_status_v1(p_user_id uuid)
RETURNS TABLE(attachment_id uuid, shown_at timestamptz,
    pending_attachment_id uuid, pending_state text, pending_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT shown.attachment_id,
    CASE WHEN shown.attachment_id IS NOT NULL THEN m.shown_at END,
    m.pending_attachment_id,
    CASE WHEN waiting.state = 'quarantined'
            OR waiting.scan_status IN ('infected', 'failed') THEN 'refused'
        ELSE m.pending_state END,
    m.pending_at
FROM public.member_avatars m
LEFT JOIN public.attachments shown
    ON shown.attachment_id = m.attachment_id AND shown.state = 'available'
    AND shown.scan_status = 'clean' AND shown.deleted_at IS NULL
LEFT JOIN public.attachments waiting
    ON waiting.attachment_id = m.pending_attachment_id
WHERE m.user_id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_status_v1(uuid) FROM PUBLIC;

-- The stored square of a member's picture at one size, for the picture's
-- address: only the picture shown, available and clean, of a member who
-- has not been erased.
CREATE FUNCTION api.community_avatar_image_v1(p_user_id uuid,
    p_variant_type text)
RETURNS TABLE(attachment_id uuid, object_key text, media_type text,
    byte_size bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT a.attachment_id, v.object_key, v.media_type, v.byte_size
FROM public.member_avatars m
JOIN public.users u ON u.id = m.user_id AND u.status <> 'deleted'
    AND u.deleted_at IS NULL
JOIN public.attachments a ON a.attachment_id = m.attachment_id
    AND a.state = 'available' AND a.scan_status = 'clean'
    AND a.deleted_at IS NULL
JOIN public.attachment_variants v ON v.attachment_id = a.attachment_id
    AND v.variant_type = p_variant_type
WHERE m.user_id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_image_v1(uuid, text)
    FROM PUBLIC;

-- The stored objects of a member's profile uploads -- the original and
-- every variant -- for the caller to delete: one upload's, or, without an
-- id, every one the member ever linked to their profile (erasure).
-- Deleted uploads are included, so a removal that failed half way is
-- repeated whole.
CREATE FUNCTION api.community_avatar_objects_v1(p_user_id uuid,
    p_attachment_id uuid)
RETURNS TABLE(attachment_id uuid, object_key text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH uploads AS (
    SELECT a.attachment_id, a.object_key
    FROM public.attachments a
    WHERE a.owner_user_id = p_user_id
        AND (p_attachment_id IS NULL OR a.attachment_id = p_attachment_id)
        AND EXISTS (SELECT 1 FROM public.attachment_links l
            WHERE l.attachment_id = a.attachment_id
                AND l.target_type = 'profile' AND l.target_id = p_user_id)
)
SELECT u.attachment_id, v.object_key
FROM uploads u
JOIN public.attachment_variants v ON v.attachment_id = u.attachment_id
UNION ALL
SELECT u.attachment_id, u.object_key FROM uploads u
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_objects_v1(uuid, uuid)
    FROM PUBLIC;

-- The thread page's posts with each author's picture, when they show one:
-- the shipped reads, in their order, and the attachment shown.
CREATE FUNCTION api.forum_thread_page_posts_v3(
    p_thread_id uuid,
    p_standing text,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid, thread_id uuid, author_user_id uuid, current_body_id uuid,
    "position" bigint, visibility text, moderation_state text,
    created_at timestamptz, deleted_at timestamptz, body text,
    body_source text, author_username text, author_display_name text,
    author_avatar_id uuid
)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p.post_id, p.thread_id, p.author_user_id, p.current_body_id,
    p.position, p.visibility, p.moderation_state, p.created_at,
    p.deleted_at, p.body, p.body_source, p.author_username,
    p.author_display_name, shown.attachment_id
FROM api.forum_thread_page_posts_v1(p_thread_id, p_standing,
    p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit)
    WITH ORDINALITY AS p
LEFT JOIN public.member_avatars m ON m.user_id = p.author_user_id
LEFT JOIN public.attachments shown ON shown.attachment_id = m.attachment_id
    AND shown.state = 'available' AND shown.scan_status = 'clean'
    AND shown.deleted_at IS NULL
ORDER BY p.ordinality
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v3(uuid, text, uuid,
    bigint, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_scoped_v3(
    p_thread_id uuid,
    p_standing text,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid, thread_id uuid, author_user_id uuid, current_body_id uuid,
    "position" bigint, visibility text, moderation_state text,
    created_at timestamptz, deleted_at timestamptz, body text,
    body_source text, author_username text, author_display_name text,
    author_avatar_id uuid
)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT p.post_id, p.thread_id, p.author_user_id, p.current_body_id,
    p.position, p.visibility, p.moderation_state, p.created_at,
    p.deleted_at, p.body, p.body_source, p.author_username,
    p.author_display_name, shown.attachment_id
FROM api.forum_thread_page_posts_scoped_v1(p_thread_id, p_standing,
    p_scope_user_id, p_viewer_user_id, p_after_position, p_after_post_id,
    p_row_limit) WITH ORDINALITY AS p
LEFT JOIN public.member_avatars m ON m.user_id = p.author_user_id
LEFT JOIN public.attachments shown ON shown.attachment_id = m.attachment_id
    AND shown.state = 'available' AND shown.scan_status = 'clean'
    AND shown.deleted_at IS NULL
ORDER BY p.ordinality
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_scoped_v3(uuid, text,
    uuid, uuid, bigint, uuid, integer) FROM PUBLIC;

-- Erasure: the member's picture row goes, and every upload they linked to
-- their profile is marked deleted. Their stored objects were deleted
-- before (Service::Community::Avatars::erase_files).
CREATE FUNCTION api.privacy_revoke_user_v17(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE rows_gone bigint; uploads_gone bigint;
BEGIN
    IF p_source = 'Avatar' THEN
        DELETE FROM public.member_avatars m WHERE m.user_id = p_user_id;
        GET DIAGNOSTICS rows_gone = ROW_COUNT;
        UPDATE public.attachments a
            SET state = 'deleted',
                deleted_at = coalesce(a.deleted_at, p_at::timestamptz)
            WHERE a.owner_user_id = p_user_id AND a.state <> 'deleted'
                AND EXISTS (SELECT 1 FROM public.attachment_links l
                    WHERE l.attachment_id = a.attachment_id
                        AND l.target_type = 'profile'
                        AND l.target_id = p_user_id);
        GET DIAGNOSTICS uploads_gone = ROW_COUNT;
        RETURN QUERY SELECT rows_gone + uploads_gone;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v15(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v17(text, uuid, text)
    FROM PUBLIC;

-- The export says whether the member shows a picture, since when, and
-- whether one is waiting; the upload itself is among their attachments.
CREATE FUNCTION api.portability_export_parts_v19(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'avatar', (SELECT jsonb_build_object(
        'attachment_id', s.attachment_id,
        'shown_at', s.shown_at,
        'pending_attachment_id', s.pending_attachment_id,
        'pending_state', s.pending_state)
        FROM (SELECT p_user_id AS user_id) me
        LEFT JOIN api.community_avatar_status_v1(p_user_id) s ON true)))::json
FROM api.portability_export_parts_v17(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v19(uuid) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.community_avatar_offer_v2(
p_user_id uuid, p_attachment_id uuid, p_now timestamptz
)
RETURNS TABLE(status text, replaced_attachment_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_offer_v1(p_user_id, p_attachment_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_offer_v2(uuid, uuid,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_settle_v2(
p_user_id uuid, p_attachment_id uuid, p_outcome text, p_now timestamptz
)
RETURNS TABLE(status text, replaced_attachment_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_settle_v1(p_user_id, p_attachment_id, p_outcome, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_settle_v2(uuid, uuid, text,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_remove_v2(
p_user_id uuid, p_attachment_id uuid, p_audit jsonb
)
RETURNS TABLE(status text, attachment_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_remove_v1(p_user_id, p_attachment_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_remove_v2(uuid, uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.community_avatar_status_v2(
p_user_id uuid
)
RETURNS TABLE(attachment_id uuid, shown_at timestamptz,
    pending_attachment_id uuid, pending_state text, pending_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_status_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_status_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.community_avatar_image_v2(
p_user_id uuid, p_variant_type text
)
RETURNS TABLE(attachment_id uuid, object_key text, media_type text,
    byte_size bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_image_v1(p_user_id, p_variant_type);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_image_v2(uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.community_avatar_objects_v2(
p_user_id uuid, p_attachment_id uuid
)
RETURNS TABLE(attachment_id uuid, object_key text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_avatar_objects_v1(p_user_id, p_attachment_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_avatar_objects_v2(uuid, uuid)
    FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_v4(
p_thread_id uuid,
    p_standing text,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid, thread_id uuid, author_user_id uuid, current_body_id uuid,
    "position" bigint, visibility text, moderation_state text,
    created_at timestamptz, deleted_at timestamptz, body text,
    body_source text, author_username text, author_display_name text,
    author_avatar_id uuid
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_posts_v3(p_thread_id, p_standing, p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v4(uuid, text, uuid,
    bigint, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_scoped_v4(
p_thread_id uuid,
    p_standing text,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid, thread_id uuid, author_user_id uuid, current_body_id uuid,
    "position" bigint, visibility text, moderation_state text,
    created_at timestamptz, deleted_at timestamptz, body text,
    body_source text, author_username text, author_display_name text,
    author_avatar_id uuid
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_thread_page_posts_scoped_v3(p_thread_id, p_standing, p_scope_user_id, p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_scoped_v4(uuid, text,
    uuid, uuid, bigint, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v18(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v17(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v18(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v20(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v19(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v20(uuid) FROM PUBLIC;

COMMIT;
