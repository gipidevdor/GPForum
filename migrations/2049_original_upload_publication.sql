-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Rights-attested originals need no separate staff decision. Malware scans
-- and checksum withdrawal remain independent publication gates.
CREATE FUNCTION api.attachment_review_submit_v3(
    p_attachment_id uuid, p_source_kind text, p_source_url text
)
RETURNS TABLE (submitted boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    INSERT INTO public.attachment_content_reviews
        (attachment_id, source_kind, source_url, status, reason)
    VALUES (p_attachment_id, p_source_kind, p_source_url,
        CASE WHEN p_source_kind = 'original' THEN 'approved' ELSE 'pending' END,
        CASE WHEN p_source_kind = 'original'
            THEN 'Original content attested by its uploader; no staff review required'
            ELSE '' END);
    IF p_source_kind <> 'original' THEN
        UPDATE public.attachments SET state = 'quarantined', quarantined_at = now()
            WHERE attachment_id = p_attachment_id AND state = 'available';
    END IF;
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_submit_v3(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.attachment_review_submit_v4(
    p_attachment_id uuid, p_source_kind text, p_source_url text
)
RETURNS TABLE (submitted boolean)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_review_submit_v3(
    p_attachment_id, p_source_kind, p_source_url) $$;
REVOKE EXECUTE ON FUNCTION api.attachment_review_submit_v4(uuid, text, text) FROM PUBLIC;

-- Adopt the policy for originals already waiting, retaining every rejection,
-- blocked checksum, scan result and deletion. Resume previously handled media
-- work with a fresh event; no staff reviewer is fabricated.
DO $$
DECLARE
    original record;
    published uuid;
    event_id uuid;
BEGIN
    FOR original IN
        UPDATE public.attachment_content_reviews r SET status = 'approved',
            reason = 'Original content attested by its uploader; no staff review required'
        FROM public.attachments a
        WHERE a.attachment_id = r.attachment_id AND r.source_kind = 'original'
            AND r.status = 'pending' AND a.deleted_at IS NULL
            AND a.state <> 'deleted' AND NOT EXISTS (
                SELECT 1 FROM public.attachment_content_blocks b WHERE b.checksum = a.checksum)
        RETURNING a.attachment_id, a.scan_status
    LOOP
        IF original.scan_status <> 'clean' THEN CONTINUE; END IF;
        UPDATE public.attachments SET state = 'available', quarantined_at = NULL
            WHERE attachment_id = original.attachment_id AND state = 'quarantined'
                AND scan_status = 'clean' AND deleted_at IS NULL
            RETURNING attachment_id INTO published;
        IF NOT FOUND THEN CONTINUE; END IF;
        event_id := api.core_uuid_v7_v1();
        PERFORM api.ops_record_event_v2(jsonb_build_object(
            'event_id', event_id, 'event_type', 'attachment.content.approved',
            'schema_version', 1, 'aggregate_type', 'attachment',
            'aggregate_id', published, 'aggregate_version', 1,
            'actor_id', NULL, 'correlation_id', event_id,
            'idempotency_key', 'original-upload-policy:' || published::text,
            'created_at', now(),
            'payload', jsonb_build_object('attachment_id', published, 'scan_status', 'clean'),
            'metadata', jsonb_build_object('decision_kind', 'original_attestation')),
            api.core_uuid_v7_v1()::text, NULL::jsonb, false);
    END LOOP;
END;
$$;

COMMIT;
