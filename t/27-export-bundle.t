# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Portability::ExportBundleBuilder;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;

our $VERSION = '0.001';

const my $EXPECTED_TESTS   => 23;
const my $TWO_RECORDS      => 2;
const my $TWO_POSTS        => 2;
const my $ONE_ATTACHMENT   => 1;
const my $ONE_NOTIFICATION => 1;
const my $ONE_SUBSCRIPTION => 1;
const my $ONE_PREFERENCE   => 1;

plan tests => $EXPECTED_TESTS;

# The bundle and its safe manifest, and completion from parts the caller
# hands over, on a call layer that answers each function as stated. The
# export request store -- the pending request a retry reuses, its races and
# id collisions, the completion from the member's rows, its replay and what
# never leaves with it -- runs on PostgreSQL in
# t/integration/postgres-privacy.t.
my $functions      = GPForum::Test::AnsweringFunctions->new;
my $export_builder = GPForum::Service::Portability::ExportBundleBuilder->new(
    schema     => {},
    functions  => $functions,
    clock      => GPForum::Test::FixedClock->new,
    id_service => GPForum::Test::Id->new,
);
my $request = $export_builder->create_request(
    {
        requester_user_id => 'user-1',
        subject_user_id   => 'user-2',
        export_type       => 'user_data',
    }
);
is( $functions->asked('privacy_insert')->[0]{row}{status},
    'pending', 'a request with none pending is inserted pending' );

my $bundle = $export_builder->build_user_bundle(
    'user-2',
    {
        profile       => { username => 'gpforum_contributors' },
        posts         => [ { post_id         => 1 }, { post_id => 2 } ],
        attachments   => [ { attachment_id   => 1 } ],
        notifications => [ { notification_id => 1 } ],
        subscriptions => [ { thread_id       => 1 } ],
        preferences   => [ { channel         => 'email' } ],
        audit_log     => [ { secret          => 'must-not-leak' } ],
    }
);
is( $bundle->{subject_user_id}, 'user-2', 'bundle stores subject' );
is( $bundle->{profile}{username},
    'gpforum_contributors', 'bundle includes profile part' );
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

$functions->answers->{privacy_find} = [ { document => { %{$request} } } ];
my $completed_export = $export_builder->complete_user_export(
    $request->{export_request_id},
    {
        profile         => { username => 'gpforum_contributors' },
        posts           => [ { post_id         => 1 }, { post_id => 2 } ],
        attachments     => [ { attachment_id   => 1 } ],
        notifications   => [ { notification_id => 1 } ],
        subscriptions   => [ { thread_id       => 1 } ],
        preferences     => [ { channel         => 'email' } ],
        direct_messages => [ { message_id      => 'm-1' } ],
        likes           => [ { post_id         => 2 } ],
    }
);
is( $completed_export->{status},
    'completed', 'export completion updates request status' );
is( $functions->asked('privacy_update')->[0]{changes}{status},
    'completed', 'export completion persists status' );
is( $completed_export->{manifest}{counts}{notifications},
    $ONE_NOTIFICATION, 'completed export stores safe notification count' );
is( $completed_export->{manifest}{posts}[0]{post_id},
    1, 'completed export stores the supplied post rows' );

# What the manifest counts, it holds: six named parts were stored and the
# rest counted only, so an export said how many messages and had none.
is( $completed_export->{manifest}{counts}{direct_messages},
    1, 'completed export counts the direct messages' );
is( $completed_export->{manifest}{direct_messages}[0]{message_id},
    'm-1', 'and stores them' );
is( $completed_export->{manifest}{counts}{likes},
    1, 'completed export counts the likes' );
is( $completed_export->{manifest}{likes}[0]{post_id}, 2, 'and stores them' );
is( $completed_export->{manifest}{second_factor}{state},
    'off', 'and the parts with a default' );
is( scalar @{ $functions->asked('ops_record_event') },
    $TWO_RECORDS, 'export completion records the second privacy event' );
is( scalar @{ $functions->asked('ops_record_audit') },
    $TWO_RECORDS, 'and its audit entry' );
is_deeply( $functions->asked('portability_export_parts'),
    [], 'the parts handed over are not read again' );

1;
