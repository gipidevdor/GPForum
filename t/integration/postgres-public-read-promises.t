# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The public pages' reads as the web worker runs them. Without a METHOD_p
# call_p ran each blocking read in a forked child that opened a PostgreSQL
# connection of its own, one child at a time per worker: a profile, a poll,
# the sitemaps and the signing keys each paid it. Each promise read here
# must answer exactly what its blocking read answers, and the pages must not
# reach the fork fallback at all.
package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use File::Temp qw(tempdir);
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Id;
use GPForum::Service::Community::Follows;
use GPForum::Service::Discovery::SitemapPages;
use GPForum::Service::Forum::Polls;
use GPForum::Service::Identity::ProfileReader;
use GPForum::Service::Operations::LocalCache;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $HTTP_OK        => 200;
const my $HTTP_NOT_FOUND => 404;
const my $PAGE           => 2;
const my $PAST_LAST_PAGE => 99_999;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare public read promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
local $ENV{GPFORUM_POST_SIGNING_KEY} =
  tempdir( CLEANUP => 1 ) . '/post-signing.pem';
my $dbh     = $database->dbh;
my $member  = seed_id( user => 2 );
my $t       = Test::Mojo->new('GPForum');
my $c       = $t->app->build_controller;
my $fixture = fixtures();

subtest 'a public profile answers what the blocking read answers' => sub {
    my $schema  = $c->gp_schema;
    my @readers = (
        [ helper => $c->gp_profile_reader ],
        [
            uncached => GPForum::Service::Identity::ProfileReader->new(
                schema => $schema
            )
        ],
        [
            cached => GPForum::Service::Identity::ProfileReader->new(
                cache  => GPForum::Service::Operations::LocalCache->new,
                schema => $schema
            )
        ],
    );
    for my $case (@readers) {
        my ( $label, $reader ) = @{$case};
        my $first = same_answer(
            $reader, 'public_profile',
            [ uc $fixture->{username}, { limit => $PAGE } ],
            "$label: profile"
        );
        ok( $first->{ok}, "$label: the author has a profile" );
        my $profile = $first->{profile};
        ok( $profile->{threads}{next_cursor}, "$label: threads page on" );
        ok( $profile->{replies}{next_cursor}, "$label: replies page on" );
        is( $profile->{user}{avatar_id}, undef, "$label: no picture shown" );
        same_answer(
            $reader,
            'public_profile',
            [
                $fixture->{username},
                {
                    limit         => $PAGE,
                    after         => $profile->{threads}{next_cursor},
                    replies_after => $profile->{replies}{next_cursor},
                }
            ],
            "$label: second pages"
        );
        is_deeply(
            same_answer(
                $reader,                          'public_profile',
                [ 'nobody-by-this-name', undef ], "$label: a missing member"
            ),
            { ok => 0, error => 'not_found' },
            "$label: a missing member has no profile"
        );
    }
    $dbh->do( q{UPDATE users SET status = 'suspended' WHERE id = ?},
        undef, $fixture->{author} );
    is(
        same_answer(
            $c->gp_profile_reader,           'public_profile',
            [ $fixture->{username}, undef ], 'a suspended member'
        )->{error},
        'not_found',
        'a suspended member has no public profile'
    );
    $dbh->do( q{UPDATE users SET status = 'active' WHERE id = ?},
        undef, $fixture->{author} );
};

subtest 'the reader relation and follow state answer the same' => sub {
    my $relations = $c->gp_relation_store;
    is(
        same_answer(
            $relations,                      'relation_between',
            [ $member, $fixture->{author} ], 'an ignored member'
        ),
        'ignore',
        'the reader ignores the author'
    );
    is(
        same_answer(
            $relations,                      'relation_between',
            [ $fixture->{author}, $member ], 'no relation'
        ),
        undef,
        'the author holds no relation'
    );
    is(
        same_answer(
            $relations, 'relation_between', [ $member, $member ], 'oneself'
        ),
        undef,
        'nobody holds a relation to themselves'
    );
    same_answer( $relations, 'relation_between', [ undef, $member ],
        'a guest' );

    my $follows =
      GPForum::Service::Community::Follows->new( schema => $c->gp_schema );
    is(
        same_answer(
            $follows,                        'following',
            [ $member, $fixture->{author} ], 'a followed author'
        ),
        1,
        'the reader follows the author'
    );
    is(
        same_answer(
            $follows,                        'following',
            [ $fixture->{author}, $member ], 'an unfollowed member'
        ),
        0,
        'the author does not follow the reader'
    );
};

subtest 'a poll answers the same for its author, a member and a guest' => sub {
    my $polls = GPForum::Service::Forum::Polls->new( schema => $c->gp_schema );
    for my $who (
        [ author => $fixture->{author} ],
        [ member => $member ],
        [ guest  => undef ]
      )
    {
        is(
            same_answer(
                $polls,                            'overview',
                [ $who->[1], $fixture->{thread} ], "$who->[0] reads the poll"
            )->{status},
            'ok',
            "$who->[0] sees the poll"
        );
    }
    is(
        same_answer(
            $polls, 'overview',
            [ $member, GPForum::Infrastructure::Id->uuid ],
            'a missing thread'
        )->{status},
        'not_found',
        'a missing thread has no poll'
    );
};

subtest 'the sitemaps and the signing keys answer the same' => sub {
    my @services = (
        [ helper => $c->gp_sitemap_pages ],
        [
            uncached => GPForum::Service::Discovery::SitemapPages->new(
                builder => $c->gp_sitemap_builder,
                schema  => $c->gp_schema
            )
        ],
        [
            cached => GPForum::Service::Discovery::SitemapPages->new(
                builder => $c->gp_sitemap_builder,
                cache   => GPForum::Service::Operations::LocalCache->new,
                schema  => $c->gp_schema
            )
        ],
    );
    for my $case (@services) {
        my ( $label, $sitemaps ) = @{$case};
        like( same_answer( $sitemaps, 'sitemap_index', [], "$label: index" ),
            qr{/sitemap-1[.]xml}msx, "$label: the index names page one" );
        like( same_answer( $sitemaps, 'page', [1], "$label: page one" ),
            qr{<urlset}msx, "$label: page one is a URL set" );
        is(
            same_answer(
                $sitemaps,         'page',
                [$PAST_LAST_PAGE], "$label: past the end"
            ),
            undef,
            "$label: no page past the last"
        );
    }
    ok(
        scalar @{
            same_answer( $c->gp_archive, 'key_set', [], 'signing keys' )->{keys}
        },
        'the key set names the signing key'
    );
};

subtest 'public pages never reach the fork fallback' => sub {
    my $gui = GPForum::Test::GuiDriver->new( test => $t );
    $gui->install_session;
    my @forked;
    my $fallback = GPForum::Infrastructure::AsyncWork->can('service_result_p');
    my $no_picture =
        '/avatars/'
      . $fixture->{author} . q{/}
      . GPForum::Infrastructure::Id->uuid . '/64';
    my @pages = (
        [ "/u/$fixture->{username}",           $HTTP_OK ],
        [ '/u/nobody-by-this-name',            $HTTP_NOT_FOUND ],
        [ "/t/$fixture->{thread}/tools/poll",  $HTTP_OK ],
        [ '/sitemap.xml',                      $HTTP_OK ],
        [ '/sitemap-1.xml',                    $HTTP_OK ],
        [ "/sitemap-$PAST_LAST_PAGE.xml",      $HTTP_NOT_FOUND ],
        [ '/.well-known/gpforum-signing-keys', $HTTP_OK ],
        [ $no_picture,                         $HTTP_NOT_FOUND ],
    );
    with_replaced_subs(
        'GPForum::Infrastructure::AsyncWork',
        {
            service_result_p => sub {
                push @forked, ref( $_[1] ) . "->$_[2]";
                return $fallback->(@_);
            },
        },
        sub {
            for my $page (@pages) {
                $t->get_ok( $page->[0] )->status_is( $page->[1] );
            }
            $gui->actor($member);
            for my $page (@pages) {
                $t->get_ok( $page->[0] )->status_is( $page->[1] );
            }
        }
    );
    is_deeply( \@forked, [], 'no public page forked a child to read' );
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

# An active author with public threads and replies, a poll on one of the
# threads, and the member following and ignoring that author.
sub fixtures {
    my ( $author, $username ) = $dbh->selectrow_array(<<'SQL');
SELECT u.id, u.username FROM users u
WHERE u.status = 'active' AND u.deleted_at IS NULL
  AND (SELECT count(*) FROM threads t
       WHERE t.author_user_id = u.id AND t.visibility = 'public'
         AND t.moderation_state = 'visible' AND t.deleted_at IS NULL) > 2
  AND (SELECT count(*) FROM posts p
       WHERE p.author_user_id = u.id AND p.position > 1
         AND p.visibility = 'public' AND p.moderation_state = 'visible'
         AND p.deleted_at IS NULL) > 2
ORDER BY u.id LIMIT 1
SQL
    croak 'the seed has no author with public threads and replies'
      if !$author;
    croak 'the member must not be the author' if $author eq $member;
    my ($thread) = $dbh->selectrow_array( <<'SQL', undef, $author );
SELECT thread_id FROM threads
WHERE author_user_id = ? AND visibility = 'public'
  AND moderation_state = 'visible' AND deleted_at IS NULL
  AND locked_at IS NULL
ORDER BY thread_id LIMIT 1
SQL
    my $created =
      GPForum::Service::Forum::Polls->new( schema => $c->gp_schema )->change(
        {
            actor     => $author,
            command   => GPForum::Infrastructure::Id->uuid,
            thread_id => $thread,
            operation => 'create',
            values    => {
                question        => 'Which one?',
                options         => [qw(this that)],
                maximum_choices => 1,
            },
        }
      );
    croak "the poll was not created: $created->{status}"
      if $created->{status} ne 'ok';
    $dbh->do( <<'SQL', undef, $member, $author );
INSERT INTO subscriptions (subscription_id, user_id, target_type, target_id)
VALUES (gen_random_uuid(), ?, 'user', ?)
SQL
    $dbh->do( <<'SQL', undef, $member, $author );
INSERT INTO member_relations VALUES (?, ?, 'ignore', now(), now())
SQL
    return { author => $author, thread => $thread, username => $username };
}

1;
