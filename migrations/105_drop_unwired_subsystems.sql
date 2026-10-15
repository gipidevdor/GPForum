-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The plugin system (ADR 0083), legacy import with its id map (ADR 0081),
-- the projection offsets and generation writes (ADR 0091) and resource_acl
-- were built and never wired: no route, command or worker reached them, and
-- this release deletes their Perl. Nothing has been released, so no install
-- holds rows a running release reads. This drops what they left in the
-- database: the api functions migrations 061, 068 and 099 made for them,
-- then their eight tables.
--
-- The functions go first. api.plugin_hooks_v1 and _v2 return SETOF
-- public.plugin_hooks, so the table cannot go while they exist, and each
-- _v2 calls its _v1, so _v2 goes before it. The catalogue no longer names
-- any of them, so the runtime role's grants on them go with them.
--
-- projection_generations stays: readiness reads it. The core_ helpers stay:
-- the other areas call them.
--
-- Locking. Dropping import_jobs and resource_acl drops their foreign keys,
-- which takes ACCESS EXCLUSIVE on users, roles and permissions until the
-- commit, and a request that reads users waits behind it. Those two drops
-- come last, so the lock is held for the few milliseconds the rest of the
-- transaction takes. lock_timeout is a second, below the application's
-- three, so a request queued behind the wait is not the one to time out;
-- if the second runs out, the migration fails whole and is run again.

BEGIN;
SET LOCAL lock_timeout = '1s';

DROP FUNCTION IF EXISTS api.plugin_insert_v2(text, jsonb);
DROP FUNCTION IF EXISTS api.plugin_insert_v1(text, jsonb);
DROP FUNCTION IF EXISTS api.plugin_find_v2(text, jsonb);
DROP FUNCTION IF EXISTS api.plugin_find_v1(text, jsonb);
DROP FUNCTION IF EXISTS api.plugin_status_v2(uuid, text, text);
DROP FUNCTION IF EXISTS api.plugin_status_v1(uuid, text, text);
DROP FUNCTION IF EXISTS api.plugin_hooks_v2(text);
DROP FUNCTION IF EXISTS api.plugin_hooks_v1(text);

DROP FUNCTION IF EXISTS api.portability_insert_v2(text, jsonb);
DROP FUNCTION IF EXISTS api.portability_insert_v1(text, jsonb);
DROP FUNCTION IF EXISTS api.portability_find_v2(text, jsonb);
DROP FUNCTION IF EXISTS api.portability_find_v1(text, jsonb);
DROP FUNCTION IF EXISTS api.portability_progress_v2(uuid, jsonb);
DROP FUNCTION IF EXISTS api.portability_progress_v1(uuid, jsonb);

DROP FUNCTION IF EXISTS api.projection_offset_get_v2(text);
DROP FUNCTION IF EXISTS api.projection_offset_get_v1(text);
DROP FUNCTION IF EXISTS api.projection_offset_write_v2(jsonb);
DROP FUNCTION IF EXISTS api.projection_offset_write_v1(jsonb);
DROP FUNCTION IF EXISTS api.projection_generation_start_v2(jsonb);
DROP FUNCTION IF EXISTS api.projection_generation_start_v1(jsonb);
DROP FUNCTION IF EXISTS api.projection_generation_update_v2(uuid, text);
DROP FUNCTION IF EXISTS api.projection_generation_update_v1(uuid, text);
DROP FUNCTION IF EXISTS api.projection_generation_activate_v2(uuid, text);
DROP FUNCTION IF EXISTS api.projection_generation_activate_v1(uuid, text);

DROP TABLE IF EXISTS public.plugin_hooks;
DROP TABLE IF EXISTS public.plugin_failures;
DROP TABLE IF EXISTS public.plugins;
DROP TABLE IF EXISTS public.projection_offsets;
DROP TABLE IF EXISTS public.import_failures;
DROP TABLE IF EXISTS public.legacy_id_map;
DROP TABLE IF EXISTS public.import_jobs;
DROP TABLE IF EXISTS public.resource_acl;

COMMIT;
