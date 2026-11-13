# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Outbox::DeadLetterRecorder;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Service::Clock;
use GPForum::X::Unavailable;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $SOURCE_TABLE => 'outbox_messages';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
__PACKAGE__->requires(qw(schema));

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('create_dead_letter');

# One call, api.outbox_dead_letter: it skips a message already recorded,
# reuses the row another worker recorded first, and mints the id again when
# the one drawn here was taken.
async sub create_dead_letter_p ( $self, $message, $failure, $context = undef ) {
    my $row = await $self->_functions->row_p( 'outbox_dead_letter',
        { letter => $self->_letter_row( $message, $failure ) }, $context );

    return $row->{letter};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'the dead-letter recorder needs the PostgreSQL function layer' );
}

sub _letter_row ( $self, $message, $failure ) {
    my $failure_time = $self->clock->now_iso8601;

    return {
        dead_letter_id => $self->id_service->uuid,
        source_table   => $SOURCE_TABLE,
        source_id      => $message->get_column('outbox_id'),
        payload        => $message->get_column('payload') || {},
        error_class    => $failure->{error_class},
        error_message  => $failure->{error_message},
        failure_type   => $failure->{failure_type} || 'transient',
        retry_count    => $failure->{attempt_count},

        # The outbox row keeps no first failure time, so the letter's is
        # the time it was written.
        first_failed_at => $failure_time,
        last_failed_at  => $failure_time,
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Outbox::DeadLetterRecorder - Copy an outbox message that will not be retried into dead_letters, once.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $recorder = GPForum::Service::Outbox::DeadLetterRecorder->new(
        schema => $schema,
    );
    my $letter = $recorder->create_dead_letter(
        $outbox_message_row,
        {
            attempt_count => 5,
            error_class   => 'smtp_timeout',
            error_message => $error,
            failure_type  => 'transient',
        }
    );
    # $letter->{skipped} is true when the message was already dead-lettered

=head1 DESCRIPTION

When L<GPForum::Service::Outbox::Dispatcher> gives up on an outbox message,
this class writes a C<dead_letters> row that keeps the message's payload and
the last failure, so an operator can inspect and replay it. There is at most
one dead letter per outbox message: the row is keyed by the source table
(C<outbox_messages>) and the message's C<outbox_id>, and a unique index
backs that rule.

The write is one call, C<api.outbox_dead_letter>. A message already
recorded is skipped. When the insert hits the source unique index (another
worker recorded the same message first), that row is reused; when it hits
the primary key (a generated id that was already taken), the function mints
the id again and inserts once more. The insert runs under the function's
own savepoint, so a conflict does not abort the caller's transaction.

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required: its function layer
(C<functions>) makes the call. C<clock> and C<id_service> default to
L<GPForum::Service::Clock> and L<GPForum::Infrastructure::Id>.

=head2 create_dead_letter_p

Takes the outbox message row (an object with C<get_column>; its
C<outbox_id> and C<payload> are read), a failure hash reference with
C<attempt_count>, C<error_class>, C<error_message> and an optional
C<failure_type> (C<transient> when absent), and an optional query context.

Resolves with the hash of the row it inserted (C<dead_letter_id>,
C<source_table>, C<source_id>, C<payload>, C<error_class>,
C<error_message>, C<failure_type>, C<retry_count>, C<first_failed_at>,
C<last_failed_at>). The outbox row keeps no first failure time, so
C<first_failed_at> is, with C<last_failed_at>, the time the letter is
written.

When a dead letter for the message already exists, nothing is written and
it resolves with C<< { skipped => 1 } >>.

=head2 create_dead_letter

The blocking twin of L</create_dead_letter_p> (ADR 0177): the same body,
settled on the blocking layer, so a caller's open transaction holds it.

=head1 DIAGNOSTICS

Dies with the database error when the insert fails for a reason other than
one of the two unique constraints, or when the reminted insert fails.
Without the function layer it throws L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
