-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.attachment_find_v1(p_attachment_id uuid, p_object_key text, p_hold boolean)
RETURNS SETOF public.attachments
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_attachment_id IS NOT NULL THEN
        IF p_hold THEN
            RETURN QUERY SELECT a.* FROM public.attachments a WHERE a.attachment_id = p_attachment_id FOR UPDATE;
        ELSE
            RETURN QUERY SELECT a.* FROM public.attachments a WHERE a.attachment_id = p_attachment_id;
        END IF;
    ELSE
        RETURN QUERY SELECT a.* FROM public.attachments a WHERE a.object_key = p_object_key LIMIT 1;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_find_v1(uuid, text, boolean) FROM PUBLIC;

CREATE FUNCTION api.attachment_links_v1(p_attachment_id uuid, p_target_type text, p_target_id uuid, p_post_ids uuid[], p_row_limit integer)
RETURNS SETOF public.attachment_links
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_post_ids IS NOT NULL THEN
        RETURN QUERY SELECT l.* FROM public.attachment_links l WHERE l.target_type = p_target_type AND l.target_id = ANY(p_post_ids) LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT l.* FROM public.attachment_links l WHERE l.attachment_id = p_attachment_id
        AND (p_target_type IS NULL OR l.target_type = p_target_type) AND (p_target_id IS NULL OR l.target_id = p_target_id) LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_links_v1(uuid, text, uuid, uuid[], integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_variants_v1(p_attachment_id uuid, p_variant_type text, p_object_key text, p_row_limit integer)
RETURNS SETOF public.attachment_variants
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    IF p_object_key IS NOT NULL THEN
        RETURN QUERY SELECT v.* FROM public.attachment_variants v WHERE v.object_key = p_object_key LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT v.* FROM public.attachment_variants v WHERE v.attachment_id = p_attachment_id
        AND (p_variant_type IS NULL OR v.variant_type = p_variant_type) LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variants_v1(uuid, text, text, integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_insert_v1(p_values jsonb)
RETURNS SETOF public.attachments
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.attachments (attachment_id, owner_user_id, object_key, original_filename, media_type, byte_size, checksum, state, scan_status, created_at, uploaded_at, scanned_at, quarantined_at, scan_engine, scan_signature, scan_attempts, scan_error, deleted_at) SELECT r.attachment_id, r.owner_user_id, r.object_key, r.original_filename, r.media_type, r.byte_size, r.checksum, r.state, r.scan_status, r.created_at, r.uploaded_at, r.scanned_at, r.quarantined_at, r.scan_engine, r.scan_signature, r.scan_attempts, r.scan_error, r.deleted_at FROM jsonb_populate_record(NULL::public.attachments,p_values) r RETURNING *;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_link_insert_v1(p_values jsonb)
RETURNS SETOF public.attachment_links
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.attachment_links (attachment_link_id, attachment_id, target_id, target_type, created_at) SELECT r.attachment_link_id, r.attachment_id, r.target_id, r.target_type, r.created_at FROM jsonb_populate_record(NULL::public.attachment_links,p_values) r RETURNING *;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_link_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_variant_insert_v1(p_values jsonb)
RETURNS SETOF public.attachment_variants
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY INSERT INTO public.attachment_variants (attachment_variant_id, attachment_id, variant_type, object_key, media_type, byte_size, created_at) SELECT r.attachment_variant_id, r.attachment_id, r.variant_type, r.object_key, r.media_type, r.byte_size, r.created_at FROM jsonb_populate_record(NULL::public.attachment_variants,p_values) r RETURNING *;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_variant_insert_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_update_v1(p_attachment_id uuid, p_changes jsonb)
RETURNS SETOF public.attachments
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY UPDATE public.attachments a SET
      state = CASE WHEN p_changes ? 'state' THEN p_changes->>'state' ELSE a.state END,
      uploaded_at = CASE WHEN p_changes ? 'uploaded_at' THEN (p_changes->>'uploaded_at')::timestamptz ELSE a.uploaded_at END,
      deleted_at = CASE WHEN p_changes ? 'deleted_at' THEN (p_changes->>'deleted_at')::timestamptz ELSE a.deleted_at END
    WHERE a.attachment_id = p_attachment_id RETURNING a.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_update_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_verdict_v1(p_attachment_id uuid, p_changes jsonb)
RETURNS TABLE(changed_count bigint)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
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
REVOKE EXECUTE ON FUNCTION api.attachment_scan_verdict_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_queue_v1(p_pending boolean, p_row_limit integer)
RETURNS TABLE(attachment_id uuid)
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
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
REVOKE EXECUTE ON FUNCTION api.attachment_scan_queue_v1(boolean, integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_confirm_clean_v1(p_attachment_id uuid, p_scan_engine text, p_scanned_at timestamptz)
RETURNS TABLE(changed_count bigint)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY WITH changed AS (
      UPDATE public.attachments a SET scan_engine = p_scan_engine, scan_error = NULL, scanned_at = p_scanned_at
      WHERE a.attachment_id = p_attachment_id AND a.deleted_at IS NULL AND a.scan_status = 'clean'
      AND (a.scan_engine IS NULL OR a.scan_engine = 'format-check') RETURNING 1
    ) SELECT count(*) FROM changed;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_confirm_clean_v1(uuid, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.attachment_scan_failure_v1(p_attachment_id uuid, p_error text)
RETURNS TABLE(changed_count bigint)
LANGUAGE plpgsql VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY WITH changed AS (
      UPDATE public.attachments a SET scan_attempts = a.scan_attempts + 1, scan_error = left(p_error,500)
      WHERE a.attachment_id = p_attachment_id RETURNING 1
    ) SELECT count(*) FROM changed;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_scan_failure_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.attachment_orphans_v1(p_cutoff timestamptz, p_row_limit integer)
RETURNS SETOF public.attachments
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT a.* FROM public.attachments a WHERE a.state = 'intent' AND a.created_at <= p_cutoff
    AND NOT EXISTS (SELECT 1 FROM public.attachment_links l WHERE l.attachment_id = a.attachment_id)
    ORDER BY a.created_at ASC LIMIT p_row_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_orphans_v1(timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_post_v1(p_target_id uuid)
RETURNS SETOF public.posts
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT a.* FROM public.posts a WHERE a.post_id = p_target_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_post_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_source_thread_v1(p_target_id uuid)
RETURNS SETOF public.threads
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
    RETURN QUERY SELECT a.* FROM public.threads a WHERE a.thread_id = p_target_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_source_thread_v1(uuid) FROM PUBLIC;

COMMIT;
