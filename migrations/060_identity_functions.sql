-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Identity persistence. Password hashing remains outside PostgreSQL; the
-- existing transaction holds its credential locks across verification.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.identity_user_by_id_v1(p_user_id uuid)
RETURNS SETOF public.users
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT u.* FROM public.users u WHERE u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_id_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_user_by_identifier_v1(p_identifier text, p_by_email boolean)
RETURNS SETOF public.users
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_by_email THEN
        RETURN QUERY SELECT u.* FROM public.users u WHERE u.email_normalized = p_identifier;
    ELSE
        RETURN QUERY SELECT u.* FROM public.users u WHERE u.username = p_identifier;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_user_by_identifier_v1(text, boolean) FROM PUBLIC;

CREATE FUNCTION api.identity_registration_duplicates_v1(p_username text, p_email text)
RETURNS TABLE(username_taken boolean, email_taken boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT EXISTS(SELECT 1 FROM public.users u WHERE u.username = p_username),
           EXISTS(SELECT 1 FROM public.users u WHERE u.email_normalized = p_email);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_registration_duplicates_v1(text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_user_v1(p_values jsonb)
RETURNS SETOF public.users
LANGUAGE sql
VOLATILE
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
    RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_user_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_update_user_v1(p_user_id uuid, p_changes jsonb)
RETURNS SETOF public.users
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_changes - ARRAY['password_hash', 'updated_at', 'email_normalized', 'email_verified_at', 'status', 'preferred_locale', 'preferred_theme', 'preferred_timezone'] <> '{}'::jsonb THEN
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
        preferred_timezone = CASE WHEN p_changes ? 'preferred_timezone' THEN (p_changes->>'preferred_timezone')::text ELSE u.preferred_timezone END
    WHERE u.id = p_user_id RETURNING u.*;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_credential_v1(p_values jsonb)
RETURNS SETOF public.credentials
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.credentials(id, user_id, type, secret_hash, created_at, revoked_at)
    VALUES ((p_values->>'id')::uuid, (p_values->>'user_id')::uuid, p_values->>'type',
        p_values->>'secret_hash', COALESCE((p_values->>'created_at')::timestamptz, now()),
        (p_values->>'revoked_at')::timestamptz) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_credential_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_credential_by_id_v1(p_credential_id uuid)
RETURNS SETOF public.credentials
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.* FROM public.credentials c WHERE c.id = p_credential_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_credential_by_id_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_active_password_v1(p_user_id uuid)
RETURNS SETOF public.credentials
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.* FROM public.credentials c WHERE c.user_id = p_user_id AND c.type = 'password'
        AND c.revoked_at IS NULL ORDER BY c.created_at DESC LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_active_password_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_hold_password_v1(p_user_id uuid, p_credential_id uuid)
RETURNS SETOF public.credentials
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.* FROM public.credentials c WHERE c.user_id = p_user_id AND c.id = p_credential_id
        AND c.type = 'password' AND c.revoked_at IS NULL FOR SHARE;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_hold_password_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_lock_passwords_v1(p_user_id uuid)
RETURNS SETOF public.credentials
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    v_round integer;
BEGIN
    FOR v_round IN 1..3 LOOP
        RETURN QUERY SELECT c.* FROM public.credentials c WHERE c.user_id = p_user_id
            AND c.type = 'password' AND c.revoked_at IS NULL FOR UPDATE;
        IF FOUND THEN RETURN; END IF;
        IF NOT EXISTS(SELECT 1 FROM public.credentials c WHERE c.user_id = p_user_id
            AND c.type = 'password' AND c.revoked_at IS NULL) THEN RETURN; END IF;
    END LOOP;
    RAISE EXCEPTION 'the password of % changed 3 times while this waited for it; try again', p_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_lock_passwords_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_revoke_passwords_v1(p_ids jsonb, p_revoked_at timestamptz)
RETURNS TABLE(updated integer)
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    WITH changed AS (UPDATE public.credentials c SET revoked_at = GREATEST(p_revoked_at, c.created_at)
        WHERE c.id IN (SELECT value::uuid FROM jsonb_array_elements_text(p_ids)) RETURNING 1)
    SELECT count(*)::integer FROM changed;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_revoke_passwords_v1(jsonb, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.identity_insert_token_v1(p_values jsonb)
RETURNS SETOF public.identity_tokens
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.identity_tokens (token_id, user_id, token_type, token_hash, email_normalized,
        created_at, expires_at, used_at, metadata)
    VALUES ((p_values->>'token_id')::uuid, (p_values->>'user_id')::uuid, p_values->>'token_type',
        p_values->>'token_hash', p_values->>'email_normalized',
        COALESCE((p_values->>'created_at')::timestamptz, now()), (p_values->>'expires_at')::timestamptz,
        (p_values->>'used_at')::timestamptz, COALESCE(p_values->'metadata', '{}'::jsonb)) RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_insert_token_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_token_by_id_v1(p_token_id uuid)
RETURNS SETOF public.identity_tokens
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.* FROM public.identity_tokens t WHERE t.token_id = p_token_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_token_by_id_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_unused_token_v1(p_user_id uuid, p_token_type text)
RETURNS SETOF public.identity_tokens
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.* FROM public.identity_tokens t WHERE t.user_id = p_user_id AND t.token_type = p_token_type
        AND t.used_at IS NULL LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_unused_token_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.identity_rotate_token_v1(p_token_id uuid, p_values jsonb)
RETURNS SETOF public.identity_tokens
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.identity_tokens t SET email_normalized = p_values->>'email_normalized',
        expires_at = (p_values->>'expires_at')::timestamptz, metadata = p_values->'metadata',
        token_hash = p_values->>'token_hash' WHERE t.token_id = p_token_id RETURNING t.*;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_rotate_token_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_consume_token_v1(p_token_hash text, p_token_type text, p_now timestamptz, p_now_epoch bigint)
RETURNS TABLE(result_code text, token_row jsonb)
LANGUAGE plpgsql
VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.identity_consume_token_v1(text, text, timestamptz, bigint) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_trust_v1(p_user_id uuid)
RETURNS SETOF public.trust_score_snapshots
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT t.* FROM public.trust_score_snapshots t WHERE t.user_id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_profile_trust_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_counts_v1(p_user_id uuid)
RETURNS TABLE(public_threads bigint, public_replies bigint, total_public bigint)
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

CREATE FUNCTION api.identity_profile_threads_v1(p_user_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS TABLE(thread_id uuid, category_id uuid, author_user_id uuid, title text, slug text, visibility text, moderation_state text, last_activity_at timestamptz, created_at timestamptz)
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
REVOKE EXECUTE ON FUNCTION api.identity_profile_threads_v1(uuid, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.identity_profile_replies_v1(p_user_id uuid, p_after_at timestamptz, p_after_id uuid, p_row_limit integer)
RETURNS TABLE(post_id uuid, thread_id uuid, author_user_id uuid, "position" bigint, visibility text, moderation_state text, created_at timestamptz, thread_title text, thread_slug text, body text)
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
REVOKE EXECUTE ON FUNCTION api.identity_profile_replies_v1(uuid, timestamptz, uuid, integer) FROM PUBLIC;

COMMIT;
