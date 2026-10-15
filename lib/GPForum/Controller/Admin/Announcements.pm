# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::Announcements;

use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

sub create_announcement ($self) {
    my $user_id = $self->authorized_write_user_id;
    if ( !$user_id ) {
        return;
    }

    return $self->announcement_write_response(
        $self->gp_admin_workflow->create_announcement(
            {
                actor_user_id => $user_id,
                command_id    => $self->command_id_param,
                message       => $self->param('message'),
                tone          => $self->param('tone'),
            }
        ),
        $self->admin_access->announcement_published_status,
    );
}

sub retire_announcement ($self) {
    my $user_id = $self->authorized_write_user_id;
    if ( !$user_id ) {
        return;
    }

    return $self->announcement_write_response(
        $self->gp_admin_workflow->retire_announcement(
            {
                actor_user_id   => $user_id,
                announcement_id => $self->param('announcement_id'),
                command_id      => $self->command_id_param,
            }
        ),
        $self->admin_access->announcement_retired_status,
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::Announcements - Site announcement write commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/admin/announcements')
      ->to('Admin::Announcements#create_announcement');

=head1 DESCRIPTION

Publishes and retires site announcements (ADR 0131) through the admin
workflow. Success status names live on L<GPForum::Web::AdminAccess>; CSRF
stays on L<GPForum::Controller::Admin::Base/authorized_write_user_id>.

=head1 SUBROUTINES/METHODS

=head2 create_announcement

Publishes an announcement from C<message> and C<tone>.

=head2 retire_announcement

Retires the announcement named in the path.

=head1 DIAGNOSTICS

CSRF, auth, and validation failures use the shared admin helpers.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the admin workflow helper configured during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Admin::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The announcement list stays on the parent admin controller.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
