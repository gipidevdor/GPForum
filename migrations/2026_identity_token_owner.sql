-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Account operations find the owner without holding a token lock, then
-- lock the credential before consuming the token and updating the account.
CREATE FUNCTION api.identity_token_user_v1(
    p_token_hash text,
    p_token_type text
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.user_id FROM public.identity_tokens t
    WHERE t.token_hash = p_token_hash AND t.token_type = p_token_type;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_token_user_v1(p_token_hash text, p_token_type text) FROM PUBLIC;

CREATE FUNCTION api.identity_token_user_v2(
    p_token_hash text,
    p_token_type text
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_token_user_v1(p_token_hash, p_token_type);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_token_user_v2(p_token_hash text, p_token_type text) FROM PUBLIC;

COMMIT;
