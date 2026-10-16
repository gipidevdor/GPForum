-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0133: watched words and automod rules. Staff keep a list of at most
-- 500 watched words or phrases, each blocking, flagging or replacing what it
-- matches in new threads, replies and edits, and one link rule: at most N
-- links in a post of a member below a trust level, blocked or flagged.
-- Matching is the application's (a bounded literal pattern per word); the
-- database keeps the rules and records the decisions. A flag is a report
-- in the existing queue whose reporter is the system (no member): at most
-- one open per target. Every rule change and every decision is audited.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A report with no reporter is the system's (automod). The existing open
-- key (reporter, target) does not hold NULLs equal, so the record function
-- serializes its own reports per target.
ALTER TABLE public.reports ALTER COLUMN reporter_user_id DROP NOT NULL;

CREATE TABLE public.watched_words (
    word_id uuid NOT NULL,
    phrase text NOT NULL,
    action text NOT NULL,
    replacement text NOT NULL DEFAULT '',
    created_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL,
    CONSTRAINT watched_words_pkey PRIMARY KEY (word_id),
    CONSTRAINT watched_words_phrase_key UNIQUE (phrase),
    CONSTRAINT watched_words_phrase_check
        CHECK (length(phrase) BETWEEN 1 AND 100),
    CONSTRAINT watched_words_action_check
        CHECK (action IN ('block', 'flag', 'replace')),
    CONSTRAINT watched_words_replacement_check
        CHECK (length(replacement) <= 100)
);

-- One row: the link rule. No row is the default, the rule off.
CREATE TABLE public.automod_settings (
    singleton boolean NOT NULL DEFAULT true,
    link_limit integer,
    link_trust_below integer NOT NULL DEFAULT 1,
    link_action text NOT NULL DEFAULT 'block',
    updated_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT automod_settings_pkey PRIMARY KEY (singleton),
    CONSTRAINT automod_settings_singleton_check CHECK (singleton),
    CONSTRAINT automod_settings_link_limit_check
        CHECK (link_limit IS NULL OR link_limit BETWEEN 0 AND 100),
    CONSTRAINT automod_settings_link_trust_below_check
        CHECK (link_trust_below BETWEEN 0 AND 100),
    CONSTRAINT automod_settings_link_action_check
        CHECK (link_action IN ('block', 'flag'))
);

-- Adds a watched word. The list is held while counted, so two staff cannot
-- both take the last place; a phrase already listed is a duplicate.
CREATE FUNCTION api.moderation_watched_word_add_v1(p_word_id uuid,
    p_phrase text, p_action text, p_replacement text, p_actor_user_id uuid,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, word_id uuid)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_word_id IS NULL OR p_phrase IS NULL
        OR length(p_phrase) NOT BETWEEN 1 AND 100
        OR p_action IS NULL OR p_action NOT IN ('block', 'flag', 'replace')
        OR length(coalesce(p_replacement, '')) > 100
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026101501, 1);
    IF EXISTS (SELECT 1 FROM public.watched_words w
        WHERE w.phrase = p_phrase) THEN
        RETURN QUERY SELECT 'duplicate'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT count(*) INTO amount FROM public.watched_words;
    IF amount >= 500 THEN
        RETURN QUERY SELECT 'limit'::text, NULL::uuid;
        RETURN;
    END IF;
    INSERT INTO public.watched_words (word_id, phrase, action, replacement,
        created_by_user_id, created_at)
        VALUES (p_word_id, p_phrase, p_action, coalesce(p_replacement, ''),
            p_actor_user_id, p_now);
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_word_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_add_v1(uuid, text,
    text, text, uuid, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_watched_word_add_v2(
p_word_id uuid, p_phrase text, p_action text, p_replacement text,
p_actor_user_id uuid, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, word_id uuid)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_watched_word_add_v1(p_word_id, p_phrase,
    p_action, p_replacement, p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_add_v2(uuid, text,
    text, text, uuid, timestamptz, jsonb) FROM PUBLIC;

-- Removes a watched word; the audit carries the phrase and action removed.
-- Removing one not listed is no error (removed is 0) and is not audited.
CREATE FUNCTION api.moderation_watched_word_remove_v1(p_word_id uuid,
    p_audit jsonb)
RETURNS TABLE(removed bigint)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE gone record;
BEGIN
    DELETE FROM public.watched_words w WHERE w.word_id = p_word_id
        RETURNING w.phrase, w.action INTO gone;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 0::bigint;
        RETURN;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object('metadata',
        coalesce(p_audit -> 'metadata', '{}'::jsonb)
        || jsonb_build_object('phrase', gone.phrase, 'action', gone.action)),
        false);
    RETURN QUERY SELECT 1::bigint;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_remove_v1(uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.moderation_watched_word_remove_v2(
p_word_id uuid, p_audit jsonb
)
RETURNS TABLE(removed bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_watched_word_remove_v1(p_word_id, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_remove_v2(uuid, jsonb)
    FROM PUBLIC;

-- The list as the admin console shows it, in phrase order, with who added
-- each word.
CREATE FUNCTION api.moderation_watched_word_list_v1()
RETURNS TABLE(word_id uuid, phrase text, action text, replacement text,
    created_by_user_id uuid, created_by_username text,
    created_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT w.word_id, w.phrase, w.action, w.replacement, w.created_by_user_id,
    u.username, w.created_at
FROM public.watched_words w
LEFT JOIN public.users u ON u.id = w.created_by_user_id
ORDER BY w.phrase, w.word_id
LIMIT 500;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_list_v1() FROM PUBLIC;

CREATE FUNCTION api.moderation_watched_word_list_v2()
RETURNS TABLE(word_id uuid, phrase text, action text, replacement text,
    created_by_user_id uuid, created_by_username text,
    created_at timestamptz)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_watched_word_list_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_watched_word_list_v2() FROM PUBLIC;

-- Sets the link rule: a NULL limit turns it off. The audit carries the
-- rule before and after; setting the rule it already is changes nothing.
CREATE FUNCTION api.moderation_automod_settings_set_v1(p_link_limit integer,
    p_link_trust_below integer, p_link_action text, p_actor_user_id uuid,
    p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record; before jsonb;
BEGIN
    IF (p_link_limit IS NOT NULL AND p_link_limit NOT BETWEEN 0 AND 100)
        OR p_link_trust_below IS NULL
        OR p_link_trust_below NOT BETWEEN 0 AND 100
        OR p_link_action IS NULL OR p_link_action NOT IN ('block', 'flag')
        OR p_now IS NULL OR p_audit IS NULL THEN
        RETURN QUERY SELECT 'invalid'::text;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026101501, 2);
    SELECT s.link_limit, s.link_trust_below, s.link_action INTO held
        FROM public.automod_settings s WHERE s.singleton;
    IF FOUND THEN
        IF held.link_limit IS NOT DISTINCT FROM p_link_limit
            AND held.link_trust_below = p_link_trust_below
            AND held.link_action = p_link_action THEN
            RETURN QUERY SELECT 'unchanged'::text;
            RETURN;
        END IF;
        before := jsonb_build_object('link_limit', held.link_limit,
            'link_trust_below', held.link_trust_below,
            'link_action', held.link_action);
    ELSE
        before := jsonb_build_object('link_limit', NULL,
            'link_trust_below', 1, 'link_action', 'block');
    END IF;
    INSERT INTO public.automod_settings (singleton, link_limit,
        link_trust_below, link_action, updated_by_user_id, updated_at)
        VALUES (true, p_link_limit, p_link_trust_below, p_link_action,
            p_actor_user_id, p_now)
        ON CONFLICT (singleton) DO UPDATE SET
            link_limit = EXCLUDED.link_limit,
            link_trust_below = EXCLUDED.link_trust_below,
            link_action = EXCLUDED.link_action,
            updated_by_user_id = EXCLUDED.updated_by_user_id,
            updated_at = EXCLUDED.updated_at;
    PERFORM api.ops_record_audit_v1(p_audit || jsonb_build_object('metadata',
        coalesce(p_audit -> 'metadata', '{}'::jsonb)
        || jsonb_build_object('before', before)), false);
    RETURN QUERY SELECT 'ok'::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_settings_set_v1(integer,
    integer, text, uuid, timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_settings_set_v2(
p_link_limit integer, p_link_trust_below integer, p_link_action text,
p_actor_user_id uuid, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_settings_set_v1(p_link_limit,
    p_link_trust_below, p_link_action, p_actor_user_id, p_now, p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_settings_set_v2(integer,
    integer, text, uuid, timestamptz, jsonb) FROM PUBLIC;

-- The rules a write is screened by, in one call: the watched words, the
-- link rule and the author's trust level (NULL for an unknown author).
CREATE FUNCTION api.moderation_automod_rules_v1(p_user_id uuid)
RETURNS TABLE(document json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT json_build_object(
    'words', coalesce((SELECT json_agg(json_build_object(
            'word_id', w.word_id, 'phrase', w.phrase, 'action', w.action,
            'replacement', w.replacement) ORDER BY w.phrase, w.word_id)
        FROM public.watched_words w), '[]'::json),
    'link_limit', s.link_limit,
    'link_trust_below', coalesce(s.link_trust_below, 1),
    'link_action', coalesce(s.link_action, 'block'),
    'updated_at', s.updated_at,
    'trust_level', (SELECT u.trust_level FROM public.users u
        WHERE u.id = p_user_id))
FROM (SELECT true AS singleton) one
LEFT JOIN public.automod_settings s ON s.singleton = one.singleton;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_rules_v2(
p_user_id uuid
)
RETURNS TABLE(document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_rules_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_rules_v2(uuid) FROM PUBLIC;

-- Records the decisions of one write. A flag (p_report) becomes a system
-- report in the queue, with its report.created event and audit, unless the
-- system already holds an open one on the target: the reports of one
-- target are serialized here. Every audit in p_audits (the decisions) is
-- recorded either way.
CREATE FUNCTION api.moderation_automod_record_v1(p_report jsonb,
    p_event jsonb, p_event_outbox_id text, p_report_audit jsonb,
    p_audits jsonb)
RETURNS TABLE(report_id uuid, flagged boolean)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held uuid; created boolean := false; item jsonb;
BEGIN
    IF p_report IS NOT NULL THEN
        IF p_report ->> 'target_type' NOT IN ('thread', 'post', 'user')
            OR p_event IS NULL OR p_report_audit IS NULL THEN
            RAISE EXCEPTION 'an automod report needs its target, event and audit'
                USING ERRCODE = '22023';
        END IF;
        PERFORM pg_advisory_xact_lock(2026101502, hashtext(
            (p_report ->> 'target_type') || ':' || (p_report ->> 'target_id')));
        SELECT r.report_id INTO held FROM public.reports r
            WHERE r.reporter_user_id IS NULL
                AND r.target_type = p_report ->> 'target_type'
                AND r.target_id = (p_report ->> 'target_id')::uuid
                AND r.status IN ('open', 'triaged')
            ORDER BY r.created_at, r.report_id LIMIT 1;
        IF NOT FOUND THEN
            INSERT INTO public.reports (report_id, reporter_user_id,
                target_type, target_id, reason, details, status, created_at)
                VALUES ((p_report ->> 'report_id')::uuid, NULL,
                    p_report ->> 'target_type',
                    (p_report ->> 'target_id')::uuid, p_report ->> 'reason',
                    coalesce(p_report ->> 'details', ''), 'open',
                    (p_report ->> 'created_at')::timestamptz);
            held := (p_report ->> 'report_id')::uuid;
            created := true;
            PERFORM api.ops_record_event_v1(p_event, p_event_outbox_id, NULL,
                false);
            PERFORM api.ops_record_audit_v1(p_report_audit, false);
        END IF;
    END IF;
    FOR item IN SELECT a.value FROM jsonb_array_elements(
        coalesce(p_audits, '[]'::jsonb)) a LOOP
        PERFORM api.ops_record_audit_v1(item, false);
    END LOOP;
    RETURN QUERY SELECT held, created;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v1(jsonb, jsonb,
    text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.moderation_automod_record_v2(
p_report jsonb, p_event jsonb, p_event_outbox_id text, p_report_audit jsonb,
p_audits jsonb
)
RETURNS TABLE(report_id uuid, flagged boolean)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_automod_record_v1(p_report, p_event,
    p_event_outbox_id, p_report_audit, p_audits);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_automod_record_v2(jsonb, jsonb,
    text, jsonb, jsonb) FROM PUBLIC;

COMMIT;
