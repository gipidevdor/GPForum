# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use DBI;
use Const::Fast;
use POSIX   qw(strftime);
use Carp    qw(carp);
use English qw(-no_match_vars);
use Test::More;
use Test::Mojo;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Schema;
use GPForum::Service::Password;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Service::Operations::MetricsSnapshot;
use GPForum::Service::Operations::Readiness;
use GPForum::Service::Operations::RetentionStore;
use GPForum::Service::Portability::ExportBundleBuilder;
use GPForum::Service::Portability::ImportJobStore;
use GPForum::Service::Portability::LegacyIdMapper;
use GPForum::Service::Privacy::Workflow;
use GPForum::Service::Privacy::DataRightsReview;
use GPForum::Service::Privacy::DeletionWorkflow;
use GPForum::Service::Privacy::RetentionHoldStore;
use GPForum::Service::Plugin::Registry;
use GPForum::Service::Plugin::HookDispatcher;
use GPForum::Service::Plugin::FailureRecorder;
use GPForum::Service::Outbox::Dispatcher;
use GPForum::Service::Projection::OffsetTracker;
use GPForum::Service::Projection::GenerationManager;
use GPForum::Worker::EventIdempotencyStore;
use GPForum::Service::Attachment::IntentBuilder;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Moderation::ReportStore;
use GPForum::Test::OutboxTransport;
use GPForum::Test::OutboxClock;
use GPForum::Service::Operations::ApiRole;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $HTTP_OK     => 200;
const my $CLAIM_DELAY => 60;
const my $CLAIM_END   => 120;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to test the separate API role';
}

my $database  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $admin     = $database->dbh;
my $owner     = "gpf_api_owner_$PROCESS_ID";
my $runtime   = "gpf_api_runtime_$PROCESS_ID";
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my $connection;
my $role_schema;

END {
    if ($role_schema) { $role_schema->storage->disconnect; }
    if ($connection)  { $connection->disconnect; }
    if ( $admin && $admin->{Active} ) {
        for my $role ( $runtime, $owner ) {
            try {
                $admin->do(
                    'DROP OWNED BY ' . $admin->quote_identifier($role) );
                $admin->do(
                    'DROP ROLE IF EXISTS ' . $admin->quote_identifier($role) );
            }
            catch ($error) { carp $error; };
        }
    }
}

for my $role ( $owner, $runtime ) {
    $admin->do( 'CREATE ROLE '
          . $admin->quote_identifier($role)
          . ' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT'
    );
}
my $roles = GPForum::Service::Operations::ApiRole->new( dbh => $admin );
my $rejected;
try { $roles->provision($runtime); }
catch ($error) { $rejected = "$error"; };
like(
    $rejected,
    qr/administrative[ ]owner/msx,
    'superuser-owned definer entry points are refused'
);

# Give a plain migration role the same data and implementation rights its
# production ownership provides, keeping the test harness's owner unchanged.
my $quoted_owner = $admin->quote_identifier($owner);
$admin->do("GRANT USAGE ON SCHEMA api, public TO $quoted_owner");
$admin->do("GRANT ALL ON ALL TABLES IN SCHEMA public TO $quoted_owner");
$admin->do("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $quoted_owner");
$admin->do(
    "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api, public TO $quoted_owner");
for my $name ( @{ $catalogue->names } ) {
    my $entry = $catalogue->function($name);
    $admin->do( 'ALTER FUNCTION '
          . $entry->{function} . '('
          . join( ', ', @{ $entry->{types} } )
          . ") OWNER TO $quoted_owner" );
}
my ( $thread, $user ) = $admin->selectrow_array(
    'SELECT thread_id, author_user_id FROM threads ORDER BY thread_id LIMIT 1');
my $configured = $roles->provision($runtime);
is(
    $configured->{functions},
    scalar @{ $catalogue->names },
    'only catalogued boundaries are granted'
);
$connection = DBI->connect( $database->dsn, $runtime, q{},
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
is( scalar $connection->selectrow_array('SELECT current_user'),
    $runtime, 'a separate runtime login connects' );

$role_schema = GPForum::Schema->connect( $database->dsn, $runtime, q{},
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
my $functions = GPForum::Infrastructure::SqlFunction->for_schema($role_schema);
is(
    $functions->row( 'forum_thread_page_head', { thread_id => $thread } )
      ->{thread_id},
    $thread,
    'a real application function reads through the restricted login'
);
ok(
    $functions->row( 'forum_resolve_viewer', { user_id => $user } )->{status},
    'request viewer resolution works without direct table rights'
);
ok(
    $functions->row( 'moderation_can_participate',
        { user_id => $user, now => '2026-10-11T12:00:00Z' } )->{ok},
    'participation checks work through the API'
);
my $bucket = $functions->row(
    'ops_rate_limit_check',
    {
        scope          => 'role-test',
        actor_hash     => 'actor',
        action         => 'read',
        window_start   => '2026-10-11T12:00:00Z',
        window_seconds => 60,
        limit          => 3,
        now            => '2026-10-11T12:00:01Z',
        expires_at     => '2026-10-11T12:01:00Z',
    }
);
ok( $bucket, 'a write executes with the boundary owner rights' );

# Exercise the service graph using only the separate runtime login. A direct
# table fallback anywhere in these workflows fails with PostgreSQL permission.
my $imports =
  GPForum::Service::Portability::ImportJobStore->new( schema => $role_schema );
my $imported = $imports->create_job(
    {
        actor_user_id => $user,
        manifest      => {
            source_system  => 'role-fixture',
            source_version => '1',
            adapter_name   => 'fixture',
            dry_run        => 1,
            records => { users => 1, categories => 1, threads => 1, posts => 1 }
        }
    }
);
ok( $imported->{ok},
    'import validation and persistence work through runtime login' );
my $job = $imported->{job}{import_job_id};
ok( $imports->update_progress( $job, { posts => 1 } ),
    'import progress uses the API' );
my $failed = $imports->record_failure(
    {
        import_job_id      => $job,
        source_record_type => 'post',
        source_record_id   => 'old-1',
        error_code         => 'invalid',
        error_message      => 'missing body'
    }
);
ok( $failed->{import_failure_id}, 'import failure persistence uses the API' );
my $mapper =
  GPForum::Service::Portability::LegacyIdMapper->new( schema => $role_schema );
my $mapped = $mapper->map_identifier(
    {
        import_job_id => $job,
        legacy_type   => 'thread',
        legacy_id     => 'old-thread',
        native_type   => 'thread',
        native_id     => $thread,
        visibility    => 'public',
        canonical_url => '/t/fixture'
    }
);
ok( $mapped->{legacy_id_map_id}, 'legacy mapping writes through the API' );
is( $mapper->find_native( 'thread', 'old-thread' )->get_column('native_id'),
    $thread, 'legacy mapping reads through the API' );

my $registry =
  GPForum::Service::Plugin::Registry->new( schema => $role_schema );
my $installed = $registry->install(
    {
        name                     => 'runtime-test',
        version                  => '1',
        author                   => 'Fixture',
        compatible_gpforum_range => '>=0.1',
        capabilities             => [],
        required_permissions     => [],
        hooks => [ { hook_name => 'post.created', callback_name => 'observe' } ]
    }
);
ok( $installed->{ok},
    'plugin and hook install atomically through runtime login' );
my $plugin = $installed->{plugin}{plugin_id};
is( $registry->enable($plugin)->{status},
    'enabled', 'plugin status writes through the API' );
my $hooks = GPForum::Service::Plugin::HookDispatcher->new(
    schema           => $role_schema,
    failure_recorder =>
      GPForum::Service::Plugin::FailureRecorder->new( schema => $role_schema )
);
my $hook_result = $hooks->dispatch( 'post.created', {} );
is( $hook_result->{results}[0]{failure}{error_class},
    'missing_handler', 'plugin hook reads and failure recording use the API' );

my $reports =
  GPForum::Service::Moderation::ReportStore->new( schema => $role_schema );
my $reported = $reports->create_report(
    {
        reporter_user_id => $user,
        target_type      => 'thread',
        target_id        => $thread,
        reason           => 'role test'
    }
);
ok( $reported->{report_id},
    'moderation report and its durable records use the API' );
my $intent = GPForum::Service::Attachment::IntentBuilder->new->build_intent(
    {
        owner_user_id     => $user,
        byte_size         => 1,
        checksum          => 'role-fixture',
        media_type        => 'text/plain',
        original_filename => 'fixture.txt'
    }
);
my $attachment_store =
  GPForum::Service::Attachment::Store->new( schema => $role_schema );
ok(
    $attachment_store->create_intent($intent)->{ok},
    'attachment intent and durable records use the API'
);
is(
    $attachment_store->find_attachment( $intent->{attachment_id} )
      ->get_column('state'),
    'intent',
    'attachment read uses the API'
);

my $privacy = GPForum::Service::Privacy::Workflow->new(
    command_idempotency =>
      GPForum::Service::Operations::CommandIdempotency->new(
        schema => $role_schema
      ),
    export_builder => GPForum::Service::Portability::ExportBundleBuilder->new(
        schema => $role_schema
    ),
    deletion_workflow => GPForum::Service::Privacy::DeletionWorkflow->new(
        schema => $role_schema
    ),
    hold_store => GPForum::Service::Privacy::RetentionHoldStore->new(
        schema => $role_schema
    ),
    reviewer => GPForum::Service::Privacy::DataRightsReview->new(
        schema => $role_schema
    )
);
my $exported = $privacy->request_export(
    { user_id => $user, command_id => 'runtime-export' } );
ok( $exported->{ok},
    'privacy export, events, audit and command persistence use the API' );
ok(
    $exported->{stored}{manifest}{profile}{email},
    'export contains the account profile'
);
my $deletion = $privacy->request_deletion(
    {
        user_id    => $user,
        command_id => 'runtime-delete',
        reason     => 'erase fixture'
    }
);
ok( $deletion->{ok}, 'deletion request and command persistence use the API' );
my $approved = $privacy->approve_deletion(
    {
        request_id    => $deletion->{stored}{deletion_request_id},
        actor_user_id => $user,
        command_id    => 'runtime-approve',
        reason        => 'confirmed'
    }
);
ok( $approved->{ok}, 'deletion approval and job scheduling use the API' );
my $erased = $privacy->run_erasure_job(
    {
        job_id        => $approved->{stored}{job}{erasure_job_id},
        actor_user_id => $user,
        command_id    => 'runtime-erase'
    }
);
ok( $erased->{ok}, 'account anonymization and export removal use the API' );
my $replayed = $privacy->request_export(
    { user_id => $user, command_id => 'runtime-export' } );
ok( $replayed->{ok}, 'erased export command remains replayable' );
ok(
    !exists $replayed->{stored}{manifest},
    'replayed export no longer contains erased data'
);

my $transport  = GPForum::Test::OutboxTransport->new;
my $dispatched = GPForum::Service::Outbox::Dispatcher->new(
    schema    => $role_schema,
    transport => $transport,
    worker_id => 'runtime-test',
    clock     => GPForum::Test::OutboxClock->new(
        now => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( time + $CLAIM_DELAY ) ),
        future => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( time + $CLAIM_END ) )
    ),
)->dispatch_pending(1);
is( $dispatched->{acknowledged},
    1, 'outbox claim, renewal and acknowledgement use the API' );
my ( $event_id, $event_created ) = $admin->selectrow_array(
'SELECT event_id,created_at FROM event_log ORDER BY created_at,event_id LIMIT 1'
);
my $worker_claims =
  GPForum::Worker::EventIdempotencyStore->new( schema => $role_schema );
my $worker_key = 'runtime-handler:' . $event_id;
ok( $worker_claims->begin( $worker_key, $event_id ),
    'worker claim uses the API' );
ok(
    !$worker_claims->begin( $worker_key, $event_id ),
    'a live worker claim excludes a second worker'
);
$worker_claims->mark_done( $worker_key, { event_id => $event_id } );
ok(
    $worker_claims->is_done($worker_key),
    'worker completion reads through the API'
);
my $offsets =
  GPForum::Service::Projection::OffsetTracker->new( schema => $role_schema );
my $source_event =
  { event_id => $event_id, event_created_at => $event_created };
is(
    $offsets->record_progress( 'runtime-projection', $source_event )
      ->{last_event_id},
    $event_id,
    'projection offset writes through the API'
);
ok(
    $offsets->record_progress( 'runtime-projection', $source_event )->{skipped},
    'repeated projection progress does not write again'
);
$offsets->mark_failed('runtime-projection');
is( $offsets->observe_lag('runtime-projection')->{status},
    'failed', 'projection failure and lag reads use the API' );
my $generations = GPForum::Service::Projection::GenerationManager->new(
    schema => $role_schema );
my $generation =
  $generations->start_generation( 'runtime-projection', $source_event );
is( $generations->mark_ready( $generation->{generation_id} )->{status},
    'ready', 'projection generation readiness uses the API' );
is(
    $generations->activate_generation( $generation->{generation_id} )->{status},
    'active',
    'projection activation uses the API'
);
ok(
    $generations->activate_generation( $generation->{generation_id} )
      ->{skipped},
    'projection activation replay does not write again'
);

my $retention =
  GPForum::Service::Operations::RetentionStore->new( schema => $role_schema );
ok( defined $retention->purge_sessions( { limit => 1 } )->{deleted},
    'retention purge uses the API' );
my $metrics =
  GPForum::Service::Operations::MetricsSnapshot->new( schema => $role_schema )
  ->collect;
is( $metrics->{database}{status},
    'ok', 'metrics collection connects with runtime credentials' );
ok(
    exists $metrics->{outbox}{pending},
    'metrics counts the outbox through the API'
);
my $ready =
  GPForum::Service::Operations::Readiness->new( schema => $role_schema )->check;
my %check = map { $_->{name} => $_ } @{ $ready->{checks} };
is( $check{database}{status},
    'ok', 'readiness connects with runtime credentials' );
is( $check{eventlog}{status}, 'ok', 'readiness table checks use the API' );

_runtime_web();

for my $sql (
    'SELECT * FROM public.users',
    'SELECT username FROM public.users',
'INSERT INTO public.users(id, username, display_name, email_normalized, password_hash) SELECT id, username, display_name, email_normalized, password_hash FROM public.users WHERE false',
    'UPDATE public.users SET display_name = display_name WHERE false',
    'DELETE FROM public.users WHERE false',
    'TRUNCATE public.rate_limit_buckets',
    'COPY public.users TO STDOUT',
    'CREATE TABLE public.api_role_bypass(id integer)',
    'CREATE TABLE api.api_role_bypass(id integer)',
    'CREATE TEMP TABLE api_role_bypass(id integer)',
    'SELECT api.core_canonical_json_v1(\'{}\'::jsonb)',
    'SELECT * FROM api.forum_thread_page_head_v1(NULL::uuid)',
    "SET ROLE $quoted_owner",
  )
{
    my $error;
    try { $connection->do($sql); }
    catch ($caught) { $error = "$caught"; };
    like( $error, qr/permission[ ]denied/msxi, "$sql is denied by PostgreSQL" );
}

# NOINHERIT alone does not prevent SET ROLE. Provisioning refuses membership.
$role_schema->storage->disconnect;
$connection->disconnect;
$admin->do( "GRANT $quoted_owner TO " . $admin->quote_identifier($runtime) );
$rejected = undef;
try { $roles->provision($runtime); }
catch ($error) { $rejected = "$error"; };
like(
    $rejected,
    qr/member[ ]of[ ]another[ ]role/msx,
    'membership cannot bypass the function boundary'
);
$admin->do( "REVOKE $quoted_owner FROM " . $admin->quote_identifier($runtime) );

done_testing();

sub _runtime_web {

    # Password-bearing fixtures are administrative setup; the app below uses
    # the restricted credentials for both authentication and every page.
    my $username = 'runtime_web_member';
    my $password = 'correct horse battery staple';
    my $hash     = GPForum::Service::Password->new->hash_password($password);
    my ($member) = $admin->selectrow_array(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status) VALUES(gen_random_uuid(),?,'Runtime member','runtime-web@example.test',?,'active') RETURNING id},
        undef, $username, $hash
    );
    $admin->do(
q{INSERT INTO credentials(id,user_id,type,secret_hash) VALUES(gen_random_uuid(),?,'password',?)},
        undef, $member, $hash
    );
    local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
    local $ENV{GPFORUM_DATABASE_USER}             = $runtime;
    local $ENV{GPFORUM_DATABASE_PASSWORD}         = q{};
    local $ENV{GPFORUM_MINION_ENABLED}            = 0;
    local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
    my $web = Test::Mojo->new('GPForum');
    $web->get_ok(q{/})
      ->status_is( $HTTP_OK, 'forum listing uses runtime credentials' );
    $web->get_ok('/login')->status_is($HTTP_OK);
    my $form = $web->tx->res->dom;
    $web->post_ok(
        '/login' => form => {
            command_id => $form->at('input[name=command_id]')->attr('value'),
            csrf_token => $form->at('input[name=csrf_token]')->attr('value'),
            identifier => $username,
            password   => $password
        }
    );
    $web->get_ok('/settings')
      ->status_is( $HTTP_OK,
        'authentication and session validation use runtime credentials' );
    $web->get_ok('/notifications')
      ->status_is( $HTTP_OK, 'notification listing uses runtime credentials' );
    $web->get_ok('/privacy')
      ->status_is( $HTTP_OK, 'privacy dashboard uses runtime credentials' );
    is(
        scalar $admin->selectrow_array(
            'SELECT count(*) FROM sessions WHERE user_id=?',
            undef, $member
        ),
        1,
        'the web login persisted exactly one session'
    );
    my $web_schema = $web->app->gp_schema;
    $web_schema->storage->disconnect;
    return;
}

1;
