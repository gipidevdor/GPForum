-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Roles, permissions and who holds which role where (ADR 0057, 0070).

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A named set of permissions.
CREATE TABLE public.roles (
    role_id uuid NOT NULL,
    name text NOT NULL,
    description text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT roles_pkey PRIMARY KEY (role_id),
    CONSTRAINT roles_name_key UNIQUE (name)
);
COMMENT ON TABLE public.roles IS 'A named set of permissions.';

-- An action on a kind of resource, by name.
CREATE TABLE public.permissions (
    permission_id uuid NOT NULL,
    name text NOT NULL,
    resource_type text NOT NULL,
    action text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT permissions_pkey PRIMARY KEY (permission_id),
    CONSTRAINT permissions_name_key UNIQUE (name),
    CONSTRAINT permissions_resource_action_key UNIQUE (resource_type, action)
);
COMMENT ON TABLE public.permissions IS 'An action on a kind of resource, by name.';

-- The permissions of each role.
CREATE TABLE public.role_permissions (
    role_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id),
    CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions (permission_id),
    CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (role_id)
);
COMMENT ON TABLE public.role_permissions IS 'The permissions of each role.';

-- A role given to a member over the whole forum, a space or a resource, until
-- revoked. One active binding per member, role and scope, a null resource or
-- space counting as equal (NULLS NOT DISTINCT).
CREATE TABLE public.role_bindings (
    binding_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role_id uuid NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid,
    space_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    created_by_user_id uuid,
    CONSTRAINT role_bindings_pkey PRIMARY KEY (binding_id),
    CONSTRAINT role_bindings_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles (role_id),
    CONSTRAINT role_bindings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id)
);
CREATE UNIQUE INDEX idx_role_bindings_active_unique
    ON public.role_bindings (user_id, role_id, resource_type, resource_id, space_id) NULLS NOT DISTINCT
    WHERE revoked_at IS NULL;
CREATE INDEX idx_role_bindings_created_by
    ON public.role_bindings (created_by_user_id, created_at DESC)
    WHERE created_by_user_id IS NOT NULL;
CREATE INDEX idx_role_bindings_user_scope_active
    ON public.role_bindings (user_id, resource_type, resource_id, space_id)
    WHERE revoked_at IS NULL;
COMMENT ON TABLE public.role_bindings IS 'A role given to a member over the whole forum, a space or a resource, until revoked.';

COMMIT;
