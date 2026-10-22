# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Mojo::File qw(path);
use Symbol     qw(gensym);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::HypnotoadScaling;
use GPForum::Command::PerformanceSeed;
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::X::Config;

our $VERSION = '0.001';

# bin/gpforum reads the host's settings file for every name the shell left
# unset, so `gpforum performance-seed` on a production host connected to the
# forum's own database and wrote the synthetic benchmark dataset into it. A
# production configuration is seeded only where GPFORUM_DATABASE_DSN was given
# for the seed: in the shell, or by a caller -- the staging drill points it at
# each throwaway database it makes. Port 1 refuses every connection, so a
# seed the guard lets through fails at PostgreSQL instead of writing.

const my $STATUS_SHIFT => 8;
const my $SEED_FAILED  => 2;
const my $RUN_FAILED   => 1;
const my $DSN          => 'GPFORUM_DATABASE_DSN';
const my $FORUM_DSN    => 'dbi:Pg:dbname=gpforum;host=127.0.0.1;port=1';
const my $SCRATCH_DSN  => 'dbi:Pg:dbname=gpforum_bench;host=127.0.0.1;port=1';
const my $DEFAULT_DSN  => 'dbi:Pg:dbname=gpforum';
const my $REFUSAL =>
  q{GPFORUM_ENV is production, so the seed would write into the forum's own}
  . ' database; point GPFORUM_DATABASE_DSN at a scratch database instead.';
const my $SERVICE => 'GPForum::Command::Support::ServiceEnvironment';

my $directory = tempdir( CLEANUP => 1 );

subtest 'a production host is not seeded through its settings file' => sub {
    my $seed = _seed( _settings( 'production', $FORUM_DSN ) );
    ok( GPForum::X::Config->caught( $seed->{error} ), 'the seed is refused' );
    is( "$seed->{error}", $REFUSAL, 'in a sentence that names the fix' );
    is_deeply( $seed->{connected}, [], 'before it connects to anything' );

    my $default = _seed( _settings('production') );
    is( "$default->{error}", $REFUSAL,
        'and a file without a DSN, which leaves the default, is refused too' );
    is_deeply( $default->{connected}, [], 'without connecting either' );
};

subtest 'a DSN given for the seed is seeded' => sub {
    my $shell =
      _seed( _settings( 'production', $FORUM_DSN ), { $DSN => $SCRATCH_DSN } );
    is_deeply( $shell->{connected}, [$SCRATCH_DSN],
        q{the shell's DSN wins over the file's, and is seeded} );

    # As the staging drill does: the host's file is read, then each
    # throwaway database is named for the seed with local $ENV{...}.
    my $drill = _seed(
        _settings( 'production', $FORUM_DSN ),
        {},
        sub ($seed) {
            ok( $SERVICE->from_file($DSN),
                q{the file's DSN reads as the file's} );
            local $ENV{$DSN} = $SCRATCH_DSN;
            ok( !$SERVICE->from_file($DSN), 'one set since does not' );
            return $seed->();
        }
    );
    is_deeply( $drill->{connected}, [$SCRATCH_DSN],
        'so the throwaway database a caller names is seeded' );
};

subtest 'a configuration that is not production is seeded as before' => sub {
    for my $environment (qw(development staging)) {
        my $seed = _seed( _settings( $environment, $FORUM_DSN ) );
        is_deeply( $seed->{connected}, [$FORUM_DSN],
            "a $environment file's DSN is seeded" );
    }
    my $default = _seed( _settings('development') );
    is_deeply( $default->{connected}, [$DEFAULT_DSN],
        'and so is the default on a development host' );
};

subtest 'the front door says the refusal as itself' => sub {
    my $file = _file( 'production.env', _settings( 'production', $FORUM_DSN ) );

    my $refused = _front_door( {}, '--env-file', $file, 'performance-seed' );
    is( $refused->{status}, $SEED_FAILED, 'the seed exits as a failed seed' );
    is(
        $refused->{errors},
        "gpforum performance-seed: $REFUSAL\n",
        'saying why and what to do, without the advice for a failed connection'
    );
    is( $refused->{output}, q{}, 'and reports no dataset' );

    my $given = _front_door( { $DSN => $SCRATCH_DSN },
        '--env-file', $file, 'performance-seed' );
    is( $given->{status}, $SEED_FAILED,
        'with a DSN in the shell it goes on to PostgreSQL' );
    like(
        $given->{errors},
        qr/\A gpforum [ ] performance-seed: [ ] PostgreSQL/msx,
        'and fails there'
    );
    like( $given->{errors}, qr/dbname=gpforum_bench/msx,
        'at the database the shell named' );
};

# hypnotoad-scaling seeds before it starts a server; a refused seed is a
# failed run, said as itself, not misuse under the usage text.
subtest 'a benchmark that seeds is refused the same way' => sub {
    local %ENV = _without_settings();
    $SERVICE->new(
        file => _file( 'scaling.env', _settings( 'production', $FORUM_DSN ) ) )
      ->load;

    my $errors = q{};
    my $status;
    {
        open my $capture, '>', \$errors or croak 'capture stderr';
        local *STDERR = $capture;
        $status = GPForum::Command::HypnotoadScaling->new->run( '--seed',
            '--profile', 'small' );
        close $capture or croak 'close stderr';
    }
    is( $status, $RUN_FAILED,  'the run fails' );
    is( $errors, "$REFUSAL\n", 'with the refusal alone, and no usage' );
};

done_testing;

# A settings file for the environment, with the DSN when one is given, valid
# for production as well.
sub _settings ( $environment, $dsn = undef ) {
    return join q{}, map { "$_\n" } "GPFORUM_ENV=$environment",
      'GPFORUM_PUBLIC_BASE_URL=https://forum.gpforum.test',
      'GPFORUM_MAIL_FROM=forum@forum.gpforum.test',
      'GPFORUM_SESSION_SECRET='
      . '3f9c2a7e5b1d48f0a6c4e2b9d7f1a3c58e0b6d4f2a9c7e1b5d3f8a0c6e4b2d97',
      'GPFORUM_METRICS_TOKEN='
      . '8d1f4b7a2c9e6f3a0b5d8c1e4f7a2b9c6d3e0f5a8b1c4d7e2f9a6b3c0d5e8f14',
      defined $dsn ? qq{$DSN="$dsn"} : ();
}

# Seeds the small profile in process, as hypnotoad-benchmark --seed does, with
# the settings file read the way bin/gpforum reads it over what the shell
# set. Returns what the seed raised and the DSN of each connection it made;
# a connection records its DSN and stops there. $around, when given, runs
# the seed itself.
sub _seed ( $text, $shell = {}, $around = undef ) {
    my @connected;
    local %ENV = ( _without_settings(), %{$shell} );
    $SERVICE->new( file => _file( 'seed.env', $text ) )->load;

    my $seed = sub {
        return with_replaced_subs(
            'GPForum::Schema',
            {
                connect_from_config => sub ( $class, $config ) {
                    push @connected, $config->database_dsn;
                    croak 'connected';
                }
            },
            sub {
                GPForum::Command::PerformanceSeed->new->seed_profile('small');
            }
        );
    };
    my $error =
      _raised( sub { return $around ? $around->($seed) : $seed->() } );

    return { connected => \@connected, error => $error };
}

# `bin/gpforum ARGUMENTS`, with no GPFORUM_ setting but the ones given.
sub _front_door ( $shell, @arguments ) {
    my %wanted = ( _without_settings(), %{$shell}, LC_ALL => 'en_US.UTF-8', );
    my ( $pid, $output, $errors );
    {
        local %ENV = %wanted;
        $errors = gensym;
        $pid    = open3( my $input, $output, $errors, $EXECUTABLE_NAME,
            'bin/gpforum', @arguments );
        close $input or croak "close child input: $OS_ERROR";
    }
    my %read;
    for my $stream ( [ output => $output ], [ errors => $errors ] ) {
        local $INPUT_RECORD_SEPARATOR = undef;
        my $handle = $stream->[1];
        $read{ $stream->[0] } = <$handle> // q{};
    }
    waitpid $pid, 0;

    return { %read, status => $CHILD_ERROR >> $STATUS_SHIFT };
}

sub _without_settings {
    return map { $_ => $ENV{$_} } grep { !/\A GPFORUM_/msx } keys %ENV;
}

sub _file ( $name, $text ) {
    my $file = path( $directory, $name );
    $file->spew($text);

    return $file->to_string;
}

sub _raised ($code) {
    try {
        $code->();
    }
    catch ($error) {
        return $error;
    };

    return undef;
}

1;
