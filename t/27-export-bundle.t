# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Portability::ExportBundleBuilder;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;
use GPForum::Test::ModerationResultSet;
use GPForum::Test::ModerationSchema;

our $VERSION = '0.001';

const my $EXPECTED_TESTS   => 16;
const my $TWO_CREATED_ROWS => 2;
const my $TWO_POSTS        => 2;
const my $ONE_ATTACHMENT   => 1;
const my $ONE_NOTIFICATION => 1;
const my $ONE_SUBSCRIPTION => 1;
const my $ONE_PREFERENCE   => 1;

plan tests => $EXPECTED_TESTS;

my $export_requests =
  GPForum::Test::ModerationResultSet->new( filter_search => 1 );
my $event_log       = GPForum::Test::ModerationResultSet->new;
my $outbox_messages = GPForum::Test::ModerationResultSet->new;
my $audit_log       = GPForum::Test::ModerationResultSet->new;
my $schema          = GPForum::Test::ModerationSchema->new(
    resultsets => {
        AuditLog      => $audit_log,
        EventLog      => $event_log,
        ExportRequest => $export_requests,
        OutboxMessage => $outbox_messages,
    },
);

my $clock = GPForum::Test::FixedClock->new;

# The bundle and its safe manifest, and completion from parts the caller
# hands over. The export request store -- the pending request a retry
# reuses, its races and id collisions, the completion from the member's
# rows, its replay and what never leaves with it -- runs on PostgreSQL in
# t/integration/postgres-privacy.t.
my $export_builder = GPForum::Service::Portability::ExportBundleBuilder->new(
    schema     => $schema,
    clock      => $clock,
    id_service => GPForum::Test::Id->new,
);
my $request = $export_builder->create_request(
    {
        requester_user_id => 'user-1',
        subject_user_id   => 'user-2',
        export_type       => 'user_data',
    }
);

my $bundle = $export_builder->build_user_bundle(
    'user-2',
    {
        profile       => { username => 'giacomo' },
        posts         => [ { post_id         => 1 }, { post_id => 2 } ],
        attachments   => [ { attachment_id   => 1 } ],
        notifications => [ { notification_id => 1 } ],
        subscriptions => [ { thread_id       => 1 } ],
        preferences   => [ { channel         => 'email' } ],
        audit_log     => [ { secret          => 'must-not-leak' } ],
    }
);
is( $bundle->{subject_user_id},   'user-2',  'bundle stores subject' );
is( $bundle->{profile}{username}, 'giacomo', 'bundle includes profile part' );
ok( !exists $bundle->{audit_log}, 'bundle excludes privileged audit details' );

my $safe_manifest = $export_builder->safe_manifest($bundle);
is( $safe_manifest->{counts}{posts}, $TWO_POSTS, 'manifest counts posts' );
is( $safe_manifest->{counts}{attachments},
    $ONE_ATTACHMENT, 'manifest counts attachments' );
is( $safe_manifest->{counts}{notifications},
    $ONE_NOTIFICATION, 'manifest counts notifications' );
is( $safe_manifest->{counts}{subscriptions},
    $ONE_SUBSCRIPTION, 'manifest counts subscriptions' );
is( $safe_manifest->{counts}{preferences},
    $ONE_PREFERENCE, 'manifest counts preferences' );
ok( !exists $safe_manifest->{audit_log}, 'safe manifest excludes audit data' );
ok(
    !exists $safe_manifest->{moderation_actions},
    'safe manifest excludes moderation data'
);

my $completed_export = $export_builder->complete_user_export(
    $request->{export_request_id},
    {
        profile       => { username => 'giacomo' },
        posts         => [ { post_id         => 1 }, { post_id => 2 } ],
        attachments   => [ { attachment_id   => 1 } ],
        notifications => [ { notification_id => 1 } ],
        subscriptions => [ { thread_id       => 1 } ],
        preferences   => [ { channel         => 'email' } ],
    }
);
is( $completed_export->{status},
    'completed', 'export completion updates request status' );
is(
    $export_requests->find( $request->{export_request_id} )
      ->get_column('status'),
    'completed',
    'export completion persists status'
);
is( $completed_export->{manifest}{counts}{notifications},
    $ONE_NOTIFICATION, 'completed export stores safe notification count' );
is( $completed_export->{manifest}{posts}[0]{post_id},
    1, 'completed export stores the supplied post rows' );
is( scalar @{ $event_log->created },
    $TWO_CREATED_ROWS, 'export completion emits second privacy event' );
is( scalar @{ $outbox_messages->created },
    $TWO_CREATED_ROWS, 'export completion queues second outbox message' );

1;
