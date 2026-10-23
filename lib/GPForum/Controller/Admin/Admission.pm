# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::Admission;

use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;
use GPForum::Service::Identity::Admission;
use GPForum::Web::Guard;

our $VERSION = '0.001';

sub show ($self) {
    my $actor = $self->authorized_user_id( $self->admin_access->view_action );
    return if !$actor;
    my $state = $self->_page($actor);
    return GPForum::Web::Guard->new->forbidden($self)
      if $state->{status} ne 'ok';
    $self->res->headers->cache_control('no-store');
    return $self->render( json     => $state ) if $self->_wants_json;
    return $self->render( template => 'admin/admission', admission => $state );
}

sub change ($self) {
    my $actor = $self->authorized_write_user_id;
    return if !$actor;
    my $result = $self->_service->change(
        {
            actor   => $actor,
            command => $self->command_id_param,
            map { $_ => $self->param($_) }
              qw(operation mode approval_required email invitation_id user_id),
        }
    );
    $self->res->headers->cache_control('no-store');
    return GPForum::Web::Guard->new->forbidden($self)
      if $result->{status} eq 'forbidden';
    return GPForum::Web::Guard->new->conflict( $self,
        { error => 'idempotency conflict' } )
      if $result->{status} eq 'conflict';
    return $self->_bad_request( { admission => $result->{status} } )
      if $result->{status} ne 'ok';
    return $self->render( json => $result ) if $self->_wants_json;
    my $state = $self->_page($actor);
    return $self->render(
        template   => 'admin/admission',
        admission  => $state,
        invitation => $result->{invitation}
    );
}

sub _page ( $self, $actor ) {
    my $page = $self->_service->overview($actor);
    $page->{commands} = { map { $_ => $self->gp_id->uuid } qw(policy invite) };
    for my $row ( @{ $page->{reviews} // [] }, @{ $page->{invitations} // [] } )
    {
        $row->{command_id} = $self->gp_id->uuid;
    }
    return $page;
}

sub _service ($self) {
    return GPForum::Service::Identity::Admission->new(
        schema => $self->gp_schema );
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::Admission - Registration policy, invitations and waiting accounts.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/admin/registration')->to('Admin::Admission#show');

=head1 DESCRIPTION

Staff console using the existing admin guards, CSRF and rate limits.

=head1 SUBROUTINES/METHODS

=head2 show

Displays the bounded admission state without caching it.

=head2 change

Runs an admission command. An invitation secret is displayed once.

=head1 DIAGNOSTICS

Uses shared authorization and validation responses.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Identity::Admission>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
