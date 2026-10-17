# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::Avatars;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Moderation::Base', -signatures;
use v5.40;

use GPForum::Web::Access;
use GPForum::Web::Guard;
use GPForum::Web::SecurityEvent;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FORBIDDEN => 403;
const my $RESOURCE       => 'avatar';
const my $ACTION         => 'moderate';
const my $HOME           => 'admin_user_roles';

# Staff take away the picture a member shows: the one they saw, named by
# the form, so a picture uploaded since is not removed unseen.
sub remove ($self) {
    my $user_id = $self->_moderator or return;

    my $answer = $self->gp_avatars->moderate(
        {
            actor_user_id   => $user_id,
            subject_user_id => $self->stash('user_id'),
            attachment_id   => $self->param('avatar_id'),
            reason          => $self->param('reason'),
        }
    );
    my $status = $answer->{status} // 'invalid';
    return $self->_not_found('profile picture not found')
      if $status eq 'not_found';
    return GPForum::Web::Guard->new->bad_request(
        $self,
        $self->moderation_access->invalid_request(
            {
                    reason => 'a reason is at most '
                  . $self->gp_avatar_store->maximum_reason
                  . ' characters'
            }
        )
    ) if $status ne 'ok';

    return $self->render(
        json   => { ok => 1, status => 'removed' },
        status => $HTTP_OK,
    ) if $self->_wants_json;

    $self->set_success_flash('profile.avatar_moderated');
    my $return_to =
      GPForum::Web::Access->new->safe_return_to( $self->param('return_to') );
    return $self->redirect_to( $return_to
          // $self->url_for( $HOME, user_id => $self->stash('user_id') ) );
}

# The staff member, or undef once the request is answered: a bad CSRF
# token, nobody signed in, no global avatar.moderate binding, over the
# moderation write limit, or suspended.
sub _moderator ($self) {
    my $user_id = $self->authorized_write_user_id( $RESOURCE, $ACTION );
    return if !$user_id;

    my $decision = $self->gp_suspension_store->can_participate($user_id);
    if ( !$decision->{ok} ) {
        GPForum::Web::SecurityEvent->new->record_event(
            $self,
            'suspended_user_block',
            {
                action => "$RESOURCE.$ACTION",
                status => $HTTP_FORBIDDEN,
            }
        );
        GPForum::Web::Guard->new->forbidden( $self,
            { error => 'user is suspended' } );
        return;
    }

    return $user_id;
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::Avatars - Staff remove a member's profile picture.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/moderation/members/:user_id/avatar/remove')
      ->to('Moderation::Avatars#remove');

=head1 DESCRIPTION

ADR 0144. A staff member holding C<avatar.moderate> globally removes the
picture a member shows, from the form on the member's profile: CSRF, the
moderation write limit, and an account that is not suspended. The removal
is audited (C<avatar.removed>, with the member and the reason given) and
the picture's files are deleted.

=head1 SUBROUTINES/METHODS

=head2 remove

Takes C<avatar_id>, the picture the form showed, an optional C<reason> and
an optional C<return_to>. Redirects there (or to the member's admin page)
with a message; C<404> when that picture is not the one shown; C<400> for a
reason too long. JSON answers C<< { ok => 1, status => 'removed' } >>.

=head1 DIAGNOSTICS

C<403> without the permission or for a suspended staff member.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Controller::Moderation::Base>,
L<GPForum::Service::Community::Avatars>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
