-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.public_cache_state (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    epoch bigint NOT NULL DEFAULT 0 CHECK (epoch >= 0)
);
COMMENT ON TABLE public.public_cache_state IS 'Committed public-content revocations. Cache keys read this epoch before reading their source rows.';
INSERT INTO public.public_cache_state(singleton) VALUES (true);

-- This is separate from the administrator's revision: content moderation
-- must not make an administrator's settings form stale. No INSERT trigger
-- takes the singleton on every new post or reply-counter update.
CREATE FUNCTION public.gpforum_public_cache_revoke()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    field_index integer;
    changed boolean := TG_OP = 'DELETE';
BEGIN
    IF TG_OP = 'UPDATE' THEN
        FOR field_index IN 0..TG_NARGS - 1 LOOP
            IF TG_ARGV[field_index] = 'current_body_id'
                AND to_jsonb(OLD) ->> TG_ARGV[field_index] IS NULL THEN
                CONTINUE;
            END IF;
            IF (to_jsonb(OLD) -> TG_ARGV[field_index]) IS DISTINCT FROM
                (to_jsonb(NEW) -> TG_ARGV[field_index]) THEN
                changed := true;
                EXIT;
            END IF;
        END LOOP;
    END IF;
    IF changed THEN
        UPDATE public.public_cache_state SET epoch = epoch + 1 WHERE singleton;
    END IF;
    RETURN NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gpforum_public_cache_revoke() FROM PUBLIC;

-- Source locks precede the epoch lock. Deferring these until commit avoids
-- taking the singleton between two source writes that another transaction
-- already holds. The epoch and source changes are visible together.
CREATE CONSTRAINT TRIGGER public_cache_threads AFTER UPDATE OR DELETE ON public.threads
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'visibility','moderation_state','deleted_at','category_id','title','slug');
CREATE CONSTRAINT TRIGGER public_cache_posts AFTER UPDATE OR DELETE ON public.posts
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'visibility','moderation_state','deleted_at','thread_id','current_body_id');
CREATE CONSTRAINT TRIGGER public_cache_categories AFTER UPDATE OR DELETE ON public.categories
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'visibility','deleted_at','space_id','title','description');
CREATE CONSTRAINT TRIGGER public_cache_spaces AFTER UPDATE OR DELETE ON public.spaces
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'visibility','deleted_at','title','description');
CREATE CONSTRAINT TRIGGER public_cache_attachments AFTER UPDATE OR DELETE ON public.attachments
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'state','scan_status','deleted_at','original_filename');
CREATE CONSTRAINT TRIGGER public_cache_attachment_links AFTER UPDATE OR DELETE ON public.attachment_links
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'attachment_id','target_type','target_id');
CREATE CONSTRAINT TRIGGER public_cache_users AFTER UPDATE OR DELETE ON public.users
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke(
        'username','display_name','bio','status','deleted_at');
CREATE CONSTRAINT TRIGGER public_cache_avatars AFTER UPDATE OR DELETE ON public.member_avatars
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke('attachment_id');
CREATE CONSTRAINT TRIGGER public_cache_announcements AFTER UPDATE OR DELETE ON public.site_announcements
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke('message','retired_at');
CREATE CONSTRAINT TRIGGER public_cache_post_bodies AFTER UPDATE OR DELETE ON public.post_bodies
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION public.gpforum_public_cache_revoke('body_source','body_rendered_safe');

CREATE FUNCTION api.admin_configuration_state_v3()
RETURNS TABLE(revision bigint, settings jsonb, public_cache_epoch bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT f.revision, f.settings, c.epoch
    FROM api.admin_configuration_state_v1() f
    CROSS JOIN public.public_cache_state c WHERE c.singleton;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_state_v3() FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_state_v4()
RETURNS TABLE(revision bigint, settings jsonb, public_cache_epoch bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.admin_configuration_state_v3() $$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_state_v4() FROM PUBLIC;

COMMIT;
