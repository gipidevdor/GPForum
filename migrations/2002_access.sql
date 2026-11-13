-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: access.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.roles (
    role_id uuid NOT NULL,
    name text NOT NULL,
    description text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT roles_name_key UNIQUE (name),
    CONSTRAINT roles_pkey PRIMARY KEY (role_id)
);
COMMENT ON TABLE public.roles IS 'A named set of permissions.';

CREATE TABLE public.permissions (
    permission_id uuid NOT NULL,
    name text NOT NULL,
    resource_type text NOT NULL,
    action text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT permissions_name_key UNIQUE (name),
    CONSTRAINT permissions_pkey PRIMARY KEY (permission_id),
    CONSTRAINT permissions_resource_action_key UNIQUE (resource_type, action)
);
COMMENT ON TABLE public.permissions IS 'An action on a kind of resource, by name.';

CREATE TABLE public.role_permissions (
    role_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id)
);
COMMENT ON TABLE public.role_permissions IS 'The permissions of each role.';

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
    CONSTRAINT role_bindings_pkey PRIMARY KEY (binding_id)
);
COMMENT ON TABLE public.role_bindings IS 'A role given to a member over the whole forum, a space or a resource, until revoked.';

CREATE UNIQUE INDEX idx_role_bindings_active_unique ON public.role_bindings (user_id, role_id, resource_type, resource_id, space_id) NULLS NOT DISTINCT WHERE revoked_at IS NULL;

CREATE INDEX idx_role_bindings_created_by ON public.role_bindings (created_by_user_id, created_at DESC) WHERE created_by_user_id IS NOT NULL;

CREATE INDEX idx_role_bindings_user_scope_active ON public.role_bindings (user_id, resource_type, resource_id, space_id) WHERE revoked_at IS NULL;

CREATE TABLE public.forum_configuration (
    singleton boolean NOT NULL DEFAULT true,
    revision bigint NOT NULL DEFAULT 0,
    settings jsonb NOT NULL DEFAULT '{"general": {}, "plugins": {}}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT forum_configuration_revision_check CHECK (revision >= 0),
    CONSTRAINT forum_configuration_settings_check CHECK (jsonb_typeof(settings) = 'object'),
    CONSTRAINT forum_configuration_singleton_check CHECK (singleton),
    CONSTRAINT forum_configuration_pkey PRIMARY KEY (singleton)
);
COMMENT ON TABLE public.forum_configuration IS 'Core-owned administrator settings. Plugins never access this table. Secret values are sealed by the application.';

INSERT INTO public.forum_configuration(singleton) VALUES (true);

COMMIT;
