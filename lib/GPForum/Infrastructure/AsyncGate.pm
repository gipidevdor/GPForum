# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::AsyncGate;

use Mojo::Base -base, -signatures;
use v5.40;
use English qw(-no_match_vars);
use Mojo::Promise;
use Mojo::IOLoop;
use GPForum::X::Unavailable;

our $VERSION = '0.001';
has concurrency   => 2;
has max_pending   => 256;
has queue_timeout => 15;
has active        => 0;
has pending       => sub { return []; };
has owner         => sub { return $PROCESS_ID; };

sub run_p ( $self, $work ) {
    if ( $self->owner != $PROCESS_ID ) {
        $self->owner($PROCESS_ID);
        $self->active(0);
        $self->pending( [] );
    }
    if ( $self->active >= $self->concurrency
        && @{ $self->pending } >= $self->max_pending )
    {
        return Mojo::Promise->reject(
            GPForum::X::Unavailable->new(
                message => 'asynchronous capacity exhausted'
            )
        );
    }
    my $promise = Mojo::Promise->new;
    my $job     = { work => $work, promise => $promise };
    push @{ $self->pending }, $job;
    if ( $self->active >= $self->concurrency ) {
        $job->{timer} = Mojo::IOLoop->timer(
            $self->queue_timeout => sub {
                @{ $self->pending } = grep { $_ != $job } @{ $self->pending };
                $promise->reject(
                    GPForum::X::Unavailable->new(
                        message => 'asynchronous queue deadline exceeded'
                    )
                );
                return;
            }
        );
    }
    $self->_pump;
    return $promise;
}

sub _pump ($self) {
    while ( $self->active < $self->concurrency && @{ $self->pending } ) {
        my $job = shift @{ $self->pending };
        if ( defined $job->{timer} ) { Mojo::IOLoop->remove( $job->{timer} ); }
        $self->active( $self->active + 1 );
        $self->_start($job);
    }
    return;
}

sub _start ( $self, $job ) {
    my ( $running, $error );
    try { $running = Mojo::Promise->resolve( $job->{work}->() ); }
    catch ($caught) { $error = $caught; };
    if ( defined $error ) {

        # Keep synchronous failures out of the admission pump's call stack.
        # A queue of failing jobs must not recursively drain the whole queue.
        Mojo::IOLoop->next_tick(
            sub { $self->_complete( $job, 'reject', $error ); return; } );
        return;
    }
    $running->then(
        sub (@values) { $self->_complete( $job, 'resolve', @values ); return; },
        sub (@errors) { $self->_complete( $job, 'reject',  @errors ); return; }
    );
    return;
}

sub _complete ( $self, $job, $status, @values ) {

    # Consumers may immediately submit another query. Release capacity before
    # their continuation runs, without a deferred finally chain retaining it.
    $self->active( $self->active - 1 );
    $self->_pump;
    $job->{promise}->$status(@values);
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::AsyncGate - Bound promise concurrency and queue residency.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $gate = GPForum::Infrastructure::AsyncGate->new;
    $gate->run_p(sub { return request_p(); });

=head1 DESCRIPTION

Runs a promise-producing callback in FIFO order. Saturation and queue expiry reject with Unavailable. The gate resets its inherited queue after a fork.

=head1 SUBROUTINES/METHODS

=head2 run_p

Bound promise concurrency and queue residency.

=head1 DIAGNOSTICS

Failures reject promises. HTTP callers finish or reject their response through the controller's request context.

=head1 CONFIGURATION AND ENVIRONMENT

Runtime limits have safe built-in defaults. No environment setting is required.

=head1 DEPENDENCIES

Mojolicious and the modules named in the source.

=head1 INCOMPATIBILITIES

HTTP callers consume promises without starting a nested event loop.

=head1 BUGS AND LIMITATIONS

Admission is bounded per web worker, not across multiple hosts. CLI workflows keep their synchronous interfaces.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
