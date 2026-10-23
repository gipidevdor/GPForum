# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use File::Temp qw(tempdir);
use FindBin;
use JSON::MaybeXS qw(encode_json decode_json);
use Test::More;
use lib "$FindBin::Bin/../script/lib", "$FindBin::Bin/../lib",
  "$FindBin::Bin/lib";
use GPForum::Performance::Operations qw(summarize inventory);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $SAMPLES      => 20;
const my $EXPECTED_P95 => 19;
const my $DB_MS        => .5;
my $directory = tempdir( CLEANUP => 1 );
my $catalogue = inventory();
ok( grep( { $_ eq 'reply_create' } @{ $catalogue->{http} } ),
    'writes are in HTTP inventory' );
ok( grep( { $_ eq 'forum_draft_save' } @{ $catalogue->{sql} } ),
    'drafts are in SQL inventory' );
ok( grep( { $_ eq 'settings_security_confirm' } @{ $catalogue->{http} } ),
    'generated routes are inventoried' );

## no critic (InputOutput::RequireBriefOpen) -- fixture streams several outcomes to one trace
open my $trace, '>', "$directory/samples-123.jsonl"
  or croak 'Cannot create test trace';
for my $latency ( 1 .. $SAMPLES ) {
    print {$trace} encode_json(
        {
            kind       => 'http',
            operation  => 'login_submit',
            outcome    => '302',
            phase      => 'subsequent',
            elapsed_ms => $latency,
            db_ms      => $DB_MS,
            queries    => 2,
            test       => 'login.t'
        }
      )
      . "\n"
      or croak 'Cannot write trace';
}
print {$trace} encode_json(
    {
        kind       => 'sql',
        operation  => 'session_create',
        outcome    => 'exception',
        phase      => 'first',
        elapsed_ms => 2,
        test       => 'login.t'
    }
  )
  . "\n"
  or croak 'Cannot write exception trace';
close $trace or croak 'Cannot close trace';
## use critic
my $report = summarize( $directory,
    { http => [ 'login_submit', 'settings' ], sql => ['session_create'] } );
is( $report->{coverage}{http}{observed}, 1,
    'observed route counts separately' );
is( $report->{coverage}{http}{successful},
    0, 'a redirect alone is never a successful page measurement' );
is( $report->{coverage}{sql}{successful},
    0, 'exceptions do not count as successful SQL' );
is_deeply( $report->{coverage}{http}{missing},
    ['settings'], 'missing routes remain explicit' );
my ($row) = grep { $_->{kind} eq 'http' } @{ $report->{measurements} };
is( $row->{latency}{p95_ms},
    $EXPECTED_P95, 'nearest rank p95 of twenty measurements' );
is( $row->{latency}{p99_ms}, $SAMPLES, 'p99 includes the tail' );
is( $row->{db}{mean_ms},
    $DB_MS, 'SQL time is retained alongside application time' );
is( $row->{low_sample_count}, 0, 'small samples are flagged separately' );

subtest 'probe preserves returns and exceptions and writes forked samples' =>
  sub {
    local $ENV{GPFORUM_BENCHMARK_TRACE_DIR} = $directory;
    with_replaced_subs(
        'GPForum::Infrastructure::SqlFunction',
        {
            _execute => sub ( $, $entry, $bound ) {
                die $bound->[0] if $bound->[0];    ## no critic (ErrorHandling::RequireCarping) -- deliberate exception identity test
                return [ { result => 'private row contents' } ];
            },
        },
        sub {
            require GPForum::Performance::OperationProbe;
            GPForum::Performance::OperationProbe->import;
            my $execute = GPForum::Infrastructure::SqlFunction->can('_execute');
            is_deeply(
                $execute->( undef, { name => 'probe' }, [undef] ),
                [ { result => 'private row contents' } ],
                'same rows returned'
            );
            my $error = bless {}, 'GPForum::Test::ProbeError';
            my $caught;
            try { $execute->( undef, { name => 'probe' }, [$error] ); }
            catch ($failure) { $caught = $failure; };
            is( $caught, $error, 'original exception object survives' );
            my $pid = fork;
            croak 'Cannot fork probe test' if !defined $pid;

            if ( !$pid ) {
                $execute->( undef, { name => 'child' }, [undef] );
                require POSIX;
                POSIX::_exit(0);
            }
            waitpid $pid, 0;
            my $captured =
              summarize( $directory, { sql => [ 'probe', 'child' ] } );
            is( $captured->{coverage}{sql}{observed},
                2, 'child survives _exit without END flushing' );
            my ($first) = grep { $_->{operation} eq 'child' }
              @{ $captured->{measurements} };
            is( $first->{phase}, 'first',
                'forked child starts a fresh measurement series' );
            unlike(
                encode_json($captured),
                qr/private row contents/msx,
                'result contents never recorded'
            );
        }
    );
  };

done_testing();
1;
