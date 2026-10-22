-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The admin console: roles and bindings, spaces and categories, announcements,
-- the audit trail, permissions.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The live ban that covers an address, the strongest scope first (writes,
-- then sign_in, then registration), then the one that lasts longest; no
-- row when none does. One GiST lookup on idx_address_bans_live_range.
CREATE FUNCTION api.admin_address_ban_covering_v1(
    p_address inet,
    p_now timestamptz
)
RETURNS TABLE (
    ban_id uuid,
    address_range text,
    scope text,
    expires_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.ban_id, b.address_range::text, b.scope, b.expires_at
FROM public.address_bans b
WHERE b.lifted_at IS NULL AND b.address_range >>= p_address
    AND b.expires_at > p_now
ORDER BY CASE b.scope WHEN 'writes' THEN 3 WHEN 'sign_in' THEN 2 ELSE 1 END
    DESC, b.expires_at DESC, b.ban_id
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_covering_v1(inet, timestamptz)
    FROM PUBLIC;

-- Changes a live ban's scope, reason and, when one is given, its expiry.
-- An ended ban (lifted or expired) is not edited; the same values again
-- change nothing and audit nothing.
CREATE FUNCTION api.admin_address_ban_edit_v1(
    p_ban_id uuid,
    p_scope text,
    p_reason text,
    p_expires_at timestamptz,
    p_actor_user_id uuid,
    p_actor_address inet,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, ban_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_ban_id IS NULL OR p_actor_user_id IS NULL OR p_scope IS NULL
        OR p_scope NOT IN ('registration', 'sign_in', 'writes')
        OR p_reason IS NULL OR length(p_reason) NOT BETWEEN 1 AND 500
        OR p_now IS NULL OR p_audit IS NULL
        OR (p_expires_at IS NOT NULL AND (p_expires_at <= p_now
            OR p_expires_at > p_now + interval '366 days'))
    THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT b.address_range, b.scope, b.reason, b.expires_at, b.lifted_at
        INTO held
        FROM public.address_bans b WHERE b.ban_id = p_ban_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    IF held.lifted_at IS NOT NULL OR held.expires_at <= p_now THEN
        RETURN QUERY SELECT 'ended'::text, p_ban_id;
        RETURN;
    END IF;
    IF p_scope IN ('sign_in', 'writes') AND p_actor_address IS NOT NULL
        AND held.address_range >>= p_actor_address
    THEN
        RETURN QUERY SELECT 'covers_self'::text, p_ban_id;
        RETURN;
    END IF;
    IF held.scope = p_scope AND held.reason = p_reason
        AND (p_expires_at IS NULL OR p_expires_at = held.expires_at)
    THEN
        RETURN QUERY SELECT 'unchanged'::text, p_ban_id;
        RETURN;
    END IF;
    UPDATE public.address_bans b
        SET scope = p_scope, reason = p_reason,
            expires_at = coalesce(p_expires_at, b.expires_at),
            updated_at = p_now, updated_by_user_id = p_actor_user_id
        WHERE b.ban_id = p_ban_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_ban_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_edit_v1(uuid, text, text, timestamptz, uuid, inet, timestamptz, jsonb)
    FROM PUBLIC;

-- Lifts a live ban now. A lifted or expired ban answers ended.
CREATE FUNCTION api.admin_address_ban_lift_v1(
    p_ban_id uuid,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, ban_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held record;
BEGIN
    IF p_ban_id IS NULL OR p_actor_user_id IS NULL OR p_now IS NULL
        OR p_audit IS NULL
    THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT b.expires_at, b.lifted_at INTO held
        FROM public.address_bans b WHERE b.ban_id = p_ban_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
        RETURN;
    END IF;
    IF held.lifted_at IS NOT NULL OR held.expires_at <= p_now THEN
        RETURN QUERY SELECT 'ended'::text, p_ban_id;
        RETURN;
    END IF;
    UPDATE public.address_bans b
        SET lifted_at = p_now, lifted_by_user_id = p_actor_user_id
        WHERE b.ban_id = p_ban_id;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_ban_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_lift_v1(uuid, uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- Places a ban. The ban id is the form's command id: the same submission
-- again answers replayed, and an id another ban holds is a conflict. A
-- range wider than the bounds is too_broad; a sign-in or writes ban that
-- covers the address the staff member writes from is covers_self; a live
-- ban on the very same range is a duplicate, answered with its id.
CREATE FUNCTION api.admin_address_ban_place_v1(
    p_ban_id uuid,
    p_range cidr,
    p_scope text,
    p_reason text,
    p_expires_at timestamptz,
    p_actor_user_id uuid,
    p_actor_address inet,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text, ban_id uuid)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    held_range cidr;
    held_author uuid;
    live_ban uuid;
BEGIN
    IF p_ban_id IS NULL OR p_range IS NULL OR p_actor_user_id IS NULL
        OR p_scope IS NULL
        OR p_scope NOT IN ('registration', 'sign_in', 'writes')
        OR p_reason IS NULL OR length(p_reason) NOT BETWEEN 1 AND 500
        OR p_now IS NULL OR p_expires_at IS NULL OR p_expires_at <= p_now
        OR p_expires_at > p_now + interval '366 days' OR p_audit IS NULL
    THEN
        RETURN QUERY SELECT 'invalid'::text, NULL::uuid;
        RETURN;
    END IF;
    IF masklen(p_range)
        < (CASE family(p_range) WHEN 4 THEN 16 ELSE 32 END)
    THEN
        RETURN QUERY SELECT 'too_broad'::text, NULL::uuid;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(
        hashtextextended('address_ban:' || p_range::text, 0));
    SELECT b.address_range, b.created_by_user_id
        INTO held_range, held_author
        FROM public.address_bans b WHERE b.ban_id = p_ban_id;
    IF FOUND THEN
        IF held_range = p_range AND held_author = p_actor_user_id THEN
            RETURN QUERY SELECT 'replayed'::text, p_ban_id;
        ELSE
            RETURN QUERY SELECT 'conflict'::text, NULL::uuid;
        END IF;
        RETURN;
    END IF;
    IF p_scope IN ('sign_in', 'writes') AND p_actor_address IS NOT NULL
        AND p_range >>= p_actor_address
    THEN
        RETURN QUERY SELECT 'covers_self'::text, NULL::uuid;
        RETURN;
    END IF;
    SELECT b.ban_id INTO live_ban FROM public.address_bans b
        WHERE b.address_range = p_range AND b.lifted_at IS NULL
            AND b.expires_at > p_now
        LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT 'duplicate'::text, live_ban;
        RETURN;
    END IF;
    DELETE FROM public.address_bans b
        WHERE coalesce(b.lifted_at, b.expires_at) < p_now - interval '90 days';
    INSERT INTO public.address_bans (ban_id, address_range, scope, reason,
        created_at, created_by_user_id, expires_at)
        VALUES (p_ban_id, p_range, p_scope, p_reason, p_now,
            p_actor_user_id, p_expires_at);
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_ban_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_ban_place_v1(uuid, cidr, text, text, timestamptz, uuid, inet, timestamptz, jsonb)
    FROM PUBLIC;

-- The bans for the console: the live ones first, newest first, then the
-- ended ones, the most recently ended first; with who placed, edited and
-- lifted each, its state, and how many are live in all.
CREATE FUNCTION api.admin_address_bans_v1(
    p_now timestamptz,
    p_row_limit integer
)
RETURNS TABLE (
    ban_id uuid,
    address_range text,
    scope text,
    reason text,
    created_at timestamptz,
    created_by_username text,
    expires_at timestamptz,
    updated_at timestamptz,
    updated_by_username text,
    lifted_at timestamptz,
    lifted_by_username text,
    state text,
    live_total bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.ban_id, s.address_range::text, s.scope, s.reason, s.created_at,
    c.username, s.expires_at, s.updated_at, e.username, s.lifted_at,
    l.username,
    CASE WHEN s.lifted_at IS NOT NULL THEN 'lifted'
        WHEN NOT s.live THEN 'expired' ELSE 'active' END,
    count(*) FILTER (WHERE s.live) OVER ()
FROM (
    SELECT b.*, (b.lifted_at IS NULL AND b.expires_at > p_now) AS live
    FROM public.address_bans b
) s
LEFT JOIN public.users c ON c.id = s.created_by_user_id
LEFT JOIN public.users e ON e.id = s.updated_by_user_id
LEFT JOIN public.users l ON l.id = s.lifted_by_user_id
ORDER BY s.live DESC,
    CASE WHEN s.live THEN s.created_at
        ELSE coalesce(s.lifted_at, s.expires_at) END DESC,
    s.ban_id DESC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.admin_address_bans_v1(timestamptz, integer)
    FROM PUBLIC;

-- Lets the console's slow answer (an export, a large listing) stay idle in its
-- transaction for p_idle_ms, for this transaction only.
CREATE FUNCTION api.admin_allow_slow_answer_v1(p_idle_ms integer)
RETURNS TABLE (timeout text)
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT set_config('idle_in_transaction_session_timeout', p_idle_ms::text, true);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_allow_slow_answer_v1(integer) FROM PUBLIC;

-- The announcement with this id.
CREATE FUNCTION api.admin_announcement_by_id_v1(p_announcement_id uuid)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT announcement_id, message, tone, created_by, created_at, retired_by,
        retired_at FROM public.site_announcements a
    WHERE a.announcement_id = p_announcement_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_announcement_by_id_v1(uuid) FROM PUBLIC;

-- The metadata of the audit rows of one action on one attachment target, for
-- the console's attachment history.
CREATE FUNCTION api.admin_attachment_audits_v1(
    p_action text,
    p_target_id uuid,
    p_target_type text
)
RETURNS TABLE (metadata jsonb)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT a.metadata FROM public.audit_log a WHERE a.action = p_action AND a.target_id = p_target_id
        AND a.target_type = p_target_type;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_attachment_audits_v1(text, uuid, text)
    FROM PUBLIC;

-- A page of the audit trail, newest first, filtered by actor, action, target
-- and time, after the cursor p_after when it is given.
CREATE FUNCTION api.admin_audit_page_v1(
    p_filters jsonb,
    p_after jsonb,
    p_row_limit integer
)
RETURNS SETOF api.admin_audit_entry_v1
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_after IS NULL THEN
        RETURN QUERY SELECT a.audit_id, a.action, a.schema_version,
            a.actor_id, a.target_type, a.target_id, a.correlation_id,
            a.previous_hash, a.record_hash, a.metadata, a.created_at
        FROM public.audit_log a WHERE (p_filters->>'actor_id' IS NULL OR a.actor_id = (p_filters->>'actor_id')::uuid)
        AND (p_filters->>'action' IS NULL OR a.action = (p_filters->>'action')::text)
        AND (p_filters->>'target_type' IS NULL OR a.target_type = (p_filters->>'target_type')::text)
        AND (p_filters->>'target_id' IS NULL OR a.target_id = (p_filters->>'target_id')::uuid)
        AND (p_filters->>'correlation_id' IS NULL OR a.correlation_id = (p_filters->>'correlation_id')::uuid)
        AND (p_filters->>'from' IS NULL OR a.created_at >= ((p_filters->>'from') || 'T00:00:00Z')::timestamptz)
        AND (p_filters->>'until' IS NULL OR a.created_at <= ((p_filters->>'until') || 'T23:59:59.999999Z')::timestamptz) ORDER BY a.created_at DESC, a.audit_id DESC LIMIT p_row_limit;
    ELSE
        RETURN QUERY SELECT a.audit_id, a.action, a.schema_version,
            a.actor_id, a.target_type, a.target_id, a.correlation_id,
            a.previous_hash, a.record_hash, a.metadata, a.created_at
        FROM public.audit_log a WHERE (p_filters->>'actor_id' IS NULL OR a.actor_id = (p_filters->>'actor_id')::uuid)
        AND (p_filters->>'action' IS NULL OR a.action = (p_filters->>'action')::text)
        AND (p_filters->>'target_type' IS NULL OR a.target_type = (p_filters->>'target_type')::text)
        AND (p_filters->>'target_id' IS NULL OR a.target_id = (p_filters->>'target_id')::uuid)
        AND (p_filters->>'correlation_id' IS NULL OR a.correlation_id = (p_filters->>'correlation_id')::uuid)
        AND (p_filters->>'from' IS NULL OR a.created_at >= ((p_filters->>'from') || 'T00:00:00Z')::timestamptz)
        AND (p_filters->>'until' IS NULL OR a.created_at <= ((p_filters->>'until') || 'T23:59:59.999999Z')::timestamptz)
            AND a.created_at <= (p_after->>'created_at')::timestamptz
            AND (a.created_at, a.audit_id) < ((p_after->>'created_at')::timestamptz, (p_after->>'audit_id')::uuid)
            ORDER BY a.created_at DESC, a.audit_id DESC LIMIT p_row_limit;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_page_v1(jsonb, jsonb, integer)
    FROM PUBLIC;

-- The newest audit rows.
CREATE FUNCTION api.admin_audit_recent_v1(p_row_limit integer)
RETURNS SETOF api.admin_audit_entry_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT a.audit_id, a.action, a.schema_version, a.actor_id, a.target_type,
        a.target_id, a.correlation_id, a.previous_hash, a.record_hash,
        a.metadata, a.created_at
    FROM public.audit_log a ORDER BY a.created_at DESC, a.audit_id DESC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_audit_recent_v1(integer) FROM PUBLIC;

-- The category with this id, deleted or not.
CREATE FUNCTION api.admin_category_by_id_v1(p_category_id uuid)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.category_id, c.space_id, c.slug, c.title, c.description,
        c.visibility, c."position", c.version, c.permission_version,
        c.created_at, c.updated_at, c.deleted_at
    FROM public.categories c WHERE c.category_id = p_category_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_category_by_id_v1(uuid) FROM PUBLIC;

-- How many dead letters, or how many outbox messages, there are, for the
-- console's counters.
CREATE FUNCTION api.admin_console_counts_v1(p_dead_letters boolean)
RETURNS TABLE (total bigint)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_dead_letters THEN RETURN QUERY SELECT count(*) FROM public.dead_letters;
    ELSE RETURN QUERY SELECT count(*) FROM public.outbox_messages;
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_counts_v1(boolean) FROM PUBLIC;

-- The dead letters for the console, with whether each was replayed and how
-- that replay stands.
CREATE FUNCTION api.admin_console_dead_letters_v1(p_row_limit integer)
RETURNS TABLE (
    dead_letter_id uuid,
    source_table text,
    source_id uuid,
    error_class text,
    error_message text,
    failure_type text,
    retry_count integer,
    first_failed_at timestamptz,
    last_failed_at timestamptz,
    replay_status text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT d.dead_letter_id, d.source_table, d.source_id, d.error_class, d.error_message, d.failure_type, d.retry_count, d.first_failed_at, d.last_failed_at,
        COALESCE((SELECT r.status FROM public.outbox_messages r
            WHERE r.idempotency_key = 'dead-letter-replay:' || d.dead_letter_id::text),
            (SELECT 'replayed'::text FROM public.audit_log a WHERE a.action = 'outbox.dead_letter_replayed'
                AND a.target_type = 'dead_letter' AND a.target_id = d.dead_letter_id LIMIT 1))
        FROM public.dead_letters d ORDER BY d.last_failed_at DESC, d.dead_letter_id DESC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_dead_letters_v1(integer)
    FROM PUBLIC;

-- The normalized email of a member not deleted, for staff to contact them.
CREATE FUNCTION api.admin_console_email_v1(p_user_id uuid)
RETURNS TABLE (email_normalized text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT u.email_normalized FROM public.users u WHERE u.id = p_user_id AND u.deleted_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_email_v1(uuid) FROM PUBLIC;

-- The outbox messages for the console, of one status or all, newest first.
CREATE FUNCTION api.admin_console_outbox_v1(
    p_status text,
    p_row_limit integer
)
RETURNS TABLE (
    outbox_id uuid,
    event_id uuid,
    queue text,
    job_type text,
    idempotency_key text,
    available_at timestamptz,
    created_at timestamptz,
    locked_at timestamptz,
    attempts integer,
    status text,
    last_error text,
    next_attempt_at timestamptz,
    locked_by text,
    locked_until timestamptz,
    attempt_count integer,
    last_error_class text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.outbox_id, r.event_id, r.queue, r.job_type, r.idempotency_key, r.available_at, r.created_at, r.locked_at, r.attempts, r.status, r.last_error, r.next_attempt_at, r.locked_by, r.locked_until, r.attempt_count, r.last_error_class FROM public.outbox_messages r WHERE (p_status IS NULL OR r.status = p_status)
        ORDER BY r.created_at DESC, r.outbox_id DESC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_outbox_v1(text, integer)
    FROM PUBLIC;

-- The reports of one status for the console, oldest first.
CREATE FUNCTION api.admin_console_reports_v1(
    p_status text,
    p_row_limit integer
)
RETURNS TABLE (
    report_id uuid,
    reporter_user_id uuid,
    target_type text,
    target_id uuid,
    reason text,
    details text,
    status text,
    assigned_moderator_user_id uuid,
    created_at timestamptz,
    resolved_at timestamptz,
    resolution text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.report_id, r.reporter_user_id, r.target_type, r.target_id, r.reason, r.details, r.status, r.assigned_moderator_user_id, r.created_at, r.resolved_at, r.resolution FROM public.reports r WHERE r.status = p_status
        ORDER BY r.created_at ASC, r.report_id ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_reports_v1(text, integer)
    FROM PUBLIC;

-- The members not deleted for the console, of one status or all, newest first.
CREATE FUNCTION api.admin_console_users_v1(p_status text, p_row_limit integer)
RETURNS TABLE (
    id uuid,
    username text,
    display_name text,
    email_normalized text,
    status text,
    trust_level integer,
    email_verified_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.id, r.username, r.display_name, r.email_normalized, r.status, r.trust_level, r.email_verified_at, r.created_at, r.updated_at, r.deleted_at FROM public.users r WHERE r.deleted_at IS NULL AND (p_status IS NULL OR r.status = p_status)
        ORDER BY r.created_at DESC, r.username ASC LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_console_users_v1(text, integer)
    FROM PUBLIC;

-- The first space not deleted, in the forum's order: where a new category goes
-- when none is named.
CREATE FUNCTION api.admin_first_live_space_v1()
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT s.space_id, s.slug, s.title, s.description, s.visibility,
        s."position", s.version, s.permission_version, s.created_at,
        s.updated_at, s.deleted_at
    FROM public.spaces s WHERE s.deleted_at IS NULL ORDER BY s.position, s.slug LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_first_live_space_v1() FROM PUBLIC;

-- Stores a new announcement and answers it.
CREATE FUNCTION api.admin_insert_announcement_v1(p_values jsonb)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.site_announcements (announcement_id, message, tone,
        created_by, created_at)
    VALUES ((p_values ->> 'announcement_id')::uuid, p_values ->> 'message',
        p_values ->> 'tone', (p_values ->> 'created_by')::uuid,
        (p_values ->> 'created_at')::timestamptz)
    RETURNING announcement_id, message, tone, created_by, created_at,
        retired_by, retired_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_announcement_v1(jsonb) FROM PUBLIC;

-- Stores a new role binding and answers it.
CREATE FUNCTION api.admin_insert_binding_v1(p_values jsonb)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.role_bindings (binding_id, user_id, role_id, resource_type, resource_id, space_id, created_by_user_id, created_at, revoked_at)
    VALUES ((p_values->>'binding_id')::uuid, (p_values->>'user_id')::uuid, (p_values->>'role_id')::uuid, (p_values->>'resource_type')::text, (p_values->>'resource_id')::uuid, (p_values->>'space_id')::uuid, (p_values->>'created_by_user_id')::uuid, (p_values->>'created_at')::timestamptz, (p_values->>'revoked_at')::timestamptz) RETURNING
        binding_id, user_id, role_id, resource_type, resource_id, space_id,
        created_at, revoked_at, created_by_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_binding_v1(jsonb) FROM PUBLIC;

-- Stores a new category and answers it.
CREATE FUNCTION api.admin_insert_category_v1(p_values jsonb)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.categories (category_id, space_id, slug, title, description, visibility, position, version, permission_version, created_at, updated_at, deleted_at)
    VALUES ((p_values->>'category_id')::uuid, (p_values->>'space_id')::uuid, (p_values->>'slug')::text, (p_values->>'title')::text, (p_values->>'description')::text, (p_values->>'visibility')::text, (p_values->>'position')::integer, (p_values->>'version')::bigint, (p_values->>'permission_version')::bigint, (p_values->>'created_at')::timestamptz, (p_values->>'updated_at')::timestamptz, (p_values->>'deleted_at')::timestamptz) RETURNING
        category_id, space_id, slug, title, description, visibility,
        "position", version, permission_version, created_at, updated_at,
        deleted_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_category_v1(jsonb) FROM PUBLIC;

-- Stores a new permission and answers it.
CREATE FUNCTION api.admin_insert_permission_v1(p_values jsonb)
RETURNS SETOF api.admin_permission_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.permissions (permission_id, name, resource_type, action, created_at)
    VALUES ((p_values->>'permission_id')::uuid, (p_values->>'name')::text, (p_values->>'resource_type')::text, (p_values->>'action')::text, (p_values->>'created_at')::timestamptz) RETURNING
        permission_id, name, resource_type, action, created_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_permission_v1(jsonb) FROM PUBLIC;

-- Gives a role a permission and answers the row.
CREATE FUNCTION api.admin_insert_role_permission_v1(p_values jsonb)
RETURNS SETOF api.admin_role_permission_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.role_permissions (role_id, permission_id, created_at)
    VALUES ((p_values->>'role_id')::uuid, (p_values->>'permission_id')::uuid, (p_values->>'created_at')::timestamptz) RETURNING
        role_id, permission_id, created_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_permission_v1(jsonb)
    FROM PUBLIC;

-- Stores a new role and answers it.
CREATE FUNCTION api.admin_insert_role_v1(p_values jsonb)
RETURNS SETOF api.admin_role_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.roles (role_id, name, description, created_at)
    VALUES ((p_values->>'role_id')::uuid, (p_values->>'name')::text, (p_values->>'description')::text, (p_values->>'created_at')::timestamptz) RETURNING
        role_id, name, description, created_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_role_v1(jsonb) FROM PUBLIC;

-- Stores a new space and answers it.
CREATE FUNCTION api.admin_insert_space_v1(p_values jsonb)
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.spaces (space_id, slug, title, description, visibility, position, version, permission_version, created_at, updated_at, deleted_at)
    VALUES ((p_values->>'space_id')::uuid, (p_values->>'slug')::text, (p_values->>'title')::text, (p_values->>'description')::text, (p_values->>'visibility')::text, (p_values->>'position')::integer, (p_values->>'version')::bigint, (p_values->>'permission_version')::bigint, (p_values->>'created_at')::timestamptz, (p_values->>'updated_at')::timestamptz, (p_values->>'deleted_at')::timestamptz) RETURNING
        space_id, slug, title, description, visibility, "position", version,
        permission_version, created_at, updated_at, deleted_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_space_v1(jsonb) FROM PUBLIC;

-- The console's list: every announcement, newest first.
CREATE FUNCTION api.admin_list_announcements_v1(p_row_limit integer)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT announcement_id, message, tone, created_by, created_at, retired_by,
        retired_at FROM public.site_announcements a
    ORDER BY a.created_at DESC, a.announcement_id DESC
    LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_announcements_v1(integer)
    FROM PUBLIC;

-- The categories not deleted, in the forum's order.
CREATE FUNCTION api.admin_list_categories_v1(p_row_limit integer)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT category_id, space_id, slug, title, description, visibility,
        "position", version, permission_version, created_at, updated_at,
        deleted_at
    FROM public.categories WHERE deleted_at IS NULL ORDER BY position, title, category_id LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_categories_v1(integer) FROM PUBLIC;

-- The permissions, by resource type and action.
CREATE FUNCTION api.admin_list_permissions_v1(p_row_limit integer)
RETURNS SETOF api.admin_permission_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT permission_id, name, resource_type, action, created_at
    FROM public.permissions ORDER BY resource_type, action, name LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_permissions_v1(integer) FROM PUBLIC;

-- The roles, by name.
CREATE FUNCTION api.admin_list_roles_v1(p_row_limit integer)
RETURNS SETOF api.admin_role_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT role_id, name, description, created_at
    FROM public.roles ORDER BY name LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_roles_v1(integer) FROM PUBLIC;

-- The category not deleted with this slug in this space.
CREATE FUNCTION api.admin_live_category_by_slug_v1(
    p_space_id uuid,
    p_slug text
)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT c.category_id, c.space_id, c.slug, c.title, c.description,
        c.visibility, c."position", c.version, c.permission_version,
        c.created_at, c.updated_at, c.deleted_at
    FROM public.categories c WHERE c.space_id = p_space_id AND c.slug = p_slug
        AND c.deleted_at IS NULL LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_live_category_by_slug_v1(uuid, text)
    FROM PUBLIC;

-- The role binding with this id, locked FOR UPDATE until the caller's
-- transaction ends.
CREATE FUNCTION api.admin_lock_binding_v1(p_binding_id uuid)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT b.binding_id, b.user_id, b.role_id, b.resource_type, b.resource_id,
        b.space_id, b.created_at, b.revoked_at, b.created_by_user_id
    FROM public.role_bindings b WHERE b.binding_id = p_binding_id FOR UPDATE;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lock_binding_v1(uuid) FROM PUBLIC;

-- The audit row of one action on one target, if there is one.
CREATE FUNCTION api.admin_lookup_audit_v1(p_query jsonb)
RETURNS SETOF api.admin_audit_entry_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.audit_id, r.action, r.schema_version, r.actor_id, r.target_type,
        r.target_id, r.correlation_id, r.previous_hash, r.record_hash,
        r.metadata, r.created_at
    FROM public.audit_log r WHERE r.action = p_query->>'action' AND r.target_id = (p_query->>'target_id')::uuid LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_audit_v1(jsonb) FROM PUBLIC;

-- The live role binding of a role over one scope (resource type, resource and
-- space), if there is one.
CREATE FUNCTION api.admin_lookup_binding_v1(p_query jsonb)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.binding_id, r.user_id, r.role_id, r.resource_type, r.resource_id,
        r.space_id, r.created_at, r.revoked_at, r.created_by_user_id
    FROM public.role_bindings r WHERE r.role_id = (p_query->>'role_id')::uuid AND r.resource_type = p_query->>'resource_type' AND r.revoked_at IS NULL
        AND (NOT p_query ? 'user_id' OR r.user_id IS NOT DISTINCT FROM (p_query->>'user_id')::uuid)
        AND (NOT p_query ? 'resource_id' OR r.resource_id IS NOT DISTINCT FROM (p_query->>'resource_id')::uuid)
        AND (NOT p_query ? 'space_id' OR r.space_id IS NOT DISTINCT FROM (p_query->>'space_id')::uuid) LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_binding_v1(jsonb) FROM PUBLIC;

-- The permission for one action on one resource type, if there is one.
CREATE FUNCTION api.admin_lookup_permission_v1(p_query jsonb)
RETURNS SETOF api.admin_permission_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.permission_id, r.name, r.resource_type, r.action, r.created_at
    FROM public.permissions r WHERE r.resource_type = p_query->>'resource_type' AND r.action = p_query->>'action' LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_permission_v1(jsonb) FROM PUBLIC;

-- The row that gives a role a permission, if there is one.
CREATE FUNCTION api.admin_lookup_role_permission_v1(p_query jsonb)
RETURNS SETOF api.admin_role_permission_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.role_id, r.permission_id, r.created_at
    FROM public.role_permissions r WHERE r.role_id = (p_query->>'role_id')::uuid AND r.permission_id = (p_query->>'permission_id')::uuid LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_permission_v1(jsonb)
    FROM PUBLIC;

-- The role with this name, if there is one.
CREATE FUNCTION api.admin_lookup_role_v1(p_query jsonb)
RETURNS SETOF api.admin_role_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.role_id, r.name, r.description, r.created_at
    FROM public.roles r WHERE r.name = p_query->>'name' LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_lookup_role_v1(jsonb) FROM PUBLIC;

-- Whether a member holds a permission over a resource, through a live binding
-- over the forum, the resource's space or the resource itself.
CREATE FUNCTION api.admin_permission_allowed_v1(
    p_user_id uuid,
    p_resource_type text,
    p_action text,
    p_resource_id uuid,
    p_space_id uuid
)
RETURNS TABLE (allowed boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (
    SELECT 1 FROM public.role_bindings b
    JOIN public.role_permissions rp ON rp.role_id = b.role_id
    JOIN public.permissions p ON p.permission_id = rp.permission_id
    WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
        AND p.resource_type = p_resource_type AND p.action = p_action
        AND ((b.resource_id IS NULL AND b.space_id IS NULL)
            OR (b.resource_id IS NOT DISTINCT FROM p_resource_id
                AND b.space_id IS NOT DISTINCT FROM p_space_id))
)
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v1(uuid, text, text, uuid, uuid)
    FROM PUBLIC;

-- The staff consoles' permission check (Service::Admin::PermissionGate):
-- while the policy requires it, staff without two-step sign-in hold no
-- staff permission: none but reading a category, which is no console's.
CREATE FUNCTION api.admin_permission_allowed_v3(
    p_user_id uuid,
    p_resource_type text,
    p_action text,
    p_resource_id uuid,
    p_space_id uuid
)
RETURNS TABLE (allowed boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.allowed AND (coalesce(p_resource_type = 'category' AND p_action = 'read',
        false) OR NOT api.core_identity_second_factor_missing_v1(p_user_id))
FROM api.admin_permission_allowed_v1(p_user_id, p_resource_type, p_action,
    p_resource_id, p_space_id) v
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permission_allowed_v3(uuid, text, text, uuid, uuid)
    FROM PUBLIC;

-- The permissions a role gives.
CREATE FUNCTION api.admin_permissions_for_role_v1(
    p_role_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.admin_role_permission_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT r.role_id, r.permission_id, r.created_at
    FROM public.role_permissions r WHERE r.role_id = p_role_id ORDER BY r.permission_id LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_permissions_for_role_v1(uuid, integer)
    FROM PUBLIC;

-- Retiring: once. An announcement already retired is returned as it is,
-- so a repeated request changes nothing.
CREATE FUNCTION api.admin_retire_announcement_v1(
    p_announcement_id uuid,
    p_values jsonb
)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.site_announcements a
    SET retired_by = (p_values ->> 'retired_by')::uuid,
        retired_at = (p_values ->> 'retired_at')::timestamptz
    WHERE a.announcement_id = p_announcement_id AND a.retired_at IS NULL
    RETURNING announcement_id, message, tone, created_by, created_at,
        retired_by, retired_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_retire_announcement_v1(uuid, jsonb)
    FROM PUBLIC;

-- Revokes a role binding at p_revoked_at and answers it.
CREATE FUNCTION api.admin_revoke_binding_v1(
    p_binding_id uuid,
    p_revoked_at timestamptz
)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.role_bindings b SET revoked_at = p_revoked_at WHERE b.binding_id = p_binding_id RETURNING
        b.binding_id, b.user_id, b.role_id, b.resource_type, b.resource_id,
        b.space_id, b.created_at, b.revoked_at, b.created_by_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_revoke_binding_v1(uuid, timestamptz)
    FROM PUBLIC;

-- The live role bindings of a member.
CREATE FUNCTION api.admin_roles_for_user_v1(
    p_user_id uuid,
    p_row_limit integer
)
RETURNS SETOF api.admin_role_binding_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT b.binding_id, b.user_id, b.role_id, b.resource_type, b.resource_id,
        b.space_id, b.created_at, b.revoked_at, b.created_by_user_id
    FROM public.role_bindings b WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
        ORDER BY b.resource_type, b.role_id LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_roles_for_user_v1(uuid, integer)
    FROM PUBLIC;

-- What staff see of a member's two-step sign-in: whether it is on, since
-- when and how many recovery codes are left. Never the secret.
CREATE FUNCTION api.admin_second_factor_member_v1(p_user_id uuid)
RETURNS TABLE (state text, confirmed_at timestamptz, recovery_left integer)
LANGUAGE sql
STABLE
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
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_member_v1(uuid) FROM PUBLIC;

-- Requires two-step sign-in of staff, or stops requiring it. Audited.
-- Refusals: invalid, unenrolled (an administrator without it cannot
-- require it: they would shut themselves out of the console). Answers
-- unchanged when it already was so.
CREATE FUNCTION api.admin_second_factor_policy_set_v1(
    p_required boolean,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_set_v1(boolean, uuid, timestamptz, jsonb)
    FROM PUBLIC;

-- Whether staff must use two-step sign-in, and who said so when.
CREATE FUNCTION api.admin_second_factor_policy_v1()
RETURNS TABLE (
    staff_required boolean,
    updated_at timestamptz,
    updated_by_username text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(p.staff_required, false), p.updated_at, u.username
FROM (SELECT true AS singleton) me
LEFT JOIN public.second_factor_policy p ON p.singleton = me.singleton
LEFT JOIN public.users u ON u.id = p.updated_by_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_policy_v1() FROM PUBLIC;

-- An administrator turns a member's two-step sign-in off, for a member who
-- lost their app and their recovery codes: audited, and the member is
-- mailed. Refusals: invalid, self (an administrator turns their own off
-- from their settings, with a code), not_found (it is not on, or begun).
CREATE FUNCTION api.admin_second_factor_reset_v1(
    p_user_id uuid,
    p_actor_user_id uuid,
    p_now timestamptz,
    p_audit jsonb,
    p_mail jsonb
)
RETURNS TABLE (status text)
LANGUAGE plpgsql
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
REVOKE EXECUTE ON FUNCTION api.admin_second_factor_reset_v1(uuid, uuid, timestamptz, jsonb, jsonb)
    FROM PUBLIC;

-- The staff, those without two-step sign-in first, so an administrator
-- sees who the requirement would shut out before turning it on.
CREATE FUNCTION api.admin_second_factor_staff_v1(p_row_limit integer)
RETURNS TABLE (
    user_id uuid,
    username text,
    display_name text,
    enabled boolean,
    confirmed_at timestamptz
)
LANGUAGE sql
STABLE
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

-- The space with this id, deleted or not.
CREATE FUNCTION api.admin_space_by_id_v1(p_space_id uuid)
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT s.space_id, s.slug, s.title, s.description, s.visibility,
        s."position", s.version, s.permission_version, s.created_at,
        s.updated_at, s.deleted_at
    FROM public.spaces s WHERE s.space_id = p_space_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_id_v1(uuid) FROM PUBLIC;

-- The space with this slug, deleted or not.
CREATE FUNCTION api.admin_space_by_slug_v1(p_slug text)
RETURNS SETOF api.forum_space_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT s.space_id, s.slug, s.title, s.description, s.visibility,
        s."position", s.version, s.permission_version, s.created_at,
        s.updated_at, s.deleted_at
    FROM public.spaces s WHERE s.slug = p_slug LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_space_by_slug_v1(text) FROM PUBLIC;

-- Writes a category's editable fields and answers it.
CREATE FUNCTION api.admin_update_category_v1(
    p_category_id uuid,
    p_values jsonb
)
RETURNS SETOF api.forum_category_v1
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.categories c SET description = (p_values->>'description')::text, position = (p_values->>'position')::integer, slug = (p_values->>'slug')::text, title = (p_values->>'title')::text, updated_at = (p_values->>'updated_at')::timestamptz, version = (p_values->>'version')::bigint, visibility = (p_values->>'visibility')::text
        WHERE c.category_id = p_category_id RETURNING c.category_id,
            c.space_id, c.slug, c.title, c.description, c.visibility,
            c."position", c.version, c.permission_version, c.created_at,
            c.updated_at, c.deleted_at;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_update_category_v1(uuid, jsonb)
    FROM PUBLIC;

COMMIT;
