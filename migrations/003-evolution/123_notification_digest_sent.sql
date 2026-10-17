-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0078, amendment of 2026-10-17: a digest is mailed at most once. The
-- worker claims its record before it hands the mail to the transport; a
-- second delivery of the event -- the outbox retrying after the mail went
-- out but before the job was marked done -- finds it claimed and sends
-- nothing. A transport that refuses the mail gives the claim back, so the
-- retry sends it.

BEGIN;
SET LOCAL lock_timeout = '1s';

ALTER TABLE public.notification_digests ADD COLUMN sent_at timestamptz;

-- Claims the queued digest p_event_id of the member's window for sending:
-- claimed the first time, sent when it already was, missing when no such
-- queued digest is recorded (or its record is past keeping), and invalid
-- without its arguments.
CREATE FUNCTION api.notification_digest_claim_v1(p_user_id uuid,
    p_frequency text, p_period_start timestamptz, p_event_id uuid,
    p_now timestamptz)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    held timestamptz;
BEGIN
    IF p_user_id IS NULL OR p_frequency IS NULL OR p_period_start IS NULL
        OR p_event_id IS NULL OR p_now IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    SELECT g.sent_at INTO held FROM public.notification_digests g
        WHERE g.user_id = p_user_id AND g.frequency = p_frequency
            AND g.period_start = p_period_start
            AND g.event_id = p_event_id
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'missing'::text;
        RETURN;
    END IF;
    IF held IS NOT NULL THEN
        RETURN QUERY SELECT 'sent'::text;
        RETURN;
    END IF;
    UPDATE public.notification_digests g SET sent_at = p_now
        WHERE g.user_id = p_user_id AND g.frequency = p_frequency
            AND g.period_start = p_period_start;
    RETURN QUERY SELECT 'claimed'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_claim_v1(uuid, text,
    timestamptz, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_claim_v2(
p_user_id uuid, p_frequency text, p_period_start timestamptz,
p_event_id uuid, p_now timestamptz
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_claim_v1(p_user_id, p_frequency,
    p_period_start, p_event_id, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_claim_v2(uuid, text,
    timestamptz, uuid, timestamptz) FROM PUBLIC;

-- Gives a claim back after the transport refused the mail: released, or
-- unchanged when the digest was not claimed.
CREATE FUNCTION api.notification_digest_release_v1(p_user_id uuid,
    p_frequency text, p_period_start timestamptz, p_event_id uuid)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    UPDATE public.notification_digests g SET sent_at = NULL
        WHERE g.user_id = p_user_id AND g.frequency = p_frequency
            AND g.period_start = p_period_start
            AND g.event_id = p_event_id AND g.sent_at IS NOT NULL;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'unchanged'::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'released'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_release_v1(uuid, text,
    timestamptz, uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_digest_release_v2(
p_user_id uuid, p_frequency text, p_period_start timestamptz,
p_event_id uuid
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_digest_release_v1(p_user_id, p_frequency,
    p_period_start, p_event_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_digest_release_v2(uuid, text,
    timestamptz, uuid) FROM PUBLIC;

COMMIT;
