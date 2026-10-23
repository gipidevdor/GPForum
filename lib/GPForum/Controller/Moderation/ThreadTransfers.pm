# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::ThreadTransfers;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Moderation::Base', -signatures;
use v5.40;
use GPForum::Service::Moderation::ThreadTransfers;
use GPForum::Web::Guard;

our $VERSION = '0.001';
const my $HTTP_CONFLICT    => 409;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_FORBIDDEN   => 403;
const my $HTTP_NOT_FOUND   => 404;
const my %FAILURE => (
    invalid   => $HTTP_BAD_REQUEST,
    forbidden => $HTTP_FORBIDDEN,
    not_found => $HTTP_NOT_FOUND,
);

sub show ($self) {
    my $actor = $self->authorized_user_id( 'thread', 'moderate' );
    return if !$actor;
    $self->res->headers->cache_control('no-store');
    my $page = $self->_service->history($actor);
    return GPForum::Web::Guard->new->forbidden($self)
      if $page->{status} ne 'ok';
    return $self->render( json => $page ) if $self->_wants_json;
    for my $row ( @{ $page->{transfers} // [] } ) {
        $row->{undo_command_id} = $self->gp_id->uuid;
    }
    $self->res->headers->cache_control('no-store');
    return $self->render(
        template            => 'moderation/transfers',
        transfer_command_id => $self->gp_id->uuid,
        transfers           => $page->{transfers} // []
    );
}

sub change ($self) {
    my $actor = $self->authorized_write_user_id( 'thread', 'moderate' );
    return if !$actor;
    my $result = $self->_service->change(
        {
            actor   => $actor,
            command => $self->command_id_param,
            map { $_ => $self->param($_) }
              qw(source target operation post_numbers title reason)
        }
    );
    return $self->_answer($result);
}

sub undo ($self) {
    my $actor = $self->authorized_write_user_id( 'thread', 'moderate' );
    return if !$actor;
    return $self->_answer(
        $self->_service->undo(
            {
                actor       => $actor,
                command     => $self->command_id_param,
                transfer_id => $self->param('transfer_id')
            }
        )
    );
}

sub _answer ( $self, $result ) {
    return $self->_refusal($result) if $result->{status} ne 'ok';
    $self->gp_local_cache->clear;
    return $self->render( json => $result ) if $self->_wants_json;
    return $self->redirect_to( 'thread', thread_id => $result->{target_id} );
}

sub _refusal ( $self, $result ) {
    $self->res->headers->cache_control('no-store');
    my $code =
      exists $FAILURE{ $result->{status} }
      ? $FAILURE{ $result->{status} }
      : $HTTP_CONFLICT;
    return $self->render( json => $result, status => $code )
      if $self->_wants_json;
    my $guard = GPForum::Web::Guard->new;
    return $guard->forbidden($self) if $code == $HTTP_FORBIDDEN;
    return $guard->not_found( $self, $self->t('forum.error_not_found') )
      if $code == $HTTP_NOT_FOUND;
    return $guard->bad_request( $self,
        { errors => { transfer => $self->t('forum.error_invalid') } } )
      if $code == $HTTP_BAD_REQUEST;
    return $guard->conflict( $self,
        { error => $self->t('moderation.transfer_conflict') } );
}

sub _service ($self) {
    return GPForum::Service::Moderation::ThreadTransfers->new(
        schema => $self->gp_schema );
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::ThreadTransfers - Thread organization console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/moderation/transfers')->to('Moderation::ThreadTransfers#show');

=head1 DESCRIPTION

Uses existing moderation permissions, CSRF and throttling. Functions own data changes.

=head1 SUBROUTINES/METHODS

=head2 show

Shows forms and bounded transfer history.

=head2 change

Moves posts, splits or merges discussions atomically.

=head2 undo

Reverses a recorded transfer when safe.

=head1 DIAGNOSTICS

Unsafe reversals and transfer conflicts return 409.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::ThreadTransfers>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Requires global thread moderation permission.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
