# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use File::Temp    qw(tempdir);
use IPC::Open3    qw(open3);
use JSON::MaybeXS qw(decode_json);
use Mojo::File    qw(path);
use Mojo::Util    qw(encode);
use Symbol        qw(gensym);
use Test::More;
use Test::Mojo;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Command::Migrate;
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Service::Admin::Bootstrapper;
use GPForum::Service::Operations::QueryBudget;
use GPForum::Service::Password;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $EXIT_FAILURE     => 1;
const my $STATUS_SHIFT     => 8;
const my $PASSWORD         => 'correct horse battery staple';
const my $UNICODE_PASSWORD => 'пароль 🔒 propriétaire';
const my $HTTP_OK          => 200;
const my $HTTP_ACCEPTED    => 202;
const my $HTTP_FOUND       => 302;

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the front door test';
}

# Iteration 2's acceptance, on a real PostgreSQL: on an empty database
# `gpforum migrate` leaves a schema the readiness report agrees with, query
# budgets included, and `gpforum admin create` makes an owner who can sign in,
# without psql and without mail.

my $database =
  GPForum::Test::PostgresHarness::create_database( $ENV{GPFORUM_DATABASE_DSN} );
local $ENV{GPFORUM_DATABASE_DSN}    = $database->{dsn};
local $ENV{GPFORUM_ENV}             = 'development';
local $ENV{GPFORUM_PUBLIC_BASE_URL} = 'https://forum.example.org';
local $ENV{LC_ALL}                  = 'en_US.UTF-8';

subtest 'gpforum migrate brings an empty database up to date' => sub {
    my $first = _run( _migrate() );
    is( $first->{status}, 0, 'it succeeds' );
    like(
        $first->{output},
        qr/\A Applied [ ] \d+ [ ] migrations, [ ] 1000 [ ] to/msx,
        'in one line: the migrations'
    );
    like(
        $first->{output},
        qr/synced [ ] the [ ] query [ ] budgets/msx,
        'and the budgets'
    );
    like(
        $first->{output},
        qr/^Next: [ ] make [ ] the [ ] forum's [ ] owner/msx,
        q{then the owner a new forum lacks}
    );
    is(
        GPForum::Service::Operations::QueryBudget->new->drift_report(
            GPForum::Test::PostgresHarness::connect_schema()
        )->{status},
        'ok',
        'so the readiness report finds no budget drift'
    );

    my $again = _run( _migrate() );
    like(
        $again->{output},
        qr/\A Schema [ ] is [ ] current [ ] [(]\d+[)][.]$/msx,
        'run again, it says the schema is current'
    );

    my $plan = decode_json( _run( _migrate(), '--plan', '--json' )->{output} );
    is_deeply( $plan->{pending}, [], '--plan asks the database: none pending' );
};

subtest 'gpforum admin create makes an owner who can sign in' => sub {
    my $created = _run( _admin( input => _input("$PASSWORD\n") ),
        'create', '--email', 'You@Example.org', '--username', 'you',
        '--password-stdin' );
    is( $created->{status}, 0, 'it succeeds' );
    like( $created->{output},
        qr/owner [ ] and [ ] can [ ] sign [ ] in [ ] now/msx,
        'saying so' );
    like(
        $created->{output},
        qr{^Next: [ ] sign [ ] in [ ] at [ ] https://forum[.]example}msx,
        'and where to sign in'
    );

    my $dbh  = $database->{dbh};
    my $user = $dbh->selectrow_hashref(
        'SELECT id, status, email_verified_at, password_hash FROM users'
          . ' WHERE username = ?',
        undef, 'you'
    );
    is( $user->{status}, 'active', 'the account is active' );
    ok( defined $user->{email_verified_at}, 'its address verified' );
    ok(
        GPForum::Service::Password->new->verify_password(
            $PASSWORD, $user->{password_hash}
        ),
        'and its password the one given'
    );
    my $bootstrapper = GPForum::Service::Admin::Bootstrapper->new(
        schema => GPForum::Test::PostgresHarness::connect_schema() );
    ok( $bootstrapper->has_owner, 'the forum has its owner' );
    is(
        $dbh->selectrow_array(
            q{SELECT count(*) FROM audit_log}
              . q{ WHERE action = 'admin.bootstrap_created' AND target_id = ?},
            undef,
            $user->{id}
        ),
        1,
        'audited as admin.bootstrap_created'
    );

    my $again = _run( _admin( input => _input("$PASSWORD\n") ),
        'create', '--email', 'you@example.org', '--username', 'you',
        '--password-stdin' );
    is( $again->{status}, $EXIT_FAILURE, 'the same account again is 1' );
    ok(
        index( $again->{errors},
            q{you (you@example.org) is the forum's owner already;} ) == 0,
        'saying it is the owner already'
    );
    unlike(
        $again->{errors},
        qr/admin [ ] grant/msx,
        'not pointing at grant, which it needs no more'
    );

    my $taken = _run( _admin( input => _input("$PASSWORD\n") ),
        'create', '--email', 'you@example.org', '--username', 'someone',
        '--password-stdin' );
    is( $taken->{status}, $EXIT_FAILURE, 'its address for another name is 1' );
    like( $taken->{errors},
        qr/\A There [ ] is [ ] already [ ] an [ ] account/msx, 'refused' );
    like(
        $taken->{errors},
        qr/admin [ ] grant [ ] you\@example[.]org/msx,
        'pointing at grant'
    );

    my $short = _run( _admin( input => _input("short\n") ),
        'create', '--email', 'other@example.org', '--username', 'other',
        '--password-stdin' );
    is( $short->{status}, $EXIT_FAILURE, 'a short password is 1' );
    like(
        $short->{errors},
        qr/at [ ] least [ ] 12 [ ] characters/msx,
        'saying how long it must be'
    );

    my $dry = _run( _admin(), 'create', '--email', 'other@example.org',
        '--username', 'other', '--dry-run' );
    is( $dry->{status}, 0, '--dry-run succeeds without a password' );
    is(
        $dbh->selectrow_array(
            q{SELECT count(*) FROM users WHERE username = 'other'}),
        0,
        'and writes nothing'
    );
};

subtest 'UTF-8 owner passwords and registration passwords work over HTTP' =>
  sub {
    my $created = _run(
        _admin( input => _input( encode( 'UTF-8', "$UNICODE_PASSWORD\n" ) ) ),
        'create',
        '--email',
        'unicode@example.org',
        '--username',
        'unicode_owner',
        '--password-stdin'
    );
    is( $created->{status}, 0, 'the CLI accepts a UTF-8 owner password' );
    my $client = Test::Mojo->new('GPForum');
    $client->get_ok('/login')->status_is($HTTP_OK);
    $client->post_ok(
        '/login' => form => {
            %{ _form_tokens($client) },
            identifier => 'unicode_owner',
            password   => $UNICODE_PASSWORD,
        }
    )->status_is($HTTP_FOUND);
    $client->get_ok('/settings')->status_is($HTTP_OK);
    my $controller = $client->app->build_controller;
    $controller->gp_schema->storage->disconnect;

    my $registered = Test::Mojo->new('GPForum');
    $registered->get_ok('/register')->status_is($HTTP_OK);
    $registered->post_ok(
        '/register' => form => {
            %{ _form_tokens($registered) },
            username     => 'unicode_member',
            email        => 'unicode-member@example.org',
            display_name => 'Unicode member',
            password     => $UNICODE_PASSWORD,
        }
    )->status_is($HTTP_ACCEPTED);
    my ($hash) = $database->{dbh}->selectrow_array(
        q{SELECT password_hash FROM users WHERE username = 'unicode_member'});
    ok(
        GPForum::Service::Password->new->verify_password(
            $UNICODE_PASSWORD, $hash
        ),
        'the HTTP registration preserves its password'
    );
    $controller = $registered->app->build_controller;
    $controller->gp_schema->storage->disconnect;
  };

subtest 'gpforum admin grant finds the member by address or name' => sub {
    my $member = GPForum::Service::Admin::Bootstrapper->new(
        schema => GPForum::Test::PostgresHarness::connect_schema() )
      ->create_owner(
        {
            email     => 'second@example.org',
            password  => $PASSWORD,
            role_name => 'second_role',
            username  => 'second',
        }
      );
    ok( $member->{ok}, 'a second account exists' );

    my $granted = _run( _admin(), 'grant', 'SECOND@example.org' );
    is( $granted->{status}, 0, 'grant by address succeeds' );
    like( $granted->{output}, qr/[(]second\@example[.]org[)] [ ] is [ ] the/msx,
        'saying so' );
    like(
        _run( _admin(), 'grant', 'second' )->{output},
        qr/was [ ] the [ ] forum's [ ] owner [ ] already/msx,
        'and by name, again, changes nothing'
    );

    my $nobody = _run( _admin(), 'grant', 'nobody' );
    is( $nobody->{status}, $EXIT_FAILURE, 'nobody to grant is 1' );
    like(
        $nobody->{errors},
        qr/gpforum [ ] admin [ ] create/msx,
        'pointing at create'
    );

    my $json =
      decode_json( _run( _admin(), 'grant', 'you', '--json' )->{output} );
    is( $json->{role},           'gpforum_owner', '--json names the role' );
    is( $json->{user}{username}, 'you',           'and the member' );

    my $owned = _run( _migrate() );
    unlike( $owned->{output}, qr/^Next:/msx,
        'with an owner and nothing to apply, migrate names no next step' );
};

subtest 'gpforum outbox and scheduled-jobs run their work' => sub {
    for my $case (
        [ 'outbox',         'gpforum-outbox-dispatch' ],
        [ 'scheduled-jobs', 'gpforum-scheduled-jobs' ],
      )
    {
        my ( $verb, $command ) = @{$case};
        my $run = _front_door( $verb, '--once', '--json' );
        is( $run->{status}, 0, "gpforum $verb --once succeeds" )
          or diag $run->{errors};
        my ($document) = grep { /\A [{]/msx } split /\n/msx, $run->{output};
        is( decode_json( $document // '{}' )->{command},
            $command, 'with the application its work comes from' );
    }
};

subtest 'a command admin offers reads the file this run read' => sub {
    my $file = path( tempdir( CLEANUP => 1 ), 'staging.env' );
    $file->spew("# nothing this test needs set\n");
    GPForum::Command::Support::ServiceEnvironment->new(
        file        => "$file",
        environment => {},
    )->load;

    my $nobody = _run( _admin(), 'grant', 'nobody' );
    like(
        $nobody->{errors},
        qr/gpforum [ ] --env-file [ ] \Q$file\E [ ] admin [ ] create/msx,
        'gpforum admin create, against the database that file names'
    );
};

GPForum::Test::PostgresHarness::drop_database($database);

done_testing();

sub _migrate {
    return GPForum::Command::Migrate->new( default_mode => 'apply' );
}

sub _admin (%attributes) {
    return GPForum::Command::AdminBootstrap->new(%attributes);
}

# bin/gpforum started as an operator starts it, with this test's database.
sub _front_door (@arguments) {
    my $errors = gensym;
    my $pid    = open3( my $input, my $output, $errors, $EXECUTABLE_NAME,
        'bin/gpforum', @arguments );
    close $input or croak "close child input: $ERRNO";
    my %read;
    for my $stream ( [ output => $output ], [ errors => $errors ] ) {
        local $INPUT_RECORD_SEPARATOR = undef;
        my $handle = $stream->[1];
        $read{ $stream->[0] } = <$handle> // q{};
    }
    waitpid $pid, 0;

    return { %read, status => $CHILD_ERROR >> $STATUS_SHIFT };
}

sub _input ($text) {
    open my $handle, '<', \$text or croak 'open input';

    return $handle;
}

sub _form_tokens ($client) {
    my $dom = $client->tx->res->dom;

    return { map { $_ => $dom->at("input[name=$_]")->attr('value') }
          qw(csrf_token command_id) };
}

sub _run ( $command, @arguments ) {
    my ( $output, $errors ) = ( q{}, q{} );
    my $status;
    {
        open my $stdout, '>', \$output or croak 'capture stdout';
        open my $stderr, '>', \$errors or croak 'capture stderr';
        local *STDOUT = $stdout;
        local *STDERR = $stderr;
        $status = $command->run(@arguments);
        close $stdout or croak 'close stdout';
        close $stderr or croak 'close stderr';
    }

    return { errors => $errors, output => $output, status => $status };
}

1;
