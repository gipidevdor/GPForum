# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::RequestPromise;
use Mojo::Base 'Mojo::Promise', -signatures;
use v5.40;

our $VERSION = '0.001';
has controller => undef, weak => 1;    # optional: commands have no HTTP context

sub clone ($self) {
    return $self->SUPER::clone->controller( $self->controller );
}

sub AWAIT_ON_READY ( $self, $callback ) {
    my $controller = $self->controller;
    return $self->SUPER::AWAIT_ON_READY(
        sub (@values) {
            my $resume = sub { return $callback->(@values); };
            return $controller
              ? $controller->within_request($resume)
              : $resume->();
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::RequestPromise - Resume native async/await callbacks in their HTTP request context.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    await $controller->await_p($operation_p);

=head1 DESCRIPTION

Extends Mojo::Promise's Future::AsyncAwait protocol to restore query counters
and logging only while a suspended callback resumes. No context remains active
while that callback waits for its next asynchronous operation.

=head1 SUBROUTINES/METHODS

=head2 clone

Preserves the weak controller reference across promise chains.

=head2 AWAIT_ON_READY

Resumes an async/await continuation in its originating request.

=head1 DIAGNOSTICS

Uses the normal Mojo::Promise failure contract.

=head1 CONFIGURATION AND ENVIRONMENT

Requires no operator configuration.

=head1 DEPENDENCIES

Mojolicious and Future::AsyncAwait.

=head1 INCOMPATIBILITIES

Does not run a nested event loop.

=head1 BUGS AND LIMITATIONS

Callers retain request controllers while their operations are pending.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
