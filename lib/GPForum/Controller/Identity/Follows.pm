# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Controller::Identity::Follows;
use Const::Fast;
use Mojo::Base 'GPForum::Controller::Identity::Base', -async_await;
use v5.40;
use GPForum::Service::Community::Follows;
our $VERSION = '0.001';
const my %STATUS => (
    ok        => 200,
    invalid   => 400,
    forbidden => 403,
    limit     => 409,
    conflict  => 409,
);

async sub show ($self) {
    my $actor = $self->current_user_id;
    return $self->settings_unauthorized if !$actor;
    my $service = $self->_service;
    my $page    = (
        await $self->call_p(
            $service,
            'feed',
            $actor,
            $self->gp_forum_viewer,
            { after => $self->param('after'), limit => $self->param('limit') }
        )
    );
    my $payload = {
        feed           => $page,
        followed_users =>
          ( await $self->call_p( $service, 'followed_users', $actor ) ),
        command_id => $self->gp_id->uuid
    };
    $self->res->headers->cache_control('private, no-store');
    return $self->render( json     => $payload ) if $self->wants_json;
    return $self->render( template => 'identity/following', %{$payload} );
}

async sub change ($self) {
    my $refused = (
        await $self->await_p(
            $self->identity_post_guard('identity.member_relation')
        )
    );
    return $refused if $refused;
    my $actor = $self->current_user_id;
    return $self->settings_unauthorized if !$actor;
    my $result = (
        await $self->call_p(
            $self->_service,
            'change',
            {
                actor     => $actor,
                command   => $self->command_id_param,
                username  => $self->param('username'),
                operation => $self->param('operation')
            }
        )
    );
    $self->res->headers->cache_control('private, no-store');
    my $status = $STATUS{ $result->{status} } // $STATUS{invalid};
    return $self->render( json => $result, status => $status )
      if $self->wants_json || $result->{status} ne 'ok';
    return $self->redirect_to('following');
}

sub _service ($self) {
    return GPForum::Service::Community::Follows->new(
        schema => $self->gp_schema );
}
1;
__END__

=head1 NAME

GPForum::Controller::Identity::Follows - Following feed and follow forms.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/following')->to('Identity::Follows#show');

=head1 DESCRIPTION

Authenticated private feed and CSRF-protected commands for following members.

=head1 SUBROUTINES/METHODS

=head2 show

Shows the actor's followed members and a page of current readable contributions.

=head2 change

Adds or removes a followed member; refuses missing command IDs and invalid operations.

=head1 DIAGNOSTICS

Refusals return the relevant HTTP status and database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Community::Follows>.

=head1 INCOMPATIBILITIES

None.

=head1 BUGS AND LIMITATIONS

This does not expose follower lists or implement mutual friend requests.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
