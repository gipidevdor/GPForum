-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A member may say a few words about themselves on their public profile
-- (PB-13): plain text, up to 500 characters, empty by default. The identity
-- update takes the column; erasure clears it with the rest of the account;
-- a member's export carries it under profile. New versions, as ADR 0126
-- section 2 asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS bio text NOT NULL DEFAULT '',
    ADD CONSTRAINT users_bio_length_check CHECK (char_length(bio) <= 500);

CREATE FUNCTION api.identity_update_user_v3(p_user_id uuid, p_changes jsonb)
RETURNS SETOF public.users
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_changes - ARRAY['bio', 'password_hash', 'updated_at', 'email_normalized', 'email_verified_at', 'status', 'preferred_locale', 'preferred_theme', 'preferred_timezone'] <> '{}'::jsonb THEN
        RAISE EXCEPTION 'unsupported identity user update' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY UPDATE public.users u SET
        password_hash = CASE WHEN p_changes ? 'password_hash' THEN (p_changes->>'password_hash')::text ELSE u.password_hash END,
        updated_at = CASE WHEN p_changes ? 'updated_at' THEN (p_changes->>'updated_at')::timestamptz ELSE u.updated_at END,
        email_normalized = CASE WHEN p_changes ? 'email_normalized' THEN (p_changes->>'email_normalized')::text ELSE u.email_normalized END,
        email_verified_at = CASE WHEN p_changes ? 'email_verified_at' THEN (p_changes->>'email_verified_at')::timestamptz ELSE u.email_verified_at END,
        status = CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE u.status END,
        preferred_locale = CASE WHEN p_changes ? 'preferred_locale' THEN (p_changes->>'preferred_locale')::text ELSE u.preferred_locale END,
        preferred_theme = CASE WHEN p_changes ? 'preferred_theme' THEN (p_changes->>'preferred_theme')::text ELSE u.preferred_theme END,
        preferred_timezone = CASE WHEN p_changes ? 'preferred_timezone' THEN (p_changes->>'preferred_timezone')::text ELSE u.preferred_timezone END,
        bio = CASE WHEN p_changes ? 'bio' THEN (p_changes->>'bio')::text ELSE u.bio END
    WHERE u.id = p_user_id RETURNING u.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v3(uuid, jsonb) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.identity_update_user_v4(
p_user_id uuid, p_changes jsonb
)
RETURNS SETOF public.users
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_update_user_v3(p_user_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v4(uuid, jsonb) FROM PUBLIC;

-- Erasure writes the account's bio away with the rest of its words: the
-- shipped update ignores a column it does not know, so this one writes
-- the bio first and hands the other changes on.
CREATE FUNCTION api.privacy_update_v3(p_source text, p_id uuid,
    p_changes jsonb)
RETURNS TABLE (document json)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_source = 'User' AND p_changes ? 'bio' THEN
        UPDATE public.users u SET bio = (p_changes ->> 'bio')::text
        WHERE u.id = p_id;
    END IF;
    RETURN QUERY SELECT * FROM api.privacy_update_v1(p_source, p_id,
        p_changes - 'bio');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_update_v3(text, uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.privacy_update_v4(
p_source text, p_id uuid, p_changes jsonb
)
RETURNS TABLE (document json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_update_v3(p_source, p_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_update_v4(text, uuid, jsonb)
    FROM PUBLIC;

-- A member's export carries their bio under profile.
CREATE FUNCTION api.portability_export_parts_v7(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_set(previous.document::jsonb, '{profile,bio}',
    to_jsonb(coalesce((SELECT u.bio FROM public.users u
        WHERE u.id = p_user_id), '')), true)::json
FROM api.portability_export_parts_v5(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v7(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v8(
p_user_id uuid
)
RETURNS TABLE (document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v7(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v8(uuid) FROM PUBLIC;

COMMIT;
