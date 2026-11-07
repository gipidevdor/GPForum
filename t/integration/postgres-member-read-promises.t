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
use GPForum::Service::Password;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $HTTP_OK    => 200;
const my $MENTIONS   => 30;
const my $MESSAGES   => 45;
const my $TAGGED     => 10;
const my $PAGE       => 10;
const my $HTTP_FOUND => 302;
const my $PASSWORD   => 'pooled-sign-in-password';

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

subtest 'settings, privacy, held posts and lookups answer the same' => sub {
    my $picture =
      same_answer( $c->gp_avatars, 'status', [$member], 'profile picture' );
    is( $picture->{pending_state},
        'checking', 'the waiting picture is read with its review' );
    same_answer( $c->gp_avatars, 'status', [$other], 'no profile picture' );
    my $two_step = same_answer( $c->gp_second_factor, 'status', [$member],
        'two-step sign-in' );
    is( $two_step->{state}, 'active', 'the member has two-step sign-in on' );
    same_answer( $c->gp_second_factor, 'status', ['not-a-member'],
        'two-step sign-in of nobody' );
    same_answer( $c->gp_passkeys, 'listed', [$member], 'passkeys' );
    is(
        scalar @{
            same_answer(
                $c->gp_relation_store, 'list_for_user',
                [$member],             'ignored members'
            )
        },
        1,
        'the member ignores one member'
    );

    for my $method (
        qw(active_holds_for_user deletion_requests_for_user
        export_requests_for_user)
      )
    {
        is(
            scalar @{
                same_answer(
                    $c->gp_data_rights_review,       $method,
                    [ $member, { limit => $PAGE } ], $method
                )
            },
            1,
            "$method lists the member's one"
        );
    }
    same_answer( $c->gp_review_store, 'mine', [ $member, $viewer ],
        'held posts' );
    ok(
        same_answer(
            $c->gp_message_store,                'recipient',
            [ $member, $fixture->{other_name} ], 'recipient'
        )->{conversation_id},
        'the recipient comes with the conversation the two hold'
    );
    same_answer( $c->gp_message_store, 'recipient',
        [ $member, 'nobody-of-that-name' ],
        'no recipient' );
    for my $identifier ( $fixture->{name}, 'nobody-of-that-name', q{} ) {
        same_answer( $c->gp_identity_store, 'account_id_for', [$identifier],
            "account of '$identifier'" );
    }
    is(
        await_result(
            $c->gp_identity_store->account_id_for_p( uc $fixture->{name} )
        ),
        $member,
        'the account is found by its name in any case'
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
                '/mentions',
                '/messages',
                "/messages/$fixture->{conversation}",
                '/bookmarks',
                '/feed',
                '/following',
                '/tags',
                '/tags/bench',
                '/tagged?tags=bench',
                '/drafts',
                '/settings',
                '/settings/avatar',
                '/settings/security',
                '/settings/passkeys',
                '/settings/ignored',
                '/privacy',
                '/pending',
                "/messages/new/$fixture->{stranger_name}",
              )
            {
                $t->get_ok($path)->status_is($HTTP_OK);
            }
        }
    );
    is_deeply( \@forked, [], 'no member page forked a child to read' );
};

# The sign-in still forks for the Argon2 check (Workflow::login) and the
# audit row it writes; the account lookup for its rate limit and the
# two-step check after it read on the pooled connections.
subtest 'signing in reads its lookups on pooled connections' => sub {
    my $guest = Test::Mojo->new;
    $guest->app( $t->app );
    $guest->get_ok('/login')->status_is($HTTP_OK);
    my $form = $guest->tx->res->dom;
    my @forked;
    my $fallback = GPForum::Infrastructure::AsyncWork->can('service_result_p');
    with_replaced_subs(
        'GPForum::Infrastructure::AsyncWork',
        {
            service_result_p => sub {
                push @forked, "$_[2]";
                return $fallback->(@_);
            },
        },
        sub {
            $guest->post_ok(
                '/login' => form => {
                    command_id =>
                      $form->at('input[name=command_id]')->attr('value'),
                    csrf_token =>
                      $form->at('input[name=csrf_token]')->attr('value'),
                    identifier => $fixture->{signer},
                    password   => $PASSWORD,
                }
              )
              ->status_is($HTTP_FOUND)
              ->header_is( Location => q{/}, 'the member is signed in' );
        }
    );
    is_deeply( [ grep { $_ eq 'account_id_for' || $_ eq 'status' } @forked ],
        [], 'the account lookup and the two-step check fork no child' );
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
    my ( $other_name, $stranger_name ) = map {
        $dbh->selectrow_array( 'SELECT username FROM users WHERE id=?',
            undef, $_ )
    } $other, seed_id( user => 4 );
    $dbh->do( <<'SQL', undef, $member, $other );
INSERT INTO member_relations VALUES (?, ?, 'ignore', now(), now())
SQL
    $dbh->do( <<'SQL', undef, $member );
INSERT INTO second_factors
VALUES (?, 'active', 'sealed', 'key', 0, now(), now(), now())
SQL
    my ($picture) = $dbh->selectrow_array( <<'SQL', undef, $member );
INSERT INTO attachments (attachment_id, owner_user_id, object_key,
    original_filename, media_type, byte_size, checksum, state, scan_status)
VALUES (gen_random_uuid(), ?, 'avatars/pooled-read', 'me.png', 'image/png',
    1, 'checksum', 'uploaded', 'clean') RETURNING attachment_id
SQL
    $dbh->do( <<'SQL', undef, $picture );
INSERT INTO attachment_content_reviews (attachment_id, source_kind)
VALUES (?, 'original')
SQL
    $dbh->do( <<'SQL', undef, $member, $picture );
INSERT INTO member_avatars (user_id, pending_attachment_id, pending_state,
    pending_at) VALUES (?, ?, 'checking', now())
SQL
    $dbh->do( <<'SQL', undef, $member, $member );
INSERT INTO deletion_requests (deletion_request_id, requester_user_id,
    resource_type, resource_id, request_type)
VALUES (gen_random_uuid(), ?, 'user', ?, 'soft_delete')
SQL
    $dbh->do( <<'SQL', undef, $member, $member );
INSERT INTO export_requests (export_request_id, requester_user_id,
    subject_user_id, export_type) VALUES (gen_random_uuid(), ?, ?, 'user_data')
SQL
    $dbh->do( <<'SQL', undef, $member );
INSERT INTO retention_holds (retention_hold_id, resource_type, resource_id,
    reason) VALUES (gen_random_uuid(), 'user', ?, 'legal hold')
SQL
    my $hash = GPForum::Service::Password->new->hash_password($PASSWORD);
    my ($signer) = $dbh->selectrow_array( <<'SQL', undef, $hash );
INSERT INTO users (id, username, display_name, email_normalized,
    password_hash, status) VALUES (gen_random_uuid(), 'pooled-signer',
    'Pooled signer', 'pooled-signer@example.test', ?, 'active') RETURNING id
SQL
    $dbh->do( <<'SQL', undef, $signer, $hash );
INSERT INTO credentials (id, user_id, type, secret_hash)
VALUES (gen_random_uuid(), ?, 'password', ?)
SQL
    return {
        conversation  => $conversation,
        name          => $name,
        other_name    => $other_name,
        stranger_name => $stranger_name,
        signer        => 'pooled-signer',
    };
}

1;
