# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Test;
use Mojo::JSON qw(decode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Notification::DigestQueue;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Test::DigestClock;
use GPForum::Test::PgDatabase;
use GPForum::Worker::Handler::NotificationDigest;

our $VERSION = '0.001';

const my $DIGEST => 'notification.digest.requested';
const my $OTHER  => '0190a5f2-0000-7000-8000-0000000000e9';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the digest sent once';
}

# ADR 0078, amendment of 2026-10-17, on a migrated PostgreSQL: the worker
# claims a queued digest before it mails it, so the outbox delivering the
# event again sends nothing, and a claim given back lets the retry send.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $clock     = GPForum::Test::DigestClock->new;

my $author = _user('sent_author');
my $member = _user('sent_member');
$dbh->do(
    q{INSERT INTO notification_preferences (user_id, channel, enabled,}
      . q{ digest_frequency, updated_at) VALUES (?, 'digest', true, 'daily',}
      . q{ now())},
    undef, $member
);
my ($thread) =
  $dbh->selectrow_array( q{SELECT t.thread_id FROM threads t}
      . q{ JOIN categories c ON c.category_id = t.category_id}
      . q{ JOIN spaces s ON s.space_id = c.space_id}
      . q{ WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'}
      . q{ AND t.visibility = 'public' AND c.visibility = 'public'}
      . q{ AND s.visibility = 'public' AND c.deleted_at IS NULL}
      . q{ ORDER BY t.thread_id LIMIT 1} );
$dbh->do(
    q{INSERT INTO posts (post_id, thread_id, author_user_id, position,}
      . q{ moderation_state, created_at, updated_at) SELECT gen_random_uuid(),}
      . q{ ?, ?, coalesce(max(position), 0) + 1, 'visible',}
      . q{ '2026-10-14 08:00:00+00', '2026-10-14 08:00:00+00'}
      . q{ FROM posts WHERE thread_id = ?},
    undef, $thread, $author, $thread
);
$dbh->do(
    q{INSERT INTO subscriptions (subscription_id, user_id, target_type,}
      . q{ target_id, preference) VALUES (gen_random_uuid(), ?, 'thread', ?,}
      . q{ 'all')},
    undef, $member, $thread
);
GPForum::Service::Notification::DigestQueue->new(
    schema    => $schema,
    functions => $functions,
    clock     => $clock,
)->run( { limit => 100 } );
my ( $event_id, $payload ) = $dbh->selectrow_array(
    q{SELECT event_id, payload FROM event_log WHERE event_type = ?}
      . q{ AND aggregate_id = ?},
    undef, $DIGEST, $member
);
my $stored = decode_json($payload);
my $event  = {
    event_id       => $event_id,
    event_type     => $DIGEST,
    domain_payload => ref $stored->{payload} eq 'HASH'
    ? $stored->{payload}
    : $stored,
};
my $store = GPForum::Service::Notification::PreferenceStore->new(
    schema    => $schema,
    functions => $functions,
    clock     => $clock,
);
my $key = {
    user_id      => $member,
    frequency    => 'daily',
    period_start => $event->{domain_payload}{period_start},
    event_id     => $event_id,
};

subtest 'a queued digest is claimed once' => sub {
    is( $store->claim_digest_send($key)->{status}, 'claimed', 'the first' );
    is( $store->claim_digest_send($key)->{status}, 'sent',    'not again' );
    is( $store->release_digest_send($key)->{status},
        'released', 'a claim given back' );
    is( $store->release_digest_send($key)->{status}, 'unchanged', 'once' );
    is(
        $store->claim_digest_send( { %{$key}, event_id => $OTHER } )->{status},
        'missing',
        'another event is not this digest'
    );
};

subtest 'the worker mails it once' => sub {
    my $transport = Email::Sender::Transport::Test->new;
    my $handler   = GPForum::Worker::Handler::NotificationDigest->new(
        mailer => GPForum::Service::Identity::Mailer->new(
            transport       => $transport,
            public_base_url => 'https://forum.example.test/',
            from_address    => 'forum@example.test',
        ),
        preference_store => $store,
        renderer         => GPForum::Service::Notification::Renderer->new,
        tokens => GPForum::Service::Notification::UnsubscribeToken->new(
            secrets => ['integration-secret']
        ),
    );
    ok( $handler->handle($event)->{delivered}, 'it is sent' );
    is( $handler->handle($event)->{reason},
        'sent', 'the event delivered again sends nothing' );
    is( scalar $transport->deliveries, 1, 'one mail' );
};

done_testing;

sub _user ($name) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now())}
          . q{ RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );

    return $id;
}

1;
