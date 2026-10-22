# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Test::More;
use Test::Exception;
use JSON::PP;
use English qw(-no_match_vars);
use Const::Fast;
use lib 'script/lib';
use GPForum::PostgreSQL::Diagnostics    qw(failure_report collect);
use GPForum::PostgreSQL::DiagnosticsCLI qw(validate_evidence);
use GPForum::Performance::Support       qw(run_bounded read_json);
use GPForum::PostgreSQL::Queries        qw(queries);

our $VERSION = '0.001';
const my $PG_16         => 16;
const my $PG_17         => 17;
const my $PG_18_VERSION => 180_006;

my $failed = failure_report('operator-connection-or-options-failed');
lives_ok { validate_evidence($failed) }
'failed collection remains valid evidence';
is( $failed->{status}, 'fail', 'absence is never a successful inspection' );
my $unmeasured = { %{$failed}, status => 'ok' };
throws_ok { validate_evidence($unmeasured) } qr/no [ ] supported/msx,
  'a successful envelope requires an observed supported server';
my $empty = {
    %{$failed},
    status      => 'ok',
    environment => { version_number => $PG_18_VERSION }
};
throws_ok { validate_evidence($empty) } qr/unmeasured [ ] section/msx,
  'a successful envelope requires all sections';
my $sensitive = { %{$failed}, query => 'private post body' };
throws_ok { validate_evidence($sensitive) } qr/unexpected [ ] query/msx,
  'public schema rejects SQL text at the root';
my $unknown = {
    %{$failed}, sections => { future_section => { status => 'ok', rows => [] } }
};
throws_ok { validate_evidence($unknown) } qr/unexpected [ ] future_section/msx,
  'unknown future data is not silently published';
my $wrong_version = { %{$failed}, schema_version => 2 };
throws_ok { validate_evidence($wrong_version) } qr/invalid [ ] value/msx,
  'schema versions cannot silently drift';

my %environment = %ENV;
delete @environment{
    qw(GPFORUM_DATABASE_DSN GPFORUM_DATABASE_USER GPFORUM_DATABASE_PASSWORD)};
my $raw = run_bounded(
    [ $EXECUTABLE_NAME, 'script/postgres-diagnostics', '--json' ],
    { timeout => 5, accepted_codes => [1], env => \%environment }
);
my $offline = JSON::PP->new->decode($raw);
is( $offline->{status}, 'fail',
    'missing connection returns structured failure and exits nonzero' );
lives_ok { validate_evidence($offline) }
'offline failure validates without DBI';
my $help =
  run_bounded( [ $EXECUTABLE_NAME, 'script/postgres-diagnostics', '--help' ],
    { timeout => 5 } );
like(
    $help,
    qr/SQL [ ] text [ ] and [ ] binds [ ] are [ ] never/msx,
    'operator privacy boundary is explicit'
);

my $old = queries($PG_16)->{checkpoints};
my $new = queries($PG_17)->{checkpoints};
like( $old, qr/pg_stat_bgwriter/msx,
    'PostgreSQL 16 checkpoint counters use the existing view' );
like( $new, qr/pg_stat_checkpointer/msx,
    '17 and 18 use the separated checkpointer view' );

my $schema = read_json('docs/ops/postgres-diagnostics-schema-v1.json');
ok(
    !$schema->{properties}{sections}{properties}{statements}{properties}{rows}
      {items}{additionalProperties},
    'statement rows enforce the public metric allowlist'
);
done_testing;
1;
