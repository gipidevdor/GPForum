# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity::Profile;

use Const::Fast;
use GPForum::Web::ErrorPayload;
use GPForum::Service::Community::Follows;
use Mojo::Base 'GPForum::Controller::Identity::Base', -async_await;
use v5.40;
use Mojo::Promise;

our $VERSION = '0.001';

const my $HTTP_NOT_FOUND => 404;
const my $HTTP_OK        => 200;

async sub profile ($self) {
    my $result = (
        await $self->call_p(
            $self->gp_profile_reader,
            'public_profile',
            $self->param('username'),
            {
                limit => $self->identity_access->profile_thread_limit(
                    $self->param('limit')
                ),
                after         => $self->param('after'),
                replies_after => $self->param('replies_after'),
            }
        )
    );
    if ( !$result->{ok} ) {
        if ( $self->wants_json ) {
            return $self->render(
                json => GPForum::Web::ErrorPayload->identity_profile_not_found,
                status => $HTTP_NOT_FOUND,
            );
        }
        return $self->render(
            template => 'identity/profile_not_found',
            status   => $HTTP_NOT_FOUND,
        );
    }

    # A signed-in reader gets the id of the form that reports the member.
    my $page   = $result->{profile} || {};
    my $reader = $self->session('user_id');
    $page->{report_command_id} = $reader ? $self->gp_id->uuid : q{};
    my $profile = $self->gp_identity_view_model->profile($page);

    # The JSON says nothing of the reader, so it needs none of the reads
    # below.
    if ( $self->wants_json ) {
        return $self->render(
            json   => { profile => $profile },
            status => $HTTP_OK,
        );
    }

    # ADR 0130: the reader's own relation to the member, for the actions,
    # read beside the follow form and the avatar moderation form: none of
    # the three waits on another.
    my $user = $page->{user} || {};
    my ( $relation, $follow_form, $avatar_moderation ) =
      map { $_->[0] } await $self->await_p(
        Mojo::Promise->all(
            $reader
            ? $self->call_p(
                $self->gp_relation_store, 'relation_between',
                $reader,                  $user->{user_id}
              )
            : Mojo::Promise->resolve(undef),
            $self->_follow_form( $reader, $user ),
            $self->_avatar_moderation( $reader, $user ),
        )
      );

    return $self->render(
        template          => 'identity/profile',
        profile           => $profile,
        relation          => $relation // q{},
        follow_form       => $follow_form,
        avatar_moderation => $avatar_moderation,
        status            => $HTTP_OK,
    );
}

async sub _follow_form ( $self, $reader, $user ) {
    return undef if !$reader || $reader eq ( $user->{user_id} // q{} );
    my $following;
    try {
        my $follows = GPForum::Service::Community::Follows->new(
            schema => $self->gp_schema );
        $following = await $self->call_p( $follows, 'following', $reader,
            $user->{user_id} );
    }
    catch ($error) {
        $self->app->log->warn('follow controls unavailable');
        return undef;
    };
    return undef if !defined $following;
    return { following => $following, command_id => $self->gp_id->uuid };
}

# ADR 0144: staff holding avatar.moderate globally see the form that removes
# the picture the member shows; nobody else, and never in the JSON.
async sub _avatar_moderation ( $self, $reader, $user ) {
    return 0 if !$reader || !$user->{avatar_id};

    return (
        await $self->call_p(
            $self->gp_permission_gate,
            'allowed',
            { user_id => $reader },
            {
                action        => 'moderate',
                resource_type => 'avatar',
                resource_id   => undef,
                space_id      => undef,
            }
        )
    ) ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity::Profile - Public member profile.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/u/:username')->to('Identity::Profile#profile');

=head1 DESCRIPTION

Renders a public-safe member profile page or JSON payload.

=head1 SUBROUTINES/METHODS

=head2 profile

Loads a visible public profile for the requested username.

=head1 DIAGNOSTICS

Missing profiles render C<404>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the profile reader helper registered during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Identity::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The profile page does not expose private or moderated content.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
