-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126, section 5: a command is one call. A registration ran as seven
-- functions while Perl kept the command log, a transaction and four
-- savepoints around them: 24 round trips. It is one call now:
-- api.identity_register_command_v1 opens the command log
-- (api.core_command_open_v1), refuses a taken username or email with the
-- answer Perl prepared, inserts the user and the password credential with
-- the recovery the stores had for a taken id, records the registration's
-- event and audit, the verification token, its audit and its mail through
-- the recording functions the stores called, and closes the command with
-- the answer the Perl path recorded. Perl still validates, hashes the
-- password, mints the ids, reads the clock and draws the token: the
-- function takes every row and document ready.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The user row inserted, or the open row already stored under its id with
-- the same username and email (a retried registration); a taken id that
-- belongs to another account raises, and the caller draws another id.
CREATE FUNCTION api.core_identity_store_user_v1(p_user jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    stored public.users;
    reported text;
BEGIN
    BEGIN
        SELECT * INTO stored FROM api.identity_insert_user_v1(p_user);
        RETURN to_jsonb(stored);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'users_pkey') THEN
            RETURN NULL;
        END IF;
        SELECT * INTO stored FROM api.identity_user_by_id_v1(
            (p_user ->> 'id')::uuid);
        IF NOT FOUND
            OR stored.username IS DISTINCT FROM p_user ->> 'username'
            OR stored.email_normalized IS DISTINCT FROM
                p_user ->> 'email_normalized'
        THEN
            RAISE;
        END IF;
        RETURN to_jsonb(stored);
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_store_user_v1(jsonb) FROM PUBLIC;

-- The password credential as CredentialStore creates it: none when the
-- account already has an active one, the row inserted, or the open row
-- stored under its id with the same secret; a taken id that is another's
-- is drawn again once.
CREATE FUNCTION api.core_identity_store_credential_v1(p_credential jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    row_in jsonb := p_credential;
    stored public.credentials;
    reported text;
BEGIN
    SELECT * INTO stored FROM api.identity_active_password_v1(
        (row_in ->> 'user_id')::uuid);
    IF FOUND THEN
        RETURN to_jsonb(stored);
    END IF;
    FOR attempt IN 1 .. 2 LOOP
        BEGIN
            SELECT * INTO stored
            FROM api.identity_insert_credential_v1(row_in);
            RETURN to_jsonb(stored);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported, 'credentials_pkey') THEN
                RAISE;
            END IF;
            SELECT * INTO stored FROM api.identity_credential_by_id_v1(
                (row_in ->> 'id')::uuid);
            IF FOUND AND stored.revoked_at IS NULL
                AND stored.user_id = (row_in ->> 'user_id')::uuid
                AND stored.type = row_in ->> 'type'
                AND stored.secret_hash = row_in ->> 'secret_hash'
            THEN
                RETURN to_jsonb(stored);
            END IF;
            IF attempt = 2 THEN
                RAISE;
            END IF;
            row_in := row_in || jsonb_build_object('id',
                api.core_uuid_v7_v1()::text);
        END;
    END LOOP;
    RETURN NULL;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_store_credential_v1(jsonb)
    FROM PUBLIC;

-- The verification token as TokenStore issues it: the row inserted, the
-- open row stored under its id with the same hash, or a taken id drawn
-- again once. A taken hash is the caller's to draw again: the raw token
-- is theirs, so the call raises.
CREATE FUNCTION api.core_identity_store_token_v1(p_token jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    row_in jsonb := p_token;
    stored public.identity_tokens;
    reported text;
BEGIN
    FOR attempt IN 1 .. 2 LOOP
        BEGIN
            SELECT * INTO stored FROM api.identity_insert_token_v1(row_in);
            RETURN to_jsonb(stored);
        EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
            IF NOT api.core_unique_on_v1(reported, 'identity_tokens_pkey') THEN
                RAISE;
            END IF;
            SELECT * INTO stored FROM public.identity_tokens me
            WHERE me.token_id = (row_in ->> 'token_id')::uuid;
            IF FOUND AND stored.used_at IS NULL
                AND stored.token_hash = row_in ->> 'token_hash'
                AND stored.token_type = row_in ->> 'token_type'
                AND stored.user_id IS NOT DISTINCT FROM
                    (row_in ->> 'user_id')::uuid
            THEN
                RETURN to_jsonb(stored);
            END IF;
            IF attempt = 2 THEN
                RAISE;
            END IF;
            row_in := row_in || jsonb_build_object('token_id',
                api.core_uuid_v7_v1()::text);
        END;
    END LOOP;
    RETURN NULL;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_identity_store_token_v1(jsonb) FROM PUBLIC;

-- The registration as one call. p_answer is an answer decided before the
-- call (the composer's refusal of the input), recorded without a write.
-- Otherwise a taken username or email records p_refused; else the writes
-- happen and p_accepted is recorded. The rows and documents are the ones
-- the stores sent one by one.
CREATE FUNCTION api.identity_register_command_v1(p_log jsonb, p_answer jsonb,
    p_accepted jsonb, p_refused jsonb, p_user jsonb, p_credential jsonb,
    p_event jsonb, p_event_outbox_id text, p_audit jsonb, p_token jsonb,
    p_token_audit jsonb, p_mail_event jsonb, p_mail_outbox_id text,
    p_mail_outbox_extras jsonb)
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
REVOKE EXECUTE ON FUNCTION api.identity_register_command_v1(jsonb, jsonb,
    jsonb, jsonb, jsonb, jsonb, jsonb, text, jsonb, jsonb, jsonb, jsonb, text,
    jsonb) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.identity_register_command_v2(
p_log jsonb, p_answer jsonb, p_accepted jsonb, p_refused jsonb, p_user jsonb,
p_credential jsonb, p_event jsonb, p_event_outbox_id text, p_audit jsonb,
p_token jsonb, p_token_audit jsonb, p_mail_event jsonb, p_mail_outbox_id text,
p_mail_outbox_extras jsonb
)
RETURNS TABLE (outcome text, response json, stored_user json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.identity_register_command_v1(p_log, p_answer, p_accepted,
    p_refused, p_user, p_credential, p_event, p_event_outbox_id, p_audit,
    p_token, p_token_audit, p_mail_event, p_mail_outbox_id,
    p_mail_outbox_extras);
$$;
REVOKE EXECUTE ON FUNCTION api.identity_register_command_v2(jsonb, jsonb,
    jsonb, jsonb, jsonb, jsonb, jsonb, text, jsonb, jsonb, jsonb, jsonb, text,
    jsonb) FROM PUBLIC;

COMMIT;
