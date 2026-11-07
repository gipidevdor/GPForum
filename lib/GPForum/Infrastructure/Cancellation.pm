# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Infrastructure::Cancellation;
use Mojo::Base -base, -signatures;
use v5.40;
has cancelled => 0;
has deadline  => undef;                # optional: monotonic admission deadline
has callbacks => sub { return {}; };
has sequence  => 0;
our $VERSION = '0.001';

sub subscribe ( $self, $callback ) {
    if ( $self->cancelled ) { $callback->(); return undef; }
    my $id = $self->sequence( $self->sequence + 1 )->sequence;
    $self->callbacks->{$id} = $callback;
    return $id;
}

sub unsubscribe ( $self, $id ) {
    if ( defined $id ) { delete $self->callbacks->{$id}; }
    return;
}

sub cancel ($self) {
    return if $self->cancelled;
    $self->cancelled(1);
    my @callbacks = values %{ $self->callbacks };
    $self->callbacks( {} );
    for my $callback (@callbacks) { $callback->(); }
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Cancellation - Request lifetime for queued work.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $token = GPForum::Infrastructure::Cancellation->new;
    my $subscription = $token->subscribe(sub { remove_waiting_work() });
    $token->unsubscribe($subscription);
    $token->cancel;

=head1 DESCRIPTION

An HTTP request owns one token and an optional monotonic admission deadline.
Queues subscribe while work waits and unsubscribe before starting it. Closing
the request removes pending work promptly; admitted transactions keep ownership
until their result or rollback is known. No write is replayed or interrupted.

=head1 SUBROUTINES/METHODS

C<subscribe> returns a registration id; C<unsubscribe> removes it. C<cancel>
marks the token closed and notifies current subscribers once. A subscription
made after cancellation is notified immediately.

=head1 DIAGNOSTICS

Subscriber exceptions propagate to the caller. Internal subscribers must not
throw and must not interrupt work that has already been admitted.

=head1 CONFIGURATION AND ENVIRONMENT

C<deadline>, when supplied, uses CLOCK_MONOTONIC seconds. No environment
variables are read.

=head1 DEPENDENCIES

Mojolicious.

=head1 INCOMPATIBILITIES

Tokens belong to one process and are not an interprocess cancellation channel.

=head1 BUGS AND LIMITATIONS

Cancellation limits queued work. It does not impose a transaction timeout or
cancel an already running database command.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
