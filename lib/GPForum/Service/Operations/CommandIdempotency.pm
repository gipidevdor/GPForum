# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::CommandIdempotency;

use Carp qw(croak);
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use JSON::MaybeXS;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Clock;
use GPForum::Infrastructure::Id;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $FAILED_STATUS => 'failed';

# What a command asks of its refusals: recorded as its answer (the default),
# or abandoned, for a command whose request cannot fingerprint what the
# member may correct.
const my $ABANDON   => 'abandon';
const my $ABANDONED => __PACKAGE__ . '::Abandoned';

# What a command already in the log is refused with, by the outcome
# api functions answer (ADR 0126) and _existing_result decides.
const my %REFUSAL => (
    conflict    => 'idempotency key was already used for another request',
    in_progress => 'idempotency key is already in progress',
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
__PACKAGE__->requires(qw(schema));

# A workflow command run under the log on its call layer, answered in the
# shape every workflow returns: the stored response on a replay, the new
# result, or a refusal -- invalid without a command id, conflict when the id
# belongs to another request or is still running. $job holds actor_id,
# command_id, command_type, request, run_p -- which takes the transaction's
# call layer and answers a promise of the result -- and may hold refusal and
# the response it records of a result. Seven workflows carried their own
# copy of this (ADR 0110).
async sub result_of_p ( $self, $job, $context = undef ) {
    my $guarded = await $self->run_p(
        {
            actor_id     => $job->{actor_id},
            command_id   => trimmed( $job->{command_id} ),
            command_type => $job->{command_type},
            request      => $job->{request} || {},
            refusal      => $job->{refusal},
            response     => $job->{response},
            run_p        => $job->{run_p},
        },
        $context
    );
    return $guarded->{response} if $guarded->{replayed};
    return $guarded->{result}   if $guarded->{recorded};

    return _refusal($guarded);
}

# The command log's lookup, its row, the job's own writes and its answer
# commit in one transaction on the call layer. A failed or abandoned result
# rolls the whole transaction back. A second request that won the key (or a
# minted id that collided) is answered by one more attempt, which finds the
# row it left or draws a new id. The log needs the function layer: without
# it a command cannot be logged, and none runs.
async sub run_p ( $self, $input, $context = undef ) {
    my $key = trimmed( $input->{command_id} );
    return { error => 'command_id is required', invalid => 1 }
      if !length $key;

    my $functions = $self->functions // GPForum::X::Unavailable->throw(
        message => 'the command log needs the PostgreSQL function layer' );
    my $attempt = {
        actor_id     => $input->{actor_id},
        command_type => $input->{command_type},
        key          => $key,
        refusal      => $input->{refusal},
        request_hash => _canonical_hash( $input->{request} || {} ),
        response     => $input->{response},
        run_p        => $input->{run_p},
    };
    my $guarded;
    for my $retry ( 0, 1 ) {
        try {
            $guarded = await $functions->transaction_p(
                sub ($scope) {
                    return $self->_guarded_p( $scope, $attempt, $context );
                },
                $context
            );
        }
        catch ($error) {
            return {
                recorded    => 1,
                result      => $error->{result},
                rolled_back => 1,
              }
              if ref $error eq $ABANDONED;
            croak $error if $retry || !GPForum::X::Conflict->caught($error);
        };
        last if $guarded;
    }

    return $guarded;
}

# A failed result is never the command's answer. Every workflow's guarded
# code catches its store's exception and returns 'failed' from inside this
# transaction. Committing then kept whatever the store wrote before it
# failed, whenever PostgreSQL survived the failure -- a savepoint rolled back,
# or not a database error at all -- and stored 'failed' as the command id's
# answer, so retrying the same command could never succeed. Abandoning the
# transaction leaves neither; run_p hands the failure back uncommitted.
async sub _guarded_p ( $self, $scope, $attempt, $context ) {
    my $found = await $scope->row_p( 'ops_command_lookup',
        { key => $attempt->{key}, command_id => undef }, $context );
    if ( $found && $found->{document} ) {
        return $self->_existing_result( $found->{document},
            $attempt->{request_hash} );
    }

    my $row = $self->_command_row($attempt);
    await $scope->row_p( 'ops_command_insert', { command => $row }, $context );
    my $result = await $attempt->{run_p}->($scope);
    if ( _is_failed($result) || _refusal_abandoned( $attempt, $result ) ) {
        croak bless { result => $result }, $ABANDONED;
    }
    await $scope->row_p(
        'ops_command_finish',
        {
            command_id => $row->{command_id},
            changes    => $self->_finish_changes(
                $row,
                $result,
                $attempt->{response}
                ? $attempt->{response}->($result)
                : $result
            ),
        },
        $context
    );

    return {
        recorded => 1,
        result   => $result,
    };
}

sub _refusal ($guarded) {
    my %refusal =
      $guarded->{invalid}
      ? (
        errors => { command_id => 'command_id is required' },
        status => 'invalid',
      )
      : ( error => $guarded->{error}, status => 'conflict' );

    return {
        error  => $refusal{error},
        errors => $refusal{errors},
        ok     => 0,
        status => $refusal{status},
        stored => undef,
    };
}

sub _existing_result ( $self, $row, $request_hash ) {
    my $payload = _payload_hash( $row->{payload} );
    if ( ( $payload->{request_hash} || q{} ) ne $request_hash ) {
        return {
            conflict => 1,
            error    => $REFUSAL{conflict},
        };
    }

    if ( !_has_response($payload) ) {
        return {
            in_progress => 1,
            error       => $REFUSAL{in_progress},
        };
    }

    return {
        replayed => 1,
        response => $payload->{response},
    };
}

sub _command_row ( $self, $attempt ) {
    return {
        actor_id        => _nullable_trim( $attempt->{actor_id} ),
        command_id      => $self->id_service->uuid,
        command_type    => trimmed( $attempt->{command_type} ),
        correlation_id  => $self->id_service->uuid,
        created_at      => $self->clock->now_iso8601,
        handled_at      => undef,
        idempotency_key => $attempt->{key},
        payload         => { request_hash => $attempt->{request_hash} },
        response_hash   => undef,
        status          => 'accepted',
    };
}

# What a finished command's row becomes: its response kept in the payload,
# with the response's hash, the time it was handled and its status.
sub _finish_changes ( $self, $row, $result, $response ) {
    my $payload = _payload_hash( $row->{payload} );
    $payload->{response} = $response || {};

    return {
        handled_at    => $self->clock->now_iso8601,
        payload       => $payload,
        response_hash => _canonical_hash( $payload->{response} ),
        status        => _result_status($result),
    };
}

sub _result_status ($result) {
    if ( ref $result ne 'HASH' ) {
        return 'rejected';
    }
    if ( $result->{ok} ) {
        return 'handled';
    }

    my $status = $result->{status} || q{};
    return $status eq 'failed' ? 'failed' : 'rejected';
}

sub _payload_hash ($payload) {
    if ( ref $payload ne 'HASH' ) {
        return {};
    }

    return { %{$payload} };
}

sub _has_response ($payload) {
    return ref $payload eq 'HASH' && exists $payload->{response} ? 1 : 0;
}

# The request's fingerprint as run_p keeps it: SHA-256 of its canonical
# JSON. For a command whose log steps run in its PostgreSQL function (ADR
# 0126).
sub request_hash ( $class, $request ) {
    return _canonical_hash( $request || {} );
}

# The words a command already in the log is refused with: conflict (another
# request under the key) or in_progress (no response yet).
sub refusal_error ( $class, $outcome ) {
    return exists $REFUSAL{ $outcome // q{} } ? $REFUSAL{$outcome} : undef;
}

sub _canonical_hash ($value) {
    my $json =
      JSON::MaybeXS->new( canonical => 1, utf8 => 1 )->encode( $value // {} );

    return sha256_hex($json);
}

# A refusal is a command's answer, recorded and replayed, since the same
# request is refused the same way. Not for a command whose request leaves
# out what the member may correct -- a password, which is no thing to
# fingerprint: recorded, the refusal came back to the corrected submission
# under the same command id for as long as the form stayed open. Such a
# command asks for its refusals to be abandoned, and the id stays free.
sub _refusal_abandoned ( $attempt, $result ) {
    return 0 if ( $attempt->{refusal} // q{} ) ne $ABANDON;

    return ref $result eq 'HASH' && $result->{ok} ? 0 : 1;
}

sub _is_failed ($result) {
    return 0 if ref $result ne 'HASH';

    return ( $result->{status} // q{} ) eq $FAILED_STATUS ? 1 : 0;
}

sub _nullable_trim ($value) {
    my $trimmed = trimmed($value);

    return length $trimmed ? $trimmed : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::CommandIdempotency - Run a write command once per command id and replay its answer.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $idempotency = GPForum::Service::Operations::CommandIdempotency->new(
        schema => $schema,
    );

    # The shape every workflow returns
    my $result = await $idempotency->result_of_p(
        {
            actor_id     => $user_id,
            command_id   => $command_id,
            command_type => 'notification.preferences',
            request      => $preferences,
            run_p        => sub ($scope) {
                return $store->save_preferences_p( $scope, $preferences );
            },
        },
        $context
    );

    # The lower-level call
    my $guarded = await $idempotency->run_p(
        {
            actor_id     => $user_id,
            command_id   => $command_id,
            command_type => 'identity.password_change',
            refusal      => 'abandon',
            request      => $request_fields,
            response     => sub ($result) { return { ok => $result->{ok} } },
            run_p        => sub ($scope) {
                return $store->change_password_p( $scope, $input );
            },
        },
        $context
    );
    # $guarded->{recorded}, ->{replayed}, ->{conflict}, ->{in_progress}
    # or ->{invalid}

=head1 DESCRIPTION

Makes a write safe to retry. The caller's command id is the key of a
C<command_log> row that holds a SHA-256 hash of the request, taken over its
canonical JSON, and, once the command has run, the response to give back.
The first call with a key inserts the row, runs the command and stores its
response, all in one transaction on the call layer, through the functions
C<api.ops_command_lookup>, C<api.ops_command_insert> and
C<api.ops_command_finish>. A later call with the same key and the same
request gets the stored response without running anything; with a
different request it is refused as a conflict, and while the first call has
not finished it is refused as in progress. Two concurrent first calls end
with one run and one replay: the loser's insert conflicts on the key, and
its second attempt finds the winner's row. A minted command id that
collides is drawn again on that second attempt.

A command whose result has C<status> C<failed> is not an answer. The
transaction is abandoned, so neither what the command wrote before it
failed nor the C<command_log> row is kept, and retrying the same command id
can still succeed. The failure is handed back to the caller uncommitted.

L</result_of_p> wraps L</run_p> in the result shape the workflows share;
seven of them used to carry their own copy of it (ADR 0110). There is no
blocking twin: every caller awaits the promise, and a command or job runs it
on a blocking call layer (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required; C<functions> defaults to
the schema's PostgreSQL function layer; C<clock> and C<id_service> default
to L<GPForum::Service::Clock> and L<GPForum::Infrastructure::Id>.

=head2 result_of_p

Takes a hash reference with C<actor_id>, C<command_id> (trimmed),
C<command_type>, C<request> (an empty hash when absent), C<run_p> (a code
reference called with the transaction's call layer, answering a promise of
the result), and optionally C<refusal> (passed to L</run_p>) and
C<response>, a code reference that makes the response recorded of the
result (the result itself when absent), and an optional request context.
Calls L</run_p> with it, and answers a promise of:

=over 4

=item * the stored response, on a replay;

=item * the command's result, when it ran (also when it failed and was
rolled back);

=item * C<< { ok => 0, status => 'invalid', errors => { command_id => 'command_id is required' }, error => undef, stored => undef } >>
for an empty command id;

=item * C<< { ok => 0, status => 'conflict', error => $message, errors => undef, stored => undef } >>
when the id was used for another request or is still in progress.

=back

=head2 run_p

Takes an input hash reference (C<command_id>, trimmed; C<request>;
C<actor_id>; C<command_type>; C<run_p>; and optionally C<response> and
C<refusal>, C<abandon> for a command whose refusals are not answers, see
below) and an optional request context. The command log's steps and the
command's writes commit in one transaction. Answers a promise of a hash
reference:

=over 4

=item * C<< { invalid => 1, error => 'command_id is required' } >> when
the command id is empty;

=item * C<< { recorded => 1, result => $result } >> after running the
command; the row's status becomes C<handled> when the result has a true
C<ok> and C<rejected> otherwise;

=item * C<< { recorded => 1, result => $result, rolled_back => 1 } >> when
the result's status was C<failed> and the transaction was abandoned, or
when the result was refused (a false C<ok>) and the input asked
C<< refusal => 'abandon' >>: a command whose request cannot fingerprint what
the member may correct, such as a password, so that the same command id
runs again with the input corrected instead of getting the refusal back;

=item * C<< { replayed => 1, response => $response } >> for a key already
answered with the same request;

=item * C<< { conflict => 1, error => 'idempotency key was already used for another request' } >>;

=item * C<< { in_progress => 1, error => 'idempotency key is already in progress' } >>.

=back

It needs the function layer, and throws L<GPForum::X::Unavailable> without
it: a command that cannot be logged does not run.

=head2 request_hash

Takes a request hash reference (an empty one when undefined). Returns its
fingerprint as L</run_p> keeps it: the SHA-256 hex of its canonical JSON. A
command whose command log steps run inside its PostgreSQL function (ADR
0126) passes it to the function.

=head2 refusal_error

Takes an outcome, C<conflict> or C<in_progress>. Returns the words L</run_p>
refuses a command already in the log with, or undef for another outcome.

=head1 DIAGNOSTICS

Rejects with the original error when the command dies or the database fails
for any reason other than the handled unique conflicts (on the command id,
drawn again, and on the idempotency key, which replays the row that won),
each answered by one more attempt; the transaction rolls back. The
workflows await L</result_of_p> inside a C<try> and turn such an error into
their own C<failed> result.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>, L<JSON::MaybeXS>, L<Digest::SHA>.

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
