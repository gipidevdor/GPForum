# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Admin::Base', -async_await;
use v5.40;
use Mojo::Promise;

use GPForum::Web::MemberNotes;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;

async sub dashboard ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $payload;
    try {
        $payload = ( await $self->await_p( $self->_dashboard_payload ) );
    }
    catch ($error) {
        $self->app->log->error("admin dashboard failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload  => $payload,
            status   => $HTTP_OK,
            template => 'admin/dashboard',
        }
    );
}

async sub roles ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $payload;
    try {
        $payload = ( await $self->await_p( $self->_roles_payload ) );
    }
    catch ($error) {
        $self->app->log->error("admin roles failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload  => $payload,
            status   => $HTTP_OK,
            template => 'admin/roles',
        }
    );
}

async sub categories ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $payload;
    try {
        $payload = ( await $self->await_p( $self->_categories_payload ) );
    }
    catch ($error) {
        $self->app->log->error("admin categories failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload  => $payload,
            status   => $HTTP_OK,
            template => 'admin/categories',
        }
    );
}

async sub user_roles ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $target_user_id = $self->optional_param('user_id');
    if ( !$target_user_id ) {
        return $self->_bad_request( { user_id => 'user_id is required' } );
    }

    return (
        await $self->await_p(
            $self->_render_user_roles( $target_user_id, $user_id )
        )
    );
}

async sub audit ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    # Checked before anything is queried: a value that is not a uuid would
    # make PostgreSQL reject the query on a uuid column, and a page filtered
    # by fewer filters than were asked for would mislead. Invalid input shows
    # the form with what was wrong, and no rows.
    my $review  = $self->gp_admin_audit_review;
    my $checked = $review->filters(
        {
            map { $_ => $self->optional_param($_) }
              qw(actor_id action target_type target_id correlation_id from until)
        }
    );
    my $invalid = %{ $checked->{errors} } ? 1 : 0;
    my $result  = { rows => [] };
    if ( !$invalid ) {
        try {
            $result = (
                await $self->call_p(
                    $review, 'page',
                    $checked->{filters},
                    {
                        after => $self->optional_param('after'),
                        limit => $self->limit_param
                    }
                )
            );
        }
        catch ($error) {
            $self->app->log->error("admin audit failed: $error");
            return $self->system_failure;
        };
    }

    return $self->render_payload(
        {
            payload => $self->gp_admin_view_model->audit_page(
                audit_rows  => $result->{rows},
                errors      => $checked->{errors},
                filters     => $checked->{filters},
                next_cursor => $result->{next_cursor},
            ),
            status   => $invalid ? $HTTP_BAD_REQUEST : $HTTP_OK,
            template => 'admin/audit',
        }
    );
}

async sub users ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $status = $self->optional_param('status');
    my $users;
    try {
        $users = (
            await $self->call_p(
                $self->gp_admin_console_reader,
                'list_users',
                {
                    limit  => $self->limit_param,
                    status => $status,
                }
            )
        );
    }
    catch ($error) {
        $self->app->log->error("admin users failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload => $self->gp_admin_view_model->users_page(
                status => $status,
                users  => $users,
            ),
            status   => $HTTP_OK,
            template => 'admin/users',
        }
    );
}

async sub jobs ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    # The jobs and search's status are read together; the status never
    # fails the page (_search_status answers unavailable instead).
    my $status = $self->optional_param('status');
    my ( $jobs, $search );
    try {
        ( $jobs, $search ) = map { $_->[0] } await $self->await_p(
            Mojo::Promise->all(
                $self->call_p(
                    $self->gp_admin_console_reader,
                    'async_jobs',
                    {
                        limit  => $self->limit_param,
                        status => $status,
                    }
                ),
                $self->_search_status,
            )
        );
    }
    catch ($error) {
        $self->app->log->error("admin jobs failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload => $self->gp_admin_view_model->jobs_page(
                jobs        => $jobs,
                maintenance => {
                    cache_purge_command_id    => $self->_new_command_id,
                    search                    => $search,
                    search_rebuild_command_id => $self->_new_command_id,
                },
                replay_command_ids => $self->_ids_for(
                    $jobs->{dead_letters} || [],
                    'dead_letter_id'
                ),
                status => $status,
            ),
            status   => $HTTP_OK,
            template => 'admin/jobs',
        }
    );
}

async sub status ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $status;
    try {
        $status = (
            await $self->call_p(
                $self->gp_admin_console_reader,
                'operations_status'
            )
        );
    }
    catch ($error) {
        $self->app->log->error("admin status failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload => $self->gp_admin_view_model->status_page(
                admin_status => $status
            ),
            status   => $HTTP_OK,
            template => 'admin/status',
        }
    );
}

# 6.5: the effective configuration, read-only, with its secrets redacted, and
# the test message and antivirus check beside it.
async sub settings ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    # The configuration and the diagnostics are read together; the
    # diagnostics never fail the page (they answer unavailable instead).
    my ( $settings, $diagnostics );
    try {
        ( $settings, $diagnostics ) = map { $_->[0] } await $self->await_p(
            Mojo::Promise->all(
                $self->call_p( $self->gp_admin_settings, 'view' ),
                $self->_diagnostics_overview($user_id),
            )
        );
    }
    catch ($error) {
        $self->app->log->error("admin settings failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload => $self->gp_admin_view_model->settings_page(
                antivirus_command_id => $self->_new_command_id,
                diagnostics          => $diagnostics,
                mail_command_id      => $self->_new_command_id,
                settings             => $settings,
            ),
            status   => $HTTP_OK,
            template => 'admin/settings',
        }
    );
}

# The summary, the recent audit rows and the roles need nothing of one
# another, so they are read together.
async sub _dashboard_payload ($self) {
    my $limit = $self->admin_access->dashboard_limit;
    my ( $console_summary, $audit_rows, $roles ) =
      map { $_->[0] } await $self->await_p(
        Mojo::Promise->all(
            $self->call_p(
                $self->gp_admin_console_reader, 'dashboard_summary',
                { limit => $limit }
            ),
            $self->call_p(
                $self->gp_admin_audit_review,
                'recent', { limit => $limit }
            ),
            $self->call_p(
                $self->gp_role_catalog, 'list_roles', { limit => $limit }
            ),
        )
      );

    return $self->gp_admin_view_model->dashboard(
        audit_rows => $audit_rows,
        csrf_token => $self->csrf_token,
        roles      => $roles,
        summary    => $console_summary,
    );
}

# The roles and the permissions are read together.
async sub _roles_payload ($self) {
    my $limit = $self->limit_param;
    my ( $roles, $permissions ) = map { $_->[0] } await $self->await_p(
        Mojo::Promise->all(
            $self->call_p(
                $self->gp_role_catalog, 'list_roles', { limit => $limit }
            ),
            $self->call_p(
                $self->gp_role_catalog, 'list_permissions',
                { limit => $limit }
            ),
        )
    );

    return $self->gp_admin_view_model->roles_page(
        attach_command_ids    => $self->_ids_for( $roles, 'role_id' ),
        csrf_token            => $self->csrf_token,
        permission_command_id => $self->_new_command_id,
        permissions           => $permissions,
        role_command_id       => $self->_new_command_id,
        roles                 => $roles,
    );
}

async sub announcements ($self) {
    my $user_id = (
        await $self->await_p(
            $self->authorized_user_id( $self->admin_access->view_action )
        )
    );
    if ( !$user_id ) {
        return;
    }

    my $payload;
    try {
        $payload = ( await $self->await_p( $self->_announcements_payload ) );
    }
    catch ($error) {
        $self->app->log->error("admin announcements failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload  => $payload,
            status   => $HTTP_OK,
            template => 'admin/announcements',
        }
    );
}

async sub _announcements_payload ($self) {
    my $announcements = (
        await $self->call_p(
            $self->gp_announcement_store, 'list_announcements',
            { limit => $self->limit_param }
        )
    );
    return $self->gp_admin_view_model->announcements_page(
        announcements      => $announcements,
        create_command_id  => $self->_new_command_id,
        csrf_token         => $self->csrf_token,
        retire_command_ids =>
          $self->_ids_for( $announcements, 'announcement_id' ),
    );
}

async sub _categories_payload ($self) {
    my $categories = (
        await $self->call_p(
            $self->gp_category_store, 'list_categories',
            { limit => $self->limit_param }
        )
    );

    return $self->gp_admin_view_model->categories_page(
        categories         => $categories,
        create_command_id  => $self->_new_command_id,
        csrf_token         => $self->csrf_token,
        update_command_ids => $self->_ids_for( $categories, 'category_id' ),
    );
}

async sub _render_user_roles ( $self, $target_user_id, $user_id ) {
    my ( $bindings, $notes, $second_factor );

    # The member's role bindings, the staff notes about them (ADR 0138, for
    # staff who may read them) and whether two-step sign-in is on (ADR 0142;
    # never the secret) are read together.
    try {
        ( $bindings, $notes, $second_factor ) =
          map { $_->[0] } await $self->await_p(
            Mojo::Promise->all(
                $self->call_p(
                    $self->gp_permission_review,
                    'roles_for_user',
                    $target_user_id,
                    { limit => $self->limit_param }
                ),
                GPForum::Web::MemberNotes->new->for_member_p(
                    $self, $user_id, $target_user_id
                ),
                $self->call_p(
                    $self->gp_second_factor, 'member_summary',
                    $target_user_id
                ),
            )
          );
    }
    catch ($error) {
        $self->app->log->error("admin user roles failed: $error");
        return $self->system_failure;
    };

    return $self->render_payload(
        {
            payload => $self->gp_admin_view_model->user_roles_page(
                bindings           => $bindings,
                bind_command_id    => $self->_new_command_id,
                csrf_token         => $self->csrf_token,
                member_notes       => $notes,
                second_factor      => $second_factor,
                revoke_command_ids =>
                  $self->_ids_for( $bindings, 'binding_id' ),
                user_id => $target_user_id,
            ),
            status   => $HTTP_OK,
            template => 'admin/user_roles',
        }
    );
}

sub _ids_for ( $self, $rows, $key ) {
    my %ids;
    for my $row ( @{$rows} ) {
        my $id = $row->{$key};
        if ($id) {
            $ids{$id} = $self->_new_command_id;
        }
    }

    return \%ids;
}

# Search's lag and last rebuild, for the jobs page. A failure to read them
# leaves the section saying so rather than failing the page.
async sub _search_status ($self) {
    my $search;
    try {
        $search =
          ( await $self->call_p( $self->gp_admin_maintenance, 'search_status' )
          );
    }
    catch ($error) {
        $self->app->log->warn("admin search status failed: $error");
        return { unavailable => 1 };
    };

    return $search;
}

# The recipient, the transports and the last results, for the settings page.
# A failure to read them leaves those sections saying so; the configuration,
# which needs no database, still shows.
async sub _diagnostics_overview ( $self, $user_id ) {
    my $overview;
    try {
        $overview = (
            await $self->call_p(
                $self->gp_admin_diagnostics, 'overview', $user_id
            )
        );
    }
    catch ($error) {
        $self->app->log->warn("admin diagnostics overview failed: $error");
        return { unavailable => 1 };
    };

    return $overview;
}

sub _new_command_id ($self) {
    return $self->gp_id->uuid;
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin - Admin review pages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/admin')->to('Admin#dashboard');

=head1 DESCRIPTION

Renders authorized dashboard, role, category, user, audit, job, status and
settings review pages.
The catalog C<view> action lives on L<GPForum::Web::AdminAccess>. Dashboard
failures stay logged here.

=head1 SUBROUTINES/METHODS

=head2 dashboard

Renders the admin dashboard.

=head2 roles

Renders the role and permission catalog.

=head2 categories

Renders the category catalog.

=head2 announcements

Renders the site announcements console (ADR 0131).

=head2 user_roles

Renders role bindings for a user.

=head2 audit

Renders recent or target-filtered audit rows.

=head2 users

Renders the admin user list.

=head2 jobs

Renders outbox and dead-letter job lists.

=head2 status

Renders operations status.

=head2 settings

Renders the effective configuration, secrets redacted, with the test message
and antivirus check forms and their last results.

=head1 DIAGNOSTICS

Unauthorized, forbidden, and reader failures use the shared admin helpers.

=head1 CONFIGURATION AND ENVIRONMENT

Uses admin reader helpers configured during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Admin::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Write commands live in sibling catalog, category, and binding controllers.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
