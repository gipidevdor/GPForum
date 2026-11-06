# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::ThreadTransfers;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Moderation::Base', -signatures;
use v5.40;
use GPForum::Service::Moderation::ThreadTransfers;
use GPForum::Web::Guard;
use List::Util qw(any);

our $VERSION = '0.001';
const my $HTTP_OK          => 200;
const my $MAX_SELECTION    => 1000;
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
    return $self->_page($actor);
}

sub _page ( $self, $actor, $status = $HTTP_OK, $error = q{} ) {
    $self->res->headers->cache_control('no-store');
    my $page = $self->_service->history($actor);
    return GPForum::Web::Guard->new->forbidden($self)
      if $page->{status} ne 'ok';
    return $self->render( json => $page ) if $self->wants_json;
    my $picker = $self->_service->picker(
        {
            actor          => $actor,
            source         => $self->param('source'),
            query          => $self->param('q'),
            after_position => $self->param('page_after')
              // $self->param('after_position')
        }
    );
    return $self->_refusal($picker) if $picker->{status} ne 'ok';
    my @numbers = split /[\s,]+/msx,
      join q{,}, @{ $self->every_param('post_numbers') };
    return $self->_refusal( { status => 'invalid' } )
      if @numbers > $MAX_SELECTION
      || any { !/\A[1-9][[:digit:]]{0,8}\z/msx } @numbers;
    my %selected = map  { $_             => 1 } @numbers;
    my %visible  = map  { $_->{position} => 1 } @{ $picker->{posts} // [] };
    my @offpage  = sort { $a <=> $b } grep { !$visible{$_} } keys %selected;
    my %values =
      map { $_ => $self->param($_) // q{} } qw(target title reason q);
    $values{operation}      = $self->param('operation') // 'move';
    $values{after_position} = $self->param('page_after')
      // $self->param('after_position') // 0;

    for my $row ( @{ $page->{transfers} // [] } ) {
        $row->{undo_command_id} = $self->gp_id->uuid;
    }
    $self->res->headers->cache_control('no-store');
    return $self->render(
        template             => 'moderation/transfers',
        picker               => $picker,
        next_posts           => $picker->{next_after},
        transfer_values      => \%values,
        selected_posts       => \%selected,
        offpage_posts        => \@offpage,
        transfer_error       => $error,
        transfer_error_field => _error_field( \%values, \%selected ),
        status               => $status,
        transfer_command_id  => $self->gp_id->uuid,
        transfers            => $page->{transfers} // []
    );
}

sub _error_field ( $values, $selected ) {
    return 'reason' if !$values->{reason};
    return 'title'  if $values->{operation} eq 'split' && !$values->{title};
    return 'target' if $values->{operation} ne 'split' && !$values->{target};
    return 'posts'  if !%{$selected} && $values->{operation} ne 'merge';
    return 'operation';
}

sub change ($self) {
    my $actor = $self->authorized_write_user_id( 'thread', 'moderate' );
    return if !$actor;
    return $self->_page($actor)
      if !$self->wants_json && defined $self->param('page_after');
    my $result = $self->_service->change(
        {
            actor        => $actor,
            command      => $self->command_id_param,
            post_numbers =>
              join( q{,}, @{ $self->every_param('post_numbers') } ),
            map { $_ => $self->param($_) }
              qw(source target operation title reason)
        }
    );
    if (  !$self->wants_json
        && $result->{status} ne 'ok'
        && $result->{status} ne 'forbidden'
        && $result->{status} ne 'not_found' )
    {
        my $invalid = $result->{status} eq 'invalid';
        return $self->_page(
            $actor,
            $invalid ? $HTTP_BAD_REQUEST : $HTTP_CONFLICT,
            $self->t(
                $invalid
                ? 'moderation.transfer_invalid'
                : 'moderation.transfer_conflict'
            )
        );
    }
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
    return $self->render( json => $result ) if $self->wants_json;
    return $self->redirect_to( 'thread', thread_id => $result->{target_id} );
}

sub _refusal ( $self, $result ) {
    $self->res->headers->cache_control('no-store');
    my $code =
      exists $FAILURE{ $result->{status} }
      ? $FAILURE{ $result->{status} }
      : $HTTP_CONFLICT;
    return $self->render( json => $result, status => $code )
      if $self->wants_json;
    my $guard = GPForum::Web::Guard->new;
    return $guard->forbidden($self) if $code == $HTTP_FORBIDDEN;
    return $guard->not_found( $self, $self->t('forum.error_not_found') )
      if $code == $HTTP_NOT_FOUND;
    return $guard->bad_request( $self,
        { errors => { transfer => $self->t('moderation.transfer_invalid') } } )
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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
