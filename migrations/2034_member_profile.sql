-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- Public profile fields only. Account ownership is supplied by the session.
CREATE FUNCTION api.identity_update_profile_v1(
    p_user_id uuid, p_display_name text, p_bio text
)
RETURNS TABLE (display_name text, bio text)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
UPDATE public.users u
SET display_name = p_display_name, bio = p_bio, updated_at = now()
WHERE u.id = p_user_id AND u.status = 'active' AND u.deleted_at IS NULL
  AND char_length(btrim(p_display_name)) BETWEEN 1 AND 100
  AND p_display_name !~ '[[:cntrl:]]' AND char_length(p_bio) <= 500
  AND NOT EXISTS (
      SELECT 1 FROM public.suspensions s
      WHERE s.user_id = u.id AND s.revoked_at IS NULL
        AND s.valid_from <= now() AND (s.valid_to IS NULL OR s.valid_to > now())
  )
RETURNING u.display_name, u.bio;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_profile_v1(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_update_profile_v2(
    p_user_id uuid, p_display_name text, p_bio text
)
RETURNS TABLE (display_name text, bio text)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_update_profile_v1(p_user_id, p_display_name, p_bio);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_profile_v2(uuid, text, text) FROM PUBLIC;
COMMIT;
