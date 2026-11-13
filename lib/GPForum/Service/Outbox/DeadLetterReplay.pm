# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Outbox::DeadLetterReplay;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::OutboxMessageBuilder;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $KEY_PREFIX => 'dead-letter-replay:';

has builder => sub ($self) {
    return GPForum::Infrastructure::OutboxMessageBuilder->new(
        id_service => $self->id_service );
};
has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('replay');

# The idempotency key of the message a replay enqueues, derived from the dead
# letter. If the replay fails in turn, it has its own dead letter.
sub replay_key ( $class, $dead_letter_id ) {
    return $KEY_PREFIX . $dead_letter_id;
}

# Puts the work of a dead letter back in the queue (ADR 0056), once its cause
# is fixed. The cancelled message and the dead letter are evidence and stay as
# they are: the replay is a new outbox message carrying the dead letter's
# envelope, with the full retry budget, and the audit log records who asked
# for it and how. Built from the dead letter alone, it works for as long as
# the dead letter is kept -- thirty days -- not only the seven the cancelled
# message is. The lock, the refusals, the outbox message and the audit row
# are one call, api.outbox_replay_dead_letter, inside the caller's
# transaction ($scope, the call layer transaction_p hands its work) or on
# its own.
async sub replay_p ( $self, $input, $context = undef, $scope = undef ) {
    return _refused( 'not_found', 'dead letter not found' )
      if !GPForum::Infrastructure::Id->is_uuid( $input->{dead_letter_id} );
    my $functions = $scope // $self->_functions;
    return ( await $functions->row_p( $self->_replay_call($input), $context ) )
      ->{result};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'the dead-letter replay needs the PostgreSQL function layer' );
}

sub _replay_call ( $self, $input ) {
    my $outbox_ids   = $self->builder->id_service;
    my $audit_record = $self->recorder->audit_record;
    my $audit_ids    = $audit_record->id_service;
    return (
        'outbox_replay_dead_letter',
        {
            input => $input,
            ids   => {
                outbox_id      => $outbox_ids->uuid,
                correlation_id => $self->id_service->uuid,
                audit_id       => $audit_ids->uuid
            },
            now => $self->clock->now_iso8601,
        }
    );
}

sub _refused ( $status, $error ) {
    return { status => $status, error => $error };
}

1;

__END__

=head1 NAME

GPForum::Service::Outbox::DeadLetterReplay - Put a dead letter's work back in the queue.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $replay = GPForum::Service::Outbox::DeadLetterReplay->new(
        schema => $schema );
    my $outcome = $replay->replay(
        {
            actor_user_id  => $admin_id,
            dead_letter_id => $dead_letter_id,
            via            => 'web',
        }
    );
    # { status => 'replayed', replayed => { outbox_id => ..., ... } }

=head1 DESCRIPTION

ADR 0056 requires that an operator can review and replay dead letters. A
replay enqueues a new outbox message for the same event, job and payload,
with a fresh retry budget. The cancelled message and the dead letter are left
as they are, as the runbook requires (F<docs/ops/dead-letters.md>), and the
audit log records the replay with its actor.

=head1 SUBROUTINES/METHODS

=head2 replay_p

Takes a hash reference with C<dead_letter_id>, C<actor_user_id> (recorded
as the audit row's actor) and an optional C<via> (C<web> when omitted),
recorded in the audit metadata, then an optional query context and an
optional call layer, inside whose transaction the replay runs (on its own
otherwise). In one call, C<api.outbox_replay_dead_letter>, holding the dead
letter's row lock, it inserts a C<pending> outbox message due at once,
whose payload is the dead letter's envelope and whose idempotency key is
C<replay_key>, and writes the C<outbox.dead_letter_replayed> audit row.
Resolves with C<{ status =E<gt> 'replayed', replayed =E<gt> {...} }>, the inner
hash holding C<dead_letter_id>, C<event_id>, C<outbox_id> and
C<source_id>. A refusal is C<{ status, error }>, C<error> a message:
C<not_found> when the id is not a uuid or there is no such dead letter,
C<conflict> when it was already replayed (the message names when and as
which outbox message), does not name its event, or is not an outbox dead
letter.

=head2 replay

The blocking twin of L</replay_p> (ADR 0177), for the command line: the
same body, settled on the blocking layer.

=head2 replay_key

A class method. Takes a dead letter id and returns the idempotency key of
the message that replays it: C<dead-letter-replay:> followed by the id.

=head1 DIAGNOSTICS

Dies when the database does. Without the function layer it throws
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::OutboxMessageBuilder>, L<GPForum::Service::Clock>.

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
