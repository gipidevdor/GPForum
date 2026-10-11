-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Read markers and their synchronization deltas move forward together. The
-- stored marker is locked before comparing positions, including insert races.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_read_state_v1(p_user_id uuid, p_thread_id uuid)
RETURNS SETOF public.thread_read_state
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.* FROM public.thread_read_state r WHERE r.user_id = p_user_id AND r.thread_id = p_thread_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_state_v1(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_mark_read_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.thread_read_state%ROWTYPE; v_position bigint := (p_row->>'last_read_position')::bigint;
  v_previous bigint := 0; v_raced boolean := false; v_state jsonb;
BEGIN
  SELECT r.* INTO v FROM public.thread_read_state r WHERE r.user_id = (p_row->>'user_id')::uuid AND r.thread_id = (p_row->>'thread_id')::uuid FOR UPDATE;
  IF v.user_id IS NULL THEN
    INSERT INTO public.thread_read_state (user_id, thread_id, last_read_position, last_read_at)
    VALUES ((p_row->>'user_id')::uuid, (p_row->>'thread_id')::uuid, v_position, (p_row->>'last_read_at')::timestamptz)
    ON CONFLICT (user_id, thread_id) DO NOTHING;
    IF FOUND THEN
      INSERT INTO public.user_read_marker_deltas (user_id, thread_id, last_read_position, last_read_at)
      VALUES ((p_row->>'user_id')::uuid, (p_row->>'thread_id')::uuid, v_position, (p_row->>'last_read_at')::timestamptz)
      ON CONFLICT (user_id, thread_id) DO NOTHING;
      RETURN QUERY SELECT jsonb_build_object('ok', 1, 'advanced', CASE WHEN v_position > 0 THEN 1 ELSE 0 END, 'read_state', p_row); RETURN;
    END IF;
    v_raced := true;
    SELECT r.* INTO v FROM public.thread_read_state r WHERE r.user_id = (p_row->>'user_id')::uuid AND r.thread_id = (p_row->>'thread_id')::uuid FOR UPDATE;
  END IF;
  v_previous := v.last_read_position;
  IF v.last_read_at IS NOT NULL AND v_position <= v_previous THEN
    IF v_raced THEN
      INSERT INTO public.user_read_marker_deltas (user_id, thread_id, last_read_position, last_read_at)
      VALUES (v.user_id, v.thread_id, v.last_read_position, v.last_read_at) ON CONFLICT (user_id, thread_id) DO NOTHING;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'advanced', 0, 'skipped', 1,
      'read_state', to_jsonb(v) || jsonb_build_object('last_read_at', v.last_read_at::text)); RETURN;
  END IF;
  v_position := greatest(v_previous, v_position);
  UPDATE public.thread_read_state r SET last_read_position = v_position, last_read_at = (p_row->>'last_read_at')::timestamptz
  WHERE r.user_id = v.user_id AND r.thread_id = v.thread_id;
  INSERT INTO public.user_read_marker_deltas (user_id, thread_id, last_read_position, last_read_at)
  VALUES (v.user_id, v.thread_id, v_position, (p_row->>'last_read_at')::timestamptz)
  ON CONFLICT (user_id, thread_id) DO UPDATE SET last_read_position = EXCLUDED.last_read_position, last_read_at = EXCLUDED.last_read_at;
  v_state := p_row || jsonb_build_object('last_read_position', v_position);
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'advanced', CASE WHEN v_position > v_previous THEN 1 ELSE 0 END, 'read_state', v_state);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_mark_read_v1(jsonb) FROM PUBLIC;
COMMIT;
