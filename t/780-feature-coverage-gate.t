# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::JSON qw(encode_json decode_json);
use IPC::Open3;
use Symbol  qw(gensym);
use Carp    qw(croak);
use English qw(-no_match_vars);
use Const::Fast;
use lib 'script/lib', 't/lib';
use GPForum::Testing::FeatureCoverage;
our $VERSION = '0.001';
const my $EXIT_SHIFT      => 8;
const my $EXECUTABLE_MODE => oct '755';
my $root    = path( tempdir( CLEANUP => 1 ) );
my $traces  = $root->child('traces')->make_path;
my $program = $root->child('feature.t');
$program->spew(<<'PROGRAM');
use v5.40;
use Test::More;
ok(1,'durable postcondition');
subtest 'nested case' => sub {ok(1,'nested postcondition');};
SKIP: {skip 'skipped postcondition',1;}
TODO: {local $TODO='pending';ok(1,'TODO passing postcondition');ok(0,'TODO failing postcondition');}
ok(0,'failed postcondition');
done_testing;
PROGRAM
my @proofs =
  map { { id => $_, test => "$program", text => "$_ postcondition" } }
  qw(durable nested skipped failed);
push @proofs,
  {
    id   => 'todo_pass',
    test => "$program",
    text => 'TODO passing postcondition'
  },
  {
    id   => 'todo_fail',
    test => "$program",
    text => 'TODO failing postcondition'
  };
my $feature = {
    id     => 'example',
    title  => 'Example',
    routes => ['example_route'],
    http   => [ { route => 'example_route', statuses => ['302'] } ],
    proofs => \@proofs
};
my $manifest = $root->child('manifest.json');
$manifest->spew( encode_json( { features => [$feature] } ) );
local $ENV{GPFORUM_FEATURE_MANIFEST}  = "$manifest";
local $ENV{GPFORUM_FEATURE_TRACE_DIR} = "$traces";
my $error = gensym;
my $pid   = open3( my $input, my $output, $error, $EXECUTABLE_NAME, '-It/lib',
    '-MGPForum::Test::FeatureProbe', "$program" );
close $input or croak 'cannot close child input';
my $tap         = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
my $diagnostics = do { local $INPUT_RECORD_SEPARATOR = undef; <$error> };
waitpid $pid, 0;
is( $CHILD_ERROR >> $EXIT_SHIFT,
    1, 'instrumentation preserves intentional child test failure' );
like(
    $tap,
    qr/not[ ]ok[^\n]*failed[ ]postcondition/msx,
    'failure remains in TAP'
);
like( $diagnostics, qr/Failed[ ]test/msx, 'failure diagnostics are preserved' );
my @recorded =
  sort map { decode_json( $_->slurp )->{proof} } $traces->list->each;
is_deeply( \@recorded, [qw(durable nested)],
'only executed successful non-TODO assertions count; skips and failures do not'
);
my $samples = $traces->child('samples-1.jsonl');
$samples->spew(
    encode_json(
        {
            kind      => 'http',
            operation => 'example_route',
            outcome   => '302',
            test      => "$program"
        }
      )
      . "\n"
);
my $report = sub ( $passed = 1, $routes = ['example_route'] ) {
    return GPForum::Testing::FeatureCoverage->report( "$manifest", "$traces",
        $passed, $routes );
};
is( $report->()->{status},
    'fail',
    'a successful HTTP response cannot substitute for missing behavior' );
$feature->{proofs} = [ @proofs[ 0, 1 ] ];
my $save =
  sub { $manifest->spew( encode_json( { features => [$feature] } ) ); };
$save->();
is( $report->()->{status},
    'ok',
    'all declared postconditions and expected HTTP outcomes pass together' );
is( $report->(0)->{status}, 'fail', 'any failing test fails the feature gate' );
is( $report->( 1, [ 'example_route', 'new_route' ] )->{status},
    'fail', 'a new unmapped operation fails closed' );
$samples->spew(
    encode_json(
        {
            kind      => 'http',
            operation => 'example_route',
            outcome   => '500',
            test      => "$program"
        }
      )
      . "\n"
);
is( $report->()->{status},
    'fail', 'an error status does not establish a working operation' );
$samples->spew(
    encode_json(
        {
            kind      => 'http',
            operation => 'example_route',
            outcome   => '302',
            test      => "$program"
        }
      )
      . "\n"
);
$feature->{http} = [];
$save->();
is( $report->()->{status},
    'fail', 'mapping a route without an executed HTTP requirement fails' );
$feature->{http} = [ { route => 'example_route', statuses => ['302'] } ];
$feature->{proofs}[0]{test} = 't/another-test.t';
$save->();
is( $report->()->{status},
    'fail',
    'a proof executed in another test cannot satisfy the declared witness' );
$feature->{proofs} = [];
$save->();
is( $report->()->{status},
    'fail', 'a feature with no behavioral criterion never passes' );
$feature->{routes} = [ 'example_route', 'example_route' ];
$save->();
is( $report->()->{status}, 'fail', 'duplicate route ownership fails closed' );

subtest
'the feature runner discovers integration once and deduplicates unit witnesses'
  => sub {
    my $bin   = $root->child('bin')->make_path;
    my $prove = $bin->child('prove')->spew(<<'PROVE');
use v5.40;
use JSON::MaybeXS;
say JSON::MaybeXS->new->encode({args => \@ARGV,
 database_dsn => $ENV{GPFORUM_DATABASE_DSN}});
exit 0;
PROVE
    chmod $EXECUTABLE_MODE, "$prove"
      or croak 'cannot make runner fixture executable';
    my $runner_manifest = $root->child('runner-manifest.json');
    $runner_manifest->spew(
        encode_json(
            {
                features => [
                    {
                        id     => 'runner',
                        title  => 'Runner',
                        routes => [],
                        http   => [],
                        proofs => [
                            map {
                                {
                                    id   => $_->[0],
                                    test => $_->[1],
                                    text => 'witness'
                                }
                            } [ 'unit-a', 't/unit-witness.t' ],
                            [ 'unit-b', 't/unit-witness.t' ],
                            [
                                'database',
                                't/integration/postgres-new-workflow.t'
                            ]
                        ],
                    },
                ],
            }
        )
    );
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    local $ENV{GPFORUM_DATABASE_DSN} =
      'dbi:Pg:dbname=gpforum_inherited;host=/nonexistent';
    my $destination  = $root->child('runner-output');
    my $runner_error = gensym;
    my $runner       = open3(
        my $runner_input,       my $runner_output,
        $runner_error,          $EXECUTABLE_NAME,
        'script/test-features', '--manifest',
        "$runner_manifest",     '--output',
        "$destination",         '--jobs',
        '2'
    );
    close $runner_input or croak 'cannot close runner input';
    my $result = do { local $INPUT_RECORD_SEPARATOR = undef; <$runner_output> };
    my $details = do { local $INPUT_RECORD_SEPARATOR = undef; <$runner_error> };
    waitpid $runner, 0;
    is(
        $CHILD_ERROR >> $EXIT_SHIFT,
        1,
        'a runner exit success without executed postconditions fails the gate'
    ) or diag $details;
    is( decode_json($result)->{status},
        'fail', 'missing witnesses stay visible' );
    my $invocation = decode_json( $destination->child('tests.log')->slurp );
    my @args       = @{ $invocation->{args} };
    is( scalar( grep { $_ eq 't/integration' } @args ),
        1, 'the complete integration directory is selected once' );
    is( scalar( grep { $_ eq 't/unit-witness.t' } @args ),
        1, 'a shared unit witness is selected once' );
    ok(
        !( grep { $_ eq 't/integration/postgres-new-workflow.t' } @args ),
        'individual integration witnesses do not repeat directory discoveries'
    );
    ok( ( grep { $_ eq '-r' } @args ),
        'new nested integration files are discovered' );
    ok(
        ( grep { /-MGPForum::Test::FeatureBootstrap/msx } @args ),
        'the executed files collect behavioral evidence'
    );
    ok( !defined $invocation->{database_dsn},
        'the default runner removes an inherited database DSN' );
  };
done_testing;
1;
