# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use File::Temp;
use Test::More;
use Test::Mojo;
use Email::Sender::Transport::Test;
use lib 'lib', 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Config;
use GPForum::Service::Forum::ThreadTags;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Admin::Diagnostics;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Discovery::WebSub;
use GPForum::Test::Antivirus;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Test::ProtocolFixture;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';
const my $HTTP_FOUND    => 302;
const my $HTTP_OK       => 200;
const my $HTTP_ACCEPTED => 202;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_SECURITY_CONTACT}          = 'mailto:security@example.org';
my $dbh   = $database->dbh;
my $admin = seed_id( user => 1 );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $admin );
    }
);
my $t   = Test::Mojo->new('GPForum');
my $gui = GPForum::Test::GuiDriver->new( test => $t );
$gui->install_session;
$gui->actor($admin);
subtest 'feature: report assignment release and resolution persist' => sub {
    my ($report) = $dbh->selectrow_array(
        q{SELECT report_id FROM reports WHERE status='open' LIMIT 1});
    my $base = '/moderation/reports/' . $report;
    $gui->visit('/moderation/reports')
      ->submit( 'form[action="' . $base . '/assign"]' );
    is(
        $dbh->selectrow_array(
            'SELECT assigned_moderator_user_id FROM reports WHERE report_id=?',
            undef,
            $report
        ),
        $admin,
        'GUI assignment persists the moderator'
    );
    $gui->visit('/moderation/reports')
      ->submit( 'form[action="' . $base . '/release"]' );
    is(
        $dbh->selectrow_array(
            'SELECT assigned_moderator_user_id FROM reports WHERE report_id=?',
            undef,
            $report
        ),
        undef,
        'GUI release clears the moderator'
    );
    $gui->visit('/moderation/reports')->submit(
        'form[action="' . $base . '/resolve"]',
        { resolution => 'no_action' }
    );
    is(
        $dbh->selectrow_array(
            'SELECT status FROM reports WHERE report_id=?',
            undef, $report
        ),
        'resolved',
        'GUI resolution closes the report'
    );
};
subtest 'feature: a moderation action can be reversed from its history' => sub {
    my ($thread) = $dbh->selectrow_array(
q{SELECT thread_id FROM threads WHERE moderation_state='visible' AND deleted_at IS NULL LIMIT 1}
    );
    $gui->visit( '/t/' . $thread )
      ->submit( 'form[action="/moderation/threads/' . $thread . '/hide"]',
        { reason => 'GUI hide with appeal' } );
    my ($action) = $dbh->selectrow_array(
q{SELECT moderation_action_id FROM moderation_actions WHERE target_id=? AND action_type='thread.hidden' ORDER BY created_at DESC LIMIT 1},
        undef, $thread
    );
    ok( $action, 'GUI hide writes its reversible action' );
    $gui->visit('/moderation/actions')
      ->submit( 'form[action="/moderation/actions/' . $action . '/reverse"]',
        { reason => 'GUI appeal upheld' } );
    is(
        $dbh->selectrow_array(
'SELECT reversed_by_user_id FROM moderation_actions WHERE moderation_action_id=?',
            undef,
            $action
        ),
        $admin,
        'GUI reversal records the reviewing moderator'
    );
    ok(
        $dbh->selectrow_array(
'SELECT reversed_at IS NOT NULL FROM moderation_actions WHERE moderation_action_id=?',
            undef,
            $action
        ),
        'GUI reversal records its timestamp'
    );
};
subtest 'feature: moving selected posts can be undone through its history' =>
  sub {
    my $ids     = GPForum::Infrastructure::Id->new;
    my @threads = ( $ids->uuid, $ids->uuid );
    for my $thread (@threads) {
        $dbh->do(
q{INSERT INTO threads(thread_id,category_id,author_user_id,title,slug) VALUES(?,?,?,'GUI transfer fixture','gui-transfer')},
            undef, $thread, seed_id( category => 1 ), $admin
        );
        for my $position ( 1 .. 2 ) {
            $dbh->do(
q{INSERT INTO posts(post_id,thread_id,author_user_id,position) VALUES(?,?,?,?)},
                undef, $ids->uuid, $thread, $admin, $position
            );
        }
    }
    my ( $post, $number ) = $dbh->selectrow_array(
'SELECT post_id,position FROM posts WHERE thread_id=? AND position>1 ORDER BY position LIMIT 1',
        undef, $threads[0]
    );
    ok( $post, 'transfer fixture contains a reply' );
    $gui->visit( '/moderation/transfers?source=' . $threads[0] )->submit(
        'form[method="post"][action="/moderation/transfers"]',
        {
            source       => $threads[0],
            target       => $threads[1],
            operation    => 'move',
            post_numbers => $number,
            reason       => 'GUI transfer feature'
        },
        $HTTP_FOUND,
        'button[data-transfer-submit]'
    );
    is(
        $dbh->selectrow_array(
            'SELECT thread_id FROM posts WHERE post_id=?',
            undef, $post
        ),
        $threads[1],
        'GUI transfer moves its selected reply'
    );
    my ($transfer) = $dbh->selectrow_array(
'SELECT transfer_id FROM thread_transfers WHERE source_id=? ORDER BY created_at DESC LIMIT 1',
        undef, $threads[0]
    );
    $gui->visit('/moderation/transfers')
      ->submit( 'form[action="/moderation/transfers/' . $transfer . '/undo"]' );
    is(
        $dbh->selectrow_array(
            'SELECT thread_id FROM posts WHERE post_id=?',
            undef, $post
        ),
        $threads[0],
        'GUI transfer undo restores its original discussion'
    );
  };
subtest 'feature: mail and antivirus diagnostics record actual outcomes' =>
  sub {
    my $transport = Email::Sender::Transport::Test->new;
    my $config    = GPForum::Config->new(
        antivirus      => 'clamd',
        mail_transport => 'smtp',
        smtp_host      => 'smtp.example.test'
    );
    my $diagnostics = GPForum::Service::Admin::Diagnostics->new(
        schema    => $database->schema,
        config    => $config,
        antivirus => GPForum::Test::Antivirus->new( detects => qr/EICAR/msx ),
        mailer    => GPForum::Service::Identity::Mailer->new(
            config    => $config,
            transport => $transport
        )
    );
    $t->app->helper( gp_admin_diagnostics => sub { return $diagnostics; } );

    # The diagnostic runs in the bounded child; a parent Perl counter cannot
    # observe its controlled transport. Record actual deliveries through the
    # inherited descriptor, as the query-budget tests do for child queries.
    my $deliveries = File::Temp->new( UNLINK => 1 );
    my $send       = $transport->can('send_email');
    with_replaced_subs(
        'Email::Sender::Transport::Test',
        {
            send_email => sub (@arguments) {
                my $result = $send->(@arguments);
                syswrite( $deliveries, q{x} ) == 1
                  or croak 'cannot record test delivery';
                return $result;
            },
        },
        sub {
            $gui->visit('/admin/settings')
              ->submit('form[action="/admin/mail/test"]');
            return;
        }
    );
    is( -s $deliveries,
        1, 'GUI mail diagnostic delivers exactly one controlled test message' );
    $gui->visit('/admin/settings')
      ->submit('form[action="/admin/antivirus/check"]');
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM audit_log WHERE action='admin.antivirus_checked' AND actor_id=?},
            undef,
            $admin
        ),
        1,
        'GUI antivirus diagnostic persists its audited result'
    );
  };
subtest 'feature: a failed outbox envelope can be replayed from jobs' => sub {
    my $id        = GPForum::Infrastructure::Id->new;
    my $aggregate = $id->uuid;
    GPForum::Infrastructure::EventRecorder->new( schema => $database->schema )
      ->record_event(
        actor_id          => $admin,
        aggregate_id      => $aggregate,
        aggregate_type    => 'category',
        aggregate_version => 1,
        event_type        => 'category.updated',
        idempotency_key   => 'gui-replay:' . $aggregate,
        payload => { category_id => $aggregate, title => 'GUI replay' }
      );
    my $source = $dbh->selectrow_hashref(
q{SELECT o.* FROM outbox_messages o JOIN event_log e USING(event_id) WHERE e.aggregate_id=? LIMIT 1},
        undef, $aggregate
    );
    my $dead = $id->uuid;
    $dbh->do(
q{INSERT INTO dead_letters(dead_letter_id,source_table,source_id,payload,failure_type,retry_count,error_class,error_message) VALUES(?,'outbox_messages',?,?::jsonb,'permanent',1,'ControlledFailure','controlled GUI failure')},
        undef, $dead, $source->{outbox_id}, $source->{payload}
    );
    $dbh->do(
        q{UPDATE outbox_messages SET status='cancelled' WHERE outbox_id=?},
        undef, $source->{outbox_id} );
    $gui->visit('/admin/jobs')
      ->submit( 'form[action="/admin/dead-letters/' . $dead . '/replay"]' );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM outbox_messages WHERE idempotency_key=? AND status='pending'},
            undef,
            'dead-letter-replay:' . $dead
        ),
        1,
        'GUI replay queues one fresh durable envelope'
    );
};
subtest 'feature: public legal discovery and tag resources are reachable' =>
  sub {
    $gui->visit('/legal/notice');
    $t->element_exists('main h1');
    $gui->visit('/.well-known/security.txt');
    $t->content_like(qr/Contact:[ ]mailto:security\@example[.]org/msx);
    $gui->visit('/icon.svg');
    $t->content_like(qr/<svg/msx);
    my ($tagged) = $dbh->selectrow_array(
q{SELECT thread_id FROM threads WHERE title='GUI transfer fixture' LIMIT 1}
    );
    GPForum::Service::Forum::ThreadTags->new( schema => $database->schema )
      ->set_thread_tags( $tagged, 'GUI coverage' );
    $gui->visit('/tags');
    my $document = $t->tx->res->dom;
    my $tag      = $document->at('a[href^="/tags/"]');
    ok( $tag, 'tag discovery exposes its native resource link' );
    $gui->visit( $tag->attr('href') );
  };
subtest 'feature: WebSub forwards only to the configured hub' => sub {
    my $agent = GPForum::Test::ProtocolFixture->new;
    my $hub   = GPForum::Service::Discovery::WebSub->new(
        hub_url => 'https://hub.example.org/',
        topic   => 'https://forum.example.org/feed.atom',
        ua      => $agent
    );
    $t->app->helper( gp_websub => sub { return $hub; } );
    $t->post_ok(
        '/websub' => form => {
            'hub.mode'     => 'subscribe',
            'hub.topic'    => $hub->topic,
            'hub.callback' => 'https://subscriber.example.org/callback'
        }
    )->status_is($HTTP_ACCEPTED);
    is( $agent->{posted_url}, $hub->hub_url,
        'WebSub request reaches the configured hub exclusively' );
};
subtest 'feature: a real socket subscribes to its own notification channel' =>
  sub {
    $gui->actor($admin);
    $t->websocket_ok('/realtime')
      ->message_ok->json_message_is( '/type' => 'realtime.connected' );
    $t->send_ok(
        {
            json =>
              { type => 'subscribe', channel => 'notifications:' . $admin }
        }
    )->message_ok->json_message_is( '/type' => 'subscribed' );
    $t->message_ok->json_message_is( '/type' => 'notification.badge' )
      ->finish_ok;
  };
done_testing;
1;
