-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- An erased member's single-use tokens -- a password reset, an email change
-- with the new address in it, a verification -- stayed in identity_tokens
-- until they expired and the retention purge took them, so the address the
-- erasure removed from the account lived on in them for up to a day. The
-- erasure now deletes the member's tokens with their credentials
-- (Service::Privacy::DeletionWorkflow, source IdentityToken). v24, the
-- boundary the previous release's workers call, stays until a release later
-- (ADR 0126, section 2).
CREATE FUNCTION api.privacy_revoke_user_v25(p_source text, p_user_id uuid, p_at text)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'IdentityToken' THEN
        DELETE FROM public.identity_tokens t WHERE t.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE RETURN QUERY SELECT * FROM api.privacy_revoke_user_v23(p_source,p_user_id,p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v25(text, uuid, text) FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.privacy_revoke_user_v26(p_source text, p_user_id uuid, p_at text)
RETURNS TABLE (revoked bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v25(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v26(text, uuid, text) FROM PUBLIC;
