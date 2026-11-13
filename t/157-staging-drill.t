# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use Test::Exception;
use Test::More;

use lib 'lib';

use GPForum::Command::StagingDrill;
use GPForum::Service::Operations::StagingDrill;

our $VERSION = '0.001';

const my $EXPECTED_TESTS => 16;

plan tests => $EXPECTED_TESTS;

my $service = GPForum::Service::Operations::StagingDrill->new;

is(
    $service->rewrite_dsn(
        'dbi:Pg:dbname=gpforum;host=127.0.0.1',
        'gpforum_drill_fresh'
    ),
    'dbi:Pg:dbname=gpforum_drill_fresh;host=127.0.0.1',
    'rewrite_dsn replaces dbname'
);

throws_ok( sub { $service->rewrite_dsn( 'dbi:Pg:host=127.0.0.1', 'x' ) },
    qr/dbname=/msx, 'rewrite_dsn requires dbname' );

# The database named as DBD::Pg takes it, as the forum's own connection does.
is(
    $service->parse_dsn('dbi:Pg:database=gpforum;host=/var/run/postgresql')
      ->{dbname},
    'gpforum', 'parse_dsn reads database='
);
is(
    $service->rewrite_dsn( 'dbi:Pg:host=/tmp; db = gpforum', 'gpforum_drill' ),
    'dbi:Pg:host=/tmp;dbname=gpforum_drill',
    'and rewrite_dsn replaces db='
);
{
    delete local $ENV{GPFORUM_DATABASE_USER};
    delete local $ENV{GPFORUM_DATABASE_PASSWORD};
    is_deeply(
        [
            @{
                $service->parse_dsn(
                    'dbi:Pg:dbname=gpforum;user=forum;password=secret')
            }{qw(user password port)}
        ],
        [ 'forum', 'secret', undef ],
        'the DSN login is the last resort, and no port is made up'
    );
}

{
    local $ENV{GPFORUM_DATABASE_USER}     = 'drill_user';
    local $ENV{GPFORUM_DATABASE_PASSWORD} = 'drill_pass';
    my $parts =
      $service->parse_dsn('dbi:Pg:dbname=gpforum;host=127.0.0.1;port=5432');
    is( $parts->{dbname},   'gpforum',    'parse_dsn dbname' );
    is( $parts->{host},     '127.0.0.1',  'parse_dsn host' );
    is( $parts->{port},     '5432',       'parse_dsn port' );
    is( $parts->{user},     'drill_user', 'parse_dsn user from env' );
    is( $parts->{password}, 'drill_pass', 'parse_dsn password from env' );
}

my $command = GPForum::Command::StagingDrill->new;
my $usage   = q{};
{
    open my $stdout, '>', \$usage or croak 'stdout';
    local *STDOUT = $stdout;
    is( $command->run('--help'), 0, 'help exits 0' );
    close $stdout or croak 'close stdout';
}
like( $usage, qr/gpforum [ ] staging-drill/msx, 'help names the command' );
like( $usage, qr/var\/attachments/msx, 'help mentions attachment gap' );

my $stderr = q{};
{
    open my $err, '>', \$stderr or croak 'stderr';
    local *STDERR = $err;
    is( $command->run( '--seed-profile', 'nope' ),
        2, 'bad seed profile exits usage' );
    close $err or croak 'close stderr';
}
like(
    $stderr,
    qr/Unsupported [ ] seed [ ] profile/msx,
    'bad seed profile message'
);

my $evidence = {
    status        => 'pass',
    fresh_migrate => { status => 'pass', schema_versions       => 36 },
    upgrade_path  => { status => 'pass', schema_versions_after => 36 },
    dump_restore  =>
      { status => 'pass', schema_versions => 36, users => 5, threads => 12 },
    attachments => { covered => \0, storage_root => 'var/attachments' },
};
my $human = $service->format_evidence( $evidence, 'human' );
like(
    $human,
    qr/staging-drill [ ] status=pass/msx,
    'human evidence status line'
);

1;
