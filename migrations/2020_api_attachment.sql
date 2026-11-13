-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: api attachment.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.attachment_post_files_v1(
    p_target_type text,
    p_post_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    file_owner_user_id uuid,
    file_object_key text,
    file_original_filename text,
    file_media_type text,
    file_byte_size bigint,
    file_state text,
    file_scan_status text,
    file_deleted_at timestamptz,
    post_thread_id uuid,
    post_author_user_id uuid,
    post_visibility text,
    post_moderation_state text,
    post_hidden_at timestamptz,
    post_deleted_at timestamptz,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_id uuid,
    category_visibility text,
    category_deleted_at timestamptz,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT a.attachment_link_id, a.attachment_id, a.target_type, a.target_id,
    a.created_at,
    f.owner_user_id, f.object_key, f.original_filename, f.media_type,
    f.byte_size, f.state, f.scan_status, f.deleted_at,
    p.thread_id, p.author_user_id, p.visibility, p.moderation_state,
    p.hidden_at, p.deleted_at,
    t.author_user_id, t.visibility, t.deleted_at, t.moderation_state,
    c.category_id, c.visibility, c.deleted_at, c.space_id, s.visibility
FROM (
    SELECT al.* FROM public.attachment_links al
    WHERE al.target_type = p_target_type
        AND al.target_id = ANY(p_post_ids)
    ORDER BY al.target_id, al.created_at, al.attachment_link_id
    LIMIT p_row_limit
) a
JOIN public.attachments f ON f.attachment_id = a.attachment_id
JOIN public.posts p ON p.post_id = a.target_id
JOIN public.threads t ON t.thread_id = p.thread_id
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
ORDER BY a.target_id, a.created_at, a.attachment_link_id
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_post_files_v1(p_target_type text, p_post_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_find_v3(
    p_attachment_id uuid,
    p_object_key text,
    p_hold boolean
)
RETURNS SETOF api.attachment_file_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_attachment_id IS NOT NULL THEN
        IF p_hold THEN
            RETURN QUERY SELECT a.attachment_id, a.owner_user_id,
                a.object_key, a.original_filename, a.media_type, a.byte_size,
                a.checksum, a.state, a.scan_status, a.created_at,
                a.uploaded_at, a.scanned_at, a.quarantined_at, a.deleted_at,
                a.scan_engine, a.scan_signature, a.scan_attempts, a.scan_error
            FROM public.attachments a WHERE a.attachment_id = p_attachment_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT a.attachment_id, a.owner_user_id,
                a.object_key, a.original_filename, a.media_type, a.byte_size,
                a.checksum, a.state, a.scan_status, a.created_at,
                a.uploaded_at, a.scanned_at, a.quarantined_at, a.deleted_at,
                a.scan_engine, a.scan_signature, a.scan_attempts, a.scan_error
            FROM public.attachments a WHERE a.attachment_id = p_attachment_id;
        END IF;
    ELSE
        RETURN QUERY SELECT a.attachment_id, a.owner_user_id, a.object_key,
            a.original_filename, a.media_type, a.byte_size, a.checksum,
            a.state, a.scan_status, a.created_at, a.uploaded_at, a.scanned_at,
            a.quarantined_at, a.deleted_at, a.scan_engine, a.scan_signature,
            a.scan_attempts, a.scan_error
        FROM public.attachments a WHERE a.object_key = p_object_key LIMIT 1;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_find_v3(p_attachment_id uuid, p_object_key text, p_hold boolean) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_post_v3(p_target_id uuid)
RETURNS SETOF api.forum_post_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY SELECT a.post_id, a.thread_id, a.author_user_id,
        a.current_body_id, a.current_revision_id, a."position", a.visibility,
        a.moderation_state, a.version, a.visibility_version,
        a.permission_version, a.created_at, a.updated_at, a.hidden_at,
        a.locked_at, a.deleted_at, a.deleted_by
    FROM public.posts a WHERE a.post_id = p_target_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_post_v3(p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_thread_v3(p_target_id uuid)
RETURNS SETOF api.forum_thread_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY SELECT a.thread_id, a.category_id, a.author_user_id, a.title,
        a.slug, a.pinned, a.visibility, a.moderation_state, a.locked_at,
        a.last_activity_at, a.version, a.visibility_version,
        a.permission_version, a.created_at, a.updated_at, a.deleted_at,
        a.deleted_by FROM public.threads a WHERE a.thread_id = p_target_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_thread_v3(p_target_id uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_variants_v3(
    p_attachment_id uuid,
    p_variant_type text,
    p_object_key text,
    p_row_limit integer
)
RETURNS SETOF api.attachment_variant_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_object_key IS NOT NULL THEN
        RETURN QUERY SELECT v.attachment_variant_id, v.attachment_id,
            v.variant_type, v.object_key, v.media_type, v.byte_size,
            v.created_at
        FROM public.attachment_variants v WHERE v.object_key = p_object_key LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT v.attachment_variant_id, v.attachment_id,
            v.variant_type, v.object_key, v.media_type, v.byte_size,
            v.created_at
        FROM public.attachment_variants v WHERE v.attachment_id = p_attachment_id
        AND (p_variant_type IS NULL OR v.variant_type = p_variant_type) LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variants_v3(p_attachment_id uuid, p_variant_type text, p_object_key text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_update_v3(
    p_attachment_id uuid,
    p_changes jsonb
)
RETURNS SETOF api.attachment_file_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.attachments a SET
      state = CASE WHEN p_changes ? 'state' THEN p_changes->>'state' ELSE a.state END,
      uploaded_at = CASE WHEN p_changes ? 'uploaded_at' THEN (p_changes->>'uploaded_at')::timestamptz ELSE a.uploaded_at END,
      deleted_at = CASE WHEN p_changes ? 'deleted_at' THEN (p_changes->>'deleted_at')::timestamptz ELSE a.deleted_at END
    WHERE a.attachment_id = p_attachment_id RETURNING a.attachment_id,
        a.owner_user_id, a.object_key, a.original_filename, a.media_type,
        a.byte_size, a.checksum, a.state, a.scan_status, a.created_at,
        a.uploaded_at, a.scanned_at, a.quarantined_at, a.deleted_at,
        a.scan_engine, a.scan_signature, a.scan_attempts, a.scan_error;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_update_v3(p_attachment_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_insert_v3(p_values jsonb)
RETURNS SETOF api.attachment_file_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.attachments (attachment_id, owner_user_id, object_key, original_filename, media_type, byte_size, checksum, state, scan_status, created_at, uploaded_at, scanned_at, quarantined_at, scan_engine, scan_signature, scan_attempts, scan_error, deleted_at) SELECT r.attachment_id, r.owner_user_id, r.object_key, r.original_filename, r.media_type, r.byte_size, r.checksum, r.state, r.scan_status, r.created_at, r.uploaded_at, r.scanned_at, r.quarantined_at, r.scan_engine, r.scan_signature, r.scan_attempts, r.scan_error, r.deleted_at FROM jsonb_populate_record(NULL::public.attachments,p_values) r RETURNING
        attachment_id, owner_user_id, object_key, original_filename,
        media_type, byte_size, checksum, state, scan_status, created_at,
        uploaded_at, scanned_at, quarantined_at, deleted_at, scan_engine,
        scan_signature, scan_attempts, scan_error;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_insert_v3(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_link_insert_v3(p_values jsonb)
RETURNS SETOF api.attachment_link_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.attachment_links (attachment_link_id, attachment_id, target_id, target_type, created_at) SELECT r.attachment_link_id, r.attachment_id, r.target_id, r.target_type, r.created_at FROM jsonb_populate_record(NULL::public.attachment_links,p_values) r RETURNING
        attachment_link_id, attachment_id, target_type, target_id, created_at;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_link_insert_v3(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_variant_insert_v3(p_values jsonb)
RETURNS SETOF api.attachment_variant_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.attachment_variants (attachment_variant_id, attachment_id, variant_type, object_key, media_type, byte_size, created_at) SELECT r.attachment_variant_id, r.attachment_id, r.variant_type, r.object_key, r.media_type, r.byte_size, r.created_at FROM jsonb_populate_record(NULL::public.attachment_variants,p_values) r RETURNING
        attachment_variant_id, attachment_id, variant_type, object_key,
        media_type, byte_size, created_at;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variant_insert_v3(p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_confirm_clean_v3(
    p_attachment_id uuid,
    p_scan_engine text,
    p_scanned_at timestamptz
)
RETURNS TABLE (changed_count bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY WITH changed AS (
      UPDATE public.attachments a SET scan_engine = p_scan_engine, scan_error = NULL, scanned_at = p_scanned_at
      WHERE a.attachment_id = p_attachment_id AND a.deleted_at IS NULL AND a.scan_status = 'clean'
      AND (a.scan_engine IS NULL OR a.scan_engine = 'format-check') RETURNING 1
    ) SELECT count(*) FROM changed;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_confirm_clean_v3(p_attachment_id uuid, p_scan_engine text, p_scanned_at timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.attachment_orphans_v3(
    p_cutoff timestamptz,
    p_row_limit integer
)
RETURNS SETOF api.attachment_file_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY SELECT a.attachment_id, a.owner_user_id, a.object_key,
        a.original_filename, a.media_type, a.byte_size, a.checksum, a.state,
        a.scan_status, a.created_at, a.uploaded_at, a.scanned_at,
        a.quarantined_at, a.deleted_at, a.scan_engine, a.scan_signature,
        a.scan_attempts, a.scan_error
    FROM public.attachments a WHERE a.state = 'intent' AND a.created_at <= p_cutoff
    AND NOT EXISTS (SELECT 1 FROM public.attachment_links l WHERE l.attachment_id = a.attachment_id)
    ORDER BY a.created_at ASC LIMIT p_row_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_orphans_v3(p_cutoff timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_failure_v3(
    p_attachment_id uuid,
    p_error text
)
RETURNS TABLE (changed_count bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY WITH changed AS (
      UPDATE public.attachments a SET scan_attempts = a.scan_attempts + 1, scan_error = left(p_error,500)
      WHERE a.attachment_id = p_attachment_id RETURNING 1
    ) SELECT count(*) FROM changed;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_failure_v3(p_attachment_id uuid, p_error text) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_queue_v3(
    p_pending boolean,
    p_row_limit integer
)
RETURNS TABLE (attachment_id uuid)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_pending THEN
        RETURN QUERY SELECT a.attachment_id FROM public.attachments a WHERE a.deleted_at IS NULL AND a.state = 'uploaded' AND a.scan_status = 'pending'
        ORDER BY a.scan_attempts ASC, a.uploaded_at ASC, a.attachment_id ASC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.attachment_id FROM public.attachments a WHERE a.deleted_at IS NULL AND a.state = 'available' AND a.scan_status = 'clean'
        AND (a.scan_engine IS NULL OR a.scan_engine = 'format-check')
        ORDER BY a.scan_attempts ASC, a.created_at ASC, a.attachment_id ASC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_queue_v3(p_pending boolean, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_verdict_v3(
    p_attachment_id uuid,
    p_changes jsonb
)
RETURNS TABLE (changed_count bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    RETURN QUERY WITH changed AS (
      UPDATE public.attachments a SET scanned_at = (p_changes->>'scanned_at')::timestamptz,
        scan_status = p_changes->>'scan_status', scan_engine = p_changes->>'scan_engine', scan_error = NULL,
        scan_signature = p_changes->>'scan_signature', state = p_changes->>'state',
        quarantined_at = CASE WHEN p_changes ? 'quarantined_at' THEN (p_changes->>'quarantined_at')::timestamptz ELSE a.quarantined_at END
      WHERE a.attachment_id = p_attachment_id AND a.deleted_at IS NULL
      AND ((a.scan_status = 'pending' AND a.state = 'uploaded') OR
           (p_changes->>'scan_status' <> 'clean' AND a.scan_status = 'clean' AND a.state = 'available'))
      RETURNING 1
    ) SELECT count(*) FROM changed;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_verdict_v3(p_attachment_id uuid, p_changes jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_links_v5(
    p_attachment_id uuid,
    p_target_type text,
    p_target_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.attachment_link_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT l.attachment_link_id, l.attachment_id, l.target_type, l.target_id,
    l.created_at
FROM public.attachment_links l
WHERE l.attachment_id = p_attachment_id
    AND (p_target_type IS NULL OR l.target_type = p_target_type)
    AND (p_target_id IS NULL OR l.target_id = p_target_id)
LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_links_v5(p_attachment_id uuid, p_target_type text, p_target_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_create_v1(p_object_key text, p_byte_size bigint, p_checksum text)
RETURNS TABLE (created boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    INSERT INTO public.attachment_objects(object_key, attachment_id, byte_size, checksum)
        VALUES (p_object_key, coalesce(
            (SELECT a.attachment_id FROM public.attachments a WHERE a.object_key = p_object_key),
            (SELECT v.attachment_id FROM public.attachment_variants v WHERE v.object_key = p_object_key)
        ), p_byte_size, p_checksum) ON CONFLICT DO NOTHING;
    IF FOUND THEN RETURN QUERY SELECT true; RETURN; END IF;
    PERFORM 1 FROM public.attachment_objects o WHERE o.object_key = p_object_key
        AND o.byte_size = p_byte_size AND o.checksum = p_checksum AND o.complete
        FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'attachment object already holds different bytes' USING ERRCODE = '22023'; END IF;
    RETURN QUERY SELECT false;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_create_v1(p_object_key text, p_byte_size bigint, p_checksum text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_chunk_insert_v1(p_object_key text, p_chunk_number integer, p_data bytea)
RETURNS TABLE (written boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM 1 FROM public.attachment_objects o WHERE o.object_key = p_object_key
        AND NOT o.complete AND p_chunk_number >= 0
        AND octet_length(p_data) = least(1048576, o.byte_size - p_chunk_number::bigint * 1048576)
        FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid attachment chunk' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.attachment_object_chunks VALUES (p_object_key, p_chunk_number, p_data);
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_chunk_insert_v1(p_object_key text, p_chunk_number integer, p_data bytea) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_finish_v1(p_object_key text)
RETURNS TABLE (finished boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    UPDATE public.attachment_objects o SET complete = true
    FROM (SELECT count(*) AS chunks, sum(octet_length(c.data)) AS bytes
        FROM public.attachment_object_chunks c WHERE c.object_key = p_object_key) totals
    WHERE o.object_key = p_object_key AND NOT o.complete
        AND totals.chunks = (o.byte_size + 1048575) / 1048576
        AND totals.bytes = o.byte_size;
    IF NOT FOUND THEN RAISE EXCEPTION 'attachment object is incomplete' USING ERRCODE = '22023'; END IF;
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_finish_v1(p_object_key text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_info_v1(p_object_key text)
RETURNS TABLE (byte_size bigint, checksum text, modified_at double precision)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT o.byte_size, o.checksum, extract(epoch FROM o.created_at)::double precision
    FROM public.attachment_objects o WHERE o.object_key = p_object_key AND o.complete $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_info_v1(p_object_key text) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_chunk_v1(p_object_key text, p_chunk_number integer)
RETURNS TABLE (data bytea)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT c.data FROM public.attachment_object_chunks c
    JOIN public.attachment_objects o USING (object_key)
    WHERE c.object_key = p_object_key AND c.chunk_number = p_chunk_number AND o.complete $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_chunk_v1(p_object_key text, p_chunk_number integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_object_delete_v1(p_object_key text)
RETURNS TABLE (deleted boolean)
LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ WITH removed AS (DELETE FROM public.attachment_objects WHERE object_key = p_object_key RETURNING 1)
    SELECT EXISTS(SELECT 1 FROM removed) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_delete_v1(p_object_key text) FROM PUBLIC;

CREATE FUNCTION public.gpforum_attachment_object_owner()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    UPDATE public.attachment_objects SET attachment_id = NEW.attachment_id
        WHERE object_key = NEW.object_key
            AND (attachment_id IS NULL OR attachment_id = NEW.attachment_id);
    IF NOT FOUND AND EXISTS (SELECT 1 FROM public.attachment_objects WHERE object_key = NEW.object_key) THEN
        RAISE EXCEPTION 'binary object belongs to another attachment' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gpforum_attachment_object_owner() FROM PUBLIC;

CREATE FUNCTION public.gpforum_attachment_variant_object_delete()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    DELETE FROM public.attachment_objects o WHERE o.object_key = OLD.object_key
        AND NOT EXISTS (SELECT 1 FROM public.attachments a WHERE a.object_key = o.object_key)
        AND NOT EXISTS (SELECT 1 FROM public.attachment_variants v WHERE v.object_key = o.object_key);
    RETURN OLD;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gpforum_attachment_variant_object_delete() FROM PUBLIC;

CREATE FUNCTION api.attachment_object_import_candidates_v1(p_after_key text, p_row_limit integer)
RETURNS TABLE (object_key text, byte_size bigint, checksum text, attachment_id uuid)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT candidate.object_key, candidate.byte_size, candidate.checksum, candidate.attachment_id FROM (
    SELECT a.object_key, a.byte_size, a.checksum, a.attachment_id FROM public.attachments a
        WHERE a.deleted_at IS NULL AND a.state <> 'deleted'
    UNION ALL SELECT v.object_key, v.byte_size, NULL::text, v.attachment_id FROM public.attachment_variants v
        JOIN public.attachments a USING(attachment_id)
        WHERE a.deleted_at IS NULL AND a.state <> 'deleted'
    ) candidate
    WHERE candidate.object_key > coalesce(p_after_key, '')
        AND NOT EXISTS (SELECT 1 FROM public.attachment_objects o WHERE o.object_key = candidate.object_key AND o.complete)
    ORDER BY candidate.object_key LIMIT least(greatest(p_row_limit, 1), 100) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_object_import_candidates_v1(p_after_key text, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION public.gpforum_attachment_review_guard()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NEW.state = 'available' AND (EXISTS (
        SELECT 1 FROM public.attachment_content_reviews r
        WHERE r.attachment_id = NEW.attachment_id AND r.status <> 'approved'
    ) OR EXISTS (SELECT 1 FROM public.attachment_content_blocks b WHERE b.checksum = NEW.checksum)) THEN
        NEW.state := 'quarantined';
        NEW.quarantined_at := coalesce(NEW.quarantined_at, now());
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gpforum_attachment_review_guard() FROM PUBLIC;

CREATE FUNCTION api.attachment_review_submit_v1(p_attachment_id uuid, p_source_kind text, p_source_url text)
RETURNS TABLE (submitted boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    INSERT INTO public.attachment_content_reviews(attachment_id, source_kind, source_url)
        VALUES (p_attachment_id, p_source_kind, p_source_url);
    UPDATE public.attachments SET state = 'quarantined', quarantined_at = now()
        WHERE attachment_id = p_attachment_id AND state = 'available';
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_submit_v1(p_attachment_id uuid, p_source_kind text, p_source_url text) FROM PUBLIC;

CREATE FUNCTION api.attachment_content_blocked_v1(p_checksum text)
RETURNS TABLE (blocked boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT EXISTS(SELECT 1 FROM public.attachment_content_blocks b WHERE b.checksum = p_checksum) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_content_blocked_v1(p_checksum text) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_queue_v1(p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT jsonb_build_object('attachment_id', a.attachment_id,
    'original_filename', a.original_filename, 'media_type', a.media_type,
    'byte_size', a.byte_size, 'owner_user_id', a.owner_user_id,
    'source_kind', r.source_kind, 'source_url', r.source_url,
    'created_at', r.created_at, 'scan_status', a.scan_status,
    'author_username', u.username)
    FROM public.attachment_content_reviews r
    JOIN public.attachments a USING (attachment_id)
    JOIN public.users u ON u.id = a.owner_user_id
    WHERE r.status = 'pending' AND a.deleted_at IS NULL
        AND (p_after_at IS NULL OR (r.created_at, r.attachment_id) > (p_after_at, p_after_id))
    ORDER BY r.created_at, r.attachment_id LIMIT least(greatest(p_row_limit, 1), 51) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_queue_v1(p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_find_v1(p_attachment_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT jsonb_build_object('attachment_id', a.attachment_id,
    'object_key', a.object_key, 'media_type', a.media_type,
    'original_filename', a.original_filename, 'byte_size', a.byte_size,
    'checksum', a.checksum, 'scan_status', a.scan_status,
    'status', r.status, 'source_kind', r.source_kind, 'source_url', r.source_url)
    FROM public.attachment_content_reviews r JOIN public.attachments a USING (attachment_id)
    WHERE a.attachment_id = p_attachment_id AND a.deleted_at IS NULL $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_find_v1(p_attachment_id uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_decide_v1(p_attachment_id uuid, p_actor uuid, p_status text, p_reason text)
RETURNS TABLE (status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE file record; held record;
BEGIN
    IF p_status IS NULL OR p_status NOT IN ('approved', 'rejected') OR p_actor IS NULL
        OR length(btrim(coalesce(p_reason, ''))) NOT BETWEEN 1 AND 500 THEN
        RETURN QUERY SELECT 'invalid'::text; RETURN;
    END IF;
    -- Decisions on duplicate bytes share one lock before taking file locks,
    -- so simultaneous withdrawal/approval cannot deadlock across duplicates.
    PERFORM pg_advisory_xact_lock(2026110101, hashtext(a.checksum))
        FROM public.attachments a WHERE a.attachment_id = p_attachment_id;
    -- File then review is the same lock order as scan -> trigger -> review.
    SELECT a.owner_user_id, a.scan_status, a.checksum, a.deleted_at INTO file
        FROM public.attachments a WHERE a.attachment_id = p_attachment_id FOR UPDATE;
    IF NOT FOUND OR file.deleted_at IS NOT NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
    SELECT r.status INTO held FROM public.attachment_content_reviews r
        WHERE r.attachment_id = p_attachment_id FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
    IF held.status = p_status THEN RETURN QUERY SELECT 'unchanged'::text; RETURN; END IF;
    IF p_status = 'approved' AND (held.status = 'rejected' OR file.owner_user_id = p_actor
        OR file.scan_status <> 'clean' OR EXISTS (
            SELECT 1 FROM public.attachment_content_blocks b WHERE b.checksum = file.checksum
        )) THEN RETURN QUERY SELECT 'refused'::text; RETURN; END IF;
    UPDATE public.attachment_content_reviews SET status = p_status, reason = btrim(p_reason),
        reviewed_by = p_actor, reviewed_at = now() WHERE attachment_id = p_attachment_id;
    IF p_status = 'rejected' THEN
        INSERT INTO public.attachment_content_blocks(checksum, reason, blocked_by)
            VALUES (file.checksum, btrim(p_reason), p_actor) ON CONFLICT DO NOTHING;
        UPDATE public.attachments a SET state = 'quarantined', quarantined_at = now()
            WHERE a.checksum = file.checksum AND a.deleted_at IS NULL
                AND a.attachment_id <> p_attachment_id;
    END IF;
    UPDATE public.attachments SET
        state = CASE WHEN p_status = 'approved' THEN 'available' ELSE 'quarantined' END,
        quarantined_at = CASE WHEN p_status = 'approved' THEN NULL ELSE now() END
        WHERE attachment_id = p_attachment_id;
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_decide_v1(p_attachment_id uuid, p_actor uuid, p_status text, p_reason text) FROM PUBLIC;

COMMIT;
