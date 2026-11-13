# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The staff pages' reads as the web worker runs them. Without a METHOD_p
# call_p ran each blocking read in a forked child that opened a PostgreSQL
# connection of its own, one child at a time per worker: every moderation
# queue and admin console page paid one to four of them. Each promise read
# here must answer exactly what its blocking read answers, and the pages
# must not reach the fork fallback for them.
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Service::Identity::Admission;
use GPForum::Service::Moderation::ThreadTransfers;
use GPForum::Test::Forks qw(children_during);
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Test::Promise qw(await_result);

our $VERSION = '0.001';
const my $HTTP_OK => 200;
const my $PAGE    => 5;
const my $ACTIONS => 8;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare staff read promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh    = $database->dbh;
my $owner  = seed_id( user => 1 );
my $member = seed_id( user => 3 );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $owner );
    }
);
my $fixture = fixtures();

my $t = Test::Mojo->new('GPForum');
my $c = $t->app->build_controller;
$c->session( user_id => $owner );

subtest 'moderation queues answer what the blocking reads answer' => sub {
    my $reader = $c->gp_moderation_review_reader;
    my $actions =
      same_answer( $reader, 'list_actions', [ { limit => $PAGE } ], 'actions' );
    ok( $actions->{next_cursor}, 'the action history has an older page' );
    same_answer(
        $reader, 'list_actions',
        [ { limit => $PAGE, after => $actions->{next_cursor} } ],
        'actions, second page'
    );
    same_answer(
        $reader, 'list_actions',
        [ { target_type => 'user', target_id => $member } ],
        'actions on one member'
    );
    same_answer( $reader, 'list_suspensions', [undef], 'active suspensions' );
    same_answer(
        $reader, 'list_suspensions',
        [ { status => 'all' } ],
        'every suspension'
    );

    my $reports =
      same_answer( $c->gp_report_store, 'list_queue',
        [ { status => 'open', limit => $PAGE } ],
        'report queue' );
    ok( scalar @{$reports}, 'the report queue lists reports' );
    my $notes = same_answer(
        $c->gp_member_note_store, 'for_reports',
        [ [ map { $_->{report_id} } @{$reports} ] ],
        'member notes beside the reports'
    );
    ok( scalar keys %{$notes}, 'the reports carry their member' );
    same_answer(
        $c->gp_member_note_store, 'for_reports',
        [ ['not-an-id'] ],        'notes for no report'
    );

    same_answer( $c->gp_review_store, 'queue', [$PAGE], 'held posts' );
    same_answer(
        $c->gp_attachment_content_review,
        'queue',
        [ undef, undef ],
        'media review queue'
    );

    my $transfers =
      GPForum::Service::Moderation::ThreadTransfers->new(
        schema => $c->gp_schema );
    is(
        same_answer( $transfers, 'history', [$owner], 'transfer history' )
          ->{status},
        'ok',
        'the owner reads the transfers'
    );
    same_answer( $transfers, 'history', [$member],
        'a member reads no transfers' );
    my $picker = same_answer(
        $transfers, 'picker',
        [ { actor => $owner, source => $fixture->{thread} } ],
        'transfer picker'
    );
    is( $picker->{status}, 'ok', 'the picker reads the source thread' );
    same_answer(
        $transfers, 'picker',
        [ { actor => $owner, after_position => 'x' } ],
        'a refused picker cursor'
    );

    my $automod = $c->gp_automod_store;
    same_answer( $automod, 'words',     [],        'watched words' );
    same_answer( $automod, 'rules_for', [undef],   'rules for no author' );
    same_answer( $automod, 'rules_for', [$member], 'rules for a member' );
};

subtest 'admin console reads answer what the blocking reads answer' => sub {
    my $audit = $c->gp_admin_audit_review;
    same_answer( $audit, 'recent', [ { limit => $PAGE } ], 'recent audit' );
    my $page =
      same_answer( $audit, 'page', [ {}, { limit => 2 } ], 'audit page' );
    ok( $page->{next_cursor}, 'the audit log has an older page' );
    same_answer(
        $audit, 'page',
        [ {}, { limit => 2, after => $page->{next_cursor} } ],
        'audit, second page'
    );

    my $console = $c->gp_admin_console_reader;
    same_answer( $console, 'list_users', [ { limit => $PAGE } ], 'users' );
    same_answer( $console, 'list_users',
        [ { limit => $PAGE, status => 'active' } ],
        'active users' );
    same_answer( $console, 'email_of',   [$owner],               'an address' );
    same_answer( $console, 'async_jobs', [ { limit => $PAGE } ], 'jobs' );

    my $catalog = $c->gp_role_catalog;
    same_answer( $catalog, 'list_roles', [ { limit => $PAGE } ], 'roles' );
    same_answer( $catalog, 'list_permissions', [ { limit => $PAGE } ],
        'permissions' );
    same_answer(
        $c->gp_announcement_store, 'list_announcements',
        [ { limit => $PAGE } ],    'announcements'
    );
    same_answer(
        $c->gp_category_store,  'list_categories',
        [ { limit => $PAGE } ], 'categories'
    );

    my $bans = $c->gp_address_bans;
    ok( scalar @{ same_answer( $bans, 'list', [], 'address bans' ) },
        'the ban is listed' );
    same_answer( $bans, 'address', ['192.0.2.7'],  'an address' );
    same_answer( $bans, 'address', ['no address'], 'no address' );

    same_answer( $c->gp_configuration,  'general_page', [], 'configuration' );
    same_answer( $c->gp_admin_settings, 'view',         [], 'settings' );
    same_answer( $c->gp_admin_diagnostics,
        'overview', [$owner], 'diagnostics overview' );

    my $admission =
      GPForum::Service::Identity::Admission->new( schema => $c->gp_schema );
    is(
        same_answer( $admission, 'overview', [$owner], 'registration' )
          ->{status},
        'ok',
        'the owner reads registration'
    );
    same_answer( $admission, 'overview', [$member],
        'a member reads no registration' );

    my $two_step = $c->gp_second_factor;
    same_answer( $two_step, 'policy', [], 'two-step policy' );
    same_answer( $two_step, 'staff',  [], 'staff two-step' );
};

subtest 'privacy review queues answer what the blocking reads answer' => sub {
    my $review = $c->gp_data_rights_review;
    for my $method (
        qw(active_holds pending_deletion_requests pending_export_requests))
    {
        my $rows =
          same_answer( $review, $method, [ { limit => $PAGE } ], $method );
        ok( scalar @{$rows}, "$method lists the fixture" );
    }
    ok(
        scalar @{
            same_answer(
                $review,                           'erasure_jobs_by_status',
                [ 'pending', { limit => $PAGE } ], 'pending erasure jobs'
            )
        },
        'the pending erasure job is listed'
    );
};

subtest 'staff pages never reach the fork fallback for these reads' => sub {
    my $gui = GPForum::Test::GuiDriver->new( test => $t );
    $gui->install_session;
    $gui->actor($owner);
    my $children = children_during(
        sub {
            for my $path (
                '/moderation/actions', '/moderation/suspensions',
                '/moderation/media',   '/moderation/reports',
                '/moderation/review',  '/moderation/transfers',
                '/admin/address-bans', '/admin/announcements',
                '/admin/audit',        '/admin/automod',
                '/admin/categories',   '/admin/configuration',
                '/admin/privacy',      '/admin/registration',
                '/admin/roles',        '/admin/security',
                '/admin/users',        '/admin/settings',
                '/admin/jobs',         '/admin',
              )
            {
                $t->get_ok($path)->status_is( $HTTP_OK, $path );
            }
        }
    );

    # The console's health block and search status read on pooled
    # connections too; only host probes run in a CPU-only child.
    is_deeply( $children->{other}, [], 'no staff page forked a child' );
};

done_testing;

# Calls METHOD and METHOD_p with the same arguments and compares them.
sub same_answer ( $service, $method, $arguments, $name ) {
    my $async    = $method . '_p';
    my $blocking = $service->$method( @{$arguments} );
    my $promised = await_result( $service->$async( @{$arguments}, undef ) );
    is_deeply( plain($promised), plain($blocking),
        "$name: promise = blocking" );
    return $promised;
}

# Rows are objects of the same classes either way; compare their columns.
sub plain ($value) {
    my $type = ref $value;
    return $value                          if !$type;
    return [ map { plain($_) } @{$value} ] if $type eq 'ARRAY';
    return { map { $_ => plain( $value->{$_} ) } keys %{$value} }
      if $type eq 'HASH' || $value->isa('HASH');
    return "$type";
}

sub fixtures {
    my ($thread) = $dbh->selectrow_array(<<'SQL');
SELECT thread_id FROM threads
WHERE visibility = 'public' AND moderation_state = 'visible'
  AND deleted_at IS NULL ORDER BY thread_id LIMIT 1
SQL
    $dbh->do( <<'SQL', undef, $owner, $member, $ACTIONS );
INSERT INTO moderation_actions
  (moderation_action_id, actor_user_id, action_type, target_type, target_id,
   reason, metadata, created_at)
SELECT gen_random_uuid(), ?, 'user.warned', 'user', ?, 'fixture', '{}'::jsonb,
       now() - n * interval '1 minute'
FROM generate_series(1, ?) n
SQL
    $dbh->do( <<'SQL', undef, $member, $owner );
INSERT INTO suspensions
  (suspension_id, user_id, actor_user_id, reason, valid_from, valid_to, metadata)
VALUES (gen_random_uuid(), ?, ?, 'fixture', now() - interval '1 day',
        now() + interval '1 day', '{}'::jsonb)
SQL
    $dbh->do( <<'SQL', undef, $owner );
INSERT INTO address_bans
  (ban_id, address_range, scope, reason, created_at, created_by_user_id,
   expires_at)
VALUES (gen_random_uuid(), '198.51.100.0/24', 'writes', 'fixture', now(), ?,
        now() + interval '1 day')
SQL
    my ($request) = $dbh->selectrow_array( <<'SQL', undef, $member, $member );
INSERT INTO deletion_requests
  (deletion_request_id, requester_user_id, resource_type, resource_id,
   request_type)
VALUES (gen_random_uuid(), ?, 'user', ?, 'anonymize')
RETURNING deletion_request_id
SQL
    $dbh->do( <<'SQL', undef, $request );
INSERT INTO erasure_jobs (erasure_job_id, deletion_request_id)
VALUES (gen_random_uuid(), ?)
SQL
    $dbh->do( <<'SQL', undef, $member, $member );
INSERT INTO export_requests
  (export_request_id, requester_user_id, subject_user_id, export_type)
VALUES (gen_random_uuid(), ?, ?, 'user_data')
SQL
    $dbh->do( <<'SQL', undef, $member, $owner );
INSERT INTO retention_holds
  (retention_hold_id, resource_type, resource_id, reason, created_by)
VALUES (gen_random_uuid(), 'user', ?, 'fixture', ?)
SQL
    return { thread => $thread };
}

1;
