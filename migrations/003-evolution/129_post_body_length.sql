-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0140: a post body holds at most 50,000 characters, the number
-- GPForum::Service::Forum::BodyLength checks before a thread, a reply, an
-- edit, a preview or a draft is written. Drafts carry the check since
-- migration 103; published and held bodies carry it here, so no writer can
-- store a body the renderer was not bounded for. No function changes.

BEGIN;
SET LOCAL lock_timeout = '1s';

ALTER TABLE public.post_bodies
    ADD CONSTRAINT post_bodies_body_source_length_check
    CHECK (char_length(body_source) <= 50000);

ALTER TABLE public.held_posts
    ADD CONSTRAINT held_posts_body_source_length_check
    CHECK (char_length(body_source) <= 50000);

COMMIT;
