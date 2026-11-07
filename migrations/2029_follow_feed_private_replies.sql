-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '5s';

-- The previous typed entry point remains for rolling workers. New workers
-- use the private-thread-only ownership exception of the canonical reader.
CREATE FUNCTION api.community_follow_feed_v3(p_actor uuid,p_member boolean,p_global_read boolean,p_category_ids uuid[],p_space_ids uuid[],
    p_after_at timestamptz,p_after_id uuid,p_row_limit integer)
RETURNS TABLE(item_id uuid,item_type text,thread_id uuid,title text,username text,display_name text,created_at timestamptz) LANGUAGE sql STABLE
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_custom_plan
AS $$
SELECT * FROM ((SELECT t.thread_id AS item_id,'thread'::text AS item_type,t.thread_id,t.title,u.username,u.display_name,t.created_at
FROM public.subscriptions followed
JOIN public.threads t ON t.author_user_id=followed.target_id
JOIN public.users u ON u.id=followed.target_id
JOIN public.categories c ON c.category_id=t.category_id
JOIN public.spaces s ON s.space_id=c.space_id
WHERE followed.user_id=p_actor AND followed.target_type='user' AND followed.revoked_at IS NULL
    AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')
    AND c.deleted_at IS NULL AND s.deleted_at IS NULL
    AND (p_global_read OR t.visibility='public' OR (p_member AND t.visibility='members')
        OR (p_member AND t.visibility='private' AND (t.author_user_id=p_actor OR t.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND (p_global_read OR c.visibility='public' OR (p_member AND c.visibility='members')
        OR (p_member AND (c.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND (p_global_read OR s.visibility='public' OR (p_member AND s.visibility='members')
        OR (p_member AND (c.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND u.deleted_at IS NULL AND u.status='active'
    AND NOT EXISTS(SELECT 1 FROM public.member_relations r WHERE
        (r.owner_user_id=p_actor AND r.other_user_id=u.id)
        OR (r.owner_user_id=u.id AND r.other_user_id=p_actor AND r.kind='block'))

    AND (t.created_at,t.thread_id) < (coalesce(p_after_at,'infinity'::timestamptz),coalesce(p_after_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
ORDER BY t.created_at DESC,t.thread_id DESC LIMIT least(greatest(p_row_limit,1),101)) UNION ALL (SELECT p.post_id AS item_id,'post'::text AS item_type,t.thread_id,t.title,u.username,u.display_name,p.created_at
FROM public.subscriptions followed
JOIN public.posts p ON p.author_user_id=followed.target_id JOIN public.threads t ON t.thread_id=p.thread_id
JOIN public.users u ON u.id=followed.target_id
JOIN public.categories c ON c.category_id=t.category_id
JOIN public.spaces s ON s.space_id=c.space_id
WHERE followed.user_id=p_actor AND followed.target_type='user' AND followed.revoked_at IS NULL
    AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')
    AND c.deleted_at IS NULL AND s.deleted_at IS NULL
    AND (p_global_read OR t.visibility='public' OR (p_member AND t.visibility='members')
        OR (p_member AND t.visibility='private' AND (t.author_user_id=p_actor OR t.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND (p_global_read OR c.visibility='public' OR (p_member AND c.visibility='members')
        OR (p_member AND (c.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND (p_global_read OR s.visibility='public' OR (p_member AND s.visibility='members')
        OR (p_member AND (c.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND u.deleted_at IS NULL AND u.status='active'
    AND NOT EXISTS(SELECT 1 FROM public.member_relations r WHERE
        (r.owner_user_id=p_actor AND r.other_user_id=u.id)
        OR (r.owner_user_id=u.id AND r.other_user_id=p_actor AND r.kind='block'))
    AND p.position>1 AND p.deleted_at IS NULL AND p.moderation_state='visible' AND (p_global_read OR p.visibility='public' OR (p_member AND p.visibility='members') OR (p_member AND p.visibility='private' AND (p.author_user_id=p_actor OR (t.visibility='private' AND t.author_user_id=p_actor) OR t.category_id=ANY(p_category_ids) OR c.space_id=ANY(p_space_ids))))
    AND (p.created_at,p.post_id) < (coalesce(p_after_at,'infinity'::timestamptz),coalesce(p_after_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
ORDER BY p.created_at DESC,p.post_id DESC LIMIT least(greatest(p_row_limit,1),101))) activity
ORDER BY activity.created_at DESC,activity.item_id DESC LIMIT least(greatest(p_row_limit,1),101);
$$;
REVOKE EXECUTE ON FUNCTION api.community_follow_feed_v3(p_actor uuid, p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.community_follow_feed_v4(p_actor uuid,p_member boolean,p_global_read boolean,p_category_ids uuid[],p_space_ids uuid[],
    p_after_at timestamptz,p_after_id uuid,p_row_limit integer)
RETURNS TABLE(item_id uuid,item_type text,thread_id uuid,title text,username text,display_name text,created_at timestamptz) LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.community_follow_feed_v3(p_actor, p_member, p_global_read, p_category_ids, p_space_ids, p_after_at, p_after_id, p_row_limit); $$;
REVOKE EXECUTE ON FUNCTION api.community_follow_feed_v4(p_actor uuid, p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_after_at timestamp with time zone, p_after_id uuid, p_row_limit integer) FROM PUBLIC;

COMMIT;
