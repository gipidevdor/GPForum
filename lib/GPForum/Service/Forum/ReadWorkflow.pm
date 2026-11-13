# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ReadWorkflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Log;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $COMMAND_TYPE => 'forum.read_marker';

__PACKAGE__->requires(qw(read_state command_idempotency));

has logger => undef;    # optional: without it nothing is logged

# The read state's call layer (Infrastructure::SqlFunction).
has functions => sub ($self) { return $self->read_state->functions; };

# Written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('mark_thread_read');

# A mark is one call (ADR 0126, section 5): api.forum_read_marker_command
# opens the command log's row, runs the mark and records the answer. A
# request the store would refuse is recorded as the store's refusal,
# without the mark.
async sub mark_thread_read_p ( $self, $input, $context = undef ) {
    my $invalid = missing_command_id($input);
    return $invalid if $invalid;
    my $functions = $self->functions // GPForum::X::Unavailable->throw(
        message => 'read markers need the PostgreSQL function layer' );
    my $log_context = GPForum::Log->request_context;
    my $request     = _mark_request($input);
    my $answer      = $self->read_state->invalid_mark($request);
    my $row;
    try {
        $row = await $functions->row_p(
            'forum_read_marker_command',
            {
                log    => $self->_command_log( $input, $request ),
                answer => $answer,
                row => $answer ? undef : $self->read_state->mark_row($request),
            },
            $context
        );
    }
    catch ($error) {
        GPForum::Log->in_context(
            $log_context,
            sub {
                log_error( $self->logger,
                    "forum read marker command failed: $error" );
                return;
            }
        );
        return _failed_result();
    };
    return _commanded_result($row);
}

sub _command_log ( $self, $input, $request ) {
    my $log = $self->command_idempotency;
    return {
        actor_id               => _nullable( $input->{user_id} ),
        command_id             => $log->id_service->uuid,
        command_correlation_id => $log->id_service->uuid,
        command_at             => $log->clock->now_iso8601,
        command_type           => $COMMAND_TYPE,
        idempotency_key        => trimmed( $input->{command_id} ),
        request_hash           => $log->request_hash($request),
    };
}

# The function's row as the result the Perl path answers: the answer it
# recorded or replays, or a conflict in the command log's words.
sub _commanded_result ($row) {
    my $outcome = $row->{outcome} // q{};
    return $row->{response}
      if $outcome eq 'recorded' || $outcome eq 'replayed';
    return workflow_result(
        error =>
          GPForum::Service::Operations::CommandIdempotency->refusal_error(
            $outcome),
        status => 'conflict',
    );
}

sub _nullable ($value) {
    return defined $value && length $value ? $value : undef;
}

sub _mark_request ($input) {
    return {
        last_read_position => $input->{last_read_position},
        thread_id          => $input->{thread_id},
        user_id            => $input->{user_id},
    };
}

sub _failed_result {
    return workflow_result(
        error  => 'read marker store failed',
        status => 'failed',
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ReadWorkflow - Thread read-marker write commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $workflow->mark_thread_read(
        {
            command_id         => $command_id,
            last_read_position => $position,
            thread_id          => $thread_id,
            user_id            => $user_id,
        }
    );

=head1 DESCRIPTION

A mark is one call: C<api.forum_read_marker_command> opens the command
log's row, runs the mark and records the answer (ADR 0126, section 5). The
call layer is the read state's. Requires C<command_id>; the same command
again replays the recorded answer. The command log's row is written as
L<GPForum::Service::Operations::CommandIdempotency> writes it, its hash over
the actor, the thread and the position only. The mark is written once, as
its promise method; the blocking method is its twin (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<read_state>, the
L<GPForum::Service::Forum::ReadState>, and C<command_idempotency>, whose ids,
clock and request hash the command log's row is written with, are
required: without either C<new> throws L<GPForum::X::Argument>. C<logger>
is optional.

=head2 mark_thread_read_p

Takes C<command_id>, C<user_id>, C<thread_id> and C<last_read_position>,
and an optional query context. Moves the viewer's last-read position
forward; the same command again answers the recorded result without a
second mark.

=head2 mark_thread_read

The blocking twin: L</mark_thread_read_p> run on the blocking call layer
(ADR 0177).

=head1 DIAGNOSTICS

Returns C<invalid>, C<conflict>, or C<failed> statuses instead of throwing
for expected write outcomes. A failed call is caught, logged at error level
(C<forum read marker command failed>) and answered C<failed>. Without the
PostgreSQL function layer a mark raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the read-state helper and command-idempotency helper supplied by the
composition root.

=head1 DEPENDENCIES

L<Mojo::Base>, L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Read-marker writes remain monotonic at the store. HTTP C<command_id> replay
avoids a second upsert for the same command.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
