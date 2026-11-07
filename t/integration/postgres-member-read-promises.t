# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The member pages' reads as the web worker runs them. Without a METHOD_p
# call_p ran each blocking read in a forked child that opened a PostgreSQL
# connection of its own, one child at a time per worker: /mentions answered
# in 64 ms and /settings in 700 ms under load. Each promise read here must
# answer exactly what its blocking read answers, and the pages must not
# reach the fork fallback at all.
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::AsyncWork;
use GPForum::Service::Community::Follows;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $HTTP_OK  => 200;
const my $MENTIONS => 30;
const my $MESSAGES => 45;
const my $TAGGED   => 10;
const my $PAGE     => 10;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare member read promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh     = $database->dbh;
my $member  = seed_id( user => 2 );
my $other   = seed_id( user => 3 );
my $fixture = fixtures();

my $t = Test::Mojo->new('GPForum');
my $c = $t->app->build_controller;
$c->session( user_id => $member );
my $viewer = $c->gp_forum_viewer;

subtest 'source list pages answer what the blocking reads answer' => sub {
    for my $case (
        [ $c->gp_mention_reader, 'list_page_for_recipient', $MENTIONS ],
        [ $c->gp_feed_reader,    'list_page_for_user' ],
        [ $c->gp_bookmark_store, 'list_page_for_user' ],
      )
    {
        my ( $service, $method, $expected ) = @{$case};
        for my $who ( [ resolved => $viewer ], [ id => $member ] ) {
            my $options = { limit => $PAGE, viewer => $who->[1] };
            my $page    = same_answer(
                $service, $method,
                [ $member, $options ],
                "$method, $who->[0] viewer"
            );
            next if !$expected || !$page->{next_cursor};
            is( scalar @{ $page->{items} }, $PAGE, "$method fills a page" );
            same_answer(
                $service, $method,
                [ $member, { %{$options}, after => $page->{next_cursor} } ],
                "$method, $who->[0] viewer, second page"
            );
        }
    }
    same_answer(
        $c->gp_bookmark_folders, 'list_folders',
        [ $member, { target_type => 'thread', viewer => $viewer } ],
        'bookmark folders'
    );
};

subtest 'direct messages answer what the blocking reads answer' => sub {
    my $inbox =
      same_answer( $c->gp_message_store, 'inbox', [ $member, undef ], 'inbox' );
    is( scalar @{ $inbox->{items} }, 1, 'the inbox lists the conversation' );
    my $head = same_answer(
        $c->gp_message_store, 'conversation',
        [ $fixture->{conversation}, $member ],
        'conversation head'
    );
    ok( $head, 'the member reads the conversation' );
    same_answer(
        $c->gp_message_store, 'conversation',
        [ $fixture->{conversation}, seed_id( user => 4 ) ],
        'a stranger reads no conversation'
    );
    my $page = same_answer( $c->gp_message_store, 'messages',
        [ $fixture->{conversation}, $member, undef ], 'messages' );
    ok( $page->{next_cursor}, 'the conversation has an older page' );
    same_answer(
        $c->gp_message_store, 'messages',
        [ $fixture->{conversation}, $member, $page->{next_cursor} ],
        'older messages'
    );
};

subtest 'follows, tags, drafts and settings answer the same' => sub {
    my $follows =
      GPForum::Service::Community::Follows->new( schema => $c->gp_schema );
    my $followed =
      same_answer( $follows, 'followed_users', [$member], 'followed users' );
    is( scalar @{$followed}, 1, 'the member follows one author' );
    my $feed =
      same_answer( $follows, 'feed', [ $member, $viewer, { limit => $PAGE } ],
        'follow feed' );
    ok( scalar @{ $feed->{items} }, 'the follow feed has contributions' );

    my $tags = $c->gp_thread_tags;
    my ($bench) = grep { $_->{slug} eq 'bench' }
      @{ same_answer( $tags, 'list_tags', [ { viewer => $viewer } ], 'tags' ) };
    is( $bench->{thread_count}, $TAGGED, 'the tag counts its threads' );
    is(
        scalar @{
            same_answer(
                $tags, 'list_tagged_threads',
                [ { slug => 'bench', viewer => $viewer } ],
                'tagged threads'
            )
        },
        $TAGGED,
        'the tag page lists its threads'
    );
    same_answer( $tags, 'filter_page',
        [ { tags => 'bench', viewer => $viewer, limit => $PAGE / 2 } ],
        'tag filter' );

    same_answer( $c->gp_draft_store, 'list_for_user', [$member], 'drafts' );
    my $preferences = $c->gp_notification_preference_store;
    same_answer(
        $preferences, 'preferences_for_user',
        [$member],    'notification preferences'
    );
    same_answer(
        $preferences, 'type_preferences_for_user',
        [$member],    'notification kinds'
    );
    my $profile = same_answer(
        $c->gp_identity_store,      'profile_for_user',
        [ { user_id => $member } ], 'profile'
    );
    ok( $profile->{ok}, 'the profile is read' );
    same_answer(
        $c->gp_identity_store,             'profile_for_user',
        [ { user_id => 'not-a-member' } ], 'a missing profile'
    );
};

subtest 'member pages never reach the fork fallback' => sub {
    my $gui = GPForum::Test::GuiDriver->new( test => $t );
    $gui->install_session;
    $gui->actor($member);
    my @forked;
    my $fallback = GPForum::Infrastructure::AsyncWork->can('service_result_p');
    with_replaced_subs(
        'GPForum::Infrastructure::AsyncWork',
        {
            service_result_p => sub {
                push @forked, ref( $_[1] ) . "->$_[2]";
                return $fallback->(@_);
            },
        },
        sub {
            for my $path (
                '/mentions',                          '/messages',
                "/messages/$fixture->{conversation}", '/bookmarks',
                '/feed',                              '/following',
                '/tags',                              '/tags/bench',
                '/tagged?tags=bench',                 '/drafts',
                '/settings',
              )
            {
                $t->get_ok($path)->status_is($HTTP_OK);
            }
        }
    );
    is_deeply( \@forked, [], 'no member page forked a child to read' );
};

done_testing;

# Calls METHOD and METHOD_p with the same arguments and compares them.
sub same_answer ( $service, $method, $arguments, $name ) {
    my $async    = $method . '_p';
    my $blocking = $service->$method( @{$arguments} );
    my $promised = await_result( $service->$async( @{$arguments}, undef ) );
    is_deeply( plain($promised), plain($blocking),
        "$name: promise = blocking" );
    return $promised;
}

# Rows are objects of the same classes either way; compare their columns.
sub plain ($value) {
    my $type = ref $value;
    return $value                          if !$type;
    return [ map { plain($_) } @{$value} ] if $type eq 'ARRAY';
    return { map { $_ => plain( $value->{$_} ) } keys %{$value} }
      if $type eq 'HASH' || $value->isa('HASH');
    return "$type";
}

sub fixtures {
    my ($name) = $dbh->selectrow_array( 'SELECT username FROM users WHERE id=?',
        undef, $member );
    $dbh->do( <<'SQL', undef, $other, $member, $name, $MENTIONS );
INSERT INTO mentions
SELECT gen_random_uuid(), 'post', post_id, ?, ?, ?, now() - n * interval '1 minute'
FROM (SELECT post_id, row_number() OVER (ORDER BY post_id) AS n FROM posts
      WHERE visibility = 'public' AND moderation_state = 'visible' LIMIT ?) p
SQL
    $dbh->do(q{INSERT INTO tags (slug, name) VALUES ('bench', 'bench')});
    $dbh->do( <<'SQL', undef, $TAGGED );
INSERT INTO thread_tags
SELECT thread_id, (SELECT tag_id FROM tags WHERE slug = 'bench'), 1
FROM threads WHERE visibility = 'public' AND moderation_state = 'visible'
  AND deleted_at IS NULL ORDER BY thread_id LIMIT ?
SQL
    my ($author) = $dbh->selectrow_array( <<'SQL', undef, $member );
SELECT author_user_id FROM posts
WHERE visibility = 'public' AND moderation_state = 'visible'
  AND author_user_id <> ? LIMIT 1
SQL
    $dbh->do( <<'SQL', undef, $member, $author );
INSERT INTO subscriptions (subscription_id, user_id, target_type, target_id)
VALUES (gen_random_uuid(), ?, 'user', ?)
SQL
    my ( $lower, $higher ) = sort $member, $other;
    my ($conversation) =
      $dbh->selectrow_array( <<'SQL', undef, $lower, $higher, $member );
INSERT INTO direct_conversations
VALUES (gen_random_uuid(), ?, ?, ?, now(), now()) RETURNING conversation_id
SQL
    $dbh->do(
        <<'SQL', undef, $conversation, $member, $other, $conversation, $other, $member );
INSERT INTO direct_conversation_members
VALUES (?, ?, ?, now(), now(), 0), (?, ?, ?, now(), now(), 0)
SQL
    $dbh->do( <<'SQL', undef, $conversation, $member, $other, $MESSAGES );
INSERT INTO direct_messages OVERRIDING SYSTEM VALUE
SELECT gen_random_uuid(), ?, CASE WHEN n % 2 = 0 THEN ?::uuid ELSE ?::uuid END,
       'message ' || n, now() - (60 - n) * interval '1 minute', n
FROM generate_series(1, ?) n
SQL
    return { conversation => $conversation };
}

1;
