-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- Private metadata for the author's upload screen. No bytes or storage keys.
CREATE FUNCTION api.attachment_owned_post_files_v1(
    p_post_id uuid, p_actor_id uuid, p_after_id uuid
)
RETURNS TABLE (
    link_id uuid, created_at timestamptz, attachment_id uuid,
    original_filename text, media_type text, byte_size bigint,
    state text, scan_status text, content_status text, reason text
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT l.attachment_link_id, l.created_at, a.attachment_id,
    a.original_filename, a.media_type, a.byte_size, a.state, a.scan_status,
    COALESCE(r.status, 'pending'), COALESCE(r.reason, '')
FROM public.attachment_links l
JOIN public.posts p ON p.post_id = l.target_id
JOIN public.attachments a ON a.attachment_id = l.attachment_id
LEFT JOIN public.attachment_content_reviews r ON r.attachment_id = a.attachment_id
WHERE l.target_type = 'post' AND l.target_id = p_post_id
  AND p.author_user_id = p_actor_id AND p.deleted_at IS NULL
  AND a.owner_user_id = p_actor_id AND a.deleted_at IS NULL
  AND (p_after_id IS NULL OR (l.created_at, l.attachment_link_id) < (
      SELECT c.created_at, c.attachment_link_id FROM public.attachment_links c
      WHERE c.attachment_link_id = p_after_id AND c.target_type = 'post'
        AND c.target_id = p_post_id
  ))
ORDER BY l.created_at DESC, l.attachment_link_id DESC LIMIT 51;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_owned_post_files_v1(uuid, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_owned_post_files_v2(
    p_post_id uuid, p_actor_id uuid, p_after_id uuid
)
RETURNS TABLE (
    link_id uuid, created_at timestamptz, attachment_id uuid,
    original_filename text, media_type text, byte_size bigint,
    state text, scan_status text, content_status text, reason text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.attachment_owned_post_files_v1(p_post_id, p_actor_id, p_after_id);
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_owned_post_files_v2(uuid, uuid, uuid) FROM PUBLIC;
COMMIT;
