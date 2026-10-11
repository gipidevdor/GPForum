# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $NOTIFICATIONS => 12;
const my $PAGE_SIZE     => 25;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for notification read differential tests';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my ($user)  = $dbh->selectrow_array('SELECT id FROM users ORDER BY id LIMIT 1');
my $threads = $dbh->selectall_arrayref(
'SELECT thread_id, category_id, author_user_id FROM threads ORDER BY thread_id LIMIT 2',
    { Slice => {} }
);
my $ids     = GPForum::Infrastructure::Id->new;
my $fixture = GPForum::Service::Notification::Dispatcher->new(
    schema    => $schema,
    functions => undef
);

for my $index ( 1 .. $NOTIFICATIONS ) {
    $fixture->create_notification(
        {
            recipient_user_id => $user,
            source_type       => 'thread',
            source_id         => $threads->[ $index % 2 ]{thread_id},
            notification_type => 'reply',
            notification_id   => $ids->uuid,
            payload           => { index => $index, message => 'payload' },
        }
    );
}
my $readability =
  GPForum::Service::Forum::Readability->new( schema => $schema );
my $legacy = GPForum::Service::Notification::Dispatcher->new(
    schema      => $schema,
    readability => $readability,
    functions   => undef
);
my $functions = GPForum::Service::Notification::Dispatcher->new(
    schema      => $schema,
    readability => $readability
);

my @viewers = (
    GPForum::Service::Forum::Viewer->anonymous,
    GPForum::Service::Forum::Viewer->new( member => 1, user_id => $user ),
    GPForum::Service::Forum::Viewer->new(
        member      => 1,
        user_id     => $user,
        global_read => 1
    ),
    GPForum::Service::Forum::Viewer->new(
        member       => 1,
        user_id      => $user,
        category_ids => [ $threads->[0]{category_id} ]
    ),
);
for my $visibility (qw(public members private)) {
    $dbh->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
        undef, $visibility, $threads->[0]{category_id} );
    for my $index ( 0 .. $#viewers ) {
        my $viewer = $viewers[$index];
        my $name   = "$visibility viewer $index";
        my %page   = ( limit => 3, viewer => $viewer );
        my $old    = $legacy->list_page_for_user( $user, \%page );
        my $new    = $functions->list_page_for_user( $user, \%page );
        is_deeply( _page($new), _page($old),
            "$name first-page rows and payloads agree" );
        if ( $old->{next_cursor} ) {
            $page{after} = $old->{next_cursor};
            is_deeply(
                _page( $functions->list_page_for_user( $user, \%page ) ),
                _page( $legacy->list_page_for_user( $user, \%page ) ),
                "$name cursor page agrees"
            );
        }
        is(
            $functions->unread_count_for_user( $user, $viewer ),
            $legacy->unread_count_for_user( $user, $viewer ),
            "$name unread cap agrees"
        );
    }
}
$dbh->do(
    'UPDATE threads SET moderation_state = \'hidden\' WHERE thread_id = ?',
    undef, $threads->[0]{thread_id} );
is_deeply(
    _page(
        $functions->list_page_for_user(
            $user, { limit => $PAGE_SIZE, viewer => $viewers[2] }
        )
    ),
    _page(
        $legacy->list_page_for_user(
            $user, { limit => $PAGE_SIZE, viewer => $viewers[2] }
        )
    ),
    'hidden sources stay hidden even for global-read viewers'
);
my $plain_new =
  GPForum::Service::Notification::Dispatcher->new( schema => $schema );
is_deeply(
    [ map { _row($_) } @{ $plain_new->list_for_user( $user, $PAGE_SIZE ) } ],
    [ map { _row($_) } @{ $fixture->list_for_user( $user, $PAGE_SIZE ) } ],
    'unfiltered lists preserve their columns and prefetched payloads'
);

done_testing();

sub _row ($row) {
    my $notification = { $row->notification->get_columns };
    $notification->{payload} = $row->notification->get_column('payload');
    return {
        inbox            => { $row->get_columns },
        notification     => $notification,
        inflated_payload => $row->notification->get_inflated_column('payload')
    };
}

sub _page ($page) {
    return { %{$page}, items => [ map { _row($_) } @{ $page->{items} } ] };
}

1;
