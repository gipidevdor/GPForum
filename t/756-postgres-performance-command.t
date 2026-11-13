# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::PostgresPerformance;
use GPForum::Config;
use GPForum::Test::PostgresSettingsDbh;

our $VERSION = '0.001';

const my $EXIT_FAILURE => 1;
const my $EXIT_USAGE   => 2;

# gpforum postgres-performance reads its options as every gpforum verb does:
# --output, plan's alone, is refused before anything connects -- apply had
# changed the cluster's settings by the time it said so -- and a relative
# path reads from the directory the command was typed in, not the code
# directory the front door moved to.

delete local $ENV{LANG};
delete local $ENV{LC_ALL};
my $here = path( tempdir( CLEANUP => 1 ) );

my $refused = _run(
    qw(apply --plan plan.json --instance one --controlled-instance),
    qw(--allow work_mem --journal journal.jsonl --output report.json)
);
is( $refused->{status}, $EXIT_USAGE, 'apply with --output is misuse' );
like(
    $refused->{errors},
    qr/\A --output [ ] is [ ] for [ ] plan [ ] only[.]\n/msx,
    'said first, then the usage'
);
ok( !-e $here->child('journal.jsonl'), 'and nothing was applied' );

my $abbreviated = _run(qw(apply --plan plan.json --c));
is( $abbreviated->{status},
    $EXIT_USAGE, 'an abbreviation is not the interlock it shortens' );
like(
    $abbreviated->{errors},
    qr/\A --c [ ] is [ ] not [ ] an [ ] option/msx,
    'it is an option the command does not know'
);

$here->child('plan.json')->spew('{"format":"another"}');
my $read = _run(qw(apply --plan plan.json --instance one));
is( $read->{status}, $EXIT_FAILURE, 'a plan of another format fails' );
like(
    $read->{errors},
    qr/unsupported [ ] plan [ ] format/msx,
    'after the relative --plan was read from where the command was typed'
);

done_testing();

sub _run (@arguments) {
    my $errors = q{};
    my $status;
    {
        open my $stderr, '>', \$errors or croak 'capture stderr';
        local *STDERR = $stderr;
        $status = GPForum::Command::PostgresPerformance->new(
            config    => GPForum::Config->new,
            dbh       => GPForum::Test::PostgresSettingsDbh->new( rows => {} ),
            directory => "$here",
        )->run(@arguments);
        close $stderr or croak 'close stderr';
    }

    return { errors => $errors, status => $status };
}

1;
