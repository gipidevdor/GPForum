-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.registration_policy (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    mode text NOT NULL DEFAULT 'open' CHECK (mode IN ('open','invite','closed')),
    approval_required boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid REFERENCES public.users(id) ON DELETE SET NULL
);
INSERT INTO public.registration_policy(singleton) VALUES (true);
COMMENT ON TABLE public.registration_policy IS 'Registration mode and independent staff approval policy for new accounts.';
CREATE TABLE public.registration_invitations (
    invitation_id uuid PRIMARY KEY,
    token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    email_normalized text NOT NULL CHECK (length(email_normalized) BETWEEN 3 AND 254),
    created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
    used_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    used_at timestamptz,
    revoked_at timestamptz
);
CREATE INDEX idx_registration_invitations_expiry ON public.registration_invitations(expires_at,invitation_id);
COMMENT ON TABLE public.registration_invitations IS 'Email-bound single-use invitation hashes; raw invitation secrets are never persisted.';
CREATE TABLE public.registration_reviews (
    user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    decision text NOT NULL DEFAULT 'pending' CHECK (decision IN ('pending','approved','rejected')),
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    decided_by uuid REFERENCES public.users(id) ON DELETE SET NULL
);
CREATE INDEX idx_registration_reviews_pending ON public.registration_reviews(created_at,user_id) WHERE decision = 'pending';
COMMENT ON TABLE public.registration_reviews IS 'Independent staff admission decisions; email verification alone cannot approve an account.';

CREATE FUNCTION api.admin_registration_state_v1(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'admin_console','view') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('status','ok',
        'policy',(SELECT to_jsonb(p)-'updated_by' FROM public.registration_policy p),
        'reviews',coalesce((SELECT jsonb_agg(x) FROM (SELECT r.user_id,u.username,
            u.email_verified_at,r.created_at FROM public.registration_reviews r
            JOIN public.users u ON u.id = r.user_id
            WHERE r.decision = 'pending' AND u.deleted_at IS NULL
            ORDER BY r.created_at,r.user_id LIMIT 100) x),'[]'::jsonb),
        'invitations',coalesce((SELECT jsonb_agg(x) FROM (SELECT i.invitation_id,
            i.email_normalized,i.expires_at,i.used_at,i.revoked_at FROM public.registration_invitations i
            ORDER BY i.created_at DESC,i.invitation_id DESC LIMIT 100) x),'[]'::jsonb));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_registration_state_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_registration_state_v2(p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_registration_state_v1(p_actor);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_registration_state_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_registration_change_v1(p_actor uuid, p_command uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; answer jsonb; target uuid; held record;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'admin_console','manage') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    IF p_operation IS NULL OR p_operation NOT IN ('policy','invite','revoke','approve','reject') OR p_values IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,
        'identity.admission.' || p_operation,p_values - 'token_hash');
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')) || jsonb_build_object('replayed',true); RETURN;
    END IF;
    IF p_operation = 'policy' THEN
        IF p_values->>'mode' IS NULL OR p_values->>'mode' NOT IN ('open','invite','closed')
            OR jsonb_typeof(p_values->'approval_required') IS DISTINCT FROM 'boolean' THEN
            answer := jsonb_build_object('status','invalid');
        ELSE
            UPDATE public.registration_policy SET mode = p_values->>'mode',
                approval_required = (p_values->>'approval_required')::boolean,
                updated_at = clock_timestamp(),updated_by = p_actor WHERE singleton;
            answer := jsonb_build_object('status','ok');
        END IF;
    ELSIF p_operation = 'invite' THEN
        IF coalesce(p_values->>'email','') !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$'
            OR length(p_values->>'email') > 254 OR coalesce(p_values->>'token_hash','') !~ '^[0-9a-f]{64}$' THEN
            answer := jsonb_build_object('status','invalid');
        ELSE
            INSERT INTO public.registration_invitations(invitation_id,token_hash,email_normalized,created_by,expires_at)
            VALUES (p_command,p_values->>'token_hash',lower(btrim(p_values->>'email')),p_actor,clock_timestamp()+interval '7 days');
            answer := jsonb_build_object('status','ok','invitation_id',p_command);
        END IF;
    ELSIF p_operation = 'revoke' THEN
        target := (p_values->>'invitation_id')::uuid;
        UPDATE public.registration_invitations i SET revoked_at = coalesce(i.revoked_at,clock_timestamp())
        WHERE i.invitation_id = target AND i.used_at IS NULL;
        answer := jsonb_build_object('status',CASE WHEN FOUND THEN 'ok' ELSE 'not_found' END);
    ELSE
        target := (p_values->>'user_id')::uuid;
        -- User before review in both approval and email verification.
        PERFORM 1 FROM public.users u WHERE u.id = target AND u.status = 'pending' FOR UPDATE;
        IF NOT FOUND THEN
            answer := jsonb_build_object('status','conflict');
        ELSE
            SELECT * INTO held FROM public.registration_reviews r WHERE r.user_id = target FOR UPDATE;
            IF NOT FOUND OR held.decision <> 'pending' THEN
                answer := jsonb_build_object('status','conflict');
            ELSE
                UPDATE public.registration_reviews SET decision = CASE WHEN p_operation = 'approve' THEN 'approved' ELSE 'rejected' END,
                    decided_at = clock_timestamp(),decided_by = p_actor WHERE user_id = target;
                UPDATE public.users u SET status = CASE WHEN p_operation = 'approve' AND u.email_verified_at IS NOT NULL THEN 'active' ELSE 'pending' END,
                    updated_at = clock_timestamp(),version = u.version+1,permission_version = u.permission_version+1 WHERE u.id = target;
                answer := jsonb_build_object('status','ok');
            END IF;
        END IF;
    END IF;
    IF answer->>'status' = 'ok' THEN
        PERFORM api.core_product_audit_v1(p_actor,p_command,'identity.admission.' || p_operation,
            coalesce(target,p_command),'registration',CASE WHEN p_operation = 'policy' THEN p_values ELSE '{}'::jsonb END);
    END IF;
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_registration_change_v1(uuid, uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_registration_change_v2(p_actor uuid, p_command uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_registration_change_v1(p_actor, p_command, p_operation, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_registration_change_v2(uuid, uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_register_command_v3(p_log jsonb, p_answer jsonb, p_accepted jsonb, p_refused jsonb, p_user jsonb, p_credential jsonb, p_event jsonb, p_event_outbox_id text, p_audit jsonb, p_token jsonb, p_token_audit jsonb, p_mail_event jsonb, p_mail_outbox_id text, p_mail_outbox_extras jsonb, p_invitation_hash text)
RETURNS TABLE (outcome text, response json, stored_user json)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    taken record;
    user_row jsonb;
    policy public.registration_policy;
    invitation public.registration_invitations;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json, NULL::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT * INTO policy FROM public.registration_policy WHERE singleton FOR SHARE;
        IF policy.mode = 'closed' THEN answer := p_refused; END IF;
        IF policy.mode = 'invite' OR p_invitation_hash IS NOT NULL THEN
            SELECT * INTO invitation FROM public.registration_invitations i
                WHERE i.token_hash = p_invitation_hash FOR UPDATE;
            IF NOT FOUND OR invitation.used_at IS NOT NULL OR invitation.revoked_at IS NOT NULL
                OR invitation.expires_at <= clock_timestamp()
                OR invitation.email_normalized <> p_user->>'email_normalized' THEN answer := p_refused; END IF;
        END IF;
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
            IF policy.approval_required THEN
                INSERT INTO public.registration_reviews(user_id) VALUES ((user_row->>'id')::uuid);
            END IF;
            IF invitation.invitation_id IS NOT NULL THEN
                UPDATE public.registration_invitations SET used_at = clock_timestamp(),used_by = (user_row->>'id')::uuid
                    WHERE invitation_id = invitation.invitation_id;
            END IF;
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
REVOKE EXECUTE ON FUNCTION api.identity_register_command_v3(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text, jsonb, jsonb, jsonb, jsonb, text, jsonb, text) FROM PUBLIC;

CREATE FUNCTION api.identity_register_command_v4(p_log jsonb, p_answer jsonb, p_accepted jsonb, p_refused jsonb, p_user jsonb, p_credential jsonb, p_event jsonb, p_event_outbox_id text, p_audit jsonb, p_token jsonb, p_token_audit jsonb, p_mail_event jsonb, p_mail_outbox_id text, p_mail_outbox_extras jsonb, p_invitation_hash text)
RETURNS TABLE (outcome text, response json, stored_user json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_register_command_v3(p_log, p_answer, p_accepted, p_refused, p_user, p_credential, p_event, p_event_outbox_id, p_audit, p_token, p_token_audit, p_mail_event, p_mail_outbox_id, p_mail_outbox_extras, p_invitation_hash);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_register_command_v4(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text, jsonb, jsonb, jsonb, jsonb, text, jsonb, text) FROM PUBLIC;

CREATE FUNCTION api.identity_update_user_v5(p_user_id uuid, p_changes jsonb)
RETURNS SETOF api.identity_user_v1
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE changes jsonb := p_changes;
BEGIN
    PERFORM 1 FROM public.users u WHERE u.id = p_user_id FOR UPDATE;
    IF changes->>'status' = 'active' AND EXISTS (SELECT 1 FROM public.registration_reviews r
        WHERE r.user_id = p_user_id AND r.decision <> 'approved') THEN
        changes := changes || jsonb_build_object('status','pending');
    END IF;
    RETURN QUERY SELECT * FROM api.identity_update_user_v3(p_user_id,changes);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v5(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.identity_update_user_v6(p_user_id uuid, p_changes jsonb)
RETURNS SETOF api.identity_user_v1
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_update_user_v5(p_user_id, p_changes);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_update_user_v6(uuid, jsonb) FROM PUBLIC;

COMMIT;
