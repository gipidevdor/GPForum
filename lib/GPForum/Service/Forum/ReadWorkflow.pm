# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ReadWorkflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Service::Operations::CommandIdempotency;

use Scalar::Util qw(blessed);

our $VERSION = '0.001';

const my $COMMAND_TYPE => 'forum.read_marker';

__PACKAGE__->requires('read_state');

has command_idempotency => undef;    # optional: without it every call runs
has logger              => undef;    # optional: without it nothing is logged

# The store's call layer (Infrastructure::SqlFunction) on PostgreSQL, undef
# on a double: with it and a command log, a mark is one call.
has functions => sub ($self) {
    my $store = $self->read_state;
    return blessed $store && $store->can('functions')
      ? $store->functions
      : undef;
};

sub mark_thread_read ( $self, $input ) {
    my $invalid = $self->_missing_command_id($input);
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_mark($input);
}

sub _commanded_mark ( $self, $input ) {
    return $self->_mark_by_function($input)
      if $self->functions && _call_layer( $self->command_idempotency );

    return $self->_commanded_write(
        {
            actor_id     => $input->{user_id},
            command_id   => $input->{command_id},
            command_type => $COMMAND_TYPE,
            request      => _mark_request($input),
            run          => sub { return $self->_run_store($input); },
        }
    );
}

# The command as one call (ADR 0126, section 5): the command log's steps and
# the mark run in api.forum_read_marker_command, which records the answer
# the Perl path records. A request the store would refuse is recorded as
# the store's refusal, without the mark.
sub _mark_by_function ( $self, $input ) {
    my $request = _mark_request($input);
    my $answer  = $self->read_state->invalid_mark($request);
    my $row;
    try {
        $row = $self->functions->row(
            'forum_read_marker_command',
            {
                log    => $self->_command_log( $input, $request ),
                answer => $answer,
                row => $answer ? undef : $self->read_state->mark_row($request),
            }
        );
    }
    catch ($error) {
        $self->_log_error("forum read marker command failed: $error");
        return _failed_result();
    };
    return _commanded_result($row);
}

# The command log's row as CommandIdempotency writes it, with the ids and
# the time drawn in its order: the command's id, its correlation id, its
# time.
sub _command_log ( $self, $input, $request ) {
    my $log = $self->command_idempotency;
    return {
        actor_id               => _nullable( $input->{user_id} ),
        command_id             => $log->id_service->uuid,
        command_correlation_id => $log->id_service->uuid,
        command_at             => $log->clock->now_iso8601,
        command_type           => $COMMAND_TYPE,
        idempotency_key        => _trim( $input->{command_id} ),
        request_hash           => $log->request_hash($request),
    };
}

# The function's row as the result the Perl path answers: the answer it
# recorded or replays, or a conflict in the command log's words.
sub _commanded_result ($row) {
    my $outcome = $row->{outcome} // q{};
    return $row->{response}
      if $outcome eq 'recorded' || $outcome eq 'replayed';
    return _result(
        error =>
          GPForum::Service::Operations::CommandIdempotency->refusal_error(
            $outcome),
        status => 'conflict',
    );
}

sub _nullable ($value) {
    return defined $value && length $value ? $value : undef;
}

# A command log that runs on the call layer; a double of it keeps the Perl
# path (ADR 0126, section 10).
sub _call_layer ($service) {
    return blessed $service && $service->can('functions')
      ? $service->functions
      : undef;
}

sub _commanded_write ( $self, $job ) {
    if ( !$self->command_idempotency ) {
        return $job->{run}->();
    }

    return $self->_idempotent_write($job);
}

sub _idempotent_write ( $self, $job ) {
    my $result;
    try { $result = $self->command_idempotency->result_of($job); }
    catch ($error) {
        $self->_log_error("forum read marker command log failed: $error");
        return _failed_result();
    };

    return $result;
}

# The store's refusal is passed on; a death, or no answer, is a failure.
sub _run_store ( $self, $input ) {
    my $value;
    try {
        $value = $self->read_state->mark_thread_read( _mark_request($input) );
    }
    catch ($error) {
        $self->_log_error("forum read marker write failed: $error");
        return _failed_result();
    };
    return _failed_result() if !$value;
    return $value           if !$value->{ok};

    return _public_marked($value);
}

sub _missing_command_id ( $, $input ) {
    if ( length _trim( $input->{command_id} ) ) {
        return undef;
    }

    return _result(
        errors => { command_id => 'command_id is required' },
        status => 'invalid',
    );
}

sub _public_marked ($marked) {
    my $state = $marked->{read_state} || {};

    return {
        advanced   => $marked->{advanced} ? 1 : 0,
        ok         => 1,
        read_state => {
            last_read_at       => $state->{last_read_at},
            last_read_position => $state->{last_read_position},
            thread_id          => $state->{thread_id},
            user_id            => $state->{user_id},
        },
        status => 'ok',
    };
}

sub _mark_request ($input) {
    return {
        last_read_position => $input->{last_read_position},
        thread_id          => $input->{thread_id},
        user_id            => $input->{user_id},
    };
}

sub _failed_result {
    return _result(
        error  => 'read marker store failed',
        status => 'failed',
    );
}

sub _result (%input) {
    return {
        error  => $input{error},
        errors => $input{errors},
        ok     => ( $input{status} || q{} ) eq 'ok' ? 1 : 0,
        status => $input{status} || 'failed',
        stored => $input{stored},
    };
}

sub _log_error ( $self, $message ) {
    if ( $self->logger ) {
        $self->logger->error($message);
    }

    return;
}

sub _trim ($value) {
    if ( !defined $value ) {
        $value = q{};
    }
    $value =~ s/\A \s+//msx;
    $value =~ s/\s+ \z//msx;

    return $value;
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

On PostgreSQL, with a command log, a mark is one call:
C<api.forum_read_marker_command> opens the command log's row, runs the
mark and records the answer (ADR 0126, section 5). The call layer is the
store's; a store that has none, a test double, runs the mark through
C<command_idempotency> as before.

Requires C<command_id> and replays from C<command_log> when the helper is
present. Persistence stays on L<GPForum::Service::Forum::ReadState>. Command
hashes include actor, thread, and position only.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<read_state>, the
L<GPForum::Service::Forum::ReadState>, is required: without it C<new>
throws L<GPForum::X::Argument>. C<command_idempotency> and C<logger> are
optional.

=head2 mark_thread_read

Upserts the viewer's last-read position. Replay returns the recorded result
without a second upsert.

=head1 DIAGNOSTICS

Returns C<invalid>, C<conflict>, or C<failed> statuses instead of throwing
for expected write outcomes. A command log or read-state error is caught,
logged at error level (C<forum read marker command log failed> or
C<forum read marker write failed>) and answered C<failed>.

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

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
