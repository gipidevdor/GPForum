-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0142: two-step sign-in with a time-based one-time password (TOTP,
-- RFC 6238). A member turns it on from their security settings: the forum
-- draws a secret, keeps it sealed with a key from the settings file (the
-- database never holds it in the clear) and shows it as a QR code; the
-- first code the member's app gives confirms it, and ten single-use
-- recovery codes, kept as SHA-256 hashes, are shown once. A sign-in whose
-- password verifies opens a challenge instead of a session; a code, or a
-- recovery code, answers it within five minutes and five tries, and ten
-- wrong answers in an hour lock the account's challenges for that hour and
-- tell the member. A code is used once: the step it was accepted for is
-- kept, and no earlier or equal step is accepted again. Turning it off
-- takes the password and a code; the member is mailed when it is turned on
-- or off, when an administrator resets it, and when the lock trips. Staff
-- see whether a member has it, never the secret. An administrator may
-- require it of staff: then the staff consoles refuse a member without it.
-- Erasure deletes all of it; the export says whether it was on. New
-- versions, as ADR 0126 section 2 asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.second_factors (
    user_id uuid NOT NULL,
    state text NOT NULL,
    secret_sealed text NOT NULL,
    key_id text NOT NULL,
    last_step bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    confirmed_at timestamptz,
    updated_at timestamptz NOT NULL,
    CONSTRAINT second_factors_pkey PRIMARY KEY (user_id),
    CONSTRAINT second_factors_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT second_factors_state_check
        CHECK (state IN ('pending', 'active')),
    CONSTRAINT second_factors_confirmed_check
        CHECK ((state = 'active') = (confirmed_at IS NOT NULL)),
    CONSTRAINT second_factors_secret_sealed_check
        CHECK (length(secret_sealed) BETWEEN 1 AND 400),
    CONSTRAINT second_factors_key_id_check
        CHECK (length(key_id) BETWEEN 1 AND 64),
    CONSTRAINT second_factors_last_step_check CHECK (last_step >= 0)
);
-- Which secrets a key still seals: a key is retired once none is left.
CREATE INDEX idx_second_factors_key_id ON public.second_factors (key_id);

CREATE TABLE public.second_factor_recovery_codes (
    user_id uuid NOT NULL,
    code_hash text NOT NULL,
    created_at timestamptz NOT NULL,
    used_at timestamptz,
    CONSTRAINT second_factor_recovery_codes_pkey
        PRIMARY KEY (user_id, code_hash),
    CONSTRAINT second_factor_recovery_codes_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT second_factor_recovery_codes_code_hash_check
        CHECK (code_hash ~ '^[0-9a-f]{64}$')
);

-- A sign-in waiting for its second step: the token's hash (the token
-- itself is in the signed cookie only), the password credential that
-- verified, and the wrong answers it took.
CREATE TABLE public.second_factor_challenges (
    challenge_id uuid NOT NULL,
    token_hash text NOT NULL,
    user_id uuid NOT NULL,
    credential_id uuid NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    failed_attempts integer NOT NULL DEFAULT 0,
    closed_at timestamptz,
    CONSTRAINT second_factor_challenges_pkey PRIMARY KEY (challenge_id),
    CONSTRAINT second_factor_challenges_token_hash_key UNIQUE (token_hash),
    CONSTRAINT second_factor_challenges_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT second_factor_challenges_expiry_check
        CHECK (expires_at > created_at),
    CONSTRAINT second_factor_challenges_failed_attempts_check
        CHECK (failed_attempts >= 0)
);
CREATE INDEX idx_second_factor_challenges_user
    ON public.second_factor_challenges (user_id, created_at);

-- One row: whether staff must use two-step sign-in. No row is the
-- default, not required.
CREATE TABLE public.second_factor_policy (
    singleton boolean NOT NULL DEFAULT true,
    staff_required boolean NOT NULL,
    updated_by_user_id uuid,
    updated_at timestamptz NOT NULL,
    CONSTRAINT second_factor_policy_pkey PRIMARY KEY (singleton),
    CONSTRAINT second_factor_policy_singleton_check CHECK (singleton),
    CONSTRAINT second_factor_policy_updated_by_user_id_fkey
        FOREIGN KEY (updated_by_user_id) REFERENCES public.users (id)
        ON DELETE SET NULL
);

-- Staff: a member holding a role that grants anything besides reading a
-- category, which every staff console's permission is.
CREATE FUNCTION api.core_identity_is_staff_v1(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (SELECT 1 FROM public.role_bindings b
    JOIN public.role_permissions rp ON rp.role_id = b.role_id
    JOIN public.permissions p ON p.permission_id = rp.permission_id
    WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
        AND NOT (p.resource_type = 'category' AND p.action = 'read'))
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_is_staff_v1(uuid) FROM PUBLIC;

-- The policy requires two-step sign-in of staff and this member has none
-- turned on.
CREATE FUNCTION api.core_identity_second_factor_missing_v1(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce((SELECT p.staff_required FROM public.second_factor_policy p),
        false)
    AND NOT EXISTS (SELECT 1 FROM public.second_factors f
        WHERE f.user_id = p_user_id AND f.state = 'active')
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_second_factor_missing_v1(uuid)
    FROM PUBLIC;

-- The notice mail a change records: an identity.mail.requested event whose
-- outbox message names the kind, and the member's address and language
-- read here, so the caller never needs them.
CREATE FUNCTION api.core_identity_second_factor_mail_v1(p_user_id uuid,
    p_mail jsonb)
RETURNS void
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE member_row record;
BEGIN
    IF p_mail IS NULL THEN
        RETURN;
    END IF;
    SELECT u.email_normalized, u.preferred_locale INTO member_row
        FROM public.users u WHERE u.id = p_user_id;
    IF NOT FOUND OR member_row.email_normalized IS NULL THEN
        RETURN;
    END IF;
    PERFORM api.ops_record_event_v1(p_mail -> 'event',
        p_mail ->> 'outbox_id',
        jsonb_build_object('mail', coalesce(p_mail -> 'outbox_extras' -> 'mail',
            '{}'::jsonb) || jsonb_build_object(
                'to', member_row.email_normalized,
                'locale', member_row.preferred_locale)),
        false);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_second_factor_mail_v1(uuid,
    jsonb) FROM PUBLIC;

-- The member's two-step sign-in: off, pending (begun, not confirmed) or
-- active, the sealed secret for the forum to open, the recovery codes
-- left, and whether the policy requires it of them as staff.
CREATE FUNCTION api.identity_second_factor_status_v1(p_user_id uuid)
RETURNS TABLE(state text, secret_sealed text, key_id text, last_step bigint,
    confirmed_at timestamptz, recovery_left integer, staff boolean,
    staff_required boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(f.state, 'off'), f.secret_sealed, f.key_id,
    coalesce(f.last_step, 0), f.confirmed_at,
    (SELECT count(*)::integer FROM public.second_factor_recovery_codes c
        WHERE c.user_id = p_user_id AND c.used_at IS NULL
            AND f.state = 'active'),
    api.core_identity_is_staff_v1(p_user_id),
    api.core_identity_is_staff_v1(p_user_id)
        AND coalesce((SELECT p.staff_required
            FROM public.second_factor_policy p), false)
FROM (SELECT p_user_id AS user_id) me
LEFT JOIN public.second_factors f ON f.user_id = me.user_id
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_status_v1(uuid)
    FROM PUBLIC;

-- Begins enrollment with a new sealed secret, replacing a pending one.
-- Refusals: invalid, forbidden (an account that cannot sign in), active
-- (already on: it is turned off first).
CREATE FUNCTION api.identity_second_factor_begin_v1(p_user_id uuid,
    p_secret_sealed text, p_key_id text, p_now timestamptz)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE current_state text;
BEGIN
    IF p_user_id IS NULL OR p_secret_sealed IS NULL OR p_key_id IS NULL
        OR p_now IS NULL OR length(p_secret_sealed) NOT BETWEEN 1 AND 400
        OR length(p_key_id) NOT BETWEEN 1 AND 64 THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u WHERE u.id = p_user_id
        AND u.status IN ('active', 'suspended') FOR KEY SHARE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'forbidden'::text;
        RETURN;
    END IF;
    SELECT f.state INTO current_state FROM public.second_factors f
        WHERE f.user_id = p_user_id FOR UPDATE;
    IF current_state = 'active' THEN
        RETURN QUERY SELECT 'active'::text;
        RETURN;
    END IF;
    INSERT INTO public.second_factors (user_id, state, secret_sealed, key_id,
        last_step, created_at, confirmed_at, updated_at)
        VALUES (p_user_id, 'pending', p_secret_sealed, p_key_id, 0, p_now,
            NULL, p_now)
        ON CONFLICT ON CONSTRAINT second_factors_pkey DO UPDATE
            SET secret_sealed = EXCLUDED.secret_sealed,
                key_id = EXCLUDED.key_id, last_step = 0,
                created_at = EXCLUDED.created_at,
                updated_at = EXCLUDED.updated_at;
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_begin_v1(uuid, text,
    text, timestamptz) FROM PUBLIC;

-- Drops an enrollment that was begun and not confirmed: not_found when
-- there is none.
CREATE FUNCTION api.identity_second_factor_cancel_v1(p_user_id uuid)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    DELETE FROM public.second_factors f
        WHERE f.user_id = p_user_id AND f.state = 'pending';
    RETURN QUERY SELECT CASE WHEN FOUND THEN 'ok' ELSE 'not_found' END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_cancel_v1(uuid)
    FROM PUBLIC;

-- The ten recovery codes are 64 hexadecimal characters each, distinct.
CREATE FUNCTION api.core_identity_recovery_hashes_valid_v1(p_hashes text[])
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_hashes IS NOT NULL AND cardinality(p_hashes) = 10
    AND (SELECT count(DISTINCT h) FROM unnest(p_hashes) h
        WHERE h ~ '^[0-9a-f]{64}$') = 10
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_recovery_hashes_valid_v1(text[])
    FROM PUBLIC;

-- Turns a pending enrollment on with the step the member's first code was
-- accepted for and the hashes of the new recovery codes. The member's
-- other sessions end: none of them passed the second step. Records the
-- audit and the notice mail. Refusals: invalid, not_found (nothing
-- pending), active (already on).
CREATE FUNCTION api.identity_second_factor_confirm_v1(p_user_id uuid,
    p_step bigint, p_code_hashes text[], p_now timestamptz,
    p_keep_session_id uuid, p_audit jsonb, p_mail jsonb)
RETURNS TABLE(status text, sessions_revoked integer)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE current_state text; revoked integer;
BEGIN
    IF p_user_id IS NULL OR p_step IS NULL OR p_step < 1 OR p_now IS NULL
        OR p_audit IS NULL
        OR NOT api.core_identity_recovery_hashes_valid_v1(p_code_hashes) THEN
        RETURN QUERY SELECT 'invalid'::text, 0;
        RETURN;
    END IF;
    SELECT f.state INTO current_state FROM public.second_factors f
        WHERE f.user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, 0;
        RETURN;
    END IF;
    IF current_state = 'active' THEN
        RETURN QUERY SELECT 'active'::text, 0;
        RETURN;
    END IF;
    UPDATE public.second_factors f
        SET state = 'active', confirmed_at = p_now, last_step = p_step,
            updated_at = p_now
        WHERE f.user_id = p_user_id;
    DELETE FROM public.second_factor_recovery_codes c
        WHERE c.user_id = p_user_id;
    INSERT INTO public.second_factor_recovery_codes (user_id, code_hash,
        created_at)
        SELECT p_user_id, h, p_now FROM unnest(p_code_hashes) h;
    UPDATE public.sessions s
        SET revoked_at = greatest(p_now, s.created_at)
        WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
            AND s.session_id IS DISTINCT FROM p_keep_session_id;
    GET DIAGNOSTICS revoked = ROW_COUNT;
    UPDATE public.second_factor_challenges c SET closed_at = p_now
        WHERE c.user_id = p_user_id AND c.closed_at IS NULL;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
        'target_id', p_user_id), false);
    PERFORM api.core_identity_second_factor_mail_v1(p_user_id, p_mail);
    RETURN QUERY SELECT 'ok'::text, revoked;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_confirm_v1(uuid, bigint,
    text[], timestamptz, uuid, jsonb, jsonb) FROM PUBLIC;

-- The hash of an unused recovery code of the member, spent now: true when
-- there was one.
CREATE FUNCTION api.core_identity_recovery_spend_v1(p_user_id uuid,
    p_hash text, p_now timestamptz)
RETURNS boolean
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_hash IS NULL THEN
        RETURN false;
    END IF;
    UPDATE public.second_factor_recovery_codes c SET used_at = p_now
        WHERE c.user_id = p_user_id AND c.code_hash = p_hash
            AND c.used_at IS NULL;
    RETURN FOUND;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_recovery_spend_v1(uuid, text,
    timestamptz) FROM PUBLIC;

-- Turns two-step sign-in off, given a code's step (newer than the last one
-- accepted) or the hash of an unused recovery code; the password was
-- checked by the caller. Records the audit and the notice mail.
-- Refusals: invalid, not_found (not on), replayed (a step already used),
-- wrong (no such unused recovery code).
CREATE FUNCTION api.identity_second_factor_disable_v1(p_user_id uuid,
    p_step bigint, p_recovery_hash text, p_now timestamptz, p_audit jsonb,
    p_mail jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL OR p_audit IS NULL
        OR (p_step IS NULL) = (p_recovery_hash IS NULL) THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    SELECT f.state, f.last_step INTO held FROM public.second_factors f
        WHERE f.user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR held.state <> 'active' THEN
        RETURN QUERY SELECT 'not_found'::text;
        RETURN;
    END IF;
    IF p_step IS NOT NULL AND p_step <= held.last_step THEN
        RETURN QUERY SELECT 'replayed'::text;
        RETURN;
    END IF;
    IF p_recovery_hash IS NOT NULL
        AND NOT api.core_identity_recovery_spend_v1(p_user_id,
            p_recovery_hash, p_now) THEN
        RETURN QUERY SELECT 'wrong'::text;
        RETURN;
    END IF;
    DELETE FROM public.second_factor_recovery_codes c
        WHERE c.user_id = p_user_id;
    DELETE FROM public.second_factor_challenges c WHERE c.user_id = p_user_id;
    DELETE FROM public.second_factors f WHERE f.user_id = p_user_id;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
        'target_id', p_user_id), false);
    PERFORM api.core_identity_second_factor_mail_v1(p_user_id, p_mail);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_disable_v1(uuid, bigint,
    text, timestamptz, jsonb, jsonb) FROM PUBLIC;

-- New recovery codes for the old ones, given a fresh code's step.
-- Refusals: invalid, not_found, replayed.
CREATE FUNCTION api.identity_second_factor_renew_v1(p_user_id uuid,
    p_step bigint, p_code_hashes text[], p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_user_id IS NULL OR p_step IS NULL OR p_now IS NULL
        OR p_audit IS NULL
        OR NOT api.core_identity_recovery_hashes_valid_v1(p_code_hashes) THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    SELECT f.state, f.last_step INTO held FROM public.second_factors f
        WHERE f.user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR held.state <> 'active' THEN
        RETURN QUERY SELECT 'not_found'::text;
        RETURN;
    END IF;
    IF p_step <= held.last_step THEN
        RETURN QUERY SELECT 'replayed'::text;
        RETURN;
    END IF;
    UPDATE public.second_factors f SET last_step = p_step, updated_at = p_now
        WHERE f.user_id = p_user_id;
    DELETE FROM public.second_factor_recovery_codes c
        WHERE c.user_id = p_user_id;
    INSERT INTO public.second_factor_recovery_codes (user_id, code_hash,
        created_at)
        SELECT p_user_id, h, p_now FROM unnest(p_code_hashes) h;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
        'target_id', p_user_id), false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_renew_v1(uuid, bigint,
    text[], timestamptz, jsonb) FROM PUBLIC;

-- The wrong answers the member's challenges took in the hour before now.
CREATE FUNCTION api.core_identity_challenge_failures_v1(p_user_id uuid,
    p_now timestamptz)
RETURNS integer
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(sum(c.failed_attempts), 0)::integer
FROM public.second_factor_challenges c
WHERE c.user_id = p_user_id AND c.created_at > p_now - interval '1 hour'
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_challenge_failures_v1(uuid,
    timestamptz) FROM PUBLIC;

-- A sign-in whose password verified asks for the second step: the
-- challenge is stored when the member has two-step sign-in on (open), and
-- nothing is when they have not (none). Challenges older than a day go.
-- Ten wrong answers in the last hour refuse a new one (locked).
CREATE FUNCTION api.identity_second_factor_challenge_open_v1(p_row jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    member_id uuid := (p_row ->> 'user_id')::uuid;
    opened_at timestamptz := (p_row ->> 'created_at')::timestamptz;
BEGIN
    IF member_id IS NULL OR opened_at IS NULL
        OR p_row ->> 'challenge_id' IS NULL OR p_row ->> 'token_hash' IS NULL
        OR p_row ->> 'credential_id' IS NULL
        OR p_row ->> 'expires_at' IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM 1 FROM public.second_factors f
        WHERE f.user_id = member_id AND f.state = 'active';
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'none'::text;
        RETURN;
    END IF;
    DELETE FROM public.second_factor_challenges c
        WHERE c.user_id = member_id AND c.created_at < opened_at - interval '1 day';
    IF api.core_identity_challenge_failures_v1(member_id, opened_at) >= 10 THEN
        RETURN QUERY SELECT 'locked'::text;
        RETURN;
    END IF;
    INSERT INTO public.second_factor_challenges (challenge_id, token_hash,
        user_id, credential_id, created_at, expires_at)
        VALUES ((p_row ->> 'challenge_id')::uuid, p_row ->> 'token_hash',
            member_id, (p_row ->> 'credential_id')::uuid, opened_at,
            (p_row ->> 'expires_at')::timestamptz);
    RETURN QUERY SELECT 'open'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_open_v1(jsonb)
    FROM PUBLIC;

-- The challenge a token names, with what checking its answer needs: the
-- member, the sealed secret, the last step used, and whether it is still
-- open. No row for a token that names none.
CREATE FUNCTION api.identity_second_factor_challenge_v1(p_token_hash text,
    p_now timestamptz)
RETURNS TABLE(user_id uuid, open boolean, secret_sealed text, key_id text,
    last_step bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT c.user_id,
    c.closed_at IS NULL AND c.expires_at > p_now AND f.state = 'active',
    f.secret_sealed, f.key_id, f.last_step
FROM public.second_factor_challenges c
LEFT JOIN public.second_factors f ON f.user_id = c.user_id
WHERE c.token_hash = p_token_hash
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_v1(text,
    timestamptz) FROM PUBLIC;

-- Answers a challenge with a code's step (Perl matched the code against
-- the secret) or a recovery code's hash; neither is a wrong answer. A
-- right one closes the challenge, records the step (or spends the code),
-- reseals the secret under the current key when the caller sends it, and
-- holds the password credential that verified, FOR SHARE, so the session
-- the caller opens next in this transaction cannot outlive a password
-- reset that commits first. A wrong one counts against the challenge (five
-- close it) and the account (ten in an hour lock it, audited and mailed
-- once). Answers: ok, wrong (attempts_left), locked, expired, not_found.
CREATE FUNCTION api.identity_second_factor_challenge_answer_v1(
    p_token_hash text, p_step bigint, p_recovery_hash text, p_resealed text,
    p_key_id text, p_now timestamptz, p_audit jsonb, p_mail jsonb)
RETURNS TABLE(status text, user_id uuid, method text, recovery_left integer,
    attempts_left integer)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    challenge record;
    held record;
    failures integer;
    used text;
BEGIN
    IF p_token_hash IS NULL OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, 0, 0;
        RETURN;
    END IF;
    SELECT c.* INTO challenge FROM public.second_factor_challenges c
        WHERE c.token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::text, 0, 0;
        RETURN;
    END IF;
    IF challenge.closed_at IS NOT NULL OR challenge.expires_at <= p_now THEN
        RETURN QUERY SELECT 'expired'::text, challenge.user_id, NULL::text,
            0, 0;
        RETURN;
    END IF;
    SELECT f.state, f.last_step INTO held FROM public.second_factors f
        WHERE f.user_id = challenge.user_id FOR UPDATE;
    PERFORM 1 FROM public.credentials k
        JOIN public.users u ON u.id = k.user_id
        WHERE k.id = challenge.credential_id
            AND k.user_id = challenge.user_id AND k.type = 'password'
            AND k.revoked_at IS NULL
            AND u.status NOT IN ('pending', 'deleted')
        FOR SHARE OF k;
    IF NOT FOUND OR held.state IS DISTINCT FROM 'active' THEN
        UPDATE public.second_factor_challenges c SET closed_at = p_now
            WHERE c.challenge_id = challenge.challenge_id;
        RETURN QUERY SELECT 'expired'::text, challenge.user_id, NULL::text,
            0, 0;
        RETURN;
    END IF;
    failures := api.core_identity_challenge_failures_v1(challenge.user_id,
        p_now);
    IF failures >= 10 THEN
        UPDATE public.second_factor_challenges c SET closed_at = p_now
            WHERE c.challenge_id = challenge.challenge_id;
        RETURN QUERY SELECT 'locked'::text, challenge.user_id, NULL::text,
            0, 0;
        RETURN;
    END IF;

    IF p_step IS NOT NULL AND p_step > held.last_step THEN
        used := 'totp';
        UPDATE public.second_factors f
            SET last_step = p_step, updated_at = p_now,
                secret_sealed = coalesce(p_resealed, f.secret_sealed),
                key_id = CASE WHEN p_resealed IS NULL THEN f.key_id
                    ELSE p_key_id END
            WHERE f.user_id = challenge.user_id;
    ELSIF p_step IS NULL AND api.core_identity_recovery_spend_v1(
            challenge.user_id, p_recovery_hash, p_now) THEN
        used := 'recovery';
    END IF;

    IF used IS NOT NULL THEN
        UPDATE public.second_factor_challenges c SET closed_at = p_now
            WHERE c.challenge_id = challenge.challenge_id;
        PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
            'action', 'identity.second_factor.passed',
            'actor_id', challenge.user_id, 'target_id', challenge.user_id,
            'metadata', jsonb_build_object('method', used)), false);
        RETURN QUERY SELECT 'ok'::text, challenge.user_id, used,
            (SELECT count(*)::integer
                FROM public.second_factor_recovery_codes r
                WHERE r.user_id = challenge.user_id AND r.used_at IS NULL),
            0;
        RETURN;
    END IF;

    UPDATE public.second_factor_challenges c
        SET failed_attempts = c.failed_attempts + 1,
            closed_at = CASE WHEN c.failed_attempts + 1 >= 5 THEN p_now END
        WHERE c.challenge_id = challenge.challenge_id;
    failures := failures + 1;
    IF failures >= 10 THEN
        UPDATE public.second_factor_challenges c SET closed_at = p_now
            WHERE c.challenge_id = challenge.challenge_id;
        PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
            'action', 'identity.second_factor.locked',
            'actor_id', NULL, 'target_id', challenge.user_id,
            'metadata', jsonb_build_object('failures', failures)), false);
        PERFORM api.core_identity_second_factor_mail_v1(challenge.user_id,
            p_mail);
        RETURN QUERY SELECT 'locked'::text, challenge.user_id, NULL::text,
            0, 0;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'wrong'::text, challenge.user_id, NULL::text, 0,
        least(5 - (challenge.failed_attempts + 1), 10 - failures);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_answer_v1(
    text, bigint, text, text, text, timestamptz, jsonb, jsonb) FROM PUBLIC;

-- What staff see of a member's two-step sign-in: whether it is on, since
-- when and how many recovery codes are left. Never the secret.
CREATE FUNCTION api.admin_second_factor_member_v1(p_user_id uuid)
RETURNS TABLE(state text, confirmed_at timestamptz, recovery_left integer)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(f.state, 'off'), f.confirmed_at,
    (SELECT count(*)::integer FROM public.second_factor_recovery_codes c
        WHERE c.user_id = p_user_id AND c.used_at IS NULL
            AND f.state = 'active')
FROM (SELECT p_user_id AS user_id) me
LEFT JOIN public.second_factors f ON f.user_id = me.user_id
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_member_v1(uuid)
    FROM PUBLIC;

-- An administrator turns a member's two-step sign-in off, for a member who
-- lost their app and their recovery codes: audited, and the member is
-- mailed. Refusals: invalid, self (an administrator turns their own off
-- from their settings, with a code), not_found (it is not on, or begun).
CREATE FUNCTION api.admin_second_factor_reset_v1(p_user_id uuid,
    p_actor_user_id uuid, p_now timestamptz, p_audit jsonb, p_mail jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_user_id IS NULL OR p_actor_user_id IS NULL OR p_now IS NULL
        OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    IF p_user_id = p_actor_user_id THEN
        RETURN QUERY SELECT 'self'::text;
        RETURN;
    END IF;
    PERFORM 1 FROM public.second_factors f WHERE f.user_id = p_user_id
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text;
        RETURN;
    END IF;
    DELETE FROM public.second_factor_recovery_codes c
        WHERE c.user_id = p_user_id;
    DELETE FROM public.second_factor_challenges c WHERE c.user_id = p_user_id;
    DELETE FROM public.second_factors f WHERE f.user_id = p_user_id;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
        'actor_id', p_actor_user_id, 'target_id', p_user_id), false);
    PERFORM api.core_identity_second_factor_mail_v1(p_user_id, p_mail);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_reset_v1(uuid, uuid,
    timestamptz, jsonb, jsonb) FROM PUBLIC;

-- Whether staff must use two-step sign-in, and who said so when.
CREATE FUNCTION api.admin_second_factor_policy_v1()
RETURNS TABLE(staff_required boolean, updated_at timestamptz,
    updated_by_username text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(p.staff_required, false), p.updated_at, u.username
FROM (SELECT true AS singleton) me
LEFT JOIN public.second_factor_policy p ON p.singleton = me.singleton
LEFT JOIN public.users u ON u.id = p.updated_by_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_v1() FROM PUBLIC;

-- The staff, those without two-step sign-in first, so an administrator
-- sees who the requirement would shut out before turning it on.
CREATE FUNCTION api.admin_second_factor_staff_v1(p_row_limit integer)
RETURNS TABLE(user_id uuid, username text, display_name text,
    enabled boolean, confirmed_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id, u.username, u.display_name, f.state IS NOT DISTINCT FROM 'active',
    f.confirmed_at
FROM public.users u
LEFT JOIN public.second_factors f ON f.user_id = u.id AND f.state = 'active'
WHERE u.status <> 'deleted' AND EXISTS (SELECT 1 FROM public.role_bindings b
    JOIN public.role_permissions rp ON rp.role_id = b.role_id
    JOIN public.permissions p ON p.permission_id = rp.permission_id
    WHERE b.user_id = u.id AND b.revoked_at IS NULL
        AND NOT (p.resource_type = 'category' AND p.action = 'read'))
ORDER BY f.state IS NOT DISTINCT FROM 'active', u.username
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_staff_v1(integer)
    FROM PUBLIC;

-- Requires two-step sign-in of staff, or stops requiring it. Audited.
-- Refusals: invalid, unenrolled (an administrator without it cannot
-- require it: they would shut themselves out of the console). Answers
-- unchanged when it already was so.
CREATE FUNCTION api.admin_second_factor_policy_set_v1(p_required boolean,
    p_actor_user_id uuid, p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE stored_required boolean;
BEGIN
    IF p_required IS NULL OR p_actor_user_id IS NULL OR p_now IS NULL
        OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    SELECT p.staff_required INTO stored_required FROM public.second_factor_policy p
        FOR UPDATE;
    IF coalesce(stored_required, false) = p_required THEN
        RETURN QUERY SELECT 'unchanged'::text;
        RETURN;
    END IF;
    IF p_required AND NOT EXISTS (SELECT 1 FROM public.second_factors f
        WHERE f.user_id = p_actor_user_id AND f.state = 'active') THEN
        RETURN QUERY SELECT 'unenrolled'::text;
        RETURN;
    END IF;
    INSERT INTO public.second_factor_policy (singleton, staff_required,
        updated_by_user_id, updated_at)
        VALUES (true, p_required, p_actor_user_id, p_now)
        ON CONFLICT ON CONSTRAINT second_factor_policy_pkey DO UPDATE
            SET staff_required = EXCLUDED.staff_required,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = EXCLUDED.updated_at;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object(
        'actor_id', p_actor_user_id,
        'metadata', jsonb_build_object('staff_required', p_required)), false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_set_v1(boolean,
    uuid, timestamptz, jsonb) FROM PUBLIC;

-- The staff consoles' permission check (Service::Admin::PermissionGate):
-- while the policy requires it, staff without two-step sign-in hold no
-- staff permission: none but reading a category, which is no console's.
CREATE FUNCTION api.admin_permission_allowed_v3(p_user_id uuid,
    p_resource_type text, p_action text, p_resource_id uuid, p_space_id uuid)
RETURNS TABLE (allowed boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.allowed AND (coalesce(p_resource_type = 'category' AND p_action = 'read',
        false) OR NOT api.core_identity_second_factor_missing_v1(p_user_id))
FROM api.admin_permission_allowed_v1(p_user_id, p_resource_type, p_action,
    p_resource_id, p_space_id) v
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v3(uuid, text, text,
    uuid, uuid) FROM PUBLIC;

-- Erasure: the member's secret, recovery codes and challenges go.
CREATE FUNCTION api.privacy_revoke_user_v15(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'SecondFactor' THEN
        DELETE FROM public.second_factor_recovery_codes c
            WHERE c.user_id = p_user_id;
        DELETE FROM public.second_factor_challenges c
            WHERE c.user_id = p_user_id;
        DELETE FROM public.second_factors f WHERE f.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v13(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v15(text, uuid, text)
    FROM PUBLIC;

-- The export says whether two-step sign-in is on, since when, and how many
-- recovery codes are left; never the secret or the codes' hashes.
CREATE FUNCTION api.portability_export_parts_v17(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'second_factor', (SELECT jsonb_build_object(
        'state', coalesce(f.state, 'off'),
        'confirmed_at', f.confirmed_at,
        'recovery_codes_left', (SELECT count(*)
            FROM public.second_factor_recovery_codes c
            WHERE c.user_id = p_user_id AND c.used_at IS NULL
                AND f.state = 'active'))
        FROM (SELECT p_user_id AS user_id) me
        LEFT JOIN public.second_factors f ON f.user_id = me.user_id)))::json
FROM api.portability_export_parts_v15(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v17(uuid) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.identity_second_factor_status_v2(
p_user_id uuid
)
RETURNS TABLE(state text, secret_sealed text, key_id text, last_step bigint,
    confirmed_at timestamptz, recovery_left integer, staff boolean,
    staff_required boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_status_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_status_v2(uuid)
    FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_begin_v2(
p_user_id uuid, p_secret_sealed text, p_key_id text, p_now timestamptz
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_begin_v1(p_user_id, p_secret_sealed,
    p_key_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_begin_v2(uuid, text,
    text, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_cancel_v2(
p_user_id uuid
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_cancel_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_cancel_v2(uuid)
    FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_confirm_v2(
p_user_id uuid, p_step bigint, p_code_hashes text[], p_now timestamptz,
p_keep_session_id uuid, p_audit jsonb, p_mail jsonb
)
RETURNS TABLE(status text, sessions_revoked integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_confirm_v1(p_user_id, p_step,
    p_code_hashes, p_now, p_keep_session_id, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_confirm_v2(uuid, bigint,
    text[], timestamptz, uuid, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_disable_v2(
p_user_id uuid, p_step bigint, p_recovery_hash text, p_now timestamptz,
p_audit jsonb, p_mail jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_disable_v1(p_user_id, p_step,
    p_recovery_hash, p_now, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_disable_v2(uuid, bigint,
    text, timestamptz, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_renew_v2(
p_user_id uuid, p_step bigint, p_code_hashes text[], p_now timestamptz,
p_audit jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_renew_v1(p_user_id, p_step,
    p_code_hashes, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_renew_v2(uuid, bigint,
    text[], timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_challenge_open_v2(
p_row jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_challenge_open_v1(p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_open_v2(jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_challenge_v2(
p_token_hash text, p_now timestamptz
)
RETURNS TABLE(user_id uuid, open boolean, secret_sealed text, key_id text,
    last_step bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_challenge_v1(p_token_hash, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_v2(text,
    timestamptz) FROM PUBLIC;

CREATE FUNCTION api.identity_second_factor_challenge_answer_v2(
p_token_hash text, p_step bigint, p_recovery_hash text, p_resealed text,
p_key_id text, p_now timestamptz, p_audit jsonb, p_mail jsonb
)
RETURNS TABLE(status text, user_id uuid, method text, recovery_left integer,
    attempts_left integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_second_factor_challenge_answer_v1(p_token_hash,
    p_step, p_recovery_hash, p_resealed, p_key_id, p_now, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_answer_v2(
    text, bigint, text, text, text, timestamptz, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_member_v2(
p_user_id uuid
)
RETURNS TABLE(state text, confirmed_at timestamptz, recovery_left integer)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_member_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_member_v2(uuid)
    FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_reset_v2(
p_user_id uuid, p_actor_user_id uuid, p_now timestamptz, p_audit jsonb,
p_mail jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_reset_v1(p_user_id, p_actor_user_id,
    p_now, p_audit, p_mail);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_reset_v2(uuid, uuid,
    timestamptz, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_policy_v2(
)
RETURNS TABLE(staff_required boolean, updated_at timestamptz,
    updated_by_username text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_policy_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_v2() FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_staff_v2(
p_row_limit integer
)
RETURNS TABLE(user_id uuid, username text, display_name text,
    enabled boolean, confirmed_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_staff_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_staff_v2(integer)
    FROM PUBLIC;

CREATE FUNCTION api.admin_second_factor_policy_set_v2(
p_required boolean, p_actor_user_id uuid, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_second_factor_policy_set_v1(p_required,
    p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_set_v2(boolean,
    uuid, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_permission_allowed_v4(
p_user_id uuid, p_resource_type text, p_action text, p_resource_id uuid,
p_space_id uuid
)
RETURNS TABLE (allowed boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_permission_allowed_v3(p_user_id, p_resource_type,
    p_action, p_resource_id, p_space_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v4(uuid, text, text,
    uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v16(p_source text, p_user_id uuid,
    p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v15(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v16(text, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v18(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v17(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v18(uuid) FROM PUBLIC;

COMMIT;
