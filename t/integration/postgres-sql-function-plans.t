# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::QueryPlanEndpoints qw(function_endpoint_names);
use GPForum::Command::QueryPlanEvidence;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $THREAD_ID        => '018f1004-0001-7000-8000-000000000001';
const my $CATEGORY_ID      => '018f1001-0001-7000-8000-000000000001';
const my $AUTHOR_ID        => '018f1002-0002-7000-8000-000000000002';
const my $SEEDED_POSTS     => 8;
const my $THREAD_POSTS     => 3_000;
const my $CATEGORY_THREADS => 1_500;
const my $DEEP_ENOUGH      => 700;
const my $MIGRATION =>
  'migrations/002-function-api/053_forum_thread_page_functions.sql';
const my $LIST_MIGRATION =>
  'migrations/002-function-api/056_forum_read_functions.sql';
const my $KEYSET_BOUND =>
  qr/\n [ ]+ AND [ ] me[.]position [ ] >= [ ] p_after_position/msx;

const my $POSTS_SQL => join q{ },
  q{INSERT INTO posts (post_id, thread_id, author_user_id, position)},
  q{SELECT gen_random_uuid(), ?, ?, n},
  q{FROM generate_series(?::bigint, ?::bigint) AS n};
const my $THREADS_SQL => join q{ },
  q{INSERT INTO threads (thread_id, category_id, author_user_id, title, slug,},
  q{last_activity_at) SELECT gen_random_uuid(), ?, ?, 'Depth ' || n,},
  q{'depth-' || n,},
  q{timestamptz '2026-01-01 00:00:00+00' + n * interval '1 minute'},
  q{FROM generate_series(1, ?::integer) AS n};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to judge the functions\' plans';
}

# ADR 0126, section 9: the plan gate judges the statements a function runs,
# which EXPLAIN cannot reach from outside it. auto_explain logs their plans
# inside the reader's own call, and the gate's rules apply to each, on the
# deep pages of t/integration/postgres-query-plan-depth.t: halfway down a
# 3,000-post thread, signed in and not, against PostgreSQL's planner.
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
$dbh->do(
    $POSTS_SQL, undef, $THREAD_ID, $AUTHOR_ID,
    $SEEDED_POSTS + 1,
    $SEEDED_POSTS + $THREAD_POSTS
);
$dbh->do( $THREADS_SQL, undef, $CATEGORY_ID, $AUTHOR_ID, $CATEGORY_THREADS );
$dbh->do('ANALYZE');

my $command =
  GPForum::Command::QueryPlanEvidence->new( schema => $database->schema );
my %report = _reports( $command, function_endpoint_names() );
for my $endpoint ( function_endpoint_names() ) {
    is( $report{$endpoint}{status}, 'ok', "$endpoint passes the plan gate" )
      or diag explain $report{$endpoint};
    cmp_ok( $report{$endpoint}{summary}{nested_statements},
        q{>=}, 1, "$endpoint: the plans inside the function were read" );
    is(
        scalar @{ $report{$endpoint}{summary}{statements} },
        $report{$endpoint}{summary}{nested_statements},
        "$endpoint: each nested statement has separate resource observations"
    );
}
for my $endpoint ( grep { /_deep/msx } function_endpoint_names() ) {
    cmp_ok( $report{$endpoint}{summary}{depth}{rows_before_cursor},
        q{>}, $DEEP_ENOUGH, "$endpoint pages deep into the thread" );
    is_deeply(
        [
            grep { /shallow_page|no_deep_page|unmeasured/msx }
              @{ $report{$endpoint}{warnings} }
        ],
        [],
        "$endpoint measures what its page filtered"
    );
}
is( $report{thread_view_function}{summary}{root_node},
    'Limit', 'the plan judged is the branch\'s, not the call\'s' );
my $observations = $report{thread_view_function}{summary}{statements};
ok(
    ( grep { defined $_->{shared_hit} } @{$observations} ),
    'actual nested thread-page buffer use is measured'
);
ok(
    ( grep { defined $_->{actual_time_ms} } @{$observations} ),
    'per-node timing remains measured for the established summary'
);
is_deeply( [ grep { defined $_->{planning_time_ms} } @{$observations} ],
    [], 'auto_explain does not report or invent planning-time measurements' );
for my $row ( @{$observations} ) {
    my @sensitive = grep { /Query [ ] Text|Filter|Parameters|Plans/msx }
      keys %{$row};
    is( scalar @sensitive,
        0, 'nested resource observations exclude SQL and predicates' );
}
my $not_analyzed = $command->evidence_report(
    { analyze => 0, dry_run => 0, endpoints => ['thread_view_function'] } );
my $not_measured = $not_analyzed->{endpoints}[0]{summary}{statements};
is_deeply(
    [
        grep {
                 defined $_->{actual_time_ms}
              || defined $_->{shared_hit}
              || defined $_->{wal_bytes}
        } @{$not_measured}
    ],
    [],
    'without ANALYZE, execution, buffers and WAL remain explicitly unmeasured'
);

# The function's posts statement without the keyset's bound on the
# position, the lexicographic OR alone, in this database only: the gate has
# to fail its deep pages, which read their way to the cursor.
my $regressed = path($MIGRATION)->slurp;
my $start = index $regressed, 'CREATE FUNCTION api.forum_thread_page_posts_v1';
my $end   = index $regressed, "\n\$\$;", $start;
my $posts = substr $regressed, $start, $end - $start + length "\n\$\$;";
ok( $posts =~ $KEYSET_BOUND, 'the function bounds its keyset' );
$posts =~ s/$KEYSET_BOUND//gmsx;
$posts =~ s/\A CREATE [ ] FUNCTION/CREATE OR REPLACE FUNCTION/msx;
$dbh->do($posts);
my %unbounded = _reports( $command,
    qw(thread_view_function_deep thread_view_function_deep_signed_in) );

for my $endpoint ( sort keys %unbounded ) {
    like(
        join( q{,}, @{ $unbounded{$endpoint}{violations} } ),
        qr/filter_grows_with_depth/msx,
        "an unbounded keyset in the function fails $endpoint"
    );
}

# The category and latest-thread functions must retain the bounded keysets
# too, including the independently limited live/deleted category scans.
# Replace only functions in this disposable database to prove their deep
# gates reject the same regression the original resultset tests reject.
my $lists = path($LIST_MIGRATION)->slurp;
for my $name (qw(forum_list_category_threads forum_list_public_threads)) {
    my $first           = index $lists, "CREATE FUNCTION api.${name}_v1";
    my $end_of_function = index $lists, "\n\$\$;", $first;
    my $body            = substr $lists, $first,
      $end_of_function - $first + length "\n\$\$;";
    $body =~ s/\n [ ]+ AND [ ] me[.]pinned [ ] <= [ ] p_after_pinned//gmsx;
    $body =~
      s/\n [ ]+ AND [ ] me[.]last_activity_at [ ] <= [ ] p_after_activity//gmsx;
    $body =~ s/\A CREATE [ ] FUNCTION/CREATE OR REPLACE FUNCTION/msx;
    $dbh->do($body);
}
my %unbounded_lists = _reports(
    $command,
    qw(home_function_deep category_threads_function_deep
      category_threads_function_deep_signed_in)
);
for my $endpoint ( sort keys %unbounded_lists ) {
    like(
        join( q{,}, @{ $unbounded_lists{$endpoint}{violations} } ),
        qr/filter_grows_with_depth/msx,
        "an unbounded function cursor fails $endpoint"
    );
}

# A role that cannot load auto_explain gets no plans: the endpoint is
# unmeasured, and the report does not pass.
my $role     = "gpf_plan_$PROCESS_ID";
my $password = "plan-$PROCESS_ID";
$dbh->do(qq{CREATE ROLE "$role" LOGIN NOSUPERUSER PASSWORD '$password'});
my $plain = DBI->connect( $database->dsn, $role, $password,
    { AutoCommit => 1, PrintError => 0, RaiseError => 1 } );
my $unmeasured = GPForum::Command::QueryPlanEvidence->new(
    dbh    => $plain,
    schema => $database->schema,
  )
  ->evidence_report(
    { analyze => 1, dry_run => 0, endpoints => ['thread_head_function'] } );
is( $unmeasured->{endpoints}[0]{status},
    'unmeasured', 'without auto_explain the endpoint is unmeasured' );
is(
    $unmeasured->{endpoints}[0]{warnings}[0],
    'auto_explain_unavailable: permission-denied',
    'permission failure has a constant reason without raw driver errors'
);
is( $unmeasured->{status}, 'fail', 'which is never a pass' );
$plain->disconnect;
$dbh->do(qq{DROP ROLE "$role"});

done_testing();

sub _reports ( $evidence, @endpoints ) {
    my $report = $evidence->evidence_report(
        { analyze => 1, dry_run => 0, endpoints => \@endpoints } );

    return map { $_->{endpoint} => $_ } @{ $report->{endpoints} };
}

1;
