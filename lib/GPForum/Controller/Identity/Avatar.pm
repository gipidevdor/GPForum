# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity::Avatar;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_NOT_MODIFIED => 304;
const my $HTTP_BAD_REQUEST  => 400;
const my $HTTP_NOT_FOUND    => 404;
const my $HTTP_TOO_LARGE    => 413;
const my $HTTP_UNSUPPORTED  => 415;
const my $HTTP_UNPROCESSED  => 422;
const my $HTTP_UNAVAILABLE  => 503;
const my $NO_STORE          => 'no-store';
const my $UPLOAD            => 'avatar.upload';
const my $REMOVE            => 'avatar.remove';

# How long a picture's address may be kept: an hour, then revalidated by its
# ETag. A picture removed or erased leaves shared caches within the hour.
const my $CURRENT_PICTURE => 'public, max-age=3600';

# An address that names a picture since replaced, from a page cached
# before the change, answers with the one shown now, briefly.
const my $REPLACED_PICTURE => 'public, max-age=60';

# What an upload's answer is, as a status and a message, for the page and
# for JSON.
const my %ANSWER => (
    shown           => [ $HTTP_OK,          'profile.avatar_shown' ],
    checking        => [ $HTTP_OK,          'profile.avatar_checking' ],
    unavailable     => [ $HTTP_UNAVAILABLE, 'profile.avatar_unavailable' ],
    missing         => [ $HTTP_BAD_REQUEST, 'profile.avatar_missing' ],
    too_large       => [ $HTTP_TOO_LARGE,   'profile.avatar_too_large' ],
    not_image       => [ $HTTP_UNSUPPORTED, 'profile.avatar_not_image' ],
    unreadable      => [ $HTTP_UNPROCESSED, 'profile.avatar_unreadable' ],
    too_many_pixels => [ $HTTP_UNPROCESSED, 'profile.avatar_too_many_pixels' ],
    invalid         => [ $HTTP_BAD_REQUEST, 'profile.avatar_invalid' ],
    refused         => [ $HTTP_UNPROCESSED, 'profile.avatar_refused' ],
    failed          => [ $HTTP_UNAVAILABLE, 'profile.avatar_failed' ],
    stale           => [ $HTTP_OK,          'profile.avatar_checking' ],
);

# The member's picture, the form that replaces it and the one that removes
# it.
sub show ($self) {
    my $user_id = $self->_member or return;

    return $self->_page( $HTTP_OK, $user_id );
}

# A new picture, from the form.
sub upload ($self) {
    my $user_id = $self->write_user_id($UPLOAD) or return;
    $self->res->headers->cache_control($NO_STORE);

    my $answer = $self->gp_avatars->upload(
        { user_id => $user_id, upload => $self->req->upload('avatar') } );
    my $status = $answer->{status} // 'failed';
    my ( $code, $key ) = @{ $ANSWER{$status} // $ANSWER{failed} };
    if ( $self->_wants_json ) {
        return $self->render(
            json   => { ok => $code == $HTTP_OK ? 1 : 0, status => $status },
            status => $code,
        );
    }
    return $self->_page( $code, $user_id, $key ) if $code != $HTTP_OK;

    $self->set_success_flash($key);
    return $self->redirect_to('settings_avatar');
}

# The member takes their picture away.
sub remove ($self) {
    my $user_id = $self->write_user_id($REMOVE) or return;
    $self->res->headers->cache_control($NO_STORE);

    my $status = $self->gp_avatars->remove_own($user_id)->{status};
    if ( $self->_wants_json ) {
        return $self->render(
            json => {
                ok     => $status eq 'ok' ? 1         : 0,
                status => $status eq 'ok' ? 'removed' : $status,
            },
            status => $status eq 'ok' ? $HTTP_OK : $HTTP_NOT_FOUND,
        );
    }
    return $self->_not_found('no profile picture') if $status ne 'ok';

    $self->set_success_flash('profile.avatar_removed');
    return $self->redirect_to('settings_avatar');
}

# A picture's square, for anyone who may read the forum: the picture the
# member shows now, at 64, 128 or 256 pixels.
sub image ($self) {
    my $side    = $self->stash('size');
    my $user_id = $self->stash('user_id');
    my $named   = $self->stash('avatar_id');
    return $self->_not_found('no such picture')
      if !_is_uuid($user_id) || !_is_uuid($named);

    my $picture = $self->gp_avatars->picture( $user_id, $named, $side );
    return $self->_not_found('no such picture') if !$picture;

    my $headers = $self->res->headers;
    my $etag    = qq{"$picture->{attachment_id}-$side"};
    $headers->cache_control(
        $picture->{current} ? $CURRENT_PICTURE : $REPLACED_PICTURE );
    $headers->etag($etag);
    $headers->header( 'X-Content-Type-Options'  => 'nosniff' );
    $headers->header( 'Content-Security-Policy' => q{default-src 'none'} );
    return $self->rendered($HTTP_NOT_MODIFIED)
      if ( $self->req->headers->if_none_match // q{} ) eq $etag;

    $headers->content_type( $picture->{media_type} );

    return $self->render( data => $picture->{content}, status => $HTTP_OK );
}

sub _member ($self) {
    my $user_id = $self->_current_user_id;
    $self->res->headers->cache_control($NO_STORE);
    if ( !$user_id ) {
        $self->_unauthorized;
        return undef;
    }

    return $user_id;
}

sub _page ( $self, $status, $user_id, $error = undef ) {
    my $avatars = $self->gp_avatars;
    my $picture = $avatars->status($user_id);
    $self->res->headers->cache_control($NO_STORE);

    return $self->render_payload(
        {
            controller => $self,
            payload    => {
                %{$picture},
                user_id       => $user_id,
                maximum_bytes => $avatars->maximum_bytes,
                maximum_side  => $avatars->maximum_side,
                error         => $error ? $self->t($error) : undef,
            },
            status   => $status,
            template => 'identity/avatar',
        }
    );
}

sub _is_uuid ($value) {
    return GPForum::Infrastructure::Id->is_uuid_spelling( $value // q{} );
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity::Avatar - A member's profile picture: the settings page, the upload, the removal and the picture itself.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/settings/avatar')->to('Identity::Avatar#show');
    $routes->post('/settings/avatar')->to('Identity::Avatar#upload');
    $routes->post('/settings/avatar/remove')->to('Identity::Avatar#remove');
    $routes->get('/avatars/:user_id/:avatar_id/:size')
      ->to('Identity::Avatar#image');

=head1 DESCRIPTION

ADR 0144. The settings page shows the picture a member shows, the state of
one waiting (being checked, refused by the scan, unreadable), the upload
form and the removal form, all working without JavaScript. Writes need a
signed-in member, a valid CSRF token and the write rate limit (ten a
minute); an upload also needs an account that is not suspended.

The picture's address names the member and the attachment shown, so a new
picture gets a new address. It answers with the PNG square, an ETag and an
hour's public caching, C<nosniff> and a CSP that allows nothing.

=head1 SUBROUTINES/METHODS

=head2 show

The settings page; C<401> without a member signed in.

=head2 upload

Takes the C<avatar> file. A picture shown or being checked redirects to the
settings page with its message; a refusal shows the page again with why
(C<400>, C<413>, C<415>, C<422> or C<503>). JSON answers
C<< { ok, status } >>.

=head2 remove

Removes the member's picture and the one waiting: a redirect, or C<404>
when there is none.

=head2 image

The square at C<size> (64, 128 or 256): C<200> with the PNG, C<304> for a
matching C<If-None-Match>, or C<404>.

=head1 DIAGNOSTICS

Missing members, pictures and sizes answer C<404>.

=head1 CONFIGURATION AND ENVIRONMENT

The image tool of C<GPFORUM_IMAGE_TOOL>, through C<gp_avatars>.

=head1 DEPENDENCIES

L<GPForum::Controller::Forum::Base>,
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
