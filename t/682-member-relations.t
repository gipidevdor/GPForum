# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Community::RelationStore;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Test::AllowLimiter;
use GPForum::Test::DenyLimiter;
use GPForum::Test::IdentityStore;
use GPForum::Test::RelationFunctions;
use GPForum::Test::RelationStore;
use GPForum::ViewModel::Forum::Page;

our $VERSION = '0.001';

const my $OWNER            => '11111111-1111-4111-8111-111111111111';
const my $OTHER            => '22222222-2222-4222-8222-222222222222';
const my $HTTP_OK          => 200;
const my $HTTP_FOUND       => 302;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_FORBIDDEN   => 403;
const my $HTTP_NOT_FOUND   => 404;
const my $HTTP_CONFLICT    => 409;
const my $HTTP_TOO_MANY    => 429;
const my $SESSION_SECONDS  => 3_600;
const my $MAXIMUM          => 500;
const my $TOO_LONG         => 201;
const my $JSON             => { Accept => 'application/json' };

subtest 'the store passes parameters and reads results' => sub {
    my $functions = GPForum::Test::RelationFunctions->new(
        answers => {
            community_relation_set => sub ($values) {
                return {
                    status        => 'ok',
                    other_user_id => $OTHER,
                    username      => $values->{username},
                    kind          => $values->{kind},
                };
            },
            community_relation_between => { kind    => 'block' },
            community_relation_remove  => { removed => 1 },
            community_relation_list    => [
                {
                    other_user_id => $OTHER,
                    username      => 'ada',
                    kind          => 'ignore'
                }
            ],
        }
    );
    my $store = GPForum::Service::Community::RelationStore->new(
        schema    => {},
        functions => $functions,
    );
    my $stored = $store->set_relation(
        { owner_user_id => $OWNER, username => 'ada', kind => 'block' } );
    is_deeply(
        $stored,
        {
            ok       => 1,
            status   => 'ok',
            changed  => 1,
            relation =>
              { other_user_id => $OTHER, username => 'ada', kind => 'block' },
        },
        'a block is stored and answered'
    );
    is_deeply(
        [ sort keys %{ $functions->calls->[0][1] } ],
        [qw(kind now owner_user_id username)],
        'with the owner, the username, the kind and the time'
    );

    for my $input (
        [
            { owner_user_id => $OWNER, username => 'ada', kind => 'mute' } =>
              'an unknown kind'
        ],
        [
            { owner_user_id => $OWNER, username => q{}, kind => 'ignore' } =>
              'no username'
        ],
        [
            {
                owner_user_id => $OWNER,
                username      => 'a' x $TOO_LONG,
                kind          => 'ignore'
            } => 'a username too long'
        ],
        [
            { owner_user_id => 'nope', username => 'ada', kind => 'ignore' } =>
              'an owner that is no id'
        ],
      )
    {
        my ( $values, $what ) = @{$input};
        my $before = scalar @{ $functions->calls };
        is( $store->set_relation($values)->{status},
            'invalid', "$what is invalid" );
        is( scalar @{ $functions->calls }, $before, 'without a call' );
    }

    for my $status (qw(self not_found limit forbidden)) {
        $functions->answers->{community_relation_set} = { status => $status };
        is_deeply(
            $store->set_relation(
                {
                    owner_user_id => $OWNER,
                    username      => 'ada',
                    kind          => 'ignore'
                }
            ),
            { ok => 0, status => $status },
            "a refusal ($status) is a result"
        );
    }
    $functions->answers->{community_relation_set} = {
        status        => 'unchanged',
        other_user_id => $OTHER,
        username      => 'ada',
        kind          => 'ignore'
    };
    is(
        $store->set_relation(
            { owner_user_id => $OWNER, username => 'ada', kind => 'ignore' }
        )->{changed},
        0,
        'an unchanged relation is ok and not changed'
    );

    is_deeply(
        $store->remove_relation(
            { owner_user_id => $OWNER, username => 'ada' }
        ),
        { ok => 1, status => 'ok', removed => 1 },
        'a removal counts its rows'
    );
    is( $store->relation_between( $OWNER, $OTHER ), 'block', 'the kind' );
    ok( $store->blocks( $OWNER, $OTHER ), 'a block blocks' );
    is( $store->relation_between( $OWNER, $OWNER ),
        undef, 'nobody holds a relation to themself' );
    is( $store->maximum_relations, $MAXIMUM, 'the bound is 500' );

    ok( $store->silences( $OWNER, 'reply',   $OTHER ), 'a reply is silenced' );
    ok( $store->silences( $OWNER, 'mention', $OTHER ),
        'a mention is silenced' );
    ok( !$store->silences( $OWNER, 'moderation_notice', $OTHER ),
        'a staff notice never is' );
    ok( !$store->silences( $OWNER, undef, $OTHER ), 'nor an untyped one' );
};

subtest 'without the function layer the list is empty and unwritable' => sub {
    my $store = GPForum::Service::Community::RelationStore->new( schema => {} );
    is_deeply( $store->list_for_user($OWNER), [], 'nothing is listed' );
    is( $store->relation_between( $OWNER, $OTHER ), undef, 'nothing held' );
    my $refused;
    try {
        $store->set_relation(
            { owner_user_id => $OWNER, username => 'ada', kind => 'ignore' } );
    }
    catch ($error) {
        $refused = $error;
    };
    isa_ok( $refused, 'GPForum::X::Unavailable', 'a write is refused' );
};

subtest 'the dispatcher skips a reply from a listed member' => sub {
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        schema    => {},
        relations => GPForum::Service::Community::RelationStore->new(
            schema    => {},
            functions => GPForum::Test::RelationFunctions->new(
                answers =>
                  { community_relation_between => { kind => 'ignore' } }
            ),
        ),
    );
    is_deeply(
        $dispatcher->create_notification(
            {
                recipient_user_id => $OWNER,
                notification_type => 'reply',
                source_type       => 'post',
                source_id         => $OTHER,
                payload           => { actor_id => $OTHER },
            }
        ),
        { ok => 0, skipped => 'member_relation' },
        'the reply is skipped'
    );
};

subtest 'a listed author is collapsed on the thread page' => sub {
    my $page = GPForum::ViewModel::Forum::Page->new;
    my %context =
      ( listed_members => { $OTHER => 'ignore' }, viewer_user_id => $OWNER );
    my $listed = { author_user_id => $OTHER };
    $page->_apply_relation_state( $listed, \%context );
    ok( $listed->{ignored}, 'a post by a listed member is collapsed' );
    my $own = { author_user_id => $OWNER };
    $page->_apply_relation_state( $own, \%context );
    ok( !$own->{ignored}, 'the reader\'s own post never is' );
    my $unknown = {};
    $page->_apply_relation_state( $unknown, \%context );
    ok( !$unknown->{ignored}, 'nor one without an author' );
};

subtest 'the routes ask the store and answer the member' => sub {
    my $store = GPForum::Test::RelationStore->new;
    my $test  = _client( $store, GPForum::Test::AllowLimiter->new );

    $test->get_ok('/settings/ignored')->status_is($HTTP_FOUND);
    $test->get_ok('/__test/relation-session')->status_is($HTTP_OK);
    $test->get_ok('/u/giacomo_forum');
    $test->status_is($HTTP_OK);
    $test->element_exists('form[action="/u/giacomo_forum/ignore"]');
    $test->element_exists(
        '#profile-block form[action="/u/giacomo_forum/block"]');
    my $dom  = $test->tx->res->dom;
    my $csrf = $dom->at('input[name=csrf_token]')->attr('value');

    $test->post_ok( '/u/giacomo_forum/ignore' => form => {} )
      ->status_is($HTTP_FORBIDDEN);
    is( scalar @{ $store->calls }, 0, 'a missing token changes nothing' );

    $test->post_ok(
        '/u/giacomo_forum/ignore' => form => { csrf_token => $csrf } )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => '/u/giacomo_forum' );
    is_deeply(
        $store->calls->[-1],
        [
            set => {
                owner_user_id => $OWNER,
                username      => 'giacomo_forum',
                kind          => 'ignore'
            }
        ],
        'the member is ignored'
    );
    $test->post_ok(
        '/u/giacomo_forum/block' => $JSON => form => { csrf_token => $csrf } )
      ->status_is($HTTP_OK)
      ->json_is( '/ok' => 1 );
    is( $store->calls->[-1][1]{kind}, 'block', 'and blocked' );
    $test->post_ok(
        '/u/giacomo_forum/relation/remove' => form => {
            csrf_token => $csrf,
            return_to  => '/settings/ignored'
        }
    )->status_is($HTTP_FOUND)->header_is( Location => '/settings/ignored' );
    $test->post_ok(
        '/u/giacomo_forum/relation/remove' => form => {
            csrf_token => $csrf,
            return_to  => 'https://elsewhere.invalid/'
        }
    )->status_is($HTTP_FOUND)->header_is( Location => q{/} );

    for my $refusal (
        [ limit     => $HTTP_CONFLICT ],
        [ self      => $HTTP_BAD_REQUEST ],
        [ not_found => $HTTP_NOT_FOUND ],
        [ invalid   => $HTTP_BAD_REQUEST ],
        [ forbidden => $HTTP_FORBIDDEN ],
      )
    {
        my ( $status, $code ) = @{$refusal};
        $store->answer( { ok => 0, status => $status } );
        $test->post_ok( '/u/giacomo_forum/ignore' => $JSON => form =>
              { csrf_token => $csrf } )
          ->status_is($code)
          ->json_is( '/status' => $status );
    }
    $store->answer( { ok => 0, status => 'limit' } );
    $test->post_ok(
        '/u/giacomo_forum/ignore' => form => { csrf_token => $csrf } )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => '/u/giacomo_forum' );

    $store->between('block');
    $test->get_ok('/u/giacomo_forum');
    $test->element_exists('form[action="/u/giacomo_forum/relation/remove"]');
    $test->element_exists_not('form[action="/u/giacomo_forum/ignore"]');
    $test->element_exists_not('#profile-block');
    $test->element_exists('p[role=status]');
    $store->between('ignore');
    $test->get_ok('/u/giacomo_forum')
      ->element_exists('form[action="/u/giacomo_forum/relation/remove"]')
      ->element_exists('#profile-block');
    $test->get_ok( '/u/giacomo_forum' => $JSON )
      ->json_hasnt('/relation')
      ->json_hasnt('/profile/relation');

    $store->listed(
        [
            {
                other_user_id => $OTHER,
                username      => 'ada',
                display_name  => 'Ada',
                kind          => 'block',
                updated_at    => '2026-10-15T08:00:00Z',
            }
        ]
    );
    $test->get_ok('/settings/ignored');
    $test->status_is($HTTP_OK);
    $test->header_like( 'Cache-Control' => qr/no-store/msx );
    $test->text_is( "#relation-$OTHER-heading a" => 'Ada' );
    $test->element_exists('form[action="/u/ada/relation/remove"]');
    $test->get_ok( '/settings/ignored' => $JSON )
      ->json_is( '/relations/0/username' => 'ada' )
      ->json_is( '/maximum_relations'    => $MAXIMUM );
    $store->listed( [] );
    $test->get_ok('/settings/ignored')
      ->element_exists('#relations-empty-heading');

    my $limited = _client( $store, GPForum::Test::DenyLimiter->new );
    $limited->get_ok('/__test/relation-session');
    $limited->get_ok('/u/giacomo_forum');
    my $page  = $limited->tx->res->dom;
    my $token = $page->at('input[name=csrf_token]')->attr('value');
    $limited->post_ok(
        '/u/giacomo_forum/ignore' => form => { csrf_token => $token } )
      ->status_is($HTTP_TOO_MANY);
};

done_testing();

sub _client ( $store, $limiter ) {
    my $test = Test::Mojo->new('GPForum');
    $test->app->helper( gp_relation_store => sub { return $store; } );
    $test->app->helper( gp_rate_limiter   => sub { return $limiter; } );
    $test->app->helper(
        gp_profile_reader => sub { return GPForum::Test::IdentityStore->new; }
    );
    my $routes = $test->app->routes;
    $routes->get('/__test/relation-session')->to(
        cb => sub ($c) {
            $c->session(
                user_id                  => $OWNER,
                session_expires_at_epoch => time + $SESSION_SECONDS,
            );
            return $c->render( json => { ok => 1 } );
        }
    );

    return $test;
}

1;
