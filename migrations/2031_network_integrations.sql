-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.integration_announcements (
    announcement_id uuid PRIMARY KEY,
    thread_id uuid NOT NULL REFERENCES public.threads ON DELETE CASCADE,
    target_hash text NOT NULL CHECK (target_hash ~ '^[0-9a-f]{64}$'),
    requested_by uuid NOT NULL REFERENCES public.users,
    status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sending','sent','uncertain','cancelled','failed')),
    remote_id text NOT NULL DEFAULT '' CHECK (length(remote_id)<=100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(thread_id,target_hash)
);
COMMENT ON TABLE public.integration_announcements IS 'Explicit staff-selected public-topic announcements; ambiguous remote outcomes never resend automatically.';
CREATE INDEX integration_announcements_recent ON public.integration_announcements(updated_at DESC,announcement_id DESC);
CREATE TABLE public.integration_feed_sources (
    source_hash text PRIMARY KEY CHECK (source_hash ~ '^[0-9a-f]{64}$'),
    source_url text NOT NULL CHECK(length(source_url) BETWEEN 1 AND 2048),
    etag text NOT NULL DEFAULT '' CHECK(length(etag)<=512),
    modified text NOT NULL DEFAULT '' CHECK(length(modified)<=128),
    next_fetch_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.integration_feed_sources IS 'Conditional-fetch cursors and five-minute polling leases for operator-authorized syndication URLs.';
CREATE TABLE public.integration_feed_items (
    item_id uuid PRIMARY KEY,
    source_hash text NOT NULL REFERENCES public.integration_feed_sources ON DELETE CASCADE,
    identity_hash text NOT NULL CHECK(identity_hash ~ '^[0-9a-f]{64}$'),
    url_hash text NOT NULL UNIQUE CHECK(url_hash ~ '^[0-9a-f]{64}$'),
    title text NOT NULL CHECK(length(title) BETWEEN 1 AND 300),
    url text NOT NULL CHECK(length(url) BETWEEN 1 AND 2048),
    status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','published','rejected')),
    thread_id uuid REFERENCES public.threads ON DELETE SET NULL,
    reviewed_by uuid REFERENCES public.users,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(source_hash,identity_hash)
);
COMMENT ON TABLE public.integration_feed_items IS 'Deduplicated title/link candidates held for a separate staff publication decision; remote HTML is never imported.';
CREATE INDEX integration_feed_items_pending ON public.integration_feed_items(item_id) WHERE status='pending';

CREATE FUNCTION api.integration_public_topics_v1()
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object('thread_id',t.thread_id,'title',t.title,'slug',t.slug)
FROM public.threads t JOIN public.categories c USING(category_id) JOIN public.spaces s USING(space_id)
WHERE t.visibility='public' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')
    AND c.visibility='public' AND c.deleted_at IS NULL AND s.visibility='public' AND s.deleted_at IS NULL
ORDER BY t.last_activity_at DESC,t.thread_id DESC LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_public_topics_v1() FROM PUBLIC;

CREATE FUNCTION api.integration_public_topics_v2()
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_public_topics_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.integration_public_topics_v2() FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_request_v1(p_actor uuid, p_announcement uuid, p_thread uuid, p_target_hash text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE kept uuid;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'admin_console','manage') OR NOT api.core_product_read_thread_v1(NULL,p_thread) THEN
        RETURN QUERY SELECT jsonb_build_object('status','refused'); RETURN;
    END IF;
    INSERT INTO public.integration_announcements(announcement_id,thread_id,target_hash,requested_by)
        VALUES(p_announcement,p_thread,p_target_hash,p_actor) ON CONFLICT(thread_id,target_hash) DO NOTHING
        RETURNING announcement_id INTO kept;
    RETURN QUERY SELECT jsonb_build_object('status',CASE WHEN kept IS NULL THEN 'unchanged' ELSE 'queued' END,
        'announcement_id',kept);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_request_v1(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_request_v2(p_actor uuid, p_announcement uuid, p_thread uuid, p_target_hash text)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_announcement_request_v1(p_actor, p_announcement, p_thread, p_target_hash);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_request_v2(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_claim_v1(p_announcement uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.integration_announcements; topic record;
BEGIN
    SELECT * INTO held FROM public.integration_announcements WHERE announcement_id=p_announcement FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF held.status='sending' THEN
        UPDATE public.integration_announcements SET status='uncertain',updated_at=now() WHERE announcement_id=p_announcement;
        RETURN QUERY SELECT jsonb_build_object('status','uncertain'); RETURN;
    END IF;
    IF held.status <> 'queued' THEN RETURN QUERY SELECT jsonb_build_object('status',held.status); RETURN; END IF;
    IF NOT api.core_product_read_thread_v1(NULL,held.thread_id) THEN
        UPDATE public.integration_announcements SET status='cancelled',updated_at=now() WHERE announcement_id=p_announcement;
        RETURN QUERY SELECT jsonb_build_object('status','cancelled'); RETURN;
    END IF;
    SELECT title,slug INTO topic FROM public.threads WHERE thread_id=held.thread_id;
    UPDATE public.integration_announcements SET status='sending',updated_at=now() WHERE announcement_id=p_announcement;
    RETURN QUERY SELECT jsonb_build_object('status','sending','target_hash',held.target_hash,'thread_id',held.thread_id,
        'title',topic.title,'slug',topic.slug);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_claim_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_claim_v2(p_announcement uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_announcement_claim_v1(p_announcement);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_claim_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_finish_v1(p_announcement uuid, p_status text, p_remote_id text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_status NOT IN ('sent','uncertain','cancelled','failed','queued') THEN RAISE EXCEPTION 'invalid announcement outcome' USING ERRCODE='22023'; END IF;
    UPDATE public.integration_announcements SET status=p_status,remote_id=coalesce(p_remote_id,''),updated_at=now()
        WHERE announcement_id=p_announcement AND status='sending';
    RETURN QUERY SELECT jsonb_build_object('updated',FOUND);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_finish_v1(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_finish_v2(p_announcement uuid, p_status text, p_remote_id text)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_announcement_finish_v1(p_announcement, p_status, p_remote_id);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_finish_v2(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_list_v1()
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object('announcement_id',a.announcement_id,'thread_id',a.thread_id,'status',a.status,
    'title',t.title,'updated_at',a.updated_at) FROM public.integration_announcements a
    JOIN public.threads t USING(thread_id) ORDER BY a.updated_at DESC,a.announcement_id DESC LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_list_v1() FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_list_v2()
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_announcement_list_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_list_v2() FROM PUBLIC;

CREATE FUNCTION api.integration_feed_begin_v1(p_source_hash text, p_source_url text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.integration_feed_sources;
BEGIN
    INSERT INTO public.integration_feed_sources(source_hash,source_url) VALUES(p_source_hash,p_source_url) ON CONFLICT DO NOTHING;
    UPDATE public.integration_feed_sources SET next_fetch_at=now()+interval '5 minutes'
        WHERE source_hash=p_source_hash AND source_url=p_source_url AND next_fetch_at<=now() RETURNING * INTO held;
    IF FOUND THEN RETURN QUERY SELECT jsonb_build_object('etag',held.etag,'modified',held.modified); END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_begin_v1(text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_begin_v2(p_source_hash text, p_source_url text)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_feed_begin_v1(p_source_hash, p_source_url);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_begin_v2(text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_finish_v1(p_source_hash text, p_etag text, p_modified text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    UPDATE public.integration_feed_sources SET etag=p_etag,modified=p_modified WHERE source_hash=p_source_hash;
    RETURN QUERY SELECT jsonb_build_object('updated',FOUND);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_finish_v1(text, text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_finish_v2(p_source_hash text, p_etag text, p_modified text)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_feed_finish_v1(p_source_hash, p_etag, p_modified);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_finish_v2(text, text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_stage_v1(p_item uuid, p_source_hash text, p_identity_hash text, p_url_hash text, p_title text, p_url text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE inserted uuid;
BEGIN
    INSERT INTO public.integration_feed_items(item_id,source_hash,identity_hash,url_hash,title,url)
        VALUES(p_item,p_source_hash,p_identity_hash,p_url_hash,p_title,p_url) ON CONFLICT DO NOTHING RETURNING item_id INTO inserted;
    RETURN QUERY SELECT jsonb_build_object('created',inserted IS NOT NULL);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_stage_v1(uuid, text, text, text, text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_stage_v2(p_item uuid, p_source_hash text, p_identity_hash text, p_url_hash text, p_title text, p_url text)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_feed_stage_v1(p_item, p_source_hash, p_identity_hash, p_url_hash, p_title, p_url);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_stage_v2(uuid, text, text, text, text, text) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_queue_v1(p_after uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object('item_id',i.item_id,'title',i.title,'url',i.url,'source_url',s.source_url)
    FROM public.integration_feed_items i JOIN public.integration_feed_sources s USING(source_hash)
    WHERE i.status='pending' AND (p_after IS NULL OR i.item_id>p_after) ORDER BY i.item_id LIMIT 51;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_queue_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_queue_v2(p_after uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_feed_queue_v1(p_after);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_queue_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_find_v1(p_item uuid, p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE item public.integration_feed_items;
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'admin_console','manage') THEN RETURN; END IF;
    SELECT * INTO item FROM public.integration_feed_items WHERE item_id=p_item FOR UPDATE;
    IF FOUND THEN RETURN QUERY SELECT to_jsonb(item); END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_find_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_find_v2(p_item uuid, p_actor uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_feed_find_v1(p_item, p_actor);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_find_v2(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_decide_v1(p_actor uuid, p_item uuid, p_status text, p_thread uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'admin_console','manage') OR p_status NOT IN ('published','rejected')
        OR (p_status='published' AND p_thread IS NULL) THEN RETURN QUERY SELECT jsonb_build_object('status','refused'); RETURN; END IF;
    UPDATE public.integration_feed_items SET status=p_status,thread_id=p_thread,reviewed_by=p_actor
        WHERE item_id=p_item AND status='pending';
    RETURN QUERY SELECT jsonb_build_object('status',CASE WHEN FOUND THEN 'ok' ELSE 'unchanged' END);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_decide_v1(uuid, uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_feed_decide_v2(p_actor uuid, p_item uuid, p_status text, p_thread uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.integration_feed_decide_v1(p_actor, p_item, p_status, p_thread);
$$;
REVOKE EXECUTE ON FUNCTION api.integration_feed_decide_v2(uuid, uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_announcement_payload_v1(p_announcement uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE topic record;
BEGIN
    SELECT t.thread_id,t.title,t.slug,t.visibility,c.visibility AS category_visibility,s.visibility AS space_visibility,
        t.deleted_at,c.deleted_at AS category_deleted,s.deleted_at AS space_deleted,t.moderation_state INTO topic
        FROM public.integration_announcements a JOIN public.threads t USING(thread_id)
        JOIN public.categories c USING(category_id) JOIN public.spaces s USING(space_id)
        WHERE a.announcement_id=p_announcement AND a.status='sending'
            AND api.core_product_staff_v1(a.requested_by,'admin_console','manage') FOR SHARE OF t,c,s;
    IF NOT FOUND OR topic.visibility<>'public' OR topic.category_visibility<>'public' OR topic.space_visibility<>'public'
        OR topic.deleted_at IS NOT NULL OR topic.category_deleted IS NOT NULL OR topic.space_deleted IS NOT NULL
        OR topic.moderation_state NOT IN ('visible','locked') THEN RETURN; END IF;
    RETURN QUERY SELECT jsonb_build_object('thread_id',topic.thread_id,'title',topic.title,'slug',topic.slug);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_payload_v1(uuid) FROM PUBLIC;
CREATE FUNCTION api.integration_announcement_payload_v2(p_announcement uuid)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.integration_announcement_payload_v1(p_announcement); $$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_payload_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.integration_public_categories_v1()
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT jsonb_build_object('category_id',c.category_id,'title',c.title) FROM public.categories c
    JOIN public.spaces s USING(space_id) WHERE c.visibility='public' AND s.visibility='public'
        AND c.deleted_at IS NULL AND s.deleted_at IS NULL ORDER BY c.title,c.category_id LIMIT 100; $$;
REVOKE EXECUTE ON FUNCTION api.integration_public_categories_v1() FROM PUBLIC;
CREATE FUNCTION api.integration_public_categories_v2()
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.integration_public_categories_v1(); $$;
REVOKE EXECUTE ON FUNCTION api.integration_public_categories_v2() FROM PUBLIC;
CREATE FUNCTION api.integration_announcement_retry_v1(p_actor uuid,p_announcement uuid,p_target_hash text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'admin_console','manage') THEN
        RETURN QUERY SELECT jsonb_build_object('status','refused'); RETURN;
    END IF;
    UPDATE public.integration_announcements SET status='queued',updated_at=now()
        WHERE announcement_id=p_announcement AND target_hash=p_target_hash AND status IN ('uncertain','failed');
    RETURN QUERY SELECT jsonb_build_object('status',CASE WHEN FOUND THEN 'queued' ELSE 'unchanged' END);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_retry_v1(uuid,uuid,text) FROM PUBLIC;
CREATE FUNCTION api.integration_announcement_retry_v2(p_actor uuid,p_announcement uuid,p_target_hash text)
RETURNS TABLE (result jsonb)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.integration_announcement_retry_v1(p_actor,p_announcement,p_target_hash); $$;
REVOKE EXECUTE ON FUNCTION api.integration_announcement_retry_v2(uuid,uuid,text) FROM PUBLIC;

-- Extend the durable administrator allowlist without changing applied APIs.
CREATE FUNCTION api.core_configuration_valid_v3(p_section text, p_key text, p_value jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT coalesce(api.core_configuration_valid_v2(p_section,p_key,p_value),false)
    OR (p_section='plugins' AND p_key IN ('vimeo','gitlab','codeberg','mastodon','peertube')
        AND jsonb_typeof(p_value)='object'
        AND jsonb_typeof(p_value->'enabled')='boolean'
        AND jsonb_typeof(p_value->'mode')='string'
        AND p_value->>'mode' IN ('link','embed')
        AND (SELECT count(*) FROM jsonb_object_keys(p_value))=2
        AND (p_value->>'mode'='link' OR p_key IN ('vimeo','peertube')))
    OR (p_section='general' AND p_key IN (
        'GPFORUM_MASTODON_HOSTS','GPFORUM_PEERTUBE_HOSTS','GPFORUM_DISCORD_WEBHOOK',
        'GPFORUM_SYNDICATION_SOURCES','GPFORUM_OIDC_ISSUER','GPFORUM_OIDC_AUTHORIZATION_ENDPOINT',
        'GPFORUM_OIDC_TOKEN_ENDPOINT','GPFORUM_OIDC_JWKS_URI','GPFORUM_OIDC_CLIENT_ID',
        'GPFORUM_OIDC_CLIENT_SECRET','GPFORUM_OIDC_SIGNING_ALGORITHM')
        AND jsonb_typeof(p_value)='string' AND length(p_value#>>'{}')<=2000
        AND (p_key NOT IN ('GPFORUM_DISCORD_WEBHOOK','GPFORUM_OIDC_CLIENT_SECRET')
            OR p_value#>>'{}' LIKE 'v1.%')); $$;
REVOKE EXECUTE ON FUNCTION api.core_configuration_valid_v3(text, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_change_v5(p_actor uuid,p_command uuid,p_expected bigint,
    p_section text,p_key text,p_operation text,p_value jsonb,p_request_hash text)
RETURNS TABLE(result jsonb) LANGUAGE plpgsql VOLATILE
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$
DECLARE opened record; held public.forum_configuration; answer jsonb; item record; items jsonb;
BEGIN
    IF p_section IS NULL OR p_section NOT IN ('plugins','general') OR p_key IS NULL
        OR p_operation IS NULL OR p_operation NOT IN ('set','reset') OR p_expected IS NULL OR p_expected<0
        OR p_request_hash IS NULL OR p_request_hash !~ '^[a-f0-9]{64}$' THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    IF p_key='__all__' THEN
        IF p_operation<>'set' OR jsonb_typeof(p_value) IS DISTINCT FROM 'object'
            OR (SELECT count(*) FROM jsonb_object_keys(p_value))>64 THEN
            RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
        END IF;
        items:=p_value;
    ELSE
        items:=jsonb_build_object(p_key,CASE WHEN p_operation='reset' THEN
            CASE WHEN p_section='plugins' THEN '{"enabled":false,"mode":"link"}'::jsonb ELSE '"v1.reset"'::jsonb END
            ELSE p_value END);
    END IF;
    FOR item IN SELECT key,value FROM jsonb_each(items) LOOP
        IF NOT coalesce(api.core_configuration_valid_v3(p_section,item.key,item.value),false) THEN
            RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
        END IF;
    END LOOP;
    PERFORM 1 FROM public.users u WHERE u.id=p_actor AND u.status='active' AND u.deleted_at IS NULL FOR SHARE;
    IF NOT FOUND OR NOT api.core_product_staff_v1(p_actor,'admin_console','manage') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'admin.configuration',
        jsonb_build_object('expected',p_expected,'section',p_section,'key',p_key,'operation',p_operation,'request_hash',p_request_hash));
    IF opened.outcome<>'opened' THEN
        RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    SELECT * INTO held FROM public.forum_configuration f WHERE f.singleton FOR UPDATE;
    IF held.revision<>p_expected THEN
        answer:=jsonb_build_object('status','conflict','revision',held.revision);
    ELSE
        UPDATE public.forum_configuration f SET settings=CASE
            WHEN p_operation='reset' THEN f.settings #- ARRAY[p_section,p_key]
            WHEN p_key='__all__' THEN jsonb_set(f.settings,ARRAY[p_section],p_value,true)
            ELSE jsonb_set(f.settings,ARRAY[p_section,p_key],p_value,true) END,
            revision=f.revision+1,updated_at=clock_timestamp() WHERE f.singleton;
        PERFORM api.core_product_audit_v1(p_actor,p_command,'admin.configuration',
            '00000000-0000-4000-8000-000000000001'::uuid,'configuration',
            jsonb_build_object('section',p_section,'key',p_key,'operation',p_operation));
        answer:=jsonb_build_object('status','ok','revision',held.revision+1);
    END IF;
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_change_v5(p_actor uuid, p_command uuid, p_expected bigint, p_section text, p_key text, p_operation text, p_value jsonb, p_request_hash text) FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_change_v6(p_actor uuid,p_command uuid,p_expected bigint,
    p_section text,p_key text,p_operation text,p_value jsonb,p_request_hash text)
RETURNS TABLE(result jsonb) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.admin_configuration_change_v5(p_actor,p_command,p_expected,p_section,p_key,p_operation,p_value,p_request_hash); $$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_change_v6(p_actor uuid, p_command uuid, p_expected bigint, p_section text, p_key text, p_operation text, p_value jsonb, p_request_hash text) FROM PUBLIC;

COMMIT;
