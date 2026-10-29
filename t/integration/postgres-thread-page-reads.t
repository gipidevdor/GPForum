# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::Store;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Community::LikeStore;
use GPForum::Service::Community::ReactionStore;
use GPForum::Service::Forum::ReadState;
use GPForum::Service::Forum::ReplyLinks;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadPageReads;
use GPForum::Service::Forum::ThreadTags;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Password;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# Migration 124: the seven reads a thread page makes once it has its posts
# are one statement (eight since the reactions of migration 133), and each
# read gets from it exactly the rows its own call returns -- for a guest and
# for a member with something to read in every part. The page they build is
# the same whether they come from the one statement or from eight, and
# costs seven statements fewer for the member, four for the guest.

const my $HTTP_OK      => 200;
const my $PASSWORD     => 'thread page reads correct horse';
const my $PAGE_SIZE    => 25;
const my $MEMBER_FEWER => 7;
const my $GUEST_FEWER  => 4;
const my $JSON         => { Accept => 'application/json' };
const my $THREAD_SQL => join q{ },
  'SELECT t.thread_id FROM threads t JOIN posts p ON p.thread_id = t.thread_id',
  q{WHERE t.deleted_at IS NULL AND t.visibility = 'public'},
  q{AND t.moderation_state = 'visible' AND p.deleted_at IS NULL},
  q{AND p.moderation_state = 'visible'},
  'GROUP BY t.thread_id HAVING count(*) >= 3 ORDER BY t.thread_id LIMIT 1';
const my $POSTS_SQL =>
  'SELECT post_id, author_user_id FROM posts WHERE thread_id = ?'
  . ' ORDER BY position LIMIT 3';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the thread page reads';
}

local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $dbh    = $database->dbh;
my $schema = $database->schema;

my ($thread_id) = $dbh->selectrow_array($THREAD_SQL);
my $posts = $dbh->selectall_arrayref( $POSTS_SQL, { Slice => {} }, $thread_id );
my ( $first, $liked, $answering ) = map { $_->{post_id} } @{$posts};
my $member = _member();
_something_in_every_part();

my %store = (
    attachment_store =>
      GPForum::Service::Attachment::Store->new( schema => $schema ),
    bookmark_store =>
      GPForum::Service::Community::BookmarkStore->new( schema => $schema ),
    like_store =>
      GPForum::Service::Community::LikeStore->new( schema => $schema ),
    reaction_store =>
      GPForum::Service::Community::ReactionStore->new( schema => $schema ),
    read_state  => GPForum::Service::Forum::ReadState->new( schema => $schema ),
    reply_links =>
      GPForum::Service::Forum::ReplyLinks->new( schema => $schema ),
    subscription_store =>
      GPForum::Service::Notification::SubscriptionStore->new(
        schema => $schema
      ),
    thread_tags =>
      GPForum::Service::Forum::ThreadTags->new( schema => $schema ),
);
my $reads =
  GPForum::Service::Forum::ThreadPageReads->new( schema => $schema, %store );
my $functions = GPForum::Infrastructure::SqlFunction->for_schema($schema);

for my $viewer ( undef, $member ) {
    my $who = $viewer ? 'a member' : 'a guest';
    subtest "for $who each read gets what its own call returns" => sub {
        my $page = _page($viewer);
        my @ids  = map { $_->get_column('post_id') } @{ $page->{posts}{items} };
        my @calls = (
            $store{like_store}->summary_call( \@ids, $viewer ),
            $store{reaction_store}->reactions_call( \@ids, $viewer ),
            $store{reply_links}->targets_call( \@ids ),
            $store{thread_tags}->tags_call( [$thread_id] ),
            $store{attachment_store}->post_files_call( \@ids ),
        );
        if ($viewer) {
            push @calls,
              $store{bookmark_store}
              ->find_call( $viewer, 'thread', $thread_id ),
              $store{subscription_store}
              ->find_call( $viewer, 'thread', $thread_id ),
              $store{read_state}->state_call( $viewer, $thread_id );
        }
        my %expected =
          map { $functions->answer_key( @{$_} ) => $functions->rows( @{$_} ) }
          @calls;
        my @empty = grep { !@{ $expected{$_} } } keys %expected;
        is_deeply( \@empty, [], 'every part has rows to answer with' );
        is_deeply(
            $reads->answers(
                {
                    page           => $page,
                    thread_id      => $thread_id,
                    viewer_user_id => $viewer,
                }
            ),
            \%expected,
            'each part, row for row and column for column'
        );
    };
}

subtest 'the page is the same, for seven statements fewer' => sub {
    my %executed;
    my $guest     = _client( \%executed, 'guest' );
    my $signed_in = _client( \%executed, 'member' );
    _sign_in($signed_in);

    my %page;
    for my $case (
        [ guest  => $guest,     $GUEST_FEWER ],
        [ member => $signed_in, $MEMBER_FEWER ]
      )
    {
        my ( $who, $client, $fewer ) = @{$case};
        my ( $answered, $one )   = _thread( $client, \%executed, $who );
        my ( $called,   $seven ) = do {
            no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- the page without the one statement, for comparison
            local *GPForum::Service::Forum::ThreadPageReads::answers =
              sub { return {}; };
            _thread( $client, \%executed, $who );
        };
        is_deeply( $answered, $called, "the $who\'s page is the same" );
        is( $seven - $one, $fewer, "for $fewer statements fewer" );
        $page{$who} = $answered;
    }

    # What the comparison compared: every part had something to show.
    my $shown = $page{member};
    is_deeply(
        [
            $shown->{posts}[0]{like_count},
            $shown->{posts}[0]{liked},
            $shown->{posts}[0]{reactions}[0]{count},
            $shown->{posts}[0]{reactions}[0]{reacted},
            $shown->{posts}[2]{reply_to}{post_id},
            [ map { $_->{slug} } @{ $shown->{thread}{tags} } ],
            $shown->{engagement}{bookmark}{bookmarked},
            $shown->{engagement}{subscription}{subscribed},
            $shown->{reading}{last_read_position},
        ],
        [ 1, 1, 1, 1, $first, [qw(sockets latency)], 1, 1, 1 ],
        'the likes, the reactions, the reply, the tags, the bookmark, the'
          . ' subscription and the read state'
    );
    for my $client ( $guest, $signed_in ) {
        _storage($client)->disconnect;
    }
};
$schema->storage->disconnect;

done_testing();

sub _page ($viewer) {
    my $as =
      $viewer
      ? GPForum::Service::Forum::ViewerResolver->new( schema => $schema )
      ->resolve($viewer)
      : GPForum::Service::Forum::Viewer->anonymous;

    return GPForum::Service::Forum::ThreadDetailReader->new( schema => $schema )
      ->thread_page(
        { thread_id => $thread_id, limit => $PAGE_SIZE, viewer => $as } );
}

# A like from the member and one from a post's author on another's post, a
# reply that answers the first post, two tags, an attachment on the first
# post, and the member's bookmark, subscription and read state.
sub _something_in_every_part {
    my $author = $posts->[0]{author_user_id};
    $dbh->do( 'INSERT INTO post_likes (post_id, user_id) VALUES (?, ?), (?, ?)',
        undef, $first, $member, $liked, $author );
    $dbh->do(
'INSERT INTO post_reactions (post_id, user_id, reaction) VALUES (?, ?, ?)',
        undef, $first, $member, 'heart'
    );
    GPForum::Service::Forum::ReplyLinks->new( schema => $schema )
      ->link_reply( $answering, $first );
    GPForum::Service::Forum::ThreadTags->new( schema => $schema )
      ->set_thread_tags( $thread_id, 'sockets, latency' );
    my ($attachment) = $dbh->selectrow_array(
        q{INSERT INTO attachments (attachment_id, owner_user_id, object_key,}
          . q{ original_filename, media_type, byte_size, checksum)}
          . q{ VALUES (gen_random_uuid(), ?, 'reads/one', 'one.txt',}
          . q{ 'text/plain', 3, 'sha256:0') RETURNING attachment_id},
        undef, $author
    );
    $dbh->do(
        q{INSERT INTO attachment_links (attachment_link_id, attachment_id,}
          . q{ target_type, target_id) VALUES (gen_random_uuid(), ?, ?, ?)},
        undef,
        $attachment,
        GPForum::Service::Attachment::Store->new( schema => $schema )
          ->lifecycle->post_link_target,
        $first
    );
    $dbh->do(
        q{INSERT INTO bookmarks (bookmark_id, user_id, target_type, target_id,}
          . q{ note) VALUES (gen_random_uuid(), ?, 'thread', ?, 'later')},
        undef, $member, $thread_id
    );
    $dbh->do(
        q{INSERT INTO subscriptions (subscription_id, user_id, target_type,}
          . q{ target_id) VALUES (gen_random_uuid(), ?, 'thread', ?)},
        undef, $member, $thread_id
    );
    $dbh->do(
        q{INSERT INTO thread_read_state (user_id, thread_id,}
          . q{ last_read_position, last_read_at) VALUES (?, ?, 1, now())},
        undef, $member, $thread_id
    );

    return;
}

sub _member {
    my $hash = GPForum::Service::Password->new->hash_password($PASSWORD);
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status) VALUES (gen_random_uuid(), 'reads',}
          . q{ 'Reads', 'reads@example.test', ?, 'active') RETURNING id},
        undef, $hash
    );
    $dbh->do(
        q{INSERT INTO credentials (id, user_id, type, secret_hash)}
          . q{ VALUES (gen_random_uuid(), ?, 'password', ?)},
        undef, $id, $hash
    );

    return $id;
}

# The storage a client's application reads through.
sub _storage ($client) {
    my $controller = $client->app->build_controller;

    return $controller->gp_schema->storage;
}

# A client whose handle counts the statements it executes, as the query
# budget test counts them.
sub _client ( $executed, $who ) {
    my $client  = Test::Mojo->new('GPForum');
    my $storage = _storage($client);
    my $count   = sub { ++$executed->{$who}; return; };
    $storage->dbh->{Callbacks} = {
        ChildCallbacks     => { execute => $count },
        do                 => $count,
        selectall_arrayref => $count,
        selectrow_array    => $count,
        selectrow_arrayref => $count,
    };

    return $client;
}

sub _sign_in ($client) {
    $client->get_ok('/login');
    my $form = $client->tx->res->dom;
    $client->post_ok(
        '/login' => form => {
            command_id => $form->at('input[name=command_id]')->attr('value'),
            csrf_token => $form->at('input[name=csrf_token]')->attr('value'),
            identifier => 'reads',
            password   => $PASSWORD,
        }
    );
    $client->get_ok('/settings')->status_is( $HTTP_OK, 'the member signs in' );

    return;
}

# The thread page's payload, its command and draft ids (new on every page)
# masked, and the statements it took.
sub _thread ( $client, $executed, $who ) {
    my $cache = $client->app->build_controller->gp_local_cache;
    $cache->invalidate_tag('forum:public-html');
    $executed->{$who} = 0;
    $client->get_ok( "/t/$thread_id" => $JSON )->status_is($HTTP_OK);

    return ( _masked( $client->tx->res->json ), $executed->{$who} );
}

sub _masked ($value) {
    if ( ref $value eq 'HASH' ) {
        return {
            map {
                $_ => /(?:command_ids?|draft_id)\z/msx
                  ? 'masked'
                  : _masked( $value->{$_} )
            } keys %{$value}
        };
    }
    return [ map { _masked($_) } @{$value} ] if ref $value eq 'ARRAY';

    return $value;
}

1;
