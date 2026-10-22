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

# Terminate at the second TRUNCATE, after the first measurement has been
# recorded, without depending on wall-clock timing or a sleep. This is an
# infrastructure interruption, so complete measurements remain usable while
# the overall result fails and only the owned database is dropped.
my $interrupted_pid = open my $interrupted_output, q{-|},
  $EXECUTABLE_NAME, '-Ilib', '-It/lib', '-e',
  _interrupted_after_first_measurement(), q{--},
  qw(--json --messages 100 --workers), '1,2', qw(--repetitions 2);
defined $interrupted_pid or croak "start interrupted benchmark: $OS_ERROR";
my $interrupted_text =
  do { local $INPUT_RECORD_SEPARATOR = undef; <$interrupted_output> };
ok( !close($interrupted_output), 'termination fails the overall benchmark' );
my $interrupted = decode_json($interrupted_text);
is( $interrupted->{status}, 'fail', 'interruption is never reported as PASS' );
like(
    $interrupted->{error},
    qr/outbox[ ]benchmark[ ]interrupted/xms,
    'the caught signal is reported as an infrastructure interruption'
);
is( scalar @{ $interrupted->{results} },
    1, 'the completed measurement survives the following interruption' );
is_deeply(
    [
        @{ $interrupted->{results}[0] }
          {qw(status delivered acknowledged done lost duplicates)}
    ],
    [ 'ok', $MESSAGES, $MESSAGES, $MESSAGES, 0, 0 ],
    'preserved evidence retains every delivery invariant'
);
my ($interrupted_leftover) = $admin->selectrow_array(
    q{SELECT count(*) FROM pg_database WHERE datname LIKE ?},
    undef, "gpforum_conc_${interrupted_pid}_%" );
is( $interrupted_leftover, 0,
    'termination still drops the interrupted subprocess owned database' );
$admin->disconnect;
done_testing();

sub _interrupted_after_first_measurement {
    return <<'PERL';
require DBI;
my $original = DBI::db->can('do');
my $truncates = 0;
{
    no warnings 'redefine';
    *DBI::db::do = sub {
        if ($_[1] eq 'TRUNCATE outbox_messages' && ++$truncates == 2) {
            kill 'TERM', $$ or die 'could not terminate benchmark';
        }
        return $original->(@_);
    };
}
do './script/performance-outbox.pl';
die $@ || $!;
PERL
}

1;
