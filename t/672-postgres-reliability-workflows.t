# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

our $VERSION = '0.001';

const my $MATRIX   => '.github/workflows/postgres-matrix.yml';
const my $OPS      => '.github/workflows/ops-drills.yml';
const my $RECOVERY => '.github/workflows/postgres-recovery.yml';
const my $PINNED_ACTION =>
  qr{uses: [ ] actions/ [\w-]+ [@] [[:xdigit:]]{40} [ ] [#] [ ] v[\d.]+}msx;

my $matrix   = path($MATRIX)->slurp;
my $ops      = path($OPS)->slurp;
my $recovery = path($RECOVERY)->slurp;

like(
    $matrix,
    qr/postgres: [ ] \['16', [ ] '17', [ ] '18'\]/msx,
    'the existing matrix retains all supported PostgreSQL majors'
);
like(
    $matrix,
    qr/run: [ ] make [ ] integration/msx,
    'the matrix still runs the entire deterministic integration tier'
);

# Both push and pull_request must see changes to the SQL consumers and the
# evidence harness, not just a new migration or a manually changed test.
for my $trigger (
    'lib/GPForum/Infrastructure/SqlFunction*',
    'lib/GPForum/Service/Forum/**',
    'lib/GPForum/Service/Search/**',
    'lib/GPForum/Service/Outbox/**',
    'lib/GPForum/Benchmark/PlanRules.pm',
    'lib/GPForum/Command/QueryPlanEvidence.pm',
    'script/query-plan-*',
    'script/postgres-diagnostics',
    'script/lib/GPForum/PostgreSQL/**',
    't/lib/GPForum/Test/PostgresHarness.pm'
  )
{
    my @matches = $matrix =~ /^ [ ]+ - [ ] '\Q$trigger\E' $/gmsx;
    is( scalar @matches, 2, "$trigger triggers both push and PR evidence" );
}

ok(
    index( $matrix,
        q{ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements'} )
      >= 0,
    'the disposable service really preloads pg_stat_statements'
);
like(
    $matrix,
    qr/job[.]services[.]postgres[.]id/msx,
    'only the owned CI service is restarted'
);
like(
    $matrix,
    qr/docker [ ] restart [ ] "[\$]POSTGRES_SERVICE_ID"/msx,
    'preload changes take effect through a real restart'
);
like(
    $matrix,
    qr/for [ ] attempt [ ] in [ ] [{]1[.][.]30[}]/msx,
    'restart readiness has a finite polling limit'
);
like(
    $matrix,
    qr/pg_stat_statements[.]track [ ] = [ ] 'all'/msx,
    'statistics include the statements nested in SQL functions'
);
like(
    $matrix,
    qr/pg_stat_statements[.]track_planning [ ] = [ ] 'on'/msx,
    'the disposable fixture records planning statistics'
);
like(
    $matrix,
    qr/postgres-diagnostics [ ] --json [ ] --require-statements/msx,
    'a missing statistics extension fails CI rather than becoming a pass'
);
like(
    $matrix,
    qr/postgres-diagnostics [ ] --validate/msx,
    'the collected diagnostics are validated against their schema'
);
ok(
    index( $matrix, q{if: always() && steps.migrate.outcome == 'success'} ) >=
      0,
    'diagnostics are retained even after a later deterministic test fails'
);

like(
    $ops,
    qr/lib\/GPForum\/Service\/Operations\/[*][*]/msx,
    'operator changes use the actual Operations namespace'
);
unlike(
    $ops,
    qr/lib\/GPForum\/Service\/Ops\/[*][*]/msx,
    'the nonexistent Ops namespace no longer silently misses changes'
);

for my $client (qw(DUMP RESTORE)) {
    like(
        $ops,
        qr/GPFORUM_PG_\Q$client\E: [ ] \/usr\/lib\/postgresql\/18\/bin\//msx,
        "operator $client uses the server-matching client"
    );
}

like(
    $recovery,
    qr/cron: [ ] '47 [ ] 3 [ ] [*] [ ] [*] [ ] 2'/msx,
    'physical recovery runs weekly on Tuesday rather than on every PR'
);
like( $recovery, qr/workflow_dispatch:/msx,
    'operators can also request the isolated drill manually' );
unlike(
    $recovery,
    qr/^ [ ]{2} (?:push|pull_request|pull_request_target):/msx,
    'physical recovery adds no PR or push matrix'
);
like(
    $recovery,
    qr/options: [ ] \['18', [ ] '17', [ ] '16'\]/msx,
    'manual runs cover any supported server major'
);
like(
    $recovery,
    qr/timeout-minutes: [ ] 15/msx,
    'the whole recovery job has a fifteen-minute hard limit'
);
like(
    $recovery,
    qr/cancel-in-progress: [ ] false/msx,
    'a new request does not cancel an advanced restore'
);
like(
    $recovery,
    qr/pitr-drill [ ] --json [ ] --timeout [ ] 180/msx,
    'the physical restore has an independent three-minute deadline'
);
like( $recovery, qr/pg_verifybackup/msx,
    'server tools include the physical backup integrity verifier' );
ok(
    index( $recovery,
        q{exec env "PATH=/usr/lib/postgresql/${POSTGRES_MAJOR}/bin:$PATH"} ) >=
      0,
    'matching server tools are pinned after the launcher normalizes PATH'
);
ok(
    index(
        $recovery, 'pitr-drill --validate artifacts/postgres-recovery.json'
    ) >= 0,
    'the recovery-specific JSON schema is checked'
);
ok(
    index( $recovery,
        'evidence-validate --strict --human artifacts/postgres-recovery.json' )
      >= 0,
    'generic evidence also checks redaction and unsupported readiness claims'
);
unlike(
    $recovery,
    qr/^ [ ]{4} services:/msx,
'the PITR tool owns its cluster instead of restoring the integration service'
);
unlike(
    $recovery,
    qr/GPFORUM_DATABASE_(?:DSN|PASSWORD)/msx,
    'the restore receives no application database credentials'
);
like(
    $recovery,
    qr/artifacts\/pitr-logs\/[*][.]log/msx,
    'the upload is restricted to sanitized diagnostic logs'
);
unlike(
    $recovery,
    qr/path: [ ] (?:[\$][{][{] [ ] runner[.]temp|artifacts\/)/msx,
    'the upload never recursively includes physical clusters or WAL archives'
);
ok(
    index( $recovery,
        "name: Summarize recovery evidence\n        if: always()" ) >= 0,
    'every outcome, including setup failure, gets a Job Summary'
);
like(
    $recovery,
    qr/No [ ] valid [ ] measurement [ ] was [ ] produced/msx,
    'the summary explicitly distinguishes unmeasured infrastructure failures'
);

for my $workflow ( [ $MATRIX, $matrix ], [ $OPS, $ops ],
    [ $RECOVERY, $recovery ] )
{
    my ( $name, $text ) = @{$workflow};
    like(
        $text,
        qr/permissions: \n [ ]{2} contents: [ ] read/msx,
        "$name grants only read access"
    );
    unlike(
        $text,
        qr/contents: [ ] write|pull-requests: [ ] write/msx,
        "$name grants no write token"
    );
    like(
        $text,
        qr/persist-credentials: [ ] false/msx,
        "$name does not retain the checkout token"
    );
    like(
        $text,
        qr/retention-days: [ ] 14/msx,
        "$name expires bulky evidence after fourteen days"
    );
    like( $text, $PINNED_ACTION, "$name pins external actions to commit SHAs" );
}

# Execute the workflow's real core-Perl summary renderer. A failed setup or
# interrupted report must still render and must never claim a measured pass.
my ($summary_program) =
  $recovery =~ /perl [ ] -MJSON::PP [ ] -e [ ] ' \n (.*?) \n [ ]+ ' [ ] >>/msx;
ok( defined $summary_program, 'the actual recovery summary renderer is found' );
for my $case (
    [ 'setup failed', undef, 'skipped', 'No valid measurement was produced' ],
    [ 'measured pass',    '{"status":"pass"}', 'success', 'status: **pass**' ],
    [ 'measured failure', '{"status":"fail"}', 'failure', 'status: **fail**' ],
    [
        'interrupted report', '{',
        'failure',            'No valid measurement was produced'
    ],
    [ 'array report',  '[]', 'failure', 'No valid measurement was produced' ],
    [ 'scalar report', '1',  'failure', 'No valid measurement was produced' ]
  )
{
    my ( $name, $json, $outcome, $expected ) = @{$case};
    my ( $finished, $summary ) = _summary( $summary_program, $json, $outcome );
    ok( $finished,                         "$name still produces a summary" );
    ok( index( $summary, $expected ) >= 0, "$name reports its actual outcome" );
}

done_testing();

sub _summary ( $program, $json, $outcome ) {
    my $fixture = tempdir( CLEANUP => 1 );
    if ( defined $json ) {
        path( $fixture, 'artifacts' )->make_path;
        path( $fixture, 'artifacts', 'postgres-recovery.json' )->spew($json);
    }
    local $ENV{ANALYZED_COMMIT}  = 'fixture-commit';
    local $ENV{POSTGRES_MAJOR}   = '18';
    local $ENV{RUNNER_NAME}      = 'fixture-runner';
    local $ENV{RUNNER_OS}        = 'Linux';
    local $ENV{DRILL_OUTCOME}    = $outcome;
    local $ENV{VALIDATE_OUTCOME} = $outcome;
    local $ENV{ARTIFACT_URL}     = 'https://example.invalid/artifact';
    local $ENV{RUN_URL}          = 'https://example.invalid/run';

    my $source = 'chdir $ARGV[0] or die "cannot enter fixture";' . $program;
    open my $pipe, q{-|}, $EXECUTABLE_NAME, '-MJSON::PP', '-e', $source,
      $fixture
      or croak 'cannot execute the recovery summary renderer';
    local $INPUT_RECORD_SEPARATOR = undef;
    my $summary  = readline $pipe;
    my $finished = close $pipe;

    return ( $finished, $summary // q{} );
}

1;
