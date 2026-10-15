# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Test::Mojo;
use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::PostingAutomod;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Moderation::Automod;
use GPForum::Service::Moderation::AutomodStore;
use GPForum::Test::AllowLimiter;
use GPForum::Test::AllowPermissionGate;
use GPForum::Test::AutomodFunctions;
use GPForum::Test::AutomodStore;
use GPForum::Test::DenyPermissionGate;

our $VERSION = '0.001';

const my $AUTHOR          => '11111111-1111-4111-8111-111111111111';
const my $STAFF           => '22222222-2222-4222-8222-222222222222';
const my $POST            => '33333333-3333-4333-8333-333333333333';
const my $WORD            => '44444444-4444-4444-8444-444444444444';
const my $HTTP_OK         => 200;
const my $HTTP_FOUND      => 302;
const my $HTTP_INVALID    => 400;
const my $HTTP_FORBIDDEN  => 403;
const my $HTTP_CONFLICT   => 409;
const my $SESSION_SECONDS => 3_600;
const my $HAYSTACK        => 200_000;
const my $FAST_ENOUGH     => 2;
const my $THREE           => 3;
const my $TOO_LONG        => 101;
const my $BELL            => chr 7;
const my $PAST_THE_SPAN   => 40;
const my $JSON            => { Accept => 'application/json' };

my $automod = GPForum::Service::Moderation::Automod->new;

subtest 'a watched word is plain words, a star only at an end' => sub {
    is( $automod->phrase('  Buy   NOW '), 'buy now', 'whitespace and case' );
    is( $automod->phrase('Spam*'),        'spam*',   'a trailing star' );
    is( $automod->phrase('*hole'),        '*hole',   'a leading star' );
    for my $wrong ( q{}, q{*}, 'a*b', '**x', q{$$$}, "x$BELL", 'x' x $TOO_LONG )
    {
        is( $automod->phrase($wrong), undef, "'$wrong' is not one" );
    }
    is( $automod->replacement(' [gone] '), '[gone]', 'a replacement' );
    is( $automod->replacement( 'x' x $TOO_LONG ),
        undef, 'at most 100 characters' );
    is( $automod->link_limit(q{}),   q{},    'an empty limit is no limit' );
    is( $automod->link_limit('3'),   $THREE, 'a limit' );
    is( $automod->link_limit('101'), undef,  'at most 100' );
    is( $automod->link_limit('-1'),  undef,  'never negative' );
    is( $automod->trust_level('x'),  undef,  'a trust level is a number' );
};

subtest 'matching is whole words, bounded wildcards, any case' => sub {
    my $match = sub ( $phrase, $text ) {
        return $text =~ $automod->pattern($phrase) ? 1 : 0;
    };
    is( $match->( 'spam',    'SPAM!' ),        1, 'any case' );
    is( $match->( 'spam',    'spammer' ),      0, 'a whole word' );
    is( $match->( 'spam*',   'spammers' ),     1, 'or its start' );
    is( $match->( '*hole',   'a rathole' ),    1, 'or its end' );
    is( $match->( 'buy now', "buy\n  now" ),   1, 'any spacing' );
    is( $match->( 'école',   'ÉCOLE privée' ), 1, 'beyond ASCII' );
    is( $match->( 'a.b',     'axb' ),          0, 'punctuation is literal' );
    is( $match->( '*x*', 'y' x $PAST_THE_SPAN . 'x' ), 0, 'a star reaches 32' );
    my $started = time;

    for my $phrase (qw(*a* *aa* a*)) {
        $match->( $phrase, 'a' x $HAYSTACK . q{!} );
    }
    cmp_ok( time - $started,
        q{<}, $FAST_ENOUGH,
        'a long run cannot make a pattern backtrack without end' );
    is( $automod->count_links('[a](http://x.y) <https://z> www.a.b'),
        $THREE, 'links in Markdown' );
    is( $automod->count_links('mail me@www.example or http://'),
        0, 'an address or a bare scheme is no link' );
};

subtest 'a verdict blocks, flags and replaces' => sub {
    my $rules = {
        words => [
            { phrase => 'forbidden', action => 'block' },
            { phrase => 'spam*',     action => 'flag' },
            { phrase => 'darn',      action => 'replace', replacement => q{} },
        ],
        link_limit       => 1,
        link_trust_below => 1,
        link_action      => 'flag',
        trust_level      => 0,
    };
    my $verdict = $automod->screen( $rules,
        { title => 'Forbidden', body_source => 'Darn spammers at www.a.b' } );
    is_deeply(
        $verdict->{blocked},
        { title => ['forbidden'] },
        'a block names the field'
    );
    ok( $automod->refuses($verdict), 'and refuses' );
    is_deeply( $verdict->{flagged}, ['spam*'], 'a flag' );
    is(
        $verdict->{fields}{body_source},
        '*** spammers at www.a.b',
        'a replace with the default'
    );

    $verdict = $automod->screen( $rules,
        { body_source => 'http://a.b and http://c.d' } );
    is( $verdict->{link_over}, 'flag', 'too many links from a new member' );
    ok( !$automod->refuses($verdict), 'are flagged, not refused' );
    ok( $automod->flags($verdict),    'into the queue' );
    $verdict = $automod->screen( { %{$rules}, trust_level => 1 },
        { body_source => 'http://a.b and http://c.d' } );
    is( $verdict->{link_over}, undef, 'a trusted member is not limited' );
    $verdict = $automod->screen( { %{$rules}, link_limit => undef },
        { body_source => 'http://a.b and http://c.d' } );
    is( $verdict->{link_over}, undef, 'nor anyone with the rule off' );
};

subtest 'the store validates before it calls' => sub {
    my $functions = GPForum::Test::AutomodFunctions->new;
    my $store     = GPForum::Service::Moderation::AutomodStore->new(
        schema    => {},
        functions => $functions,
    );
    is( $store->add_word( { phrase => 'a*b', action => 'flag' } )->{field},
        'phrase', 'a malformed phrase' );
    is( $store->add_word( { phrase => 'x', action => 'ban' } )->{field},
        'action', 'an unknown action' );
    is(
        $store->set_link_rule(
            {
                link_limit       => 'x',
                link_trust_below => 1,
                link_action      => 'block'
            }
        )->{field},
        'link_limit',
        'a malformed limit'
    );
    is( $store->remove_word( { word_id => 'nope' } )->{removed},
        0, 'a malformed id removes nothing' );
    is( scalar @{ $functions->calls }, 0, 'and none of them calls' );

    my $added = $store->add_word(
        {
            actor_user_id => $STAFF,
            phrase        => 'Casino',
            action        => 'flag',
            replacement   => 'ignored'
        }
    );
    my ( $name, $values ) = @{ $functions->calls->[-1] };
    is( $name, 'moderation_watched_word_add', 'a word is added' );
    is_deeply(
        [ @{$values}{qw(phrase action replacement actor_user_id)} ],
        [ 'casino', 'flag', q{}, $STAFF ],
        'as kept, a replacement only for replace'
    );
    is_deeply(
        [ @{ $values->{audit} }{qw(action actor_id target_type)} ],
        [ 'automod.word_added', $STAFF, 'automod_rule' ],
        'with its audit'
    );
    ok( $added->{ok}, 'and answered' );
    $store->set_link_rule(
        {
            actor_user_id    => $STAFF,
            link_limit       => q{},
            link_trust_below => '2',
            link_action      => 'flag'
        }
    );
    is_deeply(
        [ @{ $functions->calls->[-1][1] }{qw(link_limit link_trust_below)} ],
        [ undef, 2 ],
        'an empty limit is the rule off'
    );

    my $bare = GPForum::Service::Moderation::AutomodStore->new( schema => {} );
    is( $bare->rules_for($AUTHOR), undef, 'no function layer, no rules' );
    is_deeply( $bare->words, [], 'and no words' );
};

subtest 'a write is screened, refused, rewritten or flagged' => sub {
    my $store = GPForum::Test::AutomodStore->new(
        rules => {
            words => [
                { phrase => 'forbidden', action => 'block' },
                { phrase => 'spam*',     action => 'flag' },
                {
                    phrase      => 'darn',
                    action      => 'replace',
                    replacement => 'gosh'
                },
            ],
            link_limit       => undef,
            link_trust_below => 1,
            link_action      => 'block',
            trust_level      => 0,
        }
    );
    my $guard = GPForum::Service::Forum::PostingAutomod->new( store => $store );
    my $input = { author_user_id => $AUTHOR, body_source => 'forbidden!' };

    my $screen = $guard->screen( 'reply.create', $input );
    is_deeply(
        [ @{ $screen->{refusal} }{qw(ok status error)} ],
        [ 0, 'invalid', 'automod' ],
        'a block refuses as invalid'
    );
    is_deeply(
        $screen->{refusal}{automod},
        {
            field   => 'body_source',
            reason  => 'watched_word',
            phrases => ['forbidden'],
            limit   => undef,
            links   => 0
        },
        'naming the field and the word'
    );
    is( $store->recorded->[-1]{audits}[0]{action},
        'automod.blocked', 'and audits the decision' );

    my $staff = GPForum::Service::Forum::Viewer->new( moderates => 1 );
    is_deeply(
        $guard->screen( 'reply.create', { %{$input}, viewer => $staff } ),
        { input => { %{$input}, viewer => $staff } },
        'staff who moderate are not screened'
    );
    is_deeply(
        $guard->screen( 'post.delete', $input ),
        { input => $input },
        'nor is a delete'
    );

    $screen = $guard->screen( 'reply.create',
        { author_user_id => $AUTHOR, body_source => 'darn spammers' } );
    is( $screen->{input}{body_source}, 'gosh spammers', 'a replace rewrites' );
    ok( $screen->{settle}, 'and the decisions are recorded with the write' );
    my $written = {
        ok     => 1,
        status => 'ok',
        stored => { post => { post_id => $POST } }
    };
    my $result = $guard->settle( 'reply.create', $screen,
        sub ($given) { return $written; } );
    is( $result,              $written, 'the write answers' );
    is( $store->transactions, 1,        'inside one transaction' );
    my $decisions = $store->recorded->[-1];
    is_deeply(
        [ map { $_->{action} } @{ $decisions->{audits} } ],
        [ 'automod.replaced', 'automod.flagged' ],
        'each decision audited'
    );
    is_deeply(
        $decisions->{report},
        {
            target_type => 'post',
            target_id   => $POST,
            reason      => 'automod.watched_word',
            details     => q{"spam*"}
        },
        'and the post reported by the system'
    );

    my $count = scalar @{ $store->recorded };
    $guard->settle( 'reply.create', $screen,
        sub ($given) { return { %{$written}, idempotent => 1 }; } );
    is( scalar @{ $store->recorded }, $count, 'a replay records nothing' );

    $store->fail(1);
    is_deeply(
        $guard->settle( 'reply.create', $screen, sub ($given) { $written } ),
        {
            ok     => 0,
            status => 'failed',
            error  => 'automod record failed'
        },
        'a failed record fails the write'
    );
    $store->fail(0);

    my $none = GPForum::Service::Forum::PostingAutomod->new(
        store => GPForum::Test::AutomodStore->new(
            rules => { words => [], link_limit => undef }
        )
    );
    is_deeply(
        $none->screen( 'reply.create', $input ),
        { input => $input },
        'no rules, nothing screened'
    );
};

subtest 'the admin console asks the store and answers staff' => sub {
    my $store = GPForum::Test::AutomodStore->new(
        rules => {
            words            => [],
            link_limit       => 2,
            link_trust_below => 1,
            link_action      => 'block'
        },
        words => [
            {
                word_id     => $WORD,
                phrase      => 'casino',
                action      => 'replace',
                replacement => q{},
                created_at  => '2026-10-15T10:00:00Z',
            }
        ],
    );
    my $test = _client( $store, GPForum::Test::AllowPermissionGate->new );
    $test->get_ok('/admin/automod')->status_is($HTTP_OK);
    $test->text_is( 'table code' => 'casino' );
    $test->element_exists('input[name=link_limit][value="2"]');
    $test->element_exists(qq{form[action="/admin/automod/words/$WORD/remove"]});
    my $dom  = $test->tx->res->dom;
    my $csrf = $dom->at('input[name=csrf_token]')->attr('value');

    $test->post_ok(
        '/admin/automod/words' => form => { phrase => 'x', action => 'flag' } )
      ->status_is($HTTP_FORBIDDEN);
    is( scalar @{ $store->calls }, 0, 'no token, no change' );
    $test->post_ok(
        '/admin/automod/words' => form => {
            csrf_token  => $csrf,
            phrase      => 'Poker',
            action      => 'block',
            replacement => q{}
        }
    )->status_is($HTTP_FOUND)->header_is( Location => '/admin/automod' );
    is_deeply(
        $store->calls->[-1],
        [
            add_word => {
                actor_user_id => $STAFF,
                phrase        => 'Poker',
                action        => 'block',
                replacement   => q{}
            }
        ],
        'a word is added by the staff member'
    );
    $store->answer( { ok => 0, status => 'duplicate' } );
    $test->post_ok(
        '/admin/automod/words' => $JSON => form => {
            csrf_token => $csrf,
            phrase     => 'Poker',
            action     => 'block'
        }
    )->status_is($HTTP_CONFLICT)->json_is( '/status' => 'duplicate' );
    $store->answer( { ok => 0, status => 'invalid', field => 'link_limit' } );
    $test->post_ok(
        '/admin/automod/links' => form => {
            csrf_token       => $csrf,
            link_limit       => 'x',
            link_trust_below => 1,
            link_action      => 'block'
        }
    )->status_is($HTTP_FOUND);
    $test->get_ok('/admin/automod')
      ->content_like(qr/The [ ] link [ ] limit [ ] is [ ] a [ ] number/msx);
    $store->answer(undef);
    $test->post_ok( "/admin/automod/words/$WORD/remove" => $JSON => form =>
          { csrf_token => $csrf } )->status_is($HTTP_OK);
    is( $store->calls->[-1][1]{word_id}, $WORD, 'a word is removed' );

    my $denied = _client( $store, GPForum::Test::DenyPermissionGate->new );
    $denied->get_ok('/admin/automod')->status_is($HTTP_FORBIDDEN);
};

done_testing();

sub _client ( $store, $gate ) {
    my $test = Test::Mojo->new('GPForum');
    $test->app->helper( gp_automod_store   => sub { return $store; } );
    $test->app->helper( gp_permission_gate => sub { return $gate; } );
    $test->app->helper(
        gp_rate_limiter => sub { return GPForum::Test::AllowLimiter->new; } );
    my $routes = $test->app->routes;
    $routes->get('/__test/automod-session')->to(
        cb => sub ($c) {
            $c->session(
                user_id                  => $STAFF,
                session_expires_at_epoch => time + $SESSION_SECONDS,
            );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/automod-session')->status_is($HTTP_OK);

    return $test;
}

1;
