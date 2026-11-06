-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '1s';
CREATE TABLE public.oidc_account_links (
    issuer text NOT NULL CHECK(octet_length(issuer) BETWEEN 1 AND 2048),
    subject text NOT NULL CHECK(length(subject) BETWEEN 1 AND 255),
    user_id uuid NOT NULL REFERENCES public.users ON DELETE CASCADE,
    credential_id uuid NOT NULL REFERENCES public.credentials ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(issuer,subject),
    UNIQUE(issuer,user_id)
);
COMMENT ON TABLE public.oidc_account_links IS 'Explicit issuer/subject bindings to an existing local account and its password generation; email never links identities.';
CREATE INDEX oidc_account_links_user ON public.oidc_account_links(user_id);
CREATE INDEX oidc_account_links_credential ON public.oidc_account_links(credential_id);
CREATE TABLE public.oidc_login_transactions (
    state_hash text PRIMARY KEY CHECK(state_hash ~ '^[0-9a-f]{64}$'),
    binding_hash text NOT NULL CHECK(binding_hash ~ '^[0-9a-f]{64}$'),
    context_hash text NOT NULL CHECK(context_hash ~ '^[0-9a-f]{64}$'),
    nonce text NOT NULL CHECK(length(nonce)=43),
    user_id uuid REFERENCES public.users ON DELETE CASCADE,
    credential_id uuid REFERENCES public.credentials ON DELETE CASCADE,
    expires_at timestamptz NOT NULL DEFAULT now()+interval '5 minutes',
    CHECK((user_id IS NULL)=(credential_id IS NULL))
);
COMMENT ON TABLE public.oidc_login_transactions IS 'Five-minute single-use OIDC state bound to the initiating browser and pinned provider configuration; no tokens persist.';
CREATE INDEX oidc_login_transactions_expiry ON public.oidc_login_transactions(expires_at);
CREATE INDEX oidc_login_transactions_user ON public.oidc_login_transactions(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX oidc_login_transactions_credential ON public.oidc_login_transactions(credential_id) WHERE credential_id IS NOT NULL;

CREATE FUNCTION api.identity_oidc_begin_v1(p_state_hash text, p_binding_hash text, p_context_hash text, p_nonce text, p_actor uuid, p_credential uuid) RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    DELETE FROM public.oidc_login_transactions WHERE state_hash IN
        (SELECT state_hash FROM public.oidc_login_transactions WHERE expires_at<now() ORDER BY expires_at LIMIT 100);
    IF p_actor IS NOT NULL THEN
        PERFORM 1 FROM public.credentials c JOIN public.users u ON u.id=c.user_id
            WHERE c.id=p_credential AND c.user_id=p_actor AND c.revoked_at IS NULL AND c.type='password' AND u.status='active'
            FOR UPDATE OF c,u;
        IF NOT FOUND THEN RETURN; END IF;
    END IF;
    INSERT INTO public.oidc_login_transactions(state_hash,binding_hash,context_hash,nonce,user_id,credential_id)
        VALUES(p_state_hash,p_binding_hash,p_context_hash,p_nonce,p_actor,p_credential);
    RETURN QUERY SELECT jsonb_build_object('status','ok');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_begin_v1(text, text, text, text, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_begin_v2(p_state_hash text, p_binding_hash text, p_context_hash text, p_nonce text, p_actor uuid, p_credential uuid) RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_oidc_begin_v1(p_state_hash, p_binding_hash, p_context_hash, p_nonce, p_actor, p_credential);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_begin_v2(text, text, text, text, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_consume_v1(p_state_hash text, p_binding_hash text, p_context_hash text) RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.oidc_login_transactions;
BEGIN
    DELETE FROM public.oidc_login_transactions WHERE state_hash=p_state_hash AND binding_hash=p_binding_hash
        AND context_hash=p_context_hash AND expires_at>clock_timestamp() RETURNING * INTO held;
    IF FOUND THEN RETURN QUERY SELECT jsonb_build_object('nonce',held.nonce,'user_id',held.user_id,'credential_id',held.credential_id); END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_consume_v1(text, text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_consume_v2(p_state_hash text, p_binding_hash text, p_context_hash text) RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_oidc_consume_v1(p_state_hash, p_binding_hash, p_context_hash);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_consume_v2(text, text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_link_v1(p_actor uuid, p_credential uuid, p_issuer text, p_subject text) RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.oidc_account_links;
BEGIN
    PERFORM 1 FROM public.credentials c JOIN public.users u ON u.id=c.user_id
        WHERE c.id=p_credential AND c.user_id=p_actor AND c.revoked_at IS NULL AND c.type='password' AND u.status='active' FOR UPDATE OF c,u;
    IF NOT FOUND THEN RETURN QUERY SELECT jsonb_build_object('status','refused'); RETURN; END IF;
    INSERT INTO public.oidc_account_links(issuer,subject,user_id,credential_id)
        VALUES(p_issuer,p_subject,p_actor,p_credential) ON CONFLICT DO NOTHING;
    SELECT * INTO held FROM public.oidc_account_links WHERE issuer=p_issuer AND subject=p_subject FOR UPDATE;
    IF NOT FOUND OR held.user_id<>p_actor THEN RETURN QUERY SELECT jsonb_build_object('status','conflict'); RETURN; END IF;
    UPDATE public.oidc_account_links SET credential_id=p_credential WHERE issuer=p_issuer AND subject=p_subject;
    RETURN QUERY SELECT jsonb_build_object('status','linked');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_link_v1(uuid, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_link_v2(p_actor uuid, p_credential uuid, p_issuer text, p_subject text) RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_oidc_link_v1(p_actor, p_credential, p_issuer, p_subject);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_link_v2(uuid, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_resolve_v1(p_issuer text, p_subject text) RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE member record; link public.oidc_account_links;
BEGIN
    SELECT * INTO link FROM public.oidc_account_links WHERE issuer=p_issuer AND subject=p_subject;
    IF NOT FOUND THEN RETURN; END IF;
    -- Match the credential -> user -> link order used by linking/recovery.
    SELECT u.id,u.preferred_locale,u.preferred_theme,u.preferred_timezone,c.id AS credential_id INTO member
        FROM public.credentials c JOIN public.users u ON u.id=c.user_id
        WHERE c.id=link.credential_id AND u.id=link.user_id AND u.status='active'
            AND c.type='password' AND c.revoked_at IS NULL FOR UPDATE OF c,u;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.oidc_account_links l WHERE l.issuer=p_issuer AND l.subject=p_subject
        AND l.user_id=member.id AND l.credential_id=member.credential_id FOR UPDATE;
    IF FOUND THEN RETURN QUERY SELECT to_jsonb(member); END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_resolve_v1(text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_resolve_v2(p_issuer text, p_subject text) RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_oidc_resolve_v1(p_issuer, p_subject);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_resolve_v2(text, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_unlink_v1(p_actor uuid, p_credential uuid, p_issuer text, p_session uuid) RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM 1 FROM public.credentials c JOIN public.users u ON u.id=c.user_id
        WHERE c.id=p_credential AND c.user_id=p_actor AND c.revoked_at IS NULL AND c.type='password' AND u.status='active'
        FOR UPDATE OF c,u;
    IF NOT FOUND THEN RETURN QUERY SELECT jsonb_build_object('status','refused'); RETURN; END IF;
    DELETE FROM public.oidc_account_links WHERE issuer=p_issuer AND user_id=p_actor;
    DELETE FROM public.oidc_login_transactions WHERE user_id=p_actor;
    DELETE FROM public.second_factor_challenges WHERE user_id=p_actor;
    UPDATE public.sessions SET revoked_at=greatest(clock_timestamp(),created_at)
        WHERE user_id=p_actor AND revoked_at IS NULL AND session_id IS DISTINCT FROM p_session;
    RETURN QUERY SELECT jsonb_build_object('status','unlinked');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_unlink_v1(uuid, uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_unlink_v2(p_actor uuid, p_credential uuid, p_issuer text, p_session uuid) RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_oidc_unlink_v1(p_actor, p_credential, p_issuer, p_session);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_unlink_v2(uuid, uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_status_v1(p_actor uuid, p_issuer text) RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object('linked',EXISTS(SELECT 1 FROM public.oidc_account_links l JOIN public.credentials c ON c.id=l.credential_id
    WHERE l.user_id=p_actor AND l.issuer=p_issuer AND c.revoked_at IS NULL AND c.user_id=p_actor));
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_status_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.identity_oidc_status_v2(p_actor uuid, p_issuer text) RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_oidc_status_v1(p_actor, p_issuer);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_oidc_status_v2(uuid, text) FROM PUBLIC;

COMMIT;
