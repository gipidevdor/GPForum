# SPDX-FileCopyrightText: 2026 GPForum Contributors
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
const my $FIRST_PAGE    => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the notification inbox reads';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my ($user)  = $dbh->selectrow_array('SELECT id FROM users ORDER BY id LIMIT 1');
my $threads = $dbh->selectall_arrayref(
'SELECT thread_id, category_id, author_user_id FROM threads ORDER BY thread_id LIMIT 2',
    { Slice => {} }
);
my $ids = GPForum::Infrastructure::Id->new;
my $readability =
  GPForum::Service::Forum::Readability->new( schema => $schema );
my $plain =
  GPForum::Service::Notification::Dispatcher->new( schema => $schema );
my $filtered = GPForum::Service::Notification::Dispatcher->new(
    schema      => $schema,
    readability => $readability
);

# The seed's own notifications for the member are cleared: half of these
# are about each thread.
$dbh->do( 'DELETE FROM notification_inbox WHERE recipient_user_id = ?',
    undef, $user );
for my $index ( 1 .. $NOTIFICATIONS ) {
    $plain->create_notification(
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

# The inbox shows what the viewer may read: a public category to anyone, a
# members' one to members, a private one to the global reader and to the
# member granted that category.
for my $visibility (qw(public members private)) {
    $dbh->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
        undef, $visibility, $threads->[0]{category_id} );
    for my $index ( 0 .. $#viewers ) {
        my $viewer   = $viewers[$index];
        my $name     = "$visibility viewer $index";
        my $expected = _visible_count($viewer);
        my @seen;
        my %page = ( limit => $FIRST_PAGE, viewer => $viewer );
        my $page = $filtered->list_page_for_user( $user, \%page );
        is(
            scalar @{ $page->{items} },
            $expected < $FIRST_PAGE ? $expected : $FIRST_PAGE,
            "$name first page is full as far as it can be"
        );
        push @seen, @{ $page->{items} };

        while ( $page->{next_cursor} ) {
            $page{after} = $page->{next_cursor};
            $page = $filtered->list_page_for_user( $user, \%page );
            push @seen, @{ $page->{items} };
        }
        my %distinct = map { $_->get_column('notification_id') => 1 } @seen;
        is( scalar keys %distinct,
            $expected, "$name pages walk each readable notification once" );
        is( $filtered->unread_count_for_user( $user, $viewer ),
            $expected, "$name unread count is what the pages show" );
    }
}

$dbh->do(
    'UPDATE threads SET moderation_state = \'hidden\' WHERE thread_id = ?',
    undef, $threads->[0]{thread_id} );
my $hidden = $filtered->list_page_for_user( $user,
    { limit => $PAGE_SIZE, viewer => $viewers[2] } );
is_deeply(
    [
        sort map { $_->notification->get_column('source_id') }
          @{ $hidden->{items} }
    ],
    [ ( $threads->[1]{thread_id} ) x _readable_on_thread( 1, $viewers[2] ) ],
    'hidden sources stay hidden even for global-read viewers'
);

my @listed = @{ $plain->list_for_user( $user, $PAGE_SIZE ) };
is( scalar @listed, $NOTIFICATIONS, 'the unfiltered list has every one' );
is_deeply(
    [ sort { $a <=> $b } map { _row($_)->{inflated_payload}{index} } @listed ],
    [ 1 .. $NOTIFICATIONS ],
    'with its payload inflated'
);
is_deeply(
    [ map { _row($_)->{notification}{notification_id} } @listed ],
    [ map { _row($_)->{inbox}{notification_id} } @listed ],
    'each row carrying its notification'
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

# The notifications about both threads the viewer may read now.
sub _visible_count ($viewer) {
    return _readable_on_thread( 0, $viewer ) +
      _readable_on_thread( 1, $viewer );
}

sub _readable_on_thread ( $index, $viewer ) {
    my $thread = $threads->[$index];
    my ( $visibility, $state ) = $dbh->selectrow_array(
        'SELECT c.visibility, t.moderation_state FROM threads t'
          . ' JOIN categories c USING (category_id) WHERE t.thread_id = ?',
        undef, $thread->{thread_id}
    );
    return 0 if $state eq 'hidden' || $state eq 'deleted';
    my $granted =
      grep { $_ eq $thread->{category_id} } @{ $viewer->category_ids || [] };
    my $readable =
        $visibility eq 'public'  ? 1
      : $visibility eq 'members' ? $viewer->member
      :                            $viewer->global_read || $granted;
    return $readable ? $NOTIFICATIONS / 2 : 0;
}

1;
