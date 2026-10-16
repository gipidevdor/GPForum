# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
use File::Spec;
use FindBin;
use POSIX qw(tzset);
use Test::More;
use Time::Local qw(timegm);
our $VERSION = '0.001';

# Workflow contracts run before the locked dependency tree is installed.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    YEAR          => 2026,
    SUNDAY        =>  0,
    THREE_AM      =>  3,
    WEEKDAY_INDEX =>  6,
    NOT_FOUND     => -1,
};

sub source ($name) {
    my $path =
      File::Spec->catfile( $FindBin::Bin, '../../.github/workflows', $name );
    open my $handle, '<', $path or croak "Cannot read workflow: $OS_ERROR";
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> };
    close $handle or croak 'Cannot close workflow';
    return $raw;
}

my $workflow = source('performance-extreme.yml');
my ($triggers) = $workflow =~ /\non:\n(.*?)\npermissions:/msx;
like(
    $triggers,
    qr/^[ ]{2}workflow_dispatch:/msx,
    'extreme accepts manual runs'
);
unlike(
    $triggers,
    qr/^[ ]*(?:push|pull_request|pull_request_target|workflow_run):/msx,
    'no automatic code or privileged PR trigger'
);
like(
    $triggers,
    qr/^[ ]{2}schedule:$/msx,
    'verified Sunday schedule is enabled'
);
like(
    $triggers,
    qr/cron:[ ]'0[ ]3[ ][*][ ][*][ ]0'/msx,
    'one Sunday 03:00 schedule'
);
like(
    $triggers,
    qr/timezone:[ ]Europe\/Rome/msx,
    'native timezone follows DST'
);
my @crons = $triggers =~ /cron:/gmsx;
is( scalar @crons, 1, 'no duplicate UTC schedules' );
like(
    $workflow,
    qr/contents:[ ]read\n[ ]{2}actions:[ ]read/msx,
    'minimum read permissions'
);

for my $forbidden (
    'contents: write', 'services:',
    'git push',        'performance-publish',
    'overwrite:'
  )
{
    is( index( $workflow, $forbidden ),
        NOT_FOUND, "Extreme excludes $forbidden" );
}
my @runners = $workflow =~ /runs-on:/gmsx;
is( scalar @runners, 1, 'single job without combinatorial matrix' );
like( $workflow, qr/runs-on:[ ]ubuntu-26[.]04/msx, 'standard hosted runner' );
like(
    $workflow,
    qr/^[ ]{4}timeout-minutes:[ ]30$/msx,
    'entire job has hard thirty minute limit'
);
like(
    $workflow,
    qr/cancel-in-progress:[ ]false/msx,
    'advanced measurements are not cancelled'
);
like( $workflow, qr/persist-credentials:[ ]false/msx, 'checkout cannot push' );
ok(
    index( $workflow,
        q{gpforum-extreme-${{ github.run_id }}-${{ github.run_attempt }}} ) >=
      0,
    'artifact identity includes distinct attempt'
);
like( $workflow, qr/retention-days:[ ]14/msx, 'bounded artifact retention' );
cmp_ok(
    index( $workflow, 'id: clock' ),
    '<',
    index( $workflow, 'uses: actions/checkout@' ),
    'deadline starts before checkout'
);
like( $workflow, qr/origin[ ][+][ ]1800/msx, 'whole-job deadline recorded' );
like(
    $workflow,
    qr/origin[ ][+][ ]1560/msx,
    'four minutes reserved for evidence and cleanup'
);
like(
    $workflow,
    qr/clock_gettime[(]CLOCK_MONOTONIC[)][ ]-[ ]120/msx,
    'conservative clock fallback'
);
cmp_ok(
    index( $workflow, 'id: cleanup' ),
    '<',
    index( $workflow, 'id: report' ),
    'cleanup precedes report'
);
cmp_ok(
    index( $workflow, 'id: report' ),
    '<',
    index( $workflow, 'uses: actions/upload-artifact@' ),
    'report precedes artifact'
);
like(
    $workflow,
    qr/id:[ ]cleanup\n[ ]+if:[ ]always[(][)]/msx,
    'cleanup always attempted'
);
like(
    $workflow,
    qr/id:[ ]report\n[ ]+if:[ ]always[(][)]/msx,
    'partial report always attempted'
);
like( $workflow, qr/--disposable-database/msx,
    'destructive fixture setup needs explicit ownership' );

for my $action ( $workflow =~ /uses:[ ]+(\S+)/gmsx ) {
    next if index( $action, q{./} ) == 0;
    like( $action, qr/\@[[:xdigit:]]{40}\z/msx, 'remote action is pinned' );
}

my $ordinary = source('performance.yml');
like( $ordinary, qr/^[ ]{2}pull_request:/msx, 'ordinary PR evidence retained' );
like( $ordinary, qr/^[ ]{2}push:/msx, 'ordinary main evidence retained' );
like( $ordinary, qr/performance-publish/msx,
    'ordinary permanent history retained' );
like(
    $ordinary,
    qr/--concurrency[ ]1000,5000[ ]--allow-5000/msx,
    'ordinary CI compares 1000 and 5000 connections on the same runner'
);
ok(
    index( $ordinary,
        'net.core.somaxconn=8192 net.ipv4.tcp_max_syn_backlog=8192' ) >= 0,
    'the runner queues are sized for the full connection burst'
);
ok(
    index( $ordinary,
        '--scenario health_live --workers 4 --duration 10 --repetitions 3' ) >=
      0,
    'the transport capacity test is repeated and identifies its endpoint'
);
ok(
    index( $ordinary, q{PERF_CONNECTIONS: ${{ steps.connections.outcome }}} )
      >= 0,
    'connection test failure reaches the existing CI gate'
);
like(
    $ordinary,
    qr/cp[ ]-a[ ]script\/lib\/GPForum\/Performance/msx,
    'paired baseline receives exactly the head Perl harness'
);

for my $name ( 'ci.yml', 'performance.yml', 'performance-extreme.yml' ) {
    unlike(
        source($name),
        qr/python(?:3)?[ ]|performance[-_]\S*[.]py/msx,
        "$name uses Perl tooling and tests"
    );
}

{
    local $ENV{TZ} = 'Europe/Rome';
    tzset();
    for my $date (qw(01:11:02 03:29:01 07:12:01 10:25:02)) {
        my ( $month, $day, $utc_hour ) = split /:/msx, $date;
        my @local = localtime timegm( 0, 0, $utc_hour, $day, $month - 1, YEAR );
        is( $local[2], THREE_AM,
            "03:00 local on $month/$day including DST boundaries" );
        is( $local[WEEKDAY_INDEX], SUNDAY, 'local execution day is Sunday' );
    }
}
tzset();
done_testing;
1;
