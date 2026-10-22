-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Bookmarks, follows, mentions, likes and reactions, member relations, the
-- feed and direct messages.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The stored square of a member's picture at one size, for the picture's
-- address: only the picture shown, available and clean, of a member who
-- has not been erased.
CREATE FUNCTION api.community_avatar_image_v1(
    p_user_id uuid,
    p_variant_type text
)
RETURNS TABLE (
    attachment_id uuid,
    object_key text,
    media_type text,
    byte_size bigint
)
LANGUAGE sql
STABLE
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
CREATE FUNCTION api.community_avatar_objects_v1(
    p_user_id uuid,
    p_attachment_id uuid
)
RETURNS TABLE (attachment_id uuid, object_key text)
LANGUAGE sql
STABLE
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

-- The upload a member offers as their picture: an attachment they own,
-- linked to their profile and not deleted. It waits (checking) while the
-- picture shown, if any, stays; the upload it replaces as the waiting one
-- comes back, for the caller to discard. The same upload again is a
-- replay.
CREATE FUNCTION api.community_avatar_offer_v1(
    p_user_id uuid,
    p_attachment_id uuid,
    p_now timestamptz
)
RETURNS TABLE (status text, replaced_attachment_id uuid)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.community_avatar_offer_v1(uuid, uuid, timestamptz)
    FROM PUBLIC;

-- Takes a member's picture away. Without an attachment id (the member's
-- own removal) the picture shown and the one waiting both go; with one
-- (staff), only that picture, and only while it is the one shown. With an
-- audit row, the removal is audited. One row per upload removed, for the
-- caller to discard; not_found when there was none.
CREATE FUNCTION api.community_avatar_remove_v1(
    p_user_id uuid,
    p_attachment_id uuid,
    p_audit jsonb
)
RETURNS TABLE (status text, attachment_id uuid)
LANGUAGE plpgsql
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

-- What became of the waiting upload. ready, once its squares are stored
-- and while it is available and clean: it is shown from now on, and the
-- picture it replaces comes back for the caller to discard. unreadable:
-- it stays waiting with that state, so the member is told. An upload that
-- is already the one shown answers shown; one that is neither shown nor
-- waiting, stale.
CREATE FUNCTION api.community_avatar_settle_v1(
    p_user_id uuid,
    p_attachment_id uuid,
    p_outcome text,
    p_now timestamptz
)
RETURNS TABLE (status text, replaced_attachment_id uuid)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.community_avatar_settle_v1(uuid, uuid, text, timestamptz)
    FROM PUBLIC;

-- A member's picture as the settings page and the profile read it: the
-- one shown, while its attachment is available and clean, and the one
-- waiting, refused once its scan found it infected or failed it.
CREATE FUNCTION api.community_avatar_status_v1(p_user_id uuid)
RETURNS TABLE (
    attachment_id uuid,
    shown_at timestamptz,
    pending_attachment_id uuid,
    pending_state text,
    pending_at timestamptz
)
LANGUAGE sql
STABLE
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

-- Stores a member's bookmark, or restores the one they deleted when p_restore
-- is true.
CREATE FUNCTION api.community_save_bookmark_v1(p_row jsonb, p_restore boolean)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.bookmarks%ROWTYPE; v_constraint text; v_skipped boolean;
BEGIN
  IF p_restore THEN SELECT b.* INTO v FROM public.bookmarks b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE; END IF;
  IF v.bookmark_id IS NULL THEN
    BEGIN
      INSERT INTO public.bookmarks (bookmark_id, user_id, target_type, target_id, note, created_at, deleted_at) VALUES ((p_row->>'bookmark_id')::uuid, (p_row->>'user_id')::uuid, p_row->>'target_type', (p_row->>'target_id')::uuid, p_row->>'note', (p_row->>'created_at')::timestamptz, NULL);
      RETURN QUERY SELECT p_row; RETURN;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF NOT p_restore THEN RAISE; END IF;
      SELECT b.* INTO v FROM public.bookmarks b WHERE b.user_id = (p_row->>'user_id')::uuid AND b.target_type = p_row->>'target_type' AND b.target_id = (p_row->>'target_id')::uuid FOR UPDATE;
      IF v.bookmark_id IS NULL THEN
        IF v_constraint = 'bookmarks_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
        RAISE;
      END IF;
    END;
  END IF;
  v_skipped := v.deleted_at IS NULL AND v.note = p_row->>'note';
  IF NOT v_skipped THEN UPDATE public.bookmarks b SET deleted_at = NULL, note = p_row->>'note' WHERE b.bookmark_id = v.bookmark_id; END IF;
  RETURN QUERY SELECT p_row || jsonb_build_object('bookmark_id', v.bookmark_id, 'created_at', v.created_at::text) || CASE WHEN v_skipped THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_save_bookmark_v1(jsonb, boolean)
    FROM PUBLIC;

-- Bookmarking a thread: the command log around
-- api.community_save_bookmark_v1, an id a collision took drawn again once,
-- and the answer Community::Workflow records: the bookmark's public fields.
CREATE FUNCTION api.community_bookmark_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
    row_in jsonb := p_row;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved
        FROM api.community_save_bookmark_v1(row_in, true);
        IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
            row_in := row_in || jsonb_build_object('bookmark_id',
                api.core_uuid_v7_v1()::text);
            SELECT result INTO saved
            FROM api.community_save_bookmark_v1(row_in, true);
            IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
                RAISE EXCEPTION USING ERRCODE = 'unique_violation',
                    MESSAGE = 'the replacement id is already stored';
            END IF;
        END IF;
        answer := jsonb_build_object(
            'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
            'stored', jsonb_build_object(
                'bookmark_id', saved -> 'bookmark_id',
                'created_at', saved -> 'created_at',
                'deleted_at', saved -> 'deleted_at',
                'note', saved -> 'note',
                'ok', saved -> 'ok',
                'target_id', saved -> 'target_id',
                'target_type', saved -> 'target_type',
                'user_id', saved -> 'user_id'));
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_bookmark_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- Records that a post or a thread names a member, once per source and member;
-- a mention already recorded answers null.
CREATE FUNCTION api.community_create_mention_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_constraint text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.mentions m WHERE m.source_type = p_row->>'source_type' AND m.source_id = (p_row->>'source_id')::uuid AND m.mentioned_user_id = (p_row->>'mentioned_user_id')::uuid) THEN RETURN QUERY SELECT NULL::jsonb; RETURN; END IF;
  BEGIN
    INSERT INTO public.mentions (mention_id, source_type, source_id, actor_id, mentioned_user_id, mentioned_username, created_at)
    VALUES ((p_row->>'mention_id')::uuid, p_row->>'source_type', (p_row->>'source_id')::uuid, (p_row->>'actor_id')::uuid, (p_row->>'mentioned_user_id')::uuid, p_row->>'mentioned_username', (p_row->>'created_at')::timestamptz);
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF EXISTS (SELECT 1 FROM public.mentions m WHERE m.source_type = p_row->>'source_type' AND m.source_id = (p_row->>'source_id')::uuid AND m.mentioned_user_id = (p_row->>'mentioned_user_id')::uuid) THEN RETURN QUERY SELECT NULL::jsonb; RETURN; END IF;
    IF v_constraint = 'mentions_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
    RAISE;
  END;
  RETURN QUERY SELECT p_row;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_create_mention_v1(jsonb) FROM PUBLIC;

-- A member's bookmark on a target, deleted or not.
CREATE FUNCTION api.community_find_bookmark_v1(
    p_user_id uuid,
    p_target_type text,
    p_target_id uuid
)
RETURNS SETOF api.community_bookmark_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note,
    b.created_at, b.deleted_at
FROM public.bookmarks b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id
$$;
REVOKE EXECUTE ON FUNCTION api.community_find_bookmark_v1(uuid, text, uuid)
    FROM PUBLIC;

-- Liking a post: refused when the post is not there to be read, or is the
-- liker's own; a like already given is kept, and no second event is
-- recorded for it. Answers with the count as it then is.
CREATE FUNCTION api.community_like_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
    added integer := 0;
    total bigint;
BEGIN
    SELECT p.post_id, p.thread_id, p.author_user_id INTO target
    FROM public.posts p
    WHERE p.post_id = (p_row ->> 'post_id')::uuid
        AND p.deleted_at IS NULL AND p.moderation_state = 'visible';
    IF target.post_id IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'post not found',
            'ok', 0, 'status', 'not_found');
        RETURN;
    END IF;
    IF target.author_user_id = liker THEN
        RETURN QUERY SELECT jsonb_build_object('error',
            'a post is not liked by its author', 'ok', 0,
            'status', 'invalid');
        RETURN;
    END IF;
    INSERT INTO public.post_likes (post_id, user_id, created_at)
    VALUES (target.post_id, liker, (p_row ->> 'created_at')::timestamptz)
    ON CONFLICT ON CONSTRAINT post_likes_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    IF added = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_like_event_v1(p_row,
            'post.liked', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_likes l
    WHERE l.post_id = target.post_id;
    RETURN QUERY SELECT jsonb_build_object('changed', added,
        'like_count', total, 'liked', 1, 'ok', 1, 'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_post_v1(jsonb) FROM PUBLIC;

-- Liking as one command: the command log around api.community_like_post_v1,
-- as api.community_bookmark_command_v1 is around a bookmark.
CREATE FUNCTION api.community_like_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved FROM api.community_like_post_v1(p_row);
        answer := api.core_community_like_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_like_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- The member's folders, each with how many active bookmarks it holds.
CREATE FUNCTION api.community_list_bookmark_folders_v1(p_user_id uuid)
RETURNS TABLE (folder text, bookmark_count bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT f.folder, count(*)
FROM public.bookmark_folders f
JOIN public.bookmarks b ON b.bookmark_id = f.bookmark_id
WHERE b.user_id = p_user_id AND b.deleted_at IS NULL
GROUP BY f.folder
ORDER BY f.folder
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmark_folders_v1(uuid)
    FROM PUBLIC;

-- The bookmarks a member keeps, readable by the viewer, with each bookmark's
-- folder and, when p_folder is given, only the bookmarks in it.
CREATE FUNCTION api.community_list_bookmarks_v3(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_target_type text,
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer,
    p_folder text
)
RETURNS TABLE (
    bookmark_id uuid,
    user_id uuid,
    target_type text,
    target_id uuid,
    note text,
    created_at timestamptz,
    deleted_at timestamptz,
    source_thread_id uuid,
    source_thread_title text,
    folder text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note, b.created_at, b.deleted_at, CASE WHEN p_filter_sources THEN CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END) END, f.folder FROM public.bookmarks b LEFT JOIN public.bookmark_folders f ON f.bookmark_id = b.bookmark_id WHERE b.user_id = p_user_id AND b.deleted_at IS NULL AND (p_target_type IS NULL OR b.target_type = p_target_type) AND (p_folder IS NULL OR f.folder = p_folder) AND (NOT p_filter_sources OR ((b.target_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.target_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.target_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
    ORDER BY b.created_at DESC, b.bookmark_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note, b.created_at, b.deleted_at, CASE WHEN p_filter_sources THEN CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END) END, f.folder FROM public.bookmarks b LEFT JOIN public.bookmark_folders f ON f.bookmark_id = b.bookmark_id WHERE b.user_id = p_user_id AND b.deleted_at IS NULL AND (p_target_type IS NULL OR b.target_type = p_target_type) AND (p_folder IS NULL OR f.folder = p_folder) AND (NOT p_filter_sources OR ((b.target_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.target_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.target_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.bookmark_id < p_after_id))
    ORDER BY b.created_at DESC, b.bookmark_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmarks_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text, timestamptz, uuid, integer, text)
    FROM PUBLIC;

-- A page of a member's feed, newest first after the cursor, leaving out what
-- the viewer may not read and the members on their list.
CREATE FUNCTION api.community_list_feed_v3(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    user_id uuid,
    item_type text,
    item_id uuid,
    created_at timestamptz,
    rank_score numeric,
    visibility_version bigint,
    permission_version bigint,
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
    RETURN QUERY SELECT b.user_id, b.item_type, b.item_id, b.created_at, b.rank_score, b.visibility_version, b.permission_version, CASE WHEN p_filter_sources THEN CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END) END FROM public.user_feed_items b  WHERE b.user_id = p_user_id AND (NOT p_filter_sources OR ((b.item_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.item_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.item_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.item_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id
              AND r.other_user_id = CASE b.item_type
                  WHEN 'thread' THEN (SELECT t.author_user_id
                      FROM public.threads t WHERE t.thread_id = b.item_id)
                  WHEN 'post' THEN (SELECT p.author_user_id
                      FROM public.posts p WHERE p.post_id = b.item_id)
              END)
    ORDER BY b.created_at DESC, b.item_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.user_id, b.item_type, b.item_id, b.created_at, b.rank_score, b.visibility_version, b.permission_version, CASE WHEN p_filter_sources THEN CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.item_type WHEN 'thread' THEN b.item_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.item_id) END) END FROM public.user_feed_items b  WHERE b.user_id = p_user_id AND (NOT p_filter_sources OR ((b.item_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.item_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.item_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.item_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.item_id < p_after_id))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id
              AND r.other_user_id = CASE b.item_type
                  WHEN 'thread' THEN (SELECT t.author_user_id
                      FROM public.threads t WHERE t.thread_id = b.item_id)
                  WHEN 'post' THEN (SELECT p.author_user_id
                      FROM public.posts p WHERE p.post_id = b.item_id)
              END)
    ORDER BY b.created_at DESC, b.item_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_feed_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- A page of the mentions of a member, newest first after the cursor, leaving
-- out what the viewer may not read and the members on their list.
CREATE FUNCTION api.community_list_mentions_v3(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    mention_id uuid,
    source_type text,
    source_id uuid,
    actor_id uuid,
    mentioned_user_id uuid,
    mentioned_username text,
    created_at timestamptz,
    actor_username text,
    actor_display_name text,
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
    RETURN QUERY SELECT b.mention_id, b.source_type, b.source_id, b.actor_id, b.mentioned_user_id, b.mentioned_username, b.created_at, a.username, a.display_name, CASE WHEN p_filter_sources THEN CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END) END FROM public.mentions b JOIN public.users a ON a.id = b.actor_id WHERE b.mentioned_user_id = p_user_id AND (NOT p_filter_sources OR ((b.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id AND r.other_user_id = b.actor_id)
    ORDER BY b.created_at DESC, b.mention_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.mention_id, b.source_type, b.source_id, b.actor_id, b.mentioned_user_id, b.mentioned_username, b.created_at, a.username, a.display_name, CASE WHEN p_filter_sources THEN CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.source_type WHEN 'thread' THEN b.source_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.source_id) END) END FROM public.mentions b JOIN public.users a ON a.id = b.actor_id WHERE b.mentioned_user_id = p_user_id AND (NOT p_filter_sources OR ((b.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.mention_id < p_after_id))
      AND NOT EXISTS (SELECT 1 FROM public.member_relations r
          WHERE r.owner_user_id = p_user_id AND r.other_user_id = b.actor_id)
    ORDER BY b.created_at DESC, b.mention_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_mentions_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- A conversation as one of its members reads it, or no row for anyone
-- else: with whom, whether that account is gone, the reader's unread
-- count and whether the reader blocks the other member.
CREATE FUNCTION api.community_message_conversation_v1(
    p_conversation_id uuid,
    p_user_id uuid
)
RETURNS TABLE (
    conversation_id uuid,
    other_user_id uuid,
    other_username text,
    other_display_name text,
    other_gone boolean,
    unread_count integer,
    last_read_at timestamptz,
    created_at timestamptz,
    reader_blocks boolean
)
LANGUAGE sql
STABLE
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

-- Whom the member would write to by that name, and the conversation the
-- two already hold, if any: no row for a member who is not there to
-- write to.
CREATE FUNCTION api.community_message_conversation_with_v1(
    p_user_id uuid,
    p_username text
)
RETURNS TABLE (
    other_user_id uuid,
    other_username text,
    other_display_name text,
    conversation_id uuid
)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.community_message_conversation_with_v1(uuid, text)
    FROM PUBLIC;

-- A message the member may report: one in a conversation of theirs that
-- another member wrote. No row otherwise.
CREATE FUNCTION api.community_message_for_report_v1(
    p_message_id uuid,
    p_user_id uuid
)
RETURNS TABLE (message_id uuid, conversation_id uuid, author_user_id uuid)
LANGUAGE sql
STABLE
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

-- The member's conversations, the one moved last first, each with whom
-- it is held, how many messages wait and the start of the latest one.
CREATE FUNCTION api.community_message_inbox_v1(
    p_user_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    conversation_id uuid,
    other_user_id uuid,
    other_username text,
    other_display_name text,
    other_gone boolean,
    last_message_at timestamptz,
    unread_count integer,
    last_author_user_id uuid,
    last_excerpt text
)
LANGUAGE plpgsql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.community_message_inbox_v1(uuid, timestamptz, uuid, integer)
    FROM PUBLIC;

-- A page of a conversation's messages, newest first, for one of its
-- members only, in the order they were stored; before a message's
-- position for the older ones.
CREATE FUNCTION api.community_message_list_v1(
    p_conversation_id uuid,
    p_user_id uuid,
    p_before_position bigint,
    p_row_limit integer
)
RETURNS TABLE (
    message_id uuid,
    author_user_id uuid,
    author_username text,
    author_display_name text,
    body text,
    created_at timestamptz,
    message_position bigint
)
LANGUAGE plpgsql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.community_message_list_v1(uuid, uuid, bigint, integer)
    FROM PUBLIC;

-- The member has read the conversation: nothing waits, and the inbox's
-- notifications of its messages are read as well. Answers unchanged when
-- nothing waited and not_found for anyone not a member.
CREATE FUNCTION api.community_message_mark_read_v1(
    p_conversation_id uuid,
    p_user_id uuid,
    p_now timestamptz
)
RETURNS TABLE (status text, notifications_read integer)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.community_message_mark_read_v1(uuid, uuid, timestamptz)
    FROM PUBLIC;

-- Whether the member takes part in the conversation of the message: who
-- may be notified about it.
CREATE FUNCTION api.community_message_participant_v1(
    p_message_id uuid,
    p_user_id uuid
)
RETURNS TABLE (participant boolean)
LANGUAGE sql
STABLE
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

-- Sends a message in a conversation the sender is a member of. Refusals:
-- invalid, forbidden, not_found (no such conversation of the sender's),
-- gone (the other member's account was erased), blocked, conflict.
CREATE FUNCTION api.community_message_reply_v1(p_row jsonb)
RETURNS TABLE (
    status text,
    conversation_id uuid,
    message_id uuid,
    recipient_user_id uuid,
    started boolean,
    first_unread boolean
)
LANGUAGE plpgsql
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

-- Sends a message to the member named, in the one conversation the two
-- hold, starting it when there is none. Refusals: invalid, forbidden (the
-- sender cannot write), not_found (no such member to write to), self,
-- blocked (either blocks the other), limit (the sender started as many
-- conversations in the last day as their trust allows), conflict (the
-- message id is another message). The same message again is replayed.
CREATE FUNCTION api.community_message_start_v1(p_row jsonb)
RETURNS TABLE (
    status text,
    conversation_id uuid,
    message_id uuid,
    recipient_user_id uuid,
    started boolean,
    first_unread boolean
)
LANGUAGE plpgsql
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

-- The likes on the posts of a page, with whether the viewer gave one; a post
-- with none has no row.
CREATE FUNCTION api.community_post_likes_v1(
    p_post_ids uuid[],
    p_viewer_user_id uuid
)
RETURNS TABLE (post_id uuid, like_count bigint, liked boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT l.post_id, count(*)::bigint AS like_count,
    coalesce(bool_or(l.user_id = p_viewer_user_id), false) AS liked
FROM public.post_likes l
WHERE l.post_id = ANY(p_post_ids)
GROUP BY l.post_id
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_likes_v1(uuid[], uuid)
    FROM PUBLIC;

-- The reactions on the posts of a page: how many of each, and whether the
-- viewer gave it. A post nobody reacted to is absent.
CREATE FUNCTION api.community_post_reactions_v1(
    p_post_ids uuid[],
    p_viewer_user_id uuid
)
RETURNS TABLE (
    post_id uuid,
    reaction text,
    reaction_count bigint,
    reacted boolean
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.post_id, r.reaction, count(*)::bigint AS reaction_count,
    coalesce(bool_or(r.user_id = p_viewer_user_id), false) AS reacted
FROM public.post_reactions r
WHERE r.post_id = ANY(p_post_ids)
GROUP BY r.post_id, r.reaction
$$;
REVOKE EXECUTE ON FUNCTION api.community_post_reactions_v1(uuid[], uuid)
    FROM PUBLIC;

-- Writes a feed item into the feed of each member given, updating an item
-- already there when it changed.
CREATE FUNCTION api.community_project_feed_v1(p_row jsonb, p_user_ids uuid[])
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_written bigint;
BEGIN
  INSERT INTO public.user_feed_items (user_id, item_type, item_id, created_at, rank_score, visibility_version, permission_version)
  SELECT u, p_row->>'item_type', (p_row->>'item_id')::uuid, (p_row->>'created_at')::timestamptz,
    (p_row->>'rank_score')::numeric, (p_row->>'visibility_version')::bigint, (p_row->>'permission_version')::bigint FROM unnest(p_user_ids) u
  ON CONFLICT (user_id, item_type, item_id) DO UPDATE SET created_at = EXCLUDED.created_at, rank_score = EXCLUDED.rank_score, visibility_version = EXCLUDED.visibility_version, permission_version = EXCLUDED.permission_version
  WHERE (public.user_feed_items.created_at, public.user_feed_items.rank_score, public.user_feed_items.visibility_version, public.user_feed_items.permission_version)
    IS DISTINCT FROM (EXCLUDED.created_at, EXCLUDED.rank_score, EXCLUDED.visibility_version, EXCLUDED.permission_version);
  GET DIAGNOSTICS v_written = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'projected', cardinality(p_user_ids), 'written', v_written);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_project_feed_v1(jsonb, uuid[])
    FROM PUBLIC;

-- Giving a reaction: the post must be there to be read, the reaction one of
-- the four, the member not its author; given twice it is one.
CREATE FUNCTION api.community_react_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
    kind text := p_row ->> 'reaction';
    added integer := 0;
    total bigint;
BEGIN
    SELECT p.post_id, p.thread_id, p.author_user_id INTO target
    FROM public.posts p
    WHERE p.post_id = (p_row ->> 'post_id')::uuid
        AND p.deleted_at IS NULL AND p.moderation_state = 'visible';
    IF target.post_id IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'post not found',
            'ok', 0, 'status', 'not_found');
        RETURN;
    END IF;
    IF kind IS NULL OR kind NOT IN ('heart', 'laugh', 'celebrate', 'think') THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'unknown reaction',
            'ok', 0, 'status', 'invalid');
        RETURN;
    END IF;
    IF target.author_user_id = liker THEN
        RETURN QUERY SELECT jsonb_build_object('error',
            'a post is not reacted to by its author', 'ok', 0,
            'status', 'invalid');
        RETURN;
    END IF;
    INSERT INTO public.post_reactions (post_id, user_id, reaction, created_at)
    VALUES (target.post_id, liker, kind, (p_row ->> 'created_at')::timestamptz)
    ON CONFLICT ON CONSTRAINT post_reactions_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    IF added = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_reaction_event_v1(p_row,
            'post.reacted', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_reactions r
    WHERE r.post_id = target.post_id AND r.reaction = kind;
    RETURN QUERY SELECT jsonb_build_object('changed', added,
        'reaction', kind, 'reaction_count', total, 'reacted', 1, 'ok', 1,
        'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_post_v1(jsonb) FROM PUBLIC;

-- The commands around giving and taking back (ADR 0126 section 5).
CREATE FUNCTION api.community_react_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved FROM api.community_react_post_v1(p_row);
        answer := api.core_community_reaction_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_react_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- Records a change to a member's reputation, once per source, and updates
-- their score and trust level; without a source it answers the snapshot
-- unchanged.
CREATE FUNCTION api.community_record_reputation_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_event public.reputation_events%ROWTYPE; v_snapshot public.trust_score_snapshots%ROWTYPE;
  v_new boolean := false; v_constraint text; v_at text; v_event_json jsonb; v_score integer; v_trust integer; v_snapshot_json jsonb;
BEGIN
  IF COALESCE(p_row->>'source_type', '') = '' OR COALESCE(p_row->>'source_id', '') = '' THEN
    SELECT s.* INTO v_snapshot FROM public.trust_score_snapshots s WHERE s.user_id = (p_row->>'user_id')::uuid;
    v_snapshot_json := CASE WHEN v_snapshot.user_id IS NULL THEN jsonb_build_object('user_id', p_row->>'user_id', 'score', 0, 'trust_level', 0, 'version', 1)
      ELSE to_jsonb(v_snapshot) || jsonb_build_object('calculated_at', v_snapshot.calculated_at::text) END;
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'reason', 'missing_source', 'skipped', 1, 'snapshot', v_snapshot_json); RETURN;
  END IF;
  SELECT e.* INTO v_event FROM public.reputation_events e WHERE e.user_id = (p_row->>'user_id')::uuid AND e.source_type = p_row->>'source_type' AND e.source_id = (p_row->>'source_id')::uuid;
  IF v_event.reputation_event_id IS NULL THEN
    BEGIN
      INSERT INTO public.reputation_events (reputation_event_id, user_id, actor_id, source_type, source_id, delta, reason, created_at)
      VALUES ((p_row->>'reputation_event_id')::uuid, (p_row->>'user_id')::uuid, (p_row->>'actor_id')::uuid, p_row->>'source_type', (p_row->>'source_id')::uuid, (p_row->>'delta')::integer, p_row->>'reason', (p_row->>'created_at')::timestamptz);
      v_new := true;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      SELECT e.* INTO v_event FROM public.reputation_events e WHERE e.user_id = (p_row->>'user_id')::uuid AND e.source_type = p_row->>'source_type' AND e.source_id = (p_row->>'source_id')::uuid;
      IF v_event.reputation_event_id IS NULL THEN
        IF v_constraint = 'reputation_events_pkey' THEN RETURN QUERY SELECT jsonb_build_object('retry_id', 1); RETURN; END IF;
        RAISE;
      END IF;
    END;
  END IF;
  v_at := CASE WHEN v_new THEN p_row->>'created_at' ELSE v_event.created_at::text END;
  v_event_json := CASE WHEN v_new THEN jsonb_build_object('actor_id', p_row->'actor_id', 'created_at', p_row->'created_at', 'delta', p_row->'delta', 'reason', p_row->'reason', 'reputation_event_id', p_row->'reputation_event_id', 'source_id', p_row->'source_id', 'source_type', p_row->'source_type', 'user_id', p_row->'user_id') ELSE to_jsonb(v_event) || jsonb_build_object('created_at', v_event.created_at::text) END;
  SELECT s.* INTO v_snapshot FROM public.trust_score_snapshots s WHERE s.user_id = (p_row->>'user_id')::uuid FOR UPDATE;
  IF NOT v_new AND v_snapshot.user_id IS NOT NULL THEN
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'skipped', 1, 'event', v_event_json, 'snapshot', to_jsonb(v_snapshot) || jsonb_build_object('calculated_at', v_snapshot.calculated_at::text)); RETURN;
  END IF;
  IF v_snapshot.user_id IS NULL THEN
    v_score := COALESCE((p_row->>'current_score')::integer, 0) + (p_row->>'delta')::integer;
    v_trust := CASE WHEN v_score >= 500 THEN 4 WHEN v_score >= 150 THEN 3 WHEN v_score >= 50 THEN 2 WHEN v_score >= 10 THEN 1 ELSE 0 END;
    INSERT INTO public.trust_score_snapshots (user_id, score, trust_level, calculated_at, version)
    VALUES ((p_row->>'user_id')::uuid, v_score, v_trust, v_at::timestamptz, 1) ON CONFLICT (user_id) DO NOTHING;
    IF NOT FOUND THEN
      SELECT s.* INTO v_snapshot FROM public.trust_score_snapshots s WHERE s.user_id = (p_row->>'user_id')::uuid FOR UPDATE;
    END IF;
  END IF;
  IF v_snapshot.user_id IS NOT NULL THEN
    v_score := v_snapshot.score + CASE WHEN v_new THEN (p_row->>'delta')::integer ELSE 0 END;
    v_trust := CASE WHEN v_score >= 500 THEN 4 WHEN v_score >= 150 THEN 3 WHEN v_score >= 50 THEN 2 WHEN v_score >= 10 THEN 1 ELSE 0 END;
    IF v_new THEN UPDATE public.trust_score_snapshots s SET score = v_score, trust_level = v_trust, calculated_at = v_at::timestamptz, version = 1 WHERE s.user_id = v_snapshot.user_id;
    ELSE v_at := v_snapshot.calculated_at::text; END IF;
  END IF;
  UPDATE public.users u SET trust_level = v_trust WHERE u.id = (p_row->>'user_id')::uuid AND u.trust_level IS DISTINCT FROM v_trust;
  v_snapshot_json := jsonb_build_object('user_id', p_row->>'user_id', 'score', v_score, 'trust_level', v_trust, 'calculated_at', v_at, 'version', 1);
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'event', v_event_json, 'snapshot', v_snapshot_json) || CASE WHEN NOT v_new THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_record_reputation_v1(jsonb)
    FROM PUBLIC;

-- What the owner holds against one member: the profile page's actions, the
-- notification dispatcher and the mention store ask it.
CREATE FUNCTION api.community_relation_between_v1(
    p_owner_user_id uuid,
    p_other_user_id uuid
)
RETURNS TABLE (kind text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.kind FROM public.member_relations r
WHERE r.owner_user_id = p_owner_user_id AND r.other_user_id = p_other_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_between_v1(uuid, uuid)
    FROM PUBLIC;

-- The owner's list, newest change first, for the settings page.
CREATE FUNCTION api.community_relation_list_v1(p_owner_user_id uuid)
RETURNS TABLE (
    other_user_id uuid,
    username text,
    display_name text,
    kind text,
    created_at timestamptz,
    updated_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.other_user_id, u.username, u.display_name, r.kind, r.created_at,
    r.updated_at
FROM public.member_relations r JOIN public.users u ON u.id = r.other_user_id
WHERE r.owner_user_id = p_owner_user_id
ORDER BY r.updated_at DESC, u.username
LIMIT 500;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_list_v1(uuid) FROM PUBLIC;

-- Takes a member off another member's list by username. Answers how many
-- relations went.
CREATE FUNCTION api.community_relation_remove_v1(
    p_owner_user_id uuid,
    p_username text
)
RETURNS TABLE (removed bigint)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH gone AS (
    DELETE FROM public.member_relations r USING public.users u
    WHERE r.owner_user_id = p_owner_user_id AND r.other_user_id = u.id
        AND u.username = p_username
    RETURNING 1
)
SELECT count(*) FROM gone;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_remove_v1(uuid, text)
    FROM PUBLIC;

-- The owner's row is held while the list is counted, so two requests cannot
-- both take the last place. A member already listed changes kind in place.
CREATE FUNCTION api.community_relation_set_v1(
    p_owner_user_id uuid,
    p_username text,
    p_kind text,
    p_now timestamptz
)
RETURNS TABLE (status text, other_user_id uuid, username text, kind text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE target record; held text; amount bigint;
BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('ignore', 'block')
        OR p_username IS NULL OR length(p_username) NOT BETWEEN 1 AND 200
        OR p_now IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u WHERE u.id = p_owner_user_id
        AND u.deleted_at IS NULL AND u.status IN ('active', 'suspended')
        FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'forbidden'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    SELECT u.id, u.username INTO target FROM public.users u
        WHERE u.username = p_username AND u.deleted_at IS NULL
            AND u.status IN ('active', 'suspended');
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    IF target.id = p_owner_user_id THEN
        RETURN QUERY SELECT 'self'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    SELECT r.kind INTO held FROM public.member_relations r
        WHERE r.owner_user_id = p_owner_user_id AND r.other_user_id = target.id
        FOR UPDATE;
    IF FOUND THEN
        IF held = p_kind THEN
            RETURN QUERY SELECT 'unchanged'::text, target.id, target.username, held;
            RETURN;
        END IF;
        UPDATE public.member_relations r SET kind = p_kind,
            updated_at = greatest(p_now, r.created_at)
            WHERE r.owner_user_id = p_owner_user_id
                AND r.other_user_id = target.id;
        RETURN QUERY SELECT 'ok'::text, target.id, target.username, p_kind;
        RETURN;
    END IF;
    SELECT count(*) INTO amount FROM public.member_relations r
        WHERE r.owner_user_id = p_owner_user_id;
    IF amount >= 500 THEN
        RETURN QUERY SELECT 'limit'::text, NULL::uuid, NULL::text, NULL::text;
        RETURN;
    END IF;
    INSERT INTO public.member_relations (owner_user_id, other_user_id, kind,
        created_at, updated_at)
        VALUES (p_owner_user_id, target.id, p_kind, p_now, p_now);
    RETURN QUERY SELECT 'ok'::text, target.id, target.username, p_kind;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_relation_set_v1(uuid, text, text, timestamptz)
    FROM PUBLIC;

-- Removes an item from every feed.
CREATE FUNCTION api.community_remove_feed_v1(p_item_type text, p_item_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_removed bigint;
BEGIN
  DELETE FROM public.user_feed_items f WHERE f.item_type = p_item_type AND f.item_id = p_item_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'removed', v_removed);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_feed_v1(text, uuid)
    FROM PUBLIC;

-- Removes a thread and its posts from every feed.
CREATE FUNCTION api.community_remove_thread_feed_v1(p_thread_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_thread bigint; v_posts bigint;
BEGIN
  DELETE FROM public.user_feed_items f WHERE f.item_type = 'thread' AND f.item_id = p_thread_id;
  GET DIAGNOSTICS v_thread = ROW_COUNT;
  DELETE FROM public.user_feed_items f WHERE f.item_type = 'post' AND f.item_id IN (SELECT p.post_id FROM public.posts p WHERE p.thread_id = p_thread_id);
  GET DIAGNOSTICS v_posts = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'posts_removed', v_posts, 'removed', v_thread + v_posts);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_remove_thread_feed_v1(uuid)
    FROM PUBLIC;

-- The members not deleted with these usernames, for the mentions of a post.
CREATE FUNCTION api.community_resolve_mention_users_v1(p_usernames text[])
RETURNS TABLE (id uuid, username text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id, u.username FROM public.users u WHERE u.username = ANY(p_usernames) AND u.deleted_at IS NULL LIMIT cardinality(p_usernames)
$$;
REVOKE EXECUTE ON FUNCTION api.community_resolve_mention_users_v1(text[])
    FROM PUBLIC;

-- Files the member's own active bookmark in a folder; an empty folder
-- takes it out of its folder. A bookmark that is not the member's, or is
-- removed, is not filed, and nothing is answered.
CREATE FUNCTION api.community_set_bookmark_folder_v1(
    p_bookmark_id uuid,
    p_user_id uuid,
    p_folder text
)
RETURNS TABLE (bookmark_id uuid, folder text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.bookmarks b
        WHERE b.bookmark_id = p_bookmark_id AND b.user_id = p_user_id
            AND b.deleted_at IS NULL)
    THEN
        RETURN;
    END IF;
    IF p_folder IS NULL OR p_folder = '' THEN
        DELETE FROM public.bookmark_folders f WHERE f.bookmark_id = p_bookmark_id;
        RETURN QUERY SELECT p_bookmark_id, NULL::text;
        RETURN;
    END IF;
    INSERT INTO public.bookmark_folders (bookmark_id, folder)
    VALUES (p_bookmark_id, p_folder)
    ON CONFLICT ON CONSTRAINT bookmark_folders_pkey
        DO UPDATE SET folder = EXCLUDED.folder;
    RETURN QUERY SELECT p_bookmark_id, p_folder;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_set_bookmark_folder_v1(uuid, uuid, text)
    FROM PUBLIC;

-- Sets one timestamp column of a bookmark, found by id or by its member and
-- target.
CREATE FUNCTION api.community_stamp_bookmark_v1(
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
DECLARE v public.bookmarks%ROWTYPE;
BEGIN
  IF p_by_target THEN SELECT b.* INTO v FROM public.bookmarks b WHERE b.user_id = p_user_id AND b.target_type = p_target_type AND b.target_id = p_target_id FOR UPDATE;
  ELSE SELECT b.* INTO v FROM public.bookmarks b WHERE b.bookmark_id = p_id FOR UPDATE; END IF;
  IF v.bookmark_id IS NULL THEN RETURN QUERY SELECT jsonb_build_object('ok', 0, 'error', 'not_found'); RETURN; END IF;
  IF p_column = 'deleted_at' THEN
    IF v.deleted_at IS NULL THEN UPDATE public.bookmarks b SET deleted_at = p_stamped_at::timestamptz WHERE b.bookmark_id = v.bookmark_id; END IF;
    RETURN QUERY SELECT jsonb_build_object('bookmark_id', v.bookmark_id, 'deleted_at', COALESCE(v.deleted_at::text, p_stamped_at)) || CASE WHEN v.deleted_at IS NOT NULL THEN jsonb_build_object('skipped', 1) ELSE '{}'::jsonb END || CASE WHEN p_by_target THEN jsonb_build_object('ok', 1) ELSE '{}'::jsonb END; RETURN;
  END IF;
  RAISE EXCEPTION 'invalid stamp column' USING ERRCODE = '22023';
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_stamp_bookmark_v1(uuid, boolean, uuid, text, uuid, text, text)
    FROM PUBLIC;

-- Subscribing to a thread: the same around
-- api.notification_save_subscription_v1.
CREATE FUNCTION api.community_subscribe_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
    row_in jsonb := p_row;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved
        FROM api.notification_save_subscription_v1(row_in, true);
        IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
            row_in := row_in || jsonb_build_object('subscription_id',
                api.core_uuid_v7_v1()::text);
            SELECT result INTO saved
            FROM api.notification_save_subscription_v1(row_in, true);
            IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
                RAISE EXCEPTION USING ERRCODE = 'unique_violation',
                    MESSAGE = 'the replacement id is already stored';
            END IF;
        END IF;
        answer := jsonb_build_object(
            'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
            'stored', jsonb_build_object(
                'created_at', saved -> 'created_at',
                'muted_at', saved -> 'muted_at',
                'ok', saved -> 'ok',
                'preference', saved -> 'preference',
                'revoked_at', saved -> 'revoked_at',
                'subscription_id', saved -> 'subscription_id',
                'target_id', saved -> 'target_id',
                'target_type', saved -> 'target_type',
                'user_id', saved -> 'user_id'));
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_subscribe_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- Taking a like back: allowed whatever became of the post, since nothing
-- is added; a like not given is nothing to take back, and no event.
CREATE FUNCTION api.community_unlike_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
    removed integer := 0;
    total bigint;
BEGIN
    SELECT p.post_id, p.thread_id, p.author_user_id INTO target
    FROM public.posts p
    WHERE p.post_id = (p_row ->> 'post_id')::uuid;
    IF target.post_id IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'post not found',
            'ok', 0, 'status', 'not_found');
        RETURN;
    END IF;
    DELETE FROM public.post_likes l
    WHERE l.post_id = target.post_id AND l.user_id = liker;
    GET DIAGNOSTICS removed = ROW_COUNT;
    IF removed = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_like_event_v1(p_row,
            'post.unliked', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_likes l
    WHERE l.post_id = target.post_id;
    RETURN QUERY SELECT jsonb_build_object('changed', removed,
        'like_count', total, 'liked', 0, 'ok', 1, 'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_post_v1(jsonb) FROM PUBLIC;

-- Taking a like back as one command, the same around
-- api.community_unlike_post_v1.
CREATE FUNCTION api.community_unlike_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved FROM api.community_unlike_post_v1(p_row);
        answer := api.core_community_like_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unlike_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- Taking a reaction back always goes through: it adds nothing.
CREATE FUNCTION api.community_unreact_post_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    target record;
    liker uuid := (p_row ->> 'user_id')::uuid;
    kind text := p_row ->> 'reaction';
    removed integer := 0;
    total bigint;
BEGIN
    SELECT p.post_id, p.thread_id, p.author_user_id INTO target
    FROM public.posts p
    WHERE p.post_id = (p_row ->> 'post_id')::uuid;
    IF target.post_id IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('error', 'post not found',
            'ok', 0, 'status', 'not_found');
        RETURN;
    END IF;
    DELETE FROM public.post_reactions r
    WHERE r.post_id = target.post_id AND r.user_id = liker AND r.reaction = kind;
    GET DIAGNOSTICS removed = ROW_COUNT;
    IF removed = 1 THEN
        PERFORM api.core_record_event_v1(api.core_community_reaction_event_v1(p_row,
            'post.unreacted', target.thread_id, target.author_user_id),
            p_row ->> 'outbox_id');
    END IF;
    SELECT count(*) INTO total FROM public.post_reactions r
    WHERE r.post_id = target.post_id AND r.reaction = kind;
    RETURN QUERY SELECT jsonb_build_object('changed', removed,
        'reaction', kind, 'reaction_count', total, 'reacted', 0, 'ok', 1,
        'post_id', target.post_id,
        'thread_id', target.thread_id, 'user_id', liker);
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_post_v1(jsonb) FROM PUBLIC;

-- Takes back a member's reaction on a post as an idempotent command: the
-- command log first, then the work, then the answer stored.
CREATE FUNCTION api.community_unreact_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved FROM api.community_unreact_post_v1(p_row);
        answer := api.core_community_reaction_answer_v1(saved);
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_unreact_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

COMMIT;
