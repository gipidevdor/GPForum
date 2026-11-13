# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use Mojo::Promise;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::CommandLogFunctions;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;
use GPForum::Test::Schema;

our $VERSION = '0.001';

# The command log on its three functions, over rows kept in memory: a
# failed transaction takes its rows back, a second row under a command id or
# a key is a conflict (GPForum::Test::CommandLogFunctions).
my $log     = GPForum::Test::CommandLogFunctions->new;
my $service = _service($log);

my $calls = 0;
my $first = _run(
    $service,
    _command_request( body_hash => 'hash-1' ),
    sub {
        $calls++;
        return {
            ok     => 1,
            status => 'ok',
            stored => { post => { post_id => 'post-1' } },
        };
    },
    \&_post_response,
);

ok( $first->{recorded}, 'first command execution is recorded' );
is( $calls,             1, 'first command executes callback' );
is( scalar _rows($log), 1, 'command log row is created' );
my $stored = _keyed( $log, 'reply-command-1' );
is( $stored->{idempotency_key},
    'reply-command-1', 'command id is stored as the unique idempotency key' );
is( $stored->{status}, 'handled', 'successful command is marked handled' );
is( $stored->{payload}{response}{post_id},
    'post-1', 'command response envelope is stored' );
ok( $stored->{response_hash}, 'command response hash is stored' );

my $replay = _run(
    $service,
    _command_request( body_hash => 'hash-1' ),
    sub {
        $calls++;
        return { ok => 1, status => 'ok' };
    },
    sub { return { ok => 1, status => 'ok' }; }
);

ok( $replay->{replayed}, 'same command key replays stored response' );
is( $calls, 1, 'replayed command does not execute callback again' );
is( $replay->{response}{post_id},
    'post-1', 'replayed response returns original target id' );

my $conflict = _run(
    $service,
    _command_request( body_hash => 'hash-2' ),
    sub {
        $calls++;
        return { ok => 1, status => 'ok' };
    },
    sub { return { ok => 1, status => 'ok' }; }
);

ok( $conflict->{conflict},
    'same command key with different payload is rejected' );
is( $calls, 1, 'conflicting command does not execute callback' );

my $missing_key_calls = 0;
my $missing_key       = _run(
    $service,
    {
        actor_id     => 'user-1',
        command_type => 'reply.create',
        request      => { thread_id => 'thread-1' },
    },
    sub {
        $missing_key_calls++;
        return { ok => 1, status => 'ok' };
    },
    sub { return { ok => 1, status => 'ok' }; },
);
ok( $missing_key->{invalid}, 'missing command id is rejected' );
is(
    $missing_key->{error},
    'command_id is required',
    'missing command id reports stable error'
);
is( $missing_key_calls, 0, 'missing command id does not execute callback' );

my $request_hash = $stored->{payload}{request_hash};
my $pending      = _pending_log($request_hash);
my $in_progress  = _run(
    _service($pending),
    {
        actor_id     => 'user-1',
        command_id   => 'pending-key',
        command_type => 'reply.create',
        request      => {
            body_hash => 'hash-1',
            thread_id => 'thread-1',
        },
    },
    sub { return { ok => 1, status => 'ok' }; },
    sub { return { ok => 1, status => 'ok' }; },
);

ok( $in_progress->{in_progress},
    'accepted command without response is treated as in progress' );

my $race_log     = GPForum::Test::CommandLogFunctions->new;
my $race_calls   = 0;
my $race_service = _service($race_log);
my $race_first   = _run(
    $race_service,
    _command_request( body_hash => 'hash-1' ),
    sub {
        $race_calls++;
        return {
            ok     => 1,
            status => 'ok',
            stored => { post => { post_id => 'post-1' } },
        };
    },
    \&_post_response,
);
ok( $race_first->{recorded}, 'race fixture records the winning command' );

# The second request looked before the first committed: its lookup misses
# the row, and its insert conflicts on the key.
$race_log->misses(1);
my $race_second = _run(
    $race_service,
    _command_request( body_hash => 'hash-1' ),
    sub {
        $race_calls++;
        return { ok => 1, status => 'ok' };
    },
    sub { return { ok => 1, status => 'ok' }; }
);
ok( $race_second->{replayed},
    'concurrent unique insert is treated as idempotent replay' );
is( $race_calls, 1, 'losing unique insert does not run the callback' );
is( scalar _rows($race_log),
    1, 'concurrent unique insert keeps one command_log row' );
is( $race_second->{response}{post_id},
    'post-1', 'replay after unique conflict returns the original target' );

my $pending_race = _pending_log($request_hash);
$pending_race->misses(1);
my $pending_race_result = _run(
    _service($pending_race),
    {
        actor_id     => 'user-1',
        command_id   => 'pending-key',
        command_type => 'reply.create',
        request      => {
            body_hash => 'hash-1',
            thread_id => 'thread-1',
        },
    },
    sub { return { ok => 1, status => 'ok' }; },
    sub { return { ok => 1, status => 'ok' }; },
);
ok( $pending_race_result->{in_progress},
    'unique conflict on an unfinished command is in progress' );

my $id_log = GPForum::Test::CommandLogFunctions->new(
    commands => {
        'generated-1' => {
            command_id      => 'generated-1',
            idempotency_key => 'other-command',
            payload         => {
                request_hash => 'other-hash',
                response     => { post_id => 'other-post' },
            },
            status => 'handled',
        },
    }
);
my $id_calls  = 0;
my $id_result = _run(
    _service($id_log),
    _command_request( body_hash => 'hash-1' ),
    sub {
        $id_calls++;
        return {
            ok     => 1,
            status => 'ok',
            stored => { post => { post_id => 'post-1' } },
        };
    },
    \&_post_response,
);
ok( $id_result->{recorded}, 'unique command id collision remints and records' );
is( $id_calls, 1, 'unique command id collision still executes callback' );
my $reminted = _keyed( $id_log, 'reply-command-1' );
is( $reminted->{command_id},
    'generated-3', 'unique command id collision remints the id' );
is( $reminted->{idempotency_key},
    'reply-command-1',
    'unique command id collision does not replay another command' );
is( $id_log->commands->{'generated-1'}{idempotency_key},
    'other-command', 'and leaves the other command as it was' );

# A row under this command's key that a lookup missed, holding another
# request's fingerprint and no answer: the second attempt finds it, and the
# command is refused instead of finishing a row another request began.
my $leftover_log = GPForum::Test::CommandLogFunctions->new(
    commands => {
        'generated-1' => {
            command_id      => 'generated-1',
            idempotency_key => 'reply-command-1',
            payload         => { request_hash => 'pending-hash' },
            status          => 'accepted',
        },
    }
);
$leftover_log->misses(1);
my $leftover_calls  = 0;
my $leftover_result = _run(
    _service($leftover_log),
    _command_request( body_hash => 'hash-1' ),
    sub {
        $leftover_calls++;
        return { ok => 1, status => 'ok' };
    },
    \&_post_response,
);
ok( $leftover_result->{conflict},
    'a leftover row under the key for another request is a conflict' );
is( $leftover_calls, 0, 'the leftover command id race does not run it' );
is( scalar _rows($leftover_log),
    1, 'leftover command id race does not insert a second command' );
is( $leftover_log->commands->{'generated-1'}{status},
    'accepted', 'and leaves the leftover row unfinished' );

# A failed result is never the answer: the transaction is abandoned, and
# the same command id runs again.
my $failing = GPForum::Test::CommandLogFunctions->new;
my $failer  = _service($failing);
my $failed  = _run(
    $failer,
    _command_request( body_hash => 'hash-1' ),
    sub { return { ok => 0, status => 'failed' }; }, undef
);
ok( $failed->{recorded} && $failed->{rolled_back},
    'a failed command is rolled back' );
is( $failed->{result}{status}, 'failed', 'and handed back as it was' );
is( scalar _rows($failing),    0, 'no answer is stored for its command id' );
my $retried = _run(
    $failer,
    _command_request( body_hash => 'hash-1' ),
    sub { return { ok => 1, status => 'ok' }; }, undef
);
ok(
    $retried->{recorded} && !$retried->{rolled_back},
    'the same command id runs again after a failure'
);

# A command whose request cannot fingerprint what the member may correct --
# a password change names the member alone -- asks for its refusals to be
# abandoned: nothing is recorded, and the same command id runs again with
# the input corrected, where a recorded refusal came back to it.
my $abandoning      = GPForum::Test::CommandLogFunctions->new;
my $abandoner       = _service($abandoning);
my %password_change = (
    actor_id     => 'user-1',
    command_id   => 'password-change-1',
    command_type => 'identity.password_change',
    refusal      => 'abandon',
    request      => { user_id => 'user-1' },
);
my $refusals = 0;
my $refused  = _run(
    $abandoner,
    {%password_change},
    sub {
        $refusals++;
        return { ok => 0, status => 'invalid' };
    },
    undef
);
ok(
    $refused->{recorded} && $refused->{rolled_back},
    'a refusal the command asked to abandon is rolled back'
);
is( $refused->{result}{status}, 'invalid', 'and handed back as it was' );
is( scalar _rows($abandoning),  0, 'nothing is recorded under the command id' );
my $corrected =
  _run( $abandoner, {%password_change}, sub { return { ok => 1 }; }, undef );
ok(
    $corrected->{recorded} && !$corrected->{rolled_back},
    'the corrected submission runs under the same command id'
);
is( $refusals, 1, 'the refusal ran once' );
is( _keyed( $abandoning, 'password-change-1' )->{status},
    'handled', 'and the accepted result is the answer recorded' );

# Without asking, a refusal is the command's answer, as before.
my $kept = _run(
    $abandoner,
    { %password_change, command_id => 'password-change-2', refusal => undef },
    sub { return { ok => 0, status => 'invalid' }; }, undef
);
ok(
    $kept->{recorded} && !$kept->{rolled_back},
    'a refusal nobody asked to abandon is recorded'
);
is( _keyed( $abandoning, 'password-change-2' )->{status},
    'rejected', 'as rejected' );

# Without the function layer no command is logged, and none runs.
my $unlogged = 0;
my $offline  = GPForum::Service::Operations::CommandIdempotency->new(
    functions => undef,
    schema    => GPForum::Test::Schema->new,
);
my $refusal;
try {
    _run(
        $offline,
        _command_request( body_hash => 'hash-1' ),
        sub { $unlogged++; return { ok => 1 }; }, undef
    );
}
catch ($error) { $refusal = $error; };
isa_ok( $refusal, 'GPForum::X::Unavailable',
    'a command log without the function layer refuses the command' );
is( $unlogged, 0, 'and never runs it' );

done_testing();

sub _service {
    my ($functions) = @_;

    return GPForum::Service::Operations::CommandIdempotency->new(
        clock      => GPForum::Test::FixedClock->new,
        functions  => $functions,
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::Schema->new,
    );
}

# run_p's answer, settled: the double's promises are.
sub _run {
    my ( $idempotency, $input, $code, $response ) = @_;

    return GPForum::Infrastructure::SqlFunction->settled(
        $idempotency->run_p(
            {
                %{$input},
                response => $response,
                run_p    => sub { return Mojo::Promise->resolve( $code->() ) },
            }
        )
    );
}

sub _post_response {
    my ($result) = @_;

    return {
        ok      => $result->{ok},
        post_id => $result->{stored}{post}{post_id},
        status  => $result->{status},
    };
}

sub _pending_log {
    my ($fingerprint) = @_;

    return GPForum::Test::CommandLogFunctions->new(
        commands => {
            'command-1' => {
                command_id      => 'command-1',
                idempotency_key => 'pending-key',
                payload         => { request_hash => $fingerprint },
                status          => 'accepted',
            },
        }
    );
}

sub _rows {
    my ($functions) = @_;

    return values %{ $functions->commands };
}

sub _keyed {
    my ( $functions, $key ) = @_;

    my ($row) =
      grep { $_->{idempotency_key} eq $key } values %{ $functions->commands };

    return $row;
}

sub _command_request {
    my (%override) = @_;

    return {
        actor_id     => 'user-1',
        command_id   => 'reply-command-1',
        command_type => 'reply.create',
        request      => {
            body_hash => $override{body_hash},
            thread_id => 'thread-1',
        },
    };
}

1;
