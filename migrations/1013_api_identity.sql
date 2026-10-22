-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Registration, sign-in, passwords, tokens, the second factor, preferences and
-- profiles.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A member's active password credential.
CREATE FUNCTION api.identity_active_password_v1(p_user_id uuid)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.id, c.user_id, c.type, c.secret_hash, c.created_at, c.revoked_at
    FROM public.credentials c WHERE c.user_id = p_user_id AND c.type = 'password'
        AND c.revoked_at IS NULL ORDER BY c.created_at DESC LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_active_password_v1(uuid) FROM PUBLIC;

-- Uses a single-use token, locked by its hash: refused when it is of another
-- kind, already used or expired.
CREATE FUNCTION api.identity_consume_token_v1(
    p_token_hash text,
    p_token_type text,
    p_now timestamptz,
    p_now_epoch bigint
)
RETURNS TABLE (result_code text, token_row jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_token public.identity_tokens%ROWTYPE;
BEGIN
    -- Lock by hash before checking its type, as the old consumption path did.
    SELECT t.* INTO v_token FROM public.identity_tokens t WHERE t.token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND OR v_token.token_type <> p_token_type THEN
        RETURN QUERY SELECT 'invalid_token'::text, NULL::jsonb;
    ELSIF v_token.used_at IS NOT NULL THEN
        RETURN QUERY SELECT 'token_used'::text, NULL::jsonb;
    ELSIF date_trunc('second', v_token.expires_at) <= to_timestamp(p_now_epoch) THEN
        RETURN QUERY SELECT 'token_expired'::text, NULL::jsonb;
    ELSE
        UPDATE public.identity_tokens t SET used_at = p_now WHERE t.token_id = v_token.token_id
            RETURNING t.* INTO v_token;
        RETURN QUERY SELECT 'ok'::text, to_jsonb(v_token)
            || jsonb_build_object('metadata', v_token.metadata::text);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_consume_token_v1(text, text, timestamptz, bigint)
    FROM PUBLIC;

-- The credential with this id.
CREATE FUNCTION api.identity_credential_by_id_v1(p_credential_id uuid)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.id, c.user_id, c.type, c.secret_hash, c.created_at, c.revoked_at
    FROM public.credentials c WHERE c.id = p_credential_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_credential_by_id_v1(uuid) FROM PUBLIC;

-- A member's active password credential, held FOR SHARE while the caller
-- verifies it.
CREATE FUNCTION api.identity_hold_password_v1(
    p_user_id uuid,
    p_credential_id uuid
)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.id, c.user_id, c.type, c.secret_hash, c.created_at, c.revoked_at
    FROM public.credentials c WHERE c.user_id = p_user_id AND c.id = p_credential_id
        AND c.type = 'password' AND c.revoked_at IS NULL FOR SHARE;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_hold_password_v1(uuid, uuid)
    FROM PUBLIC;

-- Stores a new credential and answers it.
CREATE FUNCTION api.identity_insert_credential_v1(p_values jsonb)
RETURNS SETOF api.identity_credential_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.credentials(id, user_id, type, secret_hash, created_at, revoked_at)
    VALUES ((p_values->>'id')::uuid, (p_values->>'user_id')::uuid, p_values->>'type',
        p_values->>'secret_hash', COALESCE((p_values->>'created_at')::timestamptz, now()),
        (p_values->>'revoked_at')::timestamptz) RETURNING id, user_id, type,
            secret_hash, created_at, revoked_at;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_credential_v1(jsonb)
    FROM PUBLIC;

-- Stores a new single-use token and answers it.
CREATE FUNCTION api.identity_insert_token_v1(p_values jsonb)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.identity_tokens (token_id, user_id, token_type, token_hash, email_normalized,
        created_at, expires_at, used_at, metadata)
    VALUES ((p_values->>'token_id')::uuid, (p_values->>'user_id')::uuid, p_values->>'token_type',
        p_values->>'token_hash', p_values->>'email_normalized',
        COALESCE((p_values->>'created_at')::timestamptz, now()), (p_values->>'expires_at')::timestamptz,
        (p_values->>'used_at')::timestamptz, COALESCE(p_values->'metadata', '{}'::jsonb)) RETURNING
            token_id, user_id, token_type, token_hash, email_normalized,
            created_at, expires_at, used_at, metadata;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_token_v1(jsonb) FROM PUBLIC;

-- Stores a new member and answers them.
CREATE FUNCTION api.identity_insert_user_v1(p_values jsonb)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.users (id, username, display_name, email_normalized,
        password_hash, status, trust_level, version, permission_version,
        email_verified_at, created_at, updated_at, deleted_at,
        preferred_locale, preferred_theme, preferred_timezone)
    SELECT (p_values->>'id')::uuid, p_values->>'username', p_values->>'display_name',
        p_values->>'email_normalized', p_values->>'password_hash',
        COALESCE(p_values->>'status', 'pending'), COALESCE((p_values->>'trust_level')::integer, 0),
        COALESCE((p_values->>'version')::bigint, 1), COALESCE((p_values->>'permission_version')::bigint, 1),
        (p_values->>'email_verified_at')::timestamptz,
        COALESCE((p_values->>'created_at')::timestamptz, now()),
        COALESCE((p_values->>'updated_at')::timestamptz, now()), (p_values->>'deleted_at')::timestamptz,
        COALESCE(p_values->>'preferred_locale', 'en'), COALESCE(p_values->>'preferred_theme', 'auto'),
        p_values->>'preferred_timezone'
    RETURNING id, username, display_name, email_normalized, password_hash,
        status, trust_level, version, permission_version, email_verified_at,
        created_at, updated_at, deleted_at, preferred_locale, preferred_theme,
        preferred_timezone, bio;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_user_v1(jsonb) FROM PUBLIC;

-- Locks a member's active password credentials FOR UPDATE, retrying while a
-- concurrent change replaces them.
CREATE FUNCTION api.identity_lock_passwords_v1(p_user_id uuid)
RETURNS SETOF api.identity_credential_v1
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_round integer;
BEGIN
    FOR v_round IN 1..3 LOOP
        RETURN QUERY SELECT c.id, c.user_id, c.type, c.secret_hash,
            c.created_at, c.revoked_at
        FROM public.credentials c WHERE c.user_id = p_user_id
            AND c.type = 'password' AND c.revoked_at IS NULL FOR UPDATE;
        IF FOUND THEN RETURN; END IF;
        IF NOT EXISTS(SELECT 1 FROM public.credentials c WHERE c.user_id = p_user_id
            AND c.type = 'password' AND c.revoked_at IS NULL) THEN RETURN; END IF;
    END LOOP;
    RAISE EXCEPTION 'the password of % changed 3 times while this waited for it; try again', p_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_lock_passwords_v1(uuid) FROM PUBLIC;

-- How many public threads and replies a member has, as their profile shows
-- them.
CREATE FUNCTION api.identity_profile_counts_v1(p_user_id uuid)
RETURNS TABLE (
    public_threads bigint,
    public_replies bigint,
    total_public bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    WITH totals AS (SELECT (SELECT count(*) FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        WHERE t.author_user_id = p_user_id AND t.deleted_at IS NULL
        AND t.visibility = 'public' AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND c.visibility = 'public' AND s.visibility = 'public') AS threads,
        (SELECT count(*) FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id
        JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        WHERE p.author_user_id = p_user_id AND p.deleted_at IS NULL
        AND p.visibility = 'public' AND p.moderation_state = 'visible' AND p.position > 1
        AND t.deleted_at IS NULL AND t.visibility = 'public' AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND c.visibility = 'public' AND s.visibility = 'public') AS replies)
    SELECT threads, replies, threads + replies FROM totals;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_counts_v1(uuid) FROM PUBLIC;

-- A page of a member's public replies, newest first after the cursor.
CREATE FUNCTION api.identity_profile_replies_v1(
    p_user_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    thread_title text,
    thread_slug text,
    body text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_after_at IS NULL THEN
        RETURN QUERY SELECT p.post_id, p.thread_id, p.author_user_id, p.position, p.visibility, p.moderation_state,
        p.created_at, t.title, t.slug, b.body_rendered_safe FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id
        JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        LEFT JOIN public.post_bodies b ON b.body_id = p.current_body_id
        WHERE p.author_user_id = p_user_id AND p.deleted_at IS NULL
        AND p.visibility = 'public' AND p.moderation_state = 'visible' AND p.position > 1
        AND t.deleted_at IS NULL AND t.visibility = 'public' AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND c.visibility = 'public' AND s.visibility = 'public'
            ORDER BY p.created_at DESC, p.post_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT p.post_id, p.thread_id, p.author_user_id, p.position, p.visibility, p.moderation_state,
        p.created_at, t.title, t.slug, b.body_rendered_safe FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id
        JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        LEFT JOIN public.post_bodies b ON b.body_id = p.current_body_id
        WHERE p.author_user_id = p_user_id AND p.deleted_at IS NULL
        AND p.visibility = 'public' AND p.moderation_state = 'visible' AND p.position > 1
        AND t.deleted_at IS NULL AND t.visibility = 'public' AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND c.visibility = 'public' AND s.visibility = 'public'
            AND p.created_at <= p_after_at AND (p.created_at, p.post_id) < (p_after_at, p_after_id)
            ORDER BY p.created_at DESC, p.post_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_replies_v1(uuid, timestamptz, uuid, integer)
    FROM PUBLIC;

-- A page of a member's public threads, latest activity first after the cursor.
CREATE FUNCTION api.identity_profile_threads_v1(
    p_user_id uuid,
    p_after_at timestamptz,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    visibility text,
    moderation_state text,
    last_activity_at timestamptz,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_after_at IS NULL THEN
        RETURN QUERY SELECT t.thread_id, t.category_id, t.author_user_id, t.title, t.slug, t.visibility,
        t.moderation_state, t.last_activity_at, t.created_at FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        WHERE t.author_user_id = p_user_id AND t.deleted_at IS NULL
        AND t.visibility = 'public' AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND c.visibility = 'public' AND s.visibility = 'public'
            ORDER BY t.last_activity_at DESC, t.thread_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT t.thread_id, t.category_id, t.author_user_id, t.title, t.slug, t.visibility,
        t.moderation_state, t.last_activity_at, t.created_at FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id
        JOIN public.spaces s ON s.space_id = c.space_id
        WHERE t.author_user_id = p_user_id AND t.deleted_at IS NULL
        AND t.visibility = 'public' AND t.moderation_state IN ('visible', 'locked')
        AND c.deleted_at IS NULL AND c.visibility = 'public' AND s.visibility = 'public'
            AND t.last_activity_at <= p_after_at AND (t.last_activity_at, t.thread_id) < (p_after_at, p_after_id)
            ORDER BY t.last_activity_at DESC, t.thread_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_threads_v1(uuid, timestamptz, uuid, integer)
    FROM PUBLIC;

-- A member's trust snapshot.
CREATE FUNCTION api.identity_profile_trust_v1(p_user_id uuid)
RETURNS SETOF api.identity_trust_snapshot_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.user_id, t.score, t.trust_level, t.calculated_at, t.version
    FROM public.trust_score_snapshots t WHERE t.user_id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_trust_v1(uuid) FROM PUBLIC;

-- Whether a username and an email are already taken.
CREATE FUNCTION api.identity_registration_duplicates_v1(
    p_username text,
    p_email text
)
RETURNS TABLE (username_taken boolean, email_taken boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT EXISTS(SELECT 1 FROM public.users u WHERE u.username = p_username),
           EXISTS(SELECT 1 FROM public.users u WHERE u.email_normalized = p_email);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_registration_duplicates_v1(text, text)
    FROM PUBLIC;

-- The registration as one call. p_answer is an answer decided before the
-- call (the composer's refusal of the input), recorded without a write.
-- Otherwise a taken username or email records p_refused; else the writes
-- happen and p_accepted is recorded. The rows and documents are the ones
-- the stores sent one by one.
CREATE FUNCTION api.identity_register_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_accepted jsonb,
    p_refused jsonb,
    p_user jsonb,
    p_credential jsonb,
    p_event jsonb,
    p_event_outbox_id text,
    p_audit jsonb,
    p_token jsonb,
    p_token_audit jsonb,
    p_mail_event jsonb,
    p_mail_outbox_id text,
    p_mail_outbox_extras jsonb
)
RETURNS TABLE (outcome text, response json, stored_user json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    taken record;
    user_row jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json, NULL::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT * INTO taken FROM api.identity_registration_duplicates_v1(
            p_user ->> 'username', p_user ->> 'email_normalized');
        IF taken.username_taken OR taken.email_taken THEN
            answer := p_refused;
        ELSE
            user_row := api.core_identity_store_user_v1(p_user);
            IF user_row IS NULL THEN
                answer := p_refused;
            END IF;
        END IF;
        IF answer IS NULL THEN
            PERFORM api.core_identity_store_credential_v1(p_credential);
            PERFORM api.ops_record_event_v1(p_event, p_event_outbox_id, NULL,
                false);
            PERFORM api.ops_record_audit_v1(p_audit, false);
            PERFORM api.core_identity_store_token_v1(p_token);
            PERFORM api.ops_record_audit_v1(p_token_audit, false);
            PERFORM api.ops_record_event_v1(p_mail_event, p_mail_outbox_id,
                p_mail_outbox_extras, false);
            answer := p_accepted;
        END IF;
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json, user_row::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.identity_register_command_v1(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text, jsonb, jsonb, jsonb, jsonb, text, jsonb)
    FROM PUBLIC;

-- Revokes the given credentials. Answers how many changed.
CREATE FUNCTION api.identity_revoke_passwords_v1(
    p_ids jsonb,
    p_revoked_at timestamptz
)
RETURNS TABLE (updated integer)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    WITH changed AS (UPDATE public.credentials c SET revoked_at = GREATEST(p_revoked_at, c.created_at)
        WHERE c.id IN (SELECT value::uuid FROM jsonb_array_elements_text(p_ids)) RETURNING 1)
    SELECT count(*)::integer FROM changed;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_revoke_passwords_v1(jsonb, timestamptz)
    FROM PUBLIC;

-- Gives a single-use token a new hash, expiry and metadata, and answers it.
CREATE FUNCTION api.identity_rotate_token_v1(p_token_id uuid, p_values jsonb)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.identity_tokens t SET email_normalized = p_values->>'email_normalized',
        expires_at = (p_values->>'expires_at')::timestamptz, metadata = p_values->'metadata',
        token_hash = p_values->>'token_hash' WHERE t.token_id = p_token_id RETURNING
            t.token_id, t.user_id, t.token_type, t.token_hash,
            t.email_normalized, t.created_at, t.expires_at, t.used_at,
            t.metadata;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_rotate_token_v1(uuid, jsonb)
    FROM PUBLIC;

-- Begins enrollment with a new sealed secret, replacing a pending one.
-- Refusals: invalid, forbidden (an account that cannot sign in), active
-- (already on: it is turned off first).
CREATE FUNCTION api.identity_second_factor_begin_v1(
    p_user_id uuid,
    p_secret_sealed text,
    p_key_id text,
    p_now timestamptz
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_begin_v1(uuid, text, text, timestamptz)
    FROM PUBLIC;

-- Drops an enrollment that was begun and not confirmed: not_found when
-- there is none.
CREATE FUNCTION api.identity_second_factor_cancel_v1(p_user_id uuid)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
    p_token_hash text,
    p_step bigint,
    p_recovery_hash text,
    p_resealed text,
    p_key_id text,
    p_now timestamptz,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (
    status text,
    user_id uuid,
    method text,
    recovery_left integer,
    attempts_left integer
)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_answer_v1(text, bigint, text, text, text, timestamptz, jsonb, jsonb)
    FROM PUBLIC;

-- A sign-in whose password verified asks for the second step: the
-- challenge is stored when the member has two-step sign-in on (open), and
-- nothing is when they have not (none). Challenges older than a day go.
-- Ten wrong answers in the last hour refuse a new one (locked).
CREATE FUNCTION api.identity_second_factor_challenge_open_v1(p_row jsonb)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
CREATE FUNCTION api.identity_second_factor_challenge_v1(
    p_token_hash text,
    p_now timestamptz
)
RETURNS TABLE (
    user_id uuid,
    open boolean,
    secret_sealed text,
    key_id text,
    last_step bigint
)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_challenge_v1(text, timestamptz)
    FROM PUBLIC;

-- Turns a pending enrollment on with the step the member's first code was
-- accepted for and the hashes of the new recovery codes. The member's
-- other sessions end: none of them passed the second step. Records the
-- audit and the notice mail. Refusals: invalid, not_found (nothing
-- pending), active (already on).
CREATE FUNCTION api.identity_second_factor_confirm_v1(
    p_user_id uuid,
    p_step bigint,
    p_code_hashes text[],
    p_now timestamptz,
    p_keep_session_id uuid,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (status text, sessions_revoked integer)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_confirm_v1(uuid, bigint, text[], timestamptz, uuid, jsonb, jsonb)
    FROM PUBLIC;

-- Turns two-step sign-in off, given a code's step (newer than the last one
-- accepted) or the hash of an unused recovery code; the password was
-- checked by the caller. Records the audit and the notice mail.
-- Refusals: invalid, not_found (not on), replayed (a step already used),
-- wrong (no such unused recovery code).
CREATE FUNCTION api.identity_second_factor_disable_v1(
    p_user_id uuid,
    p_step bigint,
    p_recovery_hash text,
    p_now timestamptz,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_disable_v1(uuid, bigint, text, timestamptz, jsonb, jsonb)
    FROM PUBLIC;

-- New recovery codes for the old ones, given a fresh code's step.
-- Refusals: invalid, not_found, replayed.
CREATE FUNCTION api.identity_second_factor_renew_v1(
    p_user_id uuid,
    p_step bigint,
    p_code_hashes text[],
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.identity_second_factor_renew_v1(uuid, bigint, text[], timestamptz, jsonb)
    FROM PUBLIC;

-- The member's two-step sign-in: off, pending (begun, not confirmed) or
-- active, the sealed secret for the forum to open, the recovery codes
-- left, and whether the policy requires it of them as staff.
CREATE FUNCTION api.identity_second_factor_status_v1(p_user_id uuid)
RETURNS TABLE (
    state text,
    secret_sealed text,
    key_id text,
    last_step bigint,
    confirmed_at timestamptz,
    recovery_left integer,
    staff boolean,
    staff_required boolean
)
LANGUAGE sql
STABLE
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

-- The token with this id.
CREATE FUNCTION api.identity_token_by_id_v1(p_token_id uuid)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.token_id, t.user_id, t.token_type, t.token_hash,
        t.email_normalized, t.created_at, t.expires_at, t.used_at, t.metadata
    FROM public.identity_tokens t WHERE t.token_id = p_token_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_token_by_id_v1(uuid) FROM PUBLIC;

-- A member's unused token of one kind.
CREATE FUNCTION api.identity_unused_token_v1(
    p_user_id uuid,
    p_token_type text
)
RETURNS SETOF api.identity_token_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.token_id, t.user_id, t.token_type, t.token_hash,
        t.email_normalized, t.created_at, t.expires_at, t.used_at, t.metadata
    FROM public.identity_tokens t WHERE t.user_id = p_user_id AND t.token_type = p_token_type
        AND t.used_at IS NULL LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_unused_token_v1(uuid, text)
    FROM PUBLIC;

-- Writes the given fields of a member (password, email, status, preferences,
-- bio) and answers them; any other field is refused.
CREATE FUNCTION api.identity_update_user_v3(p_user_id uuid, p_changes jsonb)
RETURNS SETOF api.identity_user_v1
LANGUAGE plpgsql
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
    WHERE u.id = p_user_id RETURNING u.id, u.username, u.display_name,
        u.email_normalized, u.password_hash, u.status, u.trust_level,
        u.version, u.permission_version, u.email_verified_at, u.created_at,
        u.updated_at, u.deleted_at, u.preferred_locale, u.preferred_theme,
        u.preferred_timezone, u.bio;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v3(uuid, jsonb)
    FROM PUBLIC;

-- The member with this id.
CREATE FUNCTION api.identity_user_by_id_v1(p_user_id uuid)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT u.id, u.username, u.display_name, u.email_normalized,
        u.password_hash, u.status, u.trust_level, u.version,
        u.permission_version, u.email_verified_at, u.created_at, u.updated_at,
        u.deleted_at, u.preferred_locale, u.preferred_theme,
        u.preferred_timezone, u.bio
    FROM public.users u WHERE u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_id_v1(uuid) FROM PUBLIC;

-- The member with this username, or with this normalized email when p_by_email
-- is true.
CREATE FUNCTION api.identity_user_by_identifier_v1(
    p_identifier text,
    p_by_email boolean
)
RETURNS SETOF api.identity_user_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_by_email THEN
        RETURN QUERY SELECT u.id, u.username, u.display_name,
            u.email_normalized, u.password_hash, u.status, u.trust_level,
            u.version, u.permission_version, u.email_verified_at,
            u.created_at, u.updated_at, u.deleted_at, u.preferred_locale,
            u.preferred_theme, u.preferred_timezone, u.bio
        FROM public.users u WHERE u.email_normalized = p_identifier;
    ELSE
        RETURN QUERY SELECT u.id, u.username, u.display_name,
            u.email_normalized, u.password_hash, u.status, u.trust_level,
            u.version, u.permission_version, u.email_verified_at,
            u.created_at, u.updated_at, u.deleted_at, u.preferred_locale,
            u.preferred_theme, u.preferred_timezone, u.bio
        FROM public.users u WHERE u.username = p_identifier;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_identifier_v1(text, boolean)
    FROM PUBLIC;

COMMIT;
