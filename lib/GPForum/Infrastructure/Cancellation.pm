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
    delete $self->callbacks->{$id} if defined $id;
    return;
}

sub cancel ($self) {
    return if $self->cancelled;
    $self->cancelled(1);
    my @callbacks = values %{ $self->callbacks };
    $self->callbacks( {} );
    $_->() for @callbacks;
    return;
}

1;
