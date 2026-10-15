# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Admin::AnnouncementStore;
use GPForum::Service::Operations::LocalCache;
use GPForum::Test::FixedClock;
use GPForum::Test::RecordingRecorder;
use GPForum::Test::SequenceId;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# A site announcement (ADR 0131) as the store writes and reads it, on a
# handle that records the call and answers what the test gives: what is
# refused before any call, what the insert sends, what is recorded with it,
# and what the page and the console read back.

const my $ADMIN    => '018f1002-0001-7000-8000-000000000001';
const my $NOW      => '2026-10-15T12:00:00Z';
const my $PREFIX   => '018f0009-0000-7000-8000';
const my $TOO_LONG => 501;
const my $EXISTING => '018f1007-0001-7000-8000-000000000001';
const my $PAGES    => 3;

my $json = JSON::MaybeXS->new( canonical => 1 );

sub fixture ( $rows = [] ) {
    my $handle   = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $recorder = GPForum::Test::RecordingRecorder->new;
    my $store    = GPForum::Service::Admin::AnnouncementStore->new(
        clock     => GPForum::Test::FixedClock->new( iso8601 => $NOW ),
        functions =>
          GPForum::Infrastructure::SqlFunction->new( schema => $handle ),
        id_service => GPForum::Test::SequenceId->new( prefix => $PREFIX ),
        recorder   => $recorder,
        schema     => $handle,
    );
    return ( $handle, $store, $recorder );
}

subtest 'what cannot be published is refused before any call' => sub {
    my ( $handle, $store ) = fixture();
    is_deeply(
        $store->create_announcement(
            { actor_user_id => $ADMIN, message => q{ } }
        )->{errors},
        { message => 'message is required' },
        'nothing to say'
    );
    is_deeply(
        $store->create_announcement(
            { actor_user_id => $ADMIN, message => 'x' x $TOO_LONG }
        )->{errors},
        { message => 'message is too long' },
        'more than 500 characters'
    );
    is_deeply(
        $store->create_announcement(
            { actor_user_id => $ADMIN, message => 'Hello', tone => 'loud' }
        )->{errors},
        { tone => 'tone must be notice or warning' },
        'a tone the page has no voice for'
    );
    is( scalar @{ $handle->executed }, 0, 'and the database heard nothing' );
};

subtest 'a publication is one insert, with its event and audit row' => sub {
    my ( $handle, $store, $recorder ) = fixture();
    my $published = $store->create_announcement(
        {
            actor_user_id => $ADMIN,
            message       => '  Back-ups tonight.  ',
            tone          => 'warning',
        }
    );
    my ($announcement_id) =
      map { $_->uuid } GPForum::Test::SequenceId->new( prefix => $PREFIX );
    is_deeply(
        $published,
        {
            announcement_id => $announcement_id,
            created_at      => $NOW,
            created_by      => $ADMIN,
            message         => 'Back-ups tonight.',
            retired_at      => undef,
            retired_by      => undef,
            tone            => 'warning',
        },
        'the row is answered, trimmed, with the ids and the time drawn here'
    );
    is( scalar @{ $handle->executed }, 1, 'in one call' );
    like(
        $handle->prepared->[0],
        qr/api[.]admin_insert_announcement_v2/msx,
        'to the insert'
    );
    is_deeply( $json->decode( $handle->executed->[0][0] ),
        $published, 'sending the row as answered' );
    is( $recorder->events->[0]{event_type},
        'announcement.published', 'the event is recorded' );
    is( $recorder->events->[0]{aggregate_id},
        $announcement_id, 'under the announcement' );
    is( $recorder->audits->[0]{action},
        'announcement.published', 'and the audit row with it' );
};

subtest 'retiring an announcement already retired changes nothing' => sub {
    my ( $handle, $store, $recorder ) = fixture(
        [
            {
                announcement_id => $EXISTING,
                message         => 'Old news.',
                retired_at      => '2026-10-14T12:00:00Z',
                retired_by      => $ADMIN,
                tone            => 'notice',
            }
        ]
    );
    my $retired = $store->retire_announcement(
        { actor_user_id => $ADMIN, announcement_id => $EXISTING } );
    ok( $retired->{skipped}, 'the retirement is a repeat' );
    is( scalar @{ $handle->executed }, 1, 'after one look' );
    like(
        $handle->prepared->[0],
        qr/api[.]admin_announcement_by_id_v2/msx,
        'at the announcement'
    );
    is( scalar @{ $recorder->events }, 0, 'and no event is recorded' );
};

subtest 'the page and the console read through their functions' => sub {
    my ( $handle, $store ) = fixture(
        [
            {
                announcement_id => $EXISTING,
                message         => 'Hello.',
                tone            => 'notice'
            }
        ]
    );
    is( $store->active_announcements->[0]{message},
        'Hello.', 'the page reads the active announcements' );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_active_announcements_v2/msx,
        'through theirs'
    );
    $store->list_announcements;
    like(
        $handle->prepared->[-1],
        qr/api[.]admin_list_announcements_v2/msx,
        'and the console through its own'
    );
};

subtest 'with a cache every page reads the list once per lifetime' => sub {
    my ( $handle, $store ) = fixture(
        [
            {
                announcement_id => $EXISTING,
                message         => 'Hello.',
                tone            => 'notice'
            }
        ]
    );
    my $cache = GPForum::Service::Operations::LocalCache->new;
    $store->cache($cache);
    for my $page ( 1 .. $PAGES ) {
        $store->active_announcements;
    }
    is( scalar @{ $handle->executed }, 1, 'three pages cost one statement' );
    $cache->invalidate_tag('forum:public-html');
    $store->active_announcements;
    is( scalar @{ $handle->executed },
        1, 'a purge of the public html leaves the list cached' );
    $cache->invalidate_tag('announcements');
    is( $store->active_announcements->[0]{message},
        'Hello.', 'after a purge of the announcements it is read again' );
    is( scalar @{ $handle->executed }, 2, 'with one more statement' );
};

subtest 'announcements exist only as functions' => sub {
    my $store = GPForum::Service::Admin::AnnouncementStore->new(
        functions => undef,
        schema    => GPForum::Test::SqlFunctionHandle->new,
    );
    like(
        exception { $store->active_announcements },
        qr/SQL [ ] function [ ] layer/msx,
        'without the call layer the store refuses to guess'
    );
};

done_testing();

1;
