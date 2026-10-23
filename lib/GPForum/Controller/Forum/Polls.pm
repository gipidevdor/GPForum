# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Polls;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;
use GPForum::Service::Forum::Polls;

our $VERSION = '0.001';
const my $HTTP_FORBIDDEN   => 403;
const my $HTTP_CONFLICT    => 409;
const my $HTTP_BAD_REQUEST => 400;

sub show ($self) {
    my $page = $self->_service->overview( $self->_current_user_id,
        $self->param('thread_id') );
    return $self->_not_found('poll not found') if $page->{status} ne 'ok';
    $page->{commands} =
      { map { $_ => $self->gp_id->uuid } qw(create vote close) };
    $self->res->headers->cache_control('no-store');
    return $self->render( json     => $page ) if $self->_wants_json;
    return $self->render( template => 'forum/poll', poll_page => $page );
}

sub change ($self) {
    my $actor = $self->write_user_id('poll.write');
    return if !$actor;
    my @options = split /\r?\n/msx, $self->param('options') // q{};
    my $result  = $self->_service->change(
        {
            actor     => $actor,
            command   => $self->command_id_param,
            thread_id => $self->param('thread_id'),
            operation => $self->param('operation'),
            values    => {
                question => $self->param('question'),
                options  => \@options,
                choice   => $self->param('choice')
            },
        }
    );
    return $self->_not_found('poll not found')
      if $result->{status} eq 'not_found';
    return $self->_refusal($result) if $result->{status} ne 'ok';
    $self->res->headers->cache_control('no-store');
    return $self->render( json => $result ) if $self->_wants_json;
    return $self->redirect_to( 'thread_poll',
        thread_id => $self->param('thread_id') );
}

sub _refusal ( $self, $result ) {
    $self->res->headers->cache_control('no-store');
    my $status = $result->{status};
    my $code =
        $status eq 'forbidden' ? $HTTP_FORBIDDEN
      : $status eq 'invalid'   ? $HTTP_BAD_REQUEST
      :                          $HTTP_CONFLICT;
    return $self->render( json => $result, status => $code )
      if $self->_wants_json;
    return $self->_forbidden( $self->t('forum.error_forbidden') )
      if $code == $HTTP_FORBIDDEN;
    return $self->_bad_request( { poll => $self->t('forum.error_invalid') } )
      if $code == $HTTP_BAD_REQUEST;
    return $self->_conflict(
        $self->t(
            $status eq 'closed' ? 'forum.poll_closed' : 'forum.error_conflict'
        )
    );
}

sub _service ($self) {
    return GPForum::Service::Forum::Polls->new( schema => $self->gp_schema );
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Polls - Thread poll pages and forms.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/t/:thread_id/tools/poll')->to('Forum::Polls#show');

=head1 DESCRIPTION

Accessible server-rendered poll workflow with JSON responses on request.

=head1 SUBROUTINES/METHODS

=head2 show

Shows a poll or its author-only creation form, with no-store caching.

=head2 change

Runs a CSRF-protected, throttled poll command.

=head1 DIAGNOSTICS

Visibility failures are not found; command conflicts return 409.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Forum::Polls>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
