-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- A handler claim names the worker run that holds it. Without an owner, a
-- worker whose handler outlived the lease and then failed released the claim
-- the worker that took it over was still running under, and a third worker
-- could start the same side effect. A failure now releases only its own
-- claim; a completion still records the event as handled whoever holds it,
-- because the side effect has happened. v1/v2 stay for workers from the
-- preceding release.
ALTER TABLE public.event_idempotency_keys ADD COLUMN claim_token uuid;
COMMENT ON COLUMN public.event_idempotency_keys.claim_token IS 'The worker run holding the claim: set by a claim or a takeover, and the only run whose failure releases it.';

CREATE FUNCTION api.ops_event_claim_v3(
    p_operation text,
    p_key text,
    p_event_id text,
    p_now text,
    p_expired_before text,
    p_token uuid
)
RETURNS TABLE (claimed boolean)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE reported text; affected integer;
BEGIN
    IF p_operation = 'is_done' THEN
        RETURN QUERY SELECT EXISTS(SELECT 1 FROM public.event_idempotency_keys me
            WHERE me.idempotency_key = p_key AND me.completed_at IS NOT NULL); RETURN;
    ELSIF p_operation = 'failed' THEN
        DELETE FROM public.event_idempotency_keys me
        WHERE me.idempotency_key = p_key AND me.completed_at IS NULL
          AND me.claim_token IS NOT DISTINCT FROM p_token;
        GET DIAGNOSTICS affected = ROW_COUNT;
        RETURN QUERY SELECT affected > 0; RETURN;
    ELSIF p_operation = 'done' THEN
        UPDATE public.event_idempotency_keys me SET completed_at = p_now::timestamptz
        WHERE me.idempotency_key = p_key AND me.completed_at IS NULL;
        IF FOUND THEN RETURN QUERY SELECT true; RETURN; END IF;
        BEGIN
            INSERT INTO public.event_idempotency_keys(idempotency_key,event_id,created_at,completed_at,claim_token)
            VALUES (p_key,p_event_id::uuid,p_now::timestamptz,p_now::timestamptz,p_token);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported,'event_idempotency_keys_pkey') THEN RAISE; END IF;
        END;
        RETURN QUERY SELECT true; RETURN;
    ELSIF p_operation <> 'begin' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',MESSAGE = 'unknown event claim operation';
    END IF;
    IF p_token IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023',MESSAGE = 'an event claim needs its token';
    END IF;
    BEGIN
        INSERT INTO public.event_idempotency_keys(idempotency_key,event_id,created_at,completed_at,claim_token)
        VALUES (p_key,p_event_id::uuid,p_now::timestamptz,NULL,p_token);
        RETURN QUERY SELECT true; RETURN;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'event_idempotency_keys_pkey') THEN RAISE; END IF;
    END;
    UPDATE public.event_idempotency_keys me
    SET created_at = p_now::timestamptz, claim_token = p_token
    WHERE me.idempotency_key = p_key AND me.completed_at IS NULL
      AND me.created_at < p_expired_before::timestamptz;
    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN QUERY SELECT affected > 0;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_event_claim_v3(p_operation text, p_key text, p_event_id text, p_now text, p_expired_before text, p_token uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_event_claim_v4(
    p_operation text,
    p_key text,
    p_event_id text,
    p_now text,
    p_expired_before text,
    p_token uuid
)
RETURNS TABLE (claimed boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_event_claim_v3(p_operation, p_key, p_event_id, p_now, p_expired_before, p_token);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_event_claim_v4(p_operation text, p_key text, p_event_id text, p_now text, p_expired_before text, p_token uuid) FROM PUBLIC;
COMMIT;
