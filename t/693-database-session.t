# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English qw(-no_match_vars);
use Test::More;

use lib 'lib';

use GPForum::Config;

our $VERSION = '0.001';

# ADR 0137: a connection says who it is and how long it waits in its startup
# packet, and sets the session in one statement. Six statements, one a
# PL/pgSQL block with an exception handler, cost a millisecond of every
# connection's three; one SELECT costs 30 microseconds.

const my $ATTRIBUTES => 3;

sub _config (%environment) {
    return GPForum::Config->from_environment(
        { GPFORUM_ENV => 'development', %environment } );
}

subtest 'the startup packet names the process and bounds the wait' => sub {
    local $ENV{HYPNOTOAD_APP} = undef;
    local $PROGRAM_NAME = 'gpforum outbox';
    my ($dsn) = _config( GPFORUM_DATABASE_DSN => 'dbi:Pg:dbname=gpforum' )
      ->database_connect_info;
    is(
        $dsn,
        'dbi:Pg:dbname=gpforum;application_name=gpforum-outbox;'
          . 'connect_timeout=5',
        'a verb is its own role, with a five-second connect timeout'
    );

    local $ENV{HYPNOTOAD_APP} = '/opt/gpforum/bin/gpforum';
    is( _config()->database_application_name,
        'gpforum-web', 'a process Hypnotoad loaded serves the web' );

    local $ENV{HYPNOTOAD_APP} = undef;
    local $PROGRAM_NAME = 't/693-database-session.t';
    is( _config()->database_application_name,
        'gpforum', 'anything else is gpforum' );
};

subtest q{the operator's own options win} => sub {
    my $given = 'dbi:Pg:dbname=gpforum;host=/run/postgresql;'
      . 'Application_Name=mine;connect_timeout=2';
    my ($dsn) =
      _config( GPFORUM_DATABASE_DSN => $given )->database_connect_info;
    is( $dsn, $given, 'neither is added twice, whatever their case' );
};

subtest 'the session is set in one round trip' => sub {
    my $settings = _config(
        GPFORUM_DATABASE_STATEMENT_TIMEOUT_MS => 15_000,
        GPFORUM_DATABASE_LOCK_TIMEOUT_MS      => 3_000,
    )->database_session_settings;
    is( scalar @{$settings}, 1, 'one statement' );
    my ($statement) = @{$settings};
    unlike(
        $statement,
        qr/\b (?: DO | SET \s ) \b/msx,
        'a plain SELECT: no PL/pgSQL block, no SET per setting'
    );
    like(
        $statement,
        qr/'statement_timeout', \s '15000'/msx,
        'the statement timeout'
    );
    like( $statement, qr/'lock_timeout', \s '3000'/msx, 'the lock timeout' );
    like(
        $statement,
        qr/'idle_in_transaction_session_timeout'/msx,
        'the idle-in-transaction timeout'
    );
    like(
        $statement,
        qr/'pg_trgm[.]similarity_threshold', \s '0[.]18'/msx,
        q{search's similarity threshold}
    );
    like(
        $statement,
        qr/has_parameter_privilege [(] 'lc_messages', \s 'SET' [)]/msx,
        'the message locale only where the role may set it'
    );
    unlike( $statement, qr/application_name/msx,
        'and the name is in the startup packet, not here' );

    my %attributes =
      %{ ( _config()->database_connect_info )[$ATTRIBUTES] };
    is_deeply(
        $attributes{on_connect_do},
        _config()->database_session_settings,
        'DBIx::Class runs it'
    );
};

done_testing();

1;
