# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Admin;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (
    admin_configuration_snapshot => {
        version    => 2,
        parameters => [ known_revision => 'bigint' ],
        json       => ['settings'],
    },
    admin_request_context => {
        version    => 4,
        parameters => [
            known_revision         => 'bigint',
            session_id             => 'uuid',
            user_id                => 'uuid',
            token_hash             => 'text',
            now                    => 'timestamptz',
            touch_interval_seconds => 'integer',
            resolve_viewer         => 'boolean',
        ],
        json => [qw(settings validation viewer)],
    },
    admin_registration_state =>
      { version => 2, parameters => [ actor => 'uuid' ], json => ['result'] },
    admin_registration_change => {
        version    => 2,
        parameters => [
            actor     => 'uuid',
            command   => 'uuid',
            operation => 'text',
            values    => 'jsonb'
        ],
        json => ['result']
    },

    admin_lookup_role => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_permission => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_role_permission => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_audit => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
        json       => ['metadata'],
    },
    admin_lookup_binding => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_attachment_audits => {
        version    => 2,
        parameters =>
          [ action => 'text', target_id => 'uuid', target_type => 'text' ],
        json => ['metadata'],
    },
    admin_insert_role => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_permission => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_role_permission => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_binding => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_space => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_category => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_update_category => {
        version    => 2,
        parameters => [ category_id => 'uuid', values => 'jsonb' ],
    },
    admin_lock_binding => {
        version    => 2,
        parameters => [ binding_id => 'uuid' ],
    },
    admin_revoke_binding => {
        version    => 2,
        parameters => [ binding_id => 'uuid', revoked_at => 'timestamptz' ],
    },
    admin_list_roles => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_list_permissions => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_insert_announcement =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    admin_retire_announcement => {
        version    => 2,
        parameters => [ announcement_id => 'uuid', values => 'jsonb' ]
    },

    # ADR 0145: address and range bans.
    admin_address_ban_place => {
        version    => 2,
        parameters => [
            ban_id        => 'uuid',
            range         => 'cidr',
            scope         => 'text',
            reason        => 'text',
            expires_at    => 'timestamptz',
            actor_user_id => 'uuid',
            actor_address => 'inet',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_address_ban_edit => {
        version    => 2,
        parameters => [
            ban_id        => 'uuid',
            scope         => 'text',
            reason        => 'text',
            expires_at    => 'timestamptz',
            actor_user_id => 'uuid',
            actor_address => 'inet',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_address_ban_lift => {
        version    => 2,
        parameters => [
            ban_id        => 'uuid',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_address_bans => {
        version    => 2,
        parameters => [ now => 'timestamptz', row_limit => 'integer' ]
    },
    admin_address_ban_covering => {
        version    => 2,
        parameters => [ address => 'inet', now => 'timestamptz' ]
    },
    admin_announcement_by_id =>
      { version => 2, parameters => [ announcement_id => 'uuid' ] },
    admin_list_announcements =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    admin_list_categories => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_roles_for_user => {
        version    => 2,
        parameters => [ user_id => 'uuid', row_limit => 'integer' ],
    },
    admin_space_by_id => {
        version    => 2,
        parameters => [ space_id => 'uuid' ],
    },
    admin_space_by_slug => {
        version    => 2,
        parameters => [ slug => 'text' ],
    },
    admin_first_live_space => {
        version    => 2,
        parameters => [],
    },
    admin_category_by_id => {
        version    => 2,
        parameters => [ category_id => 'uuid' ],
    },
    admin_live_category_by_slug => {
        version    => 2,
        parameters => [ space_id => 'uuid', slug => 'text' ],
    },
    admin_console_users => {
        version    => 4,
        parameters => [ status => 'text', row_limit => 'integer' ],
    },
    admin_console_reports => {
        version    => 2,
        parameters => [ status => 'text', row_limit => 'integer' ],
    },
    admin_console_outbox => {
        version    => 4,
        parameters => [ status => 'text', row_limit => 'integer' ],
    },
    admin_console_email => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    admin_console_counts => {
        version    => 2,
        parameters => [ dead_letters => 'boolean' ],
    },
    admin_console_dead_letters => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_audit_recent => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
        json       => ['metadata'],
    },
    admin_audit_page => {
        version    => 4,
        parameters =>
          [ filters => 'jsonb', after => 'jsonb', row_limit => 'integer' ],
        json => ['metadata'],
    },
    admin_allow_slow_answer => {
        version    => 2,
        parameters => [ idle_ms => 'integer' ],
    },
    admin_second_factor_member =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    admin_second_factor_reset => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
            mail          => 'jsonb',
        ],
    },
    admin_second_factor_policy => { version => 2, parameters => [] },
    admin_second_factor_staff  =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    admin_second_factor_policy_set => {
        version    => 2,
        parameters => [
            required      => 'boolean',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_navigation_context => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
        json       => ['permissions'],
    },
    admin_permission_allowed => {
        version    => 4,
        parameters => [
            user_id       => 'uuid',
            resource_type => 'text',
            action        => 'text',
            resource_id   => 'uuid',
            space_id      => 'uuid',
        ],
    },
    admin_configuration_state =>
      { version => 4, parameters => [], json => ['settings'] },
    admin_configuration_change => {
        version    => 6,
        json       => ['result'],
        parameters => [
            actor        => 'uuid',
            command      => 'uuid',
            expected     => 'bigint',
            section      => 'text',
            key          => 'text',
            operation    => 'text',
            value        => 'jsonb',
            request_hash => 'text'
        ],
    },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Admin - The PostgreSQL functions of administration: settings, roles, audit review, diagnostics and the admin request context.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Admin->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of administration: settings, roles, audit review, diagnostics and the admin request context. See that module for what an
entry holds and for ADR 0126.

=head1 SUBROUTINES/METHODS

=head2 entries

The hash reference of entries, by name, read-only.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Const::Fast.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
