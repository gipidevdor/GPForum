-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE public.passkey_accounts (
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    rp_id text NOT NULL,
    user_handle text NOT NULL UNIQUE CHECK (length(user_handle) BETWEEN 32 AND 86),
    PRIMARY KEY(user_id,rp_id)
);
COMMENT ON TABLE public.passkey_accounts IS 'Stable opaque WebAuthn user handles per account and relying party.';
CREATE TABLE public.passkeys (
    id uuid PRIMARY KEY REFERENCES public.credentials(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    rp_id text NOT NULL,
    credential_id_b64 text NOT NULL UNIQUE CHECK (length(credential_id_b64) BETWEEN 1 AND 1364),
    credential_public_key_b64 text NOT NULL,
    sign_count bigint NOT NULL CHECK (sign_count BETWEEN 0 AND 4294967295),
    backup_eligible boolean NOT NULL,
    label text NOT NULL CHECK (length(label) BETWEEN 1 AND 100),
    last_used_at timestamptz,
    FOREIGN KEY(user_id,rp_id) REFERENCES public.passkey_accounts(user_id,rp_id) ON DELETE CASCADE
);
COMMENT ON TABLE public.passkeys IS 'Verified WebAuthn public keys; revocation lives in credentials and follows account erasure.';
CREATE INDEX idx_passkeys_account ON public.passkeys(user_id,rp_id);
CREATE TABLE public.passkey_challenges (
    challenge_hash text PRIMARY KEY,
    binding_hash text NOT NULL,
    purpose text NOT NULL CHECK (purpose IN ('register','login')),
    rp_id text NOT NULL,
    origin text NOT NULL,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    session_id uuid REFERENCES public.sessions(session_id) ON DELETE CASCADE,
    password_id uuid REFERENCES public.credentials(id) ON DELETE CASCADE,
    label text,
    expires_at timestamptz NOT NULL DEFAULT now()+interval '5 minutes',
    UNIQUE(binding_hash,purpose)
);
COMMENT ON TABLE public.passkey_challenges IS 'Single-use, expiring WebAuthn ceremonies bound to a browser and exact configured origin.';
CREATE INDEX idx_passkey_challenges_expiry ON public.passkey_challenges(expires_at);

CREATE FUNCTION api.identity_passkey_begin_v1(p_input jsonb)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE member public.users; handle text;
BEGIN
    IF p_input->>'purpose' NOT IN ('register','login') THEN RETURN; END IF;
    DELETE FROM public.passkey_challenges WHERE challenge_hash IN
        (SELECT c.challenge_hash FROM public.passkey_challenges c WHERE c.expires_at<now() LIMIT 100);
    IF p_input->>'purpose'='register' THEN
        PERFORM 1 FROM public.credentials c WHERE c.id=(p_input->>'password_id')::uuid
          AND c.user_id=(p_input->>'user_id')::uuid AND c.type='password' AND c.revoked_at IS NULL FOR SHARE;
        IF NOT FOUND THEN RETURN; END IF;
        SELECT u.* INTO member FROM public.users u WHERE u.id=(p_input->>'user_id')::uuid AND u.status='active';
        IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.sessions s
          WHERE s.session_id=(p_input->>'session_id')::uuid AND s.user_id=member.id
          AND s.revoked_at IS NULL AND s.expires_at>now()) THEN RETURN; END IF;
        INSERT INTO public.passkey_accounts(user_id,rp_id,user_handle)
          VALUES(member.id,p_input->>'rp_id',p_input->>'user_handle') ON CONFLICT(user_id,rp_id) DO NOTHING;
        SELECT a.user_handle INTO handle FROM public.passkey_accounts a
          WHERE a.user_id=member.id AND a.rp_id=p_input->>'rp_id';
    END IF;
    DELETE FROM public.passkey_challenges c WHERE c.binding_hash=p_input->>'binding_hash'
      AND c.purpose=p_input->>'purpose';
    INSERT INTO public.passkey_challenges(challenge_hash,binding_hash,purpose,rp_id,origin,user_id,session_id,password_id,label)
      VALUES(p_input->>'challenge_hash',p_input->>'binding_hash',p_input->>'purpose',p_input->>'rp_id',p_input->>'origin',
        member.id,(p_input->>'session_id')::uuid,(p_input->>'password_id')::uuid,p_input->>'label');
    RETURN QUERY SELECT jsonb_build_object('user_handle',handle,'name',member.username,'display_name',member.display_name);
END;
$$;

CREATE FUNCTION api.identity_passkey_consume_v1(p_input jsonb)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DELETE FROM public.passkey_challenges c WHERE c.challenge_hash=p_input->>'challenge_hash'
  AND c.binding_hash=p_input->>'binding_hash' AND c.purpose=p_input->>'purpose'
  AND c.rp_id=p_input->>'rp_id' AND c.origin=p_input->>'origin' AND c.expires_at>now()
  AND c.user_id IS NOT DISTINCT FROM (p_input->>'user_id')::uuid
  AND c.session_id IS NOT DISTINCT FROM (p_input->>'session_id')::uuid
RETURNING to_jsonb(c);
$$;

CREATE FUNCTION api.identity_passkey_list_v1(p_user_id uuid,p_rp_id text)
RETURNS TABLE(result jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object('id',k.id,'credential_id_b64',k.credential_id_b64,
  'label',k.label,'created_at',c.created_at,'last_used_at',k.last_used_at)
FROM public.passkeys k JOIN public.credentials c ON c.id=k.id
WHERE k.user_id=p_user_id AND k.rp_id=p_rp_id AND c.revoked_at IS NULL
ORDER BY c.created_at,k.id LIMIT 10;
$$;

CREATE FUNCTION api.identity_passkey_register_v1(p_input jsonb)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM 1 FROM public.credentials c WHERE c.id=(p_input->>'password_id')::uuid
      AND c.user_id=(p_input->>'user_id')::uuid AND c.type='password' AND c.revoked_at IS NULL FOR SHARE;
    IF NOT FOUND THEN RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.sessions s WHERE s.session_id=(p_input->>'session_id')::uuid
      AND s.user_id=(p_input->>'user_id')::uuid AND s.revoked_at IS NULL AND s.expires_at>now()) THEN RETURN; END IF;
    PERFORM 1 FROM public.passkey_accounts a WHERE a.user_id=(p_input->>'user_id')::uuid
      AND a.rp_id=p_input->>'rp_id' FOR UPDATE;
    IF NOT FOUND OR (SELECT count(*) FROM public.passkeys k JOIN public.credentials c ON c.id=k.id
      WHERE k.user_id=(p_input->>'user_id')::uuid AND c.revoked_at IS NULL)>=10 THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.passkeys k WHERE k.credential_id_b64=p_input->>'credential_id_b64') THEN RETURN; END IF;
    INSERT INTO public.credentials(id,user_id,type,secret_hash)
      VALUES((p_input->>'id')::uuid,(p_input->>'user_id')::uuid,'webauthn','public-key');
    INSERT INTO public.passkeys(id,user_id,rp_id,credential_id_b64,credential_public_key_b64,sign_count,backup_eligible,label)
      VALUES((p_input->>'id')::uuid,(p_input->>'user_id')::uuid,p_input->>'rp_id',p_input->>'credential_id_b64',
        p_input->>'credential_public_key_b64',(p_input->>'sign_count')::bigint,(p_input->>'backup_eligible')::boolean,p_input->>'label');
    RETURN QUERY SELECT jsonb_build_object('status','registered','id',p_input->>'id');
END;
$$;

CREATE FUNCTION api.identity_passkey_resolve_v1(p_credential_id_b64 text,p_rp_id text)
RETURNS TABLE(result jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT to_jsonb(k)||jsonb_build_object('user_handle',a.user_handle,'password_id',pw.id)
FROM public.passkeys k JOIN public.credentials c ON c.id=k.id
JOIN public.passkey_accounts a ON a.user_id=k.user_id AND a.rp_id=k.rp_id
JOIN public.users u ON u.id=k.user_id
JOIN public.credentials pw ON pw.user_id=u.id AND pw.type='password' AND pw.revoked_at IS NULL
WHERE k.credential_id_b64=p_credential_id_b64 AND k.rp_id=p_rp_id
  AND c.revoked_at IS NULL AND u.status NOT IN ('pending','deleted') AND u.deleted_at IS NULL;
$$;

CREATE FUNCTION api.identity_passkey_advance_v1(p_id uuid,p_password_id uuid,p_sign_count bigint)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.passkeys;
BEGIN
    PERFORM 1 FROM public.credentials c WHERE c.id=p_password_id AND c.type='password' AND c.revoked_at IS NULL FOR SHARE;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.credentials c JOIN public.passkeys k ON k.id=c.id
      WHERE c.id=p_id AND c.revoked_at IS NULL AND k.user_id=c.user_id
      AND c.user_id=(SELECT p.user_id FROM public.credentials p WHERE p.id=p_password_id) FOR SHARE OF c;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT k.* INTO held FROM public.passkeys k WHERE k.id=p_id FOR UPDATE;
    IF NOT held.backup_eligible AND (held.sign_count>0 OR p_sign_count>0) AND p_sign_count<=held.sign_count THEN RETURN; END IF;
    UPDATE public.passkeys SET sign_count=greatest(sign_count,p_sign_count),last_used_at=now() WHERE id=p_id;
    RETURN QUERY SELECT to_jsonb(u) FROM public.users u WHERE u.id=held.user_id
      AND u.status NOT IN ('pending','deleted') AND u.deleted_at IS NULL;
END;
$$;

CREATE FUNCTION api.identity_passkey_revoke_v1(p_user_id uuid,p_id uuid,p_password_id uuid,p_session_id uuid)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM 1 FROM public.credentials c WHERE c.id=p_password_id AND c.user_id=p_user_id
      AND c.type='password' AND c.revoked_at IS NULL FOR SHARE;
    IF NOT FOUND THEN RETURN; END IF;
    UPDATE public.credentials c SET revoked_at=greatest(now(),c.created_at)
      WHERE c.id=p_id AND c.user_id=p_user_id AND c.type='webauthn' AND c.revoked_at IS NULL;
    IF NOT FOUND THEN RETURN; END IF;
    UPDATE public.sessions s SET revoked_at=greatest(now(),s.created_at)
      WHERE s.user_id=p_user_id AND s.revoked_at IS NULL AND s.session_id IS DISTINCT FROM p_session_id;
    UPDATE public.second_factor_challenges c SET closed_at=now() WHERE c.user_id=p_user_id AND c.closed_at IS NULL;
    RETURN QUERY SELECT jsonb_build_object('status','revoked');
END;
$$;

CREATE FUNCTION api.core_identity_passkey_recovery_v1()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    UPDATE public.credentials c SET revoked_at=greatest(now(),c.created_at)
      WHERE c.user_id=NEW.user_id AND c.type='webauthn' AND c.revoked_at IS NULL;
    DELETE FROM public.passkey_challenges c WHERE c.user_id=NEW.user_id;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_passkey_recovery_v1() FROM PUBLIC;
CREATE TRIGGER credentials_passkey_recovery AFTER UPDATE OF revoked_at ON public.credentials
  FOR EACH ROW WHEN (NEW.type='password' AND OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL)
  EXECUTE FUNCTION api.core_identity_passkey_recovery_v1();

REVOKE EXECUTE ON FUNCTION api.identity_passkey_begin_v1(p_input jsonb) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_begin_v2(p_input jsonb)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_begin_v1(p_input);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_begin_v2(p_input jsonb) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION api.identity_passkey_consume_v1(p_input jsonb) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_consume_v2(p_input jsonb)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_consume_v1(p_input);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_consume_v2(p_input jsonb) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION api.identity_passkey_list_v1(p_user_id uuid,p_rp_id text) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_list_v2(p_user_id uuid,p_rp_id text)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_list_v1(p_user_id,p_rp_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_list_v2(p_user_id uuid,p_rp_id text) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION api.identity_passkey_register_v1(p_input jsonb) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_register_v2(p_input jsonb)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_register_v1(p_input);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_register_v2(p_input jsonb) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION api.identity_passkey_resolve_v1(p_credential_id_b64 text,p_rp_id text) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_resolve_v2(p_credential_id_b64 text,p_rp_id text)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_resolve_v1(p_credential_id_b64,p_rp_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_resolve_v2(p_credential_id_b64 text,p_rp_id text) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION api.identity_passkey_advance_v1(p_id uuid,p_password_id uuid,p_sign_count bigint) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_advance_v2(p_id uuid,p_password_id uuid,p_sign_count bigint)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_advance_v1(p_id,p_password_id,p_sign_count);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_advance_v2(p_id uuid,p_password_id uuid,p_sign_count bigint) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION api.identity_passkey_revoke_v1(p_user_id uuid,p_id uuid,p_password_id uuid,p_session_id uuid) FROM PUBLIC;
CREATE FUNCTION api.identity_passkey_revoke_v2(p_user_id uuid,p_id uuid,p_password_id uuid,p_session_id uuid)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_passkey_revoke_v1(p_user_id,p_id,p_password_id,p_session_id);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_passkey_revoke_v2(p_user_id uuid,p_id uuid,p_password_id uuid,p_session_id uuid) FROM PUBLIC;

CREATE FUNCTION api.core_identity_passkey_erasure_v1()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    DELETE FROM public.passkey_challenges c WHERE c.user_id=NEW.id;
    DELETE FROM public.passkey_accounts a WHERE a.user_id=NEW.id;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_passkey_erasure_v1() FROM PUBLIC;
CREATE TRIGGER users_passkey_erasure AFTER UPDATE OF status,deleted_at ON public.users
  FOR EACH ROW WHEN (NEW.status='deleted' OR NEW.deleted_at IS NOT NULL)
  EXECUTE FUNCTION api.core_identity_passkey_erasure_v1();

CREATE FUNCTION api.portability_export_parts_v33(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('passkeys',coalesce((
    SELECT jsonb_agg(jsonb_build_object('id',k.id,'label',k.label,'rp_id',k.rp_id,
        'created_at',c.created_at,'last_used_at',k.last_used_at,'revoked_at',c.revoked_at)
        ORDER BY c.created_at,k.id)
    FROM public.passkeys k JOIN public.credentials c ON c.id=k.id
    WHERE k.user_id=p_user_id),'[]'::jsonb)))::json
FROM api.portability_export_parts_v31(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v33(uuid) FROM PUBLIC;
CREATE FUNCTION api.portability_export_parts_v34(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v33(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v34(uuid) FROM PUBLIC;

COMMIT;
