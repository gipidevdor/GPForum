# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Admin::AnnouncementStore;
use GPForum::Service::Admin::Workflow;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0131 against the migrated schema: an announcement is published and
# shown, retired once, and each write leaves its event and its audit row;
# as commands, a repeated request is answered the same.

const my $EVENTS_SQL =>
  'SELECT count(*) FROM event_log WHERE event_type = ? AND aggregate_id = ?';
const my $AUDITS_SQL =>
  'SELECT count(*) FROM audit_log WHERE action = ? AND target_id = ?';
const my $TOO_LONG => 501;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the site announcements test';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $schema   = $database->schema;
my $admin    = seed_id( user => 1 );
my $store =
  GPForum::Service::Admin::AnnouncementStore->new( schema => $schema );

is_deeply( $store->active_announcements, [],
    'a fresh forum announces nothing' );

my $published = $store->create_announcement(
    {
        actor_user_id => $admin,
        message       => '  Back-ups tonight at 22:00.  ',
        tone          => 'warning',
    }
);
ok( $published->{announcement_id},
    'an administrator publishes an announcement' );
is( $published->{message}, 'Back-ups tonight at 22:00.', 'trimmed' );
is( $published->{tone},    'warning',                    'in its tone' );
my $id = $published->{announcement_id};
is( _count( $EVENTS_SQL, 'announcement.published', $id ), 1, 'with its event' );
is( _count( $AUDITS_SQL, 'announcement.published', $id ),
    1, 'and its audit row' );
is_deeply( [ map { $_->{announcement_id} } @{ $store->active_announcements } ],
    [$id], 'every page now shows it' );

is_deeply(
    $store->create_announcement(
        { actor_user_id => $admin, message => q{  } }
    )->{errors},
    { message => 'message is required' },
    'nothing to say is refused'
);
is_deeply(
    $store->create_announcement(
        { actor_user_id => $admin, message => 'x' x $TOO_LONG }
    )->{errors},
    { message => 'message is too long' },
    'as is more than 500 characters'
);
is_deeply(
    $store->create_announcement(
        { actor_user_id => $admin, message => 'Hello', tone => 'loud' }
    )->{errors},
    { tone => 'tone must be notice or warning' },
    'and a tone the page has no voice for'
);

my $retired = $store->retire_announcement(
    { actor_user_id => $admin, announcement_id => $id } );
ok( $retired->{retired_at}, 'the announcement is retired' );
is( $retired->{retired_by}, $admin, 'by the administrator' );
is( _count( $EVENTS_SQL, 'announcement.retired', $id ), 1, 'with its event' );
is_deeply( $store->active_announcements, [], 'and no page shows it' );
ok(
    $store->retire_announcement(
        { actor_user_id => $admin, announcement_id => $id }
    )->{skipped},
    'retiring it again changes nothing'
);
is( _count( $EVENTS_SQL, 'announcement.retired', $id ),
    1, 'and records no event' );
is(
    $store->retire_announcement(
        { actor_user_id => $admin, announcement_id => seed_id( user => 2 ) }
    ),
    undef,
    'an unknown announcement is nothing'
);
is( scalar @{ $store->list_announcements }, 1, 'the console lists it still' );

my $workflow = GPForum::Service::Admin::Workflow->new(
    announcement_store  => $store,
    command_idempotency =>
      GPForum::Service::Operations::CommandIdempotency->new(
        schema => $schema
      ),
    logger => GPForum::Test::LogLines->new,
);
my $command = {
    actor_user_id => $admin,
    command_id    => 'announce-1',
    message       => 'Welcome to the new forum.',
    tone          => 'notice',
};
my $first = $workflow->create_announcement($command);
is( $first->{status}, 'ok', 'the command publishes' );
is_deeply( $workflow->create_announcement($command),
    $first, 'and the same command again is answered the same' );
is( scalar @{ $store->active_announcements },
    1, 'with one announcement published, not two' );
is(
    $workflow->retire_announcement(
        {
            actor_user_id   => $admin,
            announcement_id => $first->{stored}{announcement_id},
            command_id      => 'retire-1',
        }
    )->{status},
    'ok',
    'the retire command retires it'
);
is_deeply( $store->active_announcements, [], 'and every page is quiet again' );

done_testing();

sub _count ( $sql, @values ) {
    return scalar $dbh->selectrow_array( $sql, undef, @values );
}

1;
