-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.privacy_insert_v1(p_source text, p_row jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'RetentionHold' THEN
        INSERT INTO public.retention_holds (retention_hold_id, resource_type, resource_id, reason, starts_at, ends_at, created_by, created_at)
        VALUES ((p_row->>'retention_hold_id')::uuid, (p_row->>'resource_type')::text, (p_row->>'resource_id')::uuid, (p_row->>'reason')::text, (p_row->>'starts_at')::timestamptz, (p_row->>'ends_at')::timestamptz, (p_row->>'created_by')::uuid, (p_row->>'created_at')::timestamptz);
    WHEN 'DeletionRequest' THEN
        INSERT INTO public.deletion_requests (deletion_request_id, requester_user_id, resource_type, resource_id, request_type, reason, status, created_at, completed_at)
        VALUES ((p_row->>'deletion_request_id')::uuid, (p_row->>'requester_user_id')::uuid, (p_row->>'resource_type')::text, (p_row->>'resource_id')::uuid, (p_row->>'request_type')::text, (p_row->>'reason')::text, (p_row->>'status')::text, (p_row->>'created_at')::timestamptz, (p_row->>'completed_at')::timestamptz);
    WHEN 'DeletionAction' THEN
        INSERT INTO public.deletion_actions (deletion_action_id, deletion_request_id, actor_id, action_type, metadata, created_at)
        VALUES ((p_row->>'deletion_action_id')::uuid, (p_row->>'deletion_request_id')::uuid, (p_row->>'actor_id')::uuid, (p_row->>'action_type')::text, p_row->'metadata', (p_row->>'created_at')::timestamptz);
    WHEN 'ErasureJob' THEN
        INSERT INTO public.erasure_jobs (erasure_job_id, deletion_request_id, status, scheduled_at, completed_at, last_error)
        VALUES ((p_row->>'erasure_job_id')::uuid, (p_row->>'deletion_request_id')::uuid, (p_row->>'status')::text, (p_row->>'scheduled_at')::timestamptz, (p_row->>'completed_at')::timestamptz, (p_row->>'last_error')::text);
    WHEN 'ExportRequest' THEN
        INSERT INTO public.export_requests (export_request_id, requester_user_id, subject_user_id, export_type, format, status, created_at, finished_at, manifest)
        VALUES ((p_row->>'export_request_id')::uuid, (p_row->>'requester_user_id')::uuid, (p_row->>'subject_user_id')::uuid, (p_row->>'export_type')::text, (p_row->>'format')::text, (p_row->>'status')::text, (p_row->>'created_at')::timestamptz, (p_row->>'finished_at')::timestamptz, p_row->'manifest');
    ELSE RAISE EXCEPTION 'unsupported persistence source %', p_source USING ERRCODE = '22023';
    END CASE;
    RETURN QUERY SELECT p_row::json;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_insert_v1(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.portability_insert_v1(p_source text, p_row jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'ImportJob' THEN
        INSERT INTO public.import_jobs (import_job_id, source_system, adapter_name, status, dry_run, manifest, progress, created_by, created_at, started_at, finished_at)
        VALUES ((p_row->>'import_job_id')::uuid, (p_row->>'source_system')::text, (p_row->>'adapter_name')::text, (p_row->>'status')::text, CASE WHEN p_row->>'dry_run' IN ('1','true') THEN true ELSE false END, p_row->'manifest', p_row->'progress', (p_row->>'created_by')::uuid, (p_row->>'created_at')::timestamptz, (p_row->>'started_at')::timestamptz, (p_row->>'finished_at')::timestamptz);
    WHEN 'ImportFailure' THEN
        INSERT INTO public.import_failures (import_failure_id, import_job_id, source_record_type, source_record_id, error_code, error_message, payload, created_at)
        VALUES ((p_row->>'import_failure_id')::uuid, (p_row->>'import_job_id')::uuid, (p_row->>'source_record_type')::text, (p_row->>'source_record_id')::text, (p_row->>'error_code')::text, (p_row->>'error_message')::text, p_row->'payload', (p_row->>'created_at')::timestamptz);
    WHEN 'LegacyIdMap' THEN
        INSERT INTO public.legacy_id_map (legacy_id_map_id, import_job_id, legacy_type, legacy_id, native_type, native_id, canonical_url, visibility, created_at)
        VALUES ((p_row->>'legacy_id_map_id')::uuid, (p_row->>'import_job_id')::uuid, (p_row->>'legacy_type')::text, (p_row->>'legacy_id')::text, (p_row->>'native_type')::text, (p_row->>'native_id')::uuid, (p_row->>'canonical_url')::text, (p_row->>'visibility')::text, (p_row->>'created_at')::timestamptz);
    ELSE RAISE EXCEPTION 'unsupported persistence source %', p_source USING ERRCODE = '22023';
    END CASE;
    RETURN QUERY SELECT p_row::json;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.portability_insert_v1(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.plugin_insert_v1(p_source text, p_row jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'Plugin' THEN
        INSERT INTO public.plugins (plugin_id, name, version, author, compatible_gpforum_range, status, capabilities, required_permissions, config_schema, installed_at, enabled_at, disabled_at)
        VALUES ((p_row->>'plugin_id')::uuid, (p_row->>'name')::text, (p_row->>'version')::text, (p_row->>'author')::text, (p_row->>'compatible_gpforum_range')::text, (p_row->>'status')::text, p_row->'capabilities', p_row->'required_permissions', p_row->'config_schema', (p_row->>'installed_at')::timestamptz, (p_row->>'enabled_at')::timestamptz, (p_row->>'disabled_at')::timestamptz);
    WHEN 'PluginHook' THEN
        INSERT INTO public.plugin_hooks (hook_id, plugin_id, hook_name, callback_name, execution_order, timeout_ms, side_effect_policy, enabled, created_at)
        VALUES ((p_row->>'hook_id')::uuid, (p_row->>'plugin_id')::uuid, (p_row->>'hook_name')::text, (p_row->>'callback_name')::text, (p_row->>'execution_order')::integer, (p_row->>'timeout_ms')::integer, (p_row->>'side_effect_policy')::text, CASE WHEN p_row->>'enabled' IN ('1','true') THEN true ELSE false END, (p_row->>'created_at')::timestamptz);
    WHEN 'PluginFailure' THEN
        INSERT INTO public.plugin_failures (plugin_failure_id, plugin_id, hook_name, error_class, error_message, context, created_at)
        VALUES ((p_row->>'plugin_failure_id')::uuid, (p_row->>'plugin_id')::uuid, (p_row->>'hook_name')::text, (p_row->>'error_class')::text, (p_row->>'error_message')::text, p_row->'context', (p_row->>'created_at')::timestamptz);
    ELSE RAISE EXCEPTION 'unsupported persistence source %', p_source USING ERRCODE = '22023';
    END CASE;
    RETURN QUERY SELECT p_row::json;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.plugin_insert_v1(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_find_v1(p_source text, p_id uuid, p_lock_row boolean) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
DECLARE held jsonb;
BEGIN
    CASE p_source
    WHEN 'DeletionRequest' THEN
        IF p_lock_row THEN SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text)) INTO held FROM public.deletion_requests r WHERE deletion_request_id=p_id FOR UPDATE;
        ELSE SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text)) INTO held FROM public.deletion_requests r WHERE deletion_request_id=p_id; END IF;
    WHEN 'ErasureJob' THEN SELECT (to_jsonb(r)||jsonb_build_object('scheduled_at',r.scheduled_at::text,'completed_at',r.completed_at::text)) INTO held FROM public.erasure_jobs r WHERE erasure_job_id=p_id;
    WHEN 'ExportRequest' THEN SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'finished_at',r.finished_at::text)) INTO held FROM public.export_requests r WHERE export_request_id=p_id;
    WHEN 'User' THEN SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'updated_at',r.updated_at::text,'deleted_at',r.deleted_at::text,'email_verified_at',r.email_verified_at::text)) INTO held FROM public.users r WHERE r.id=p_id;
    ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
    END CASE;
    IF held IS NOT NULL THEN RETURN QUERY SELECT held::json; END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_find_v1(text, uuid, boolean) FROM PUBLIC;

CREATE FUNCTION api.privacy_latest_v1(p_source text, p_query jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'DeletionRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text))::json FROM public.deletion_requests r
      WHERE resource_type=p_query->>'resource_type' AND resource_id=(p_query->>'resource_id')::uuid
      AND request_type=p_query->>'request_type' AND status IN ('pending','approved','held') ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
    WHEN 'ErasureJob' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('scheduled_at',r.scheduled_at::text,'completed_at',r.completed_at::text))::json FROM public.erasure_jobs r
      WHERE deletion_request_id=(p_query->>'deletion_request_id')::uuid ORDER BY scheduled_at DESC LIMIT 1;
    WHEN 'RetentionHold' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('starts_at',r.starts_at::text,'ends_at',r.ends_at::text,'created_at',r.created_at::text))::json FROM public.retention_holds r
      WHERE resource_type=p_query->>'resource_type' AND resource_id=(p_query->>'resource_id')::uuid AND ends_at IS NULL ORDER BY created_at DESC LIMIT 1;
    WHEN 'DeletionAction' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text))::json FROM public.deletion_actions r
      WHERE deletion_request_id=(p_query->>'deletion_request_id')::uuid AND action_type=p_query->>'action_type' ORDER BY created_at DESC LIMIT 1;
    WHEN 'ExportRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'finished_at',r.finished_at::text))::json FROM public.export_requests r
      WHERE export_type=p_query->>'export_type' AND format=p_query->>'format' AND requester_user_id=(p_query->>'requester_user_id')::uuid
      AND subject_user_id=(p_query->>'subject_user_id')::uuid AND status='pending' ORDER BY created_at DESC LIMIT 1;
    ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
    END CASE;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_latest_v1(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_review_v1(p_source text, p_query jsonb, p_row_limit integer, p_oldest boolean) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'DeletionRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text))::json FROM public.deletion_requests r
      WHERE (NOT p_query ? 'status' OR status=p_query->>'status')
      AND (NOT p_query ? 'requester_user_id' OR requester_user_id=(p_query->>'requester_user_id')::uuid)
      AND (NOT p_query ? 'resource_type' OR resource_type=p_query->>'resource_type')
      AND (NOT p_query ? 'resource_id' OR resource_id=(p_query->>'resource_id')::uuid)
      ORDER BY CASE WHEN p_oldest THEN created_at END ASC, CASE WHEN NOT p_oldest THEN created_at END DESC LIMIT p_row_limit;
    WHEN 'ExportRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'finished_at',r.finished_at::text))::json FROM public.export_requests r
      WHERE (NOT p_query ? 'status' OR status=p_query->>'status')
      AND (NOT p_query ? 'requester_user_id' OR requester_user_id=(p_query->>'requester_user_id')::uuid)
      AND (NOT p_query ? 'subject_user_id' OR subject_user_id=(p_query->>'subject_user_id')::uuid)
      AND (NOT p_query ? 'export_request_id' OR export_request_id=(p_query->>'export_request_id')::uuid)
      ORDER BY CASE WHEN p_oldest THEN created_at END ASC, CASE WHEN NOT p_oldest THEN created_at END DESC LIMIT p_row_limit;
    WHEN 'RetentionHold' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('starts_at',r.starts_at::text,'ends_at',r.ends_at::text,'created_at',r.created_at::text))::json FROM public.retention_holds r
      WHERE ends_at IS NULL AND (NOT p_query ? 'resource_type' OR resource_type=p_query->>'resource_type')
      AND (NOT p_query ? 'resource_id' OR resource_id=(p_query->>'resource_id')::uuid) ORDER BY created_at DESC LIMIT p_row_limit;
    WHEN 'ErasureJob' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('scheduled_at',r.scheduled_at::text,'completed_at',r.completed_at::text))::json FROM public.erasure_jobs r
      WHERE status=p_query->>'status' ORDER BY scheduled_at ASC LIMIT p_row_limit;
    ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
    END CASE;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_review_v1(text, jsonb, integer, boolean) FROM PUBLIC;

CREATE FUNCTION api.privacy_update_v1(p_source text, p_id uuid, p_changes jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
 CASE p_source
 WHEN 'DeletionRequest' THEN RETURN QUERY UPDATE public.deletion_requests r SET status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, completed_at=CASE WHEN p_changes ? 'completed_at' THEN (p_changes->>'completed_at')::timestamptz ELSE r.completed_at END WHERE deletion_request_id=p_id RETURNING to_json(r);
 WHEN 'ErasureJob' THEN RETURN QUERY UPDATE public.erasure_jobs r SET status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, completed_at=CASE WHEN p_changes ? 'completed_at' THEN (p_changes->>'completed_at')::timestamptz ELSE r.completed_at END, last_error=CASE WHEN p_changes ? 'last_error' THEN (p_changes->>'last_error')::text ELSE r.last_error END WHERE erasure_job_id=p_id RETURNING to_json(r);
 WHEN 'ExportRequest' THEN RETURN QUERY UPDATE public.export_requests r SET status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, finished_at=CASE WHEN p_changes ? 'finished_at' THEN (p_changes->>'finished_at')::timestamptz ELSE r.finished_at END, manifest=CASE WHEN p_changes ? 'manifest' THEN p_changes->'manifest' ELSE r.manifest END WHERE export_request_id=p_id RETURNING to_json(r);
 WHEN 'User' THEN RETURN QUERY UPDATE public.users r SET deleted_at=CASE WHEN p_changes ? 'deleted_at' THEN (p_changes->>'deleted_at')::timestamptz ELSE r.deleted_at END, display_name=CASE WHEN p_changes ? 'display_name' THEN (p_changes->>'display_name')::text ELSE r.display_name END, email_normalized=CASE WHEN p_changes ? 'email_normalized' THEN (p_changes->>'email_normalized')::text ELSE r.email_normalized END, email_verified_at=CASE WHEN p_changes ? 'email_verified_at' THEN (p_changes->>'email_verified_at')::timestamptz ELSE r.email_verified_at END, password_hash=CASE WHEN p_changes ? 'password_hash' THEN (p_changes->>'password_hash')::text ELSE r.password_hash END, status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, trust_level=CASE WHEN p_changes ? 'trust_level' THEN (p_changes->>'trust_level')::integer ELSE r.trust_level END, updated_at=CASE WHEN p_changes ? 'updated_at' THEN (p_changes->>'updated_at')::timestamptz ELSE r.updated_at END, username=CASE WHEN p_changes ? 'username' THEN (p_changes->>'username')::text ELSE r.username END WHERE id=p_id RETURNING to_json(r);
 ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
 END CASE;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_update_v1(text, uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v1(p_source text, p_user_id uuid, p_at text) RETURNS TABLE(revoked bigint)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
DECLARE amount bigint;
BEGIN
 IF p_source='Credential' THEN UPDATE public.credentials r SET revoked_at=GREATEST(p_at::timestamptz,r.created_at) WHERE r.user_id=p_user_id AND revoked_at IS NULL;
 ELSIF p_source='Session' THEN UPDATE public.sessions r SET revoked_at=GREATEST(p_at::timestamptz,r.created_at) WHERE r.user_id=p_user_id AND revoked_at IS NULL;
 ELSE RAISE EXCEPTION 'unsupported revocation source %',p_source USING ERRCODE='22023'; END IF;
 GET DIAGNOSTICS amount=ROW_COUNT;
 RETURN QUERY SELECT amount;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v1(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.privacy_may_export_v1(p_user_id uuid) RETURNS TABLE(allowed boolean)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
DECLARE held public.users%ROWTYPE;
BEGIN
 SELECT * INTO held FROM public.users WHERE id=p_user_id FOR SHARE;
 RETURN QUERY SELECT FOUND AND held.deleted_at IS NULL;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_may_export_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.privacy_discard_exports_v1(p_user_id uuid) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
DECLARE ids jsonb; answer record; payload jsonb; response jsonb;
BEGIN
 WITH discarded AS (DELETE FROM public.export_requests WHERE subject_user_id=p_user_id RETURNING export_request_id)
 SELECT COALESCE(jsonb_agg(export_request_id ORDER BY export_request_id),'[]'::jsonb) INTO ids FROM discarded;
 FOR answer IN SELECT c.command_id,c.payload FROM public.command_log c WHERE actor_id=p_user_id AND command_type='privacy.export' FOR UPDATE LOOP
   payload=answer.payload;
   IF jsonb_typeof(payload->'response'->'stored')='object' AND payload->'response'->'stored' ? 'manifest' THEN
     response=jsonb_set(payload->'response','{stored}',(payload->'response'->'stored')-'manifest');
     UPDATE public.command_log SET payload=jsonb_set(payload,'{response}',response),
       response_hash=encode(sha256(convert_to(api.core_canonical_json_v1(response),'UTF8')),'hex') WHERE command_id=answer.command_id;
   END IF;
 END LOOP;
 RETURN QUERY SELECT ids::json;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.privacy_discard_exports_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_find_v1(p_source text, p_query jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
 CASE p_source
 WHEN 'ImportJob' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'started_at',r.started_at::text,'finished_at',r.finished_at::text))::json FROM public.import_jobs r WHERE import_job_id=(p_query->>'import_job_id')::uuid;
 WHEN 'ImportFailure' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('payload',r.payload::text)||jsonb_build_object('created_at',r.created_at::text))::json FROM public.import_failures r WHERE import_job_id=(p_query->>'import_job_id')::uuid
   AND source_record_id=p_query->>'source_record_id' AND source_record_type=p_query->>'source_record_type' LIMIT 1;
 WHEN 'LegacyIdMap' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text))::json FROM public.legacy_id_map r WHERE legacy_type=p_query->>'legacy_type' AND legacy_id=p_query->>'legacy_id' LIMIT 1;
 ELSE RAISE EXCEPTION 'unsupported portability source %',p_source USING ERRCODE='22023';
 END CASE;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.portability_find_v1(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.portability_progress_v1(p_job_id uuid, p_progress jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
 UPDATE public.import_jobs SET progress=p_progress WHERE import_job_id=p_job_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'import job not found' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT json_build_object('import_job_id',p_job_id,'progress',p_progress);
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.portability_progress_v1(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION api.plugin_find_v1(p_source text, p_query jsonb) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
BEGIN
 CASE p_source
 WHEN 'Plugin' THEN
   IF p_query ? 'plugin_id' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('capabilities',r.capabilities::text,'required_permissions',r.required_permissions::text,'config_schema',r.config_schema::text)||jsonb_build_object('installed_at',r.installed_at::text,'enabled_at',r.enabled_at::text,'disabled_at',r.disabled_at::text))::json FROM public.plugins r WHERE plugin_id=(p_query->>'plugin_id')::uuid;
   ELSE RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('capabilities',r.capabilities::text,'required_permissions',r.required_permissions::text,'config_schema',r.config_schema::text)||jsonb_build_object('installed_at',r.installed_at::text,'enabled_at',r.enabled_at::text,'disabled_at',r.disabled_at::text))::json FROM public.plugins r WHERE name=p_query->>'name' AND version=p_query->>'version' LIMIT 1; END IF;
 WHEN 'PluginHook' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text))::json FROM public.plugin_hooks r WHERE hook_name=p_query->>'hook_name' AND plugin_id=(p_query->>'plugin_id')::uuid LIMIT 1;
 ELSE RAISE EXCEPTION 'unsupported plugin source %',p_source USING ERRCODE='22023';
 END CASE;
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.plugin_find_v1(text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.plugin_status_v1(p_plugin_id uuid, p_status text, p_at text) RETURNS TABLE(document json)
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
#variable_conflict use_variable
DECLARE held text;
BEGIN
 SELECT r.status INTO held FROM public.plugins r WHERE r.plugin_id=p_plugin_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'plugin not found' USING ERRCODE='22023'; END IF;
 IF held=p_status THEN RETURN QUERY SELECT json_build_object('plugin_id',p_plugin_id,'status',p_status,'skipped',1); RETURN; END IF;
 IF p_status='enabled' THEN UPDATE public.plugins SET disabled_at=NULL, enabled_at=p_at::timestamptz,status=p_status WHERE plugins.plugin_id=p_plugin_id;
 ELSE UPDATE public.plugins SET disabled_at=p_at::timestamptz,status=p_status WHERE plugins.plugin_id=p_plugin_id; END IF;
 RETURN QUERY SELECT json_build_object('plugin_id',p_plugin_id,'status',p_status);
END;
$function$;

REVOKE EXECUTE ON FUNCTION api.plugin_status_v1(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.plugin_hooks_v1(p_hook_name text) RETURNS SETOF public.plugin_hooks
LANGUAGE sql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
SELECT h.hook_id,h.plugin_id,h.hook_name,h.callback_name,h.execution_order,h.timeout_ms,h.side_effect_policy,h.enabled,h.created_at
FROM public.plugin_hooks h WHERE h.hook_name=p_hook_name AND h.enabled=true ORDER BY h.execution_order ASC;
$function$;

REVOKE EXECUTE ON FUNCTION api.plugin_hooks_v1(text) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v1(p_user_id uuid) RETURNS TABLE(document json)
LANGUAGE sql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
SELECT jsonb_build_object(
'profile',(SELECT COALESCE(jsonb_build_object('created_at',u.created_at::text,'display_name',u.display_name,'email',u.email_normalized,'email_verified_at',u.email_verified_at::text,'preferred_locale',u.preferred_locale,'preferred_theme',u.preferred_theme,'preferred_timezone',u.preferred_timezone,'status',u.status,'user_id',u.id,'username',u.username),'{}'::jsonb) FROM public.users u WHERE u.id=p_user_id),
'attachments',(SELECT COALESCE(jsonb_agg(jsonb_build_object('attachment_id',r.attachment_id,'original_filename',r.original_filename,'media_type',r.media_type,'byte_size',r.byte_size,'checksum',r.checksum,'state',r.state,'scan_status',r.scan_status,'created_at',r.created_at::text,'uploaded_at',r.uploaded_at::text,'deleted_at',r.deleted_at::text)),'[]'::jsonb) FROM public.attachments r WHERE r.owner_user_id=p_user_id),
'notifications',(SELECT COALESCE(jsonb_agg(jsonb_build_object('notification_id',r.notification_id,'created_at',r.created_at::text,'read_at',r.read_at::text)),'[]'::jsonb) FROM public.notification_inbox r WHERE r.recipient_user_id=p_user_id),
'subscriptions',(SELECT COALESCE(jsonb_agg(jsonb_build_object('subscription_id',r.subscription_id,'target_type',r.target_type,'target_id',r.target_id,'preference',r.preference,'created_at',r.created_at::text,'muted_at',r.muted_at::text,'revoked_at',r.revoked_at::text)),'[]'::jsonb) FROM public.subscriptions r WHERE r.user_id=p_user_id),
'preferences',(SELECT COALESCE(jsonb_agg(jsonb_build_object('channel',r.channel,'enabled',r.enabled::integer,'digest_frequency',r.digest_frequency,'updated_at',r.updated_at::text)),'[]'::jsonb) FROM public.notification_preferences r WHERE r.user_id=p_user_id),
'posts',(SELECT COALESCE(jsonb_agg(jsonb_build_object('post_id',p.post_id,'thread_id',p.thread_id,'visibility',p.visibility,'moderation_state',p.moderation_state,'position',p.position,'created_at',p.created_at::text,'updated_at',p.updated_at::text,'deleted_at',p.deleted_at::text,'body_format',b.body_format,'body_source',b.body_source)),'[]'::jsonb) FROM public.posts p LEFT JOIN public.post_bodies b USING(post_id) WHERE p.author_user_id=p_user_id))::json;
$function$;

REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_next_position_v1(p_thread_id uuid) RETURNS TABLE(next_position bigint)
LANGUAGE sql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $function$
SELECT COALESCE(MAX(p.position),0)+1 FROM public.posts p WHERE p.thread_id=p_thread_id;
$function$;

REVOKE EXECUTE ON FUNCTION api.forum_next_position_v1(uuid) FROM PUBLIC;

COMMIT;
