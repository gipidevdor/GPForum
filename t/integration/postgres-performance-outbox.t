# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(decode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';
const my $MESSAGES   => 100;
const my $RESULTS    => 4;
const my $EXIT_SHIFT => 8;

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all =>
      'set GPFORUM_DATABASE_DSN for the real outbox worker benchmark';
}

# A one-worker smoke cannot expose a buffered pipe stealing another child's
# start token. Run two real workers too, on the helper's owned database, and
# verify every child's evidence plus final DB state and database cleanup.
my $pid = open my $output, q{-|}, $EXECUTABLE_NAME,
  'script/performance-outbox.pl', '--json', '--messages',    $MESSAGES,
  '--workers',                    '1,2',    '--repetitions', 2;
defined $pid or croak "start benchmark: $OS_ERROR";
my $text   = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
my $closed = close $output;
my $status = $CHILD_ERROR >> $EXIT_SHIFT;
ok( $closed, 'outbox benchmark subprocess succeeds' ) or diag $text;
is( $status, 0, 'outbox benchmark exit status is zero' );
my $report = decode_json($text);
is( $report->{status}, 'ok', 'every owned PostgreSQL run succeeds' );
is( scalar @{ $report->{results} }, $RESULTS, 'both worker counts repeated' );
is_deeply(
    [ map { $_->{workers} } @{ $report->{results} } ],
    [ 1, 2, 2, 1 ],
    'worker order alternates across repetitions'
);

for my $row ( @{ $report->{results} } ) {
    my $label = "workers=$row->{workers} repetition=$row->{repetition}";
    is( $row->{status}, 'ok', "$label produced complete evidence" );
    is_deeply(
        [ @{$row}{qw(delivered acknowledged done lost duplicates)} ],
        [ $MESSAGES, $MESSAGES, $MESSAGES, 0, 0 ],
        "$label preserves delivery and acknowledgement invariants"
    );
    is_deeply( $row->{errors}, [], "$label loses no worker report" );
}

my $admin =
  GPForum::Test::PostgresHarness::connect_dbi( $ENV{GPFORUM_DATABASE_DSN} );
my ($leftover) = $admin->selectrow_array(
    q{SELECT count(*) FROM pg_database WHERE datname LIKE ?},
    undef, "gpforum_conc_${pid}_%" );
is( $leftover, 0, 'the subprocess drops its owned benchmark database' );
$admin->disconnect;
done_testing();

1;
