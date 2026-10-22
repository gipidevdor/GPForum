# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojolicious;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Admin::AddressBans;
use GPForum::Service::Operations::SecurityTelemetry;
use GPForum::Test::AddressBans;
use GPForum::Web::AddressBans;
use GPForum::Web::ClientAddress;
use GPForum::Web::ErrorPayload;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FORBIDDEN => 403;
const my $TOO_LONG       => 501;
const my $JSON           => { Accept => 'application/json' };
const my $REPEATS        => 20;

# ADR 0146: how a written range becomes the stored network, which writes
# each scope refuses, and the one place a covered request is refused.
my $bans = GPForum::Service::Admin::AddressBans->new( schema => {} );

subtest 'a written range is made the stored network' => sub {
    my %range = (
        '203.0.113.7'             => '203.0.113.7/32',
        ' 203.0.113.7/24 '        => '203.0.113.0/24',
        '10.20.30.40/16'          => '10.20.0.0/16',
        '2001:DB8:0:0::1'         => '2001:db8::1/128',
        '2001:db8:aa:bb::/48'     => '2001:db8:aa::/48',
        '2001:db8::/32'           => '2001:db8::/32',
        '::ffff:198.51.100.9'     => '198.51.100.9/32',
        '::ffff:198.51.100.0/120' => '198.51.100.0/24',
    );
    for my $written ( sort keys %range ) {
        is( $bans->range($written)->{range},
            $range{$written}, "'$written' is $range{$written}" );
    }
    for
      my $broad (qw(10.0.0.0/15 0.0.0.0/0 2001:db8::/31 ::/0 ::ffff:1.2.3.4/95))
    {
        is_deeply(
            $bans->range($broad),
            { error => 'too_broad' },
            "'$broad' is too broad"
        );
    }
    for my $wrong (
        q{},                  '1.2.3',
        '256.1.1.1',          '1.2.3.4/33',
        '2001:db8::/129',     'host.example',
        '1.2.3.4/x',          '1::2::3',
        '::ffff:1.2.3.4/129', '1.2.3.4' x $REPEATS
      )
    {
        is_deeply(
            $bans->range($wrong),
            { error => 'invalid' },
            "no range: $wrong"
        );
    }
    is( $bans->shown_range('203.0.113.7/32'),
        '203.0.113.7', 'a single IPv4 address is shown bare' );
    is( $bans->shown_range('2001:db8::1/128'),
        '2001:db8::1', 'and a single IPv6 one' );
    is( $bans->shown_range('203.0.113.0/24'),
        '203.0.113.0/24', 'a range keeps its length' );
};

subtest 'an address is read as the lookup reads it' => sub {
    is( $bans->address('198.51.100.9'),    '198.51.100.9', 'IPv4' );
    is( $bans->address('2001:0DB8::0001'), '2001:db8::1',  'IPv6, compressed' );
    is( $bans->address('::ffff:198.51.100.9'),
        '198.51.100.9', 'IPv4-mapped, as IPv4' );
    for my $none ( undef, q{}, 'connection:7', 'unix:', '1.2.3.4/24', ':::' ) {
        ok(
            !defined $bans->address($none),
            'no address: ' . ( $none // 'undef' )
        );
    }
};

subtest 'the reason is one bounded line' => sub {
    is( $bans->reason("  Spam\n\t wave  "), 'Spam wave', 'made one line' );
    ok( !defined $bans->reason(" \n "),            'an empty one is refused' );
    ok( !defined $bans->reason( 'x' x $TOO_LONG ), 'and one too long' );
    is( length $bans->reason( 'x' x $bans->maximum_reason ),
        $bans->maximum_reason, 'the longest is kept whole' );
};

subtest 'the store refuses before it calls the database' => sub {
    my %good = (
        range         => '203.0.113.0/24',
        scope         => 'writes',
        duration      => '7d',
        reason        => 'spam',
        actor_user_id => '6f1c2f1e-0f6a-4d55-9d3a-2b0d7f9a1c11',
    );
    is_deeply(
        $bans->place( { %good, range => '10.0.0.0/8' } ),
        { status => 'too_broad', field => 'range' },
        'too broad'
    );
    is_deeply(
        $bans->place( { %good, scope => 'all' } ),
        { status => 'invalid', field => 'scope' },
        'an unknown scope'
    );
    is_deeply(
        $bans->place( { %good, duration => 'forever' } ),
        { status => 'invalid', field => 'duration' },
        'an unknown length'
    );
    is_deeply(
        $bans->edit( { %good, ban_id => 'nope' } ),
        { status => 'not_found' },
        'an edit of no ban'
    );
    is_deeply(
        $bans->lift( { ban_id => 'nope' } ),
        { status => 'not_found' },
        'a lift of no ban'
    );
    ok(
        !defined $bans->covering('203.0.113.9'),
        'the in-memory doubles hold no ban'
    );
    my $error;
    try {
        $bans->place( \%good );
    }
    catch ($caught) {
        $error = $caught;
    };
    isa_ok( $error, 'GPForum::X::Unavailable',
        'a write without the function layer' );
    is_deeply( $bans->scopes,    [qw(registration sign_in writes)], 'scopes' );
    is_deeply( $bans->durations, [qw(1h 1d 7d 30d 90d 365d)],       'lengths' );
};

subtest 'what each scope refuses' => sub {
    my $web     = GPForum::Web::AddressBans->new;
    my %refused = (
        registration => [qw(register_submit)],
        sign_in      => [
            qw(register_submit login_submit login_second_factor_submit
              password_reset_request_submit password_reset_complete)
        ],
        writes => [qw(register_submit login_submit thread_create post_like)],
    );
    my @open = qw(logout locale_update theme_update unsubscribe_confirm
      privacy_export_request privacy_deletion_request
      admin_address_ban_create admin_address_ban_update
      admin_address_ban_lift);
    for my $scope ( sort keys %refused ) {
        for my $route ( @{ $refused{$scope} } ) {
            ok( $web->refuses( $scope, $route ), "$scope refuses $route" );
        }
        for my $route (@open) {
            ok( !$web->refuses( $scope, $route ), "$scope leaves $route" );
        }
    }
    ok( !$web->refuses( 'registration', 'login_submit' ),
        'a registration ban leaves sign-in' );
    ok(
        !$web->refuses( 'sign_in', 'thread_create' ),
        'a sign-in ban leaves other writes'
    );
    ok( !$web->refuses( undef, 'register_submit' ), 'no ban, no refusal' );
};

subtest 'the refusal page names no reason and no range' => sub {
    my $payload = GPForum::Web::ErrorPayload->address_banned;
    is( $payload->{status}, 'address_banned', 'its status' );
    my $page = GPForum::Web::ErrorPayload->page($payload);
    is( $page->{title_key}, 'forum.error_address_banned_title', 'its title' );
    ok( !defined $page->{detail}, 'and no detail' );
};

subtest 'a covered write is refused around its action' => sub {
    my $store     = GPForum::Test::AddressBans->new;
    my $telemetry = GPForum::Service::Operations::SecurityTelemetry->new;
    my $test      = _app( $store, $telemetry );
    $test->post_ok( '/register' => $JSON )
      ->status_is( $HTTP_OK, 'no ban: the action answers' )
      ->content_is('register_submit');
    $store->scope('registration');
    $test->post_ok( '/register' => $JSON )
      ->status_is( $HTTP_FORBIDDEN, 'a registration ban refuses it' )
      ->json_is( '/status' => 'address_banned' );
    is( $store->asked, '127.0.0.1', 'for the client address' );
    $test->post_ok('/login')->status_is( $HTTP_OK, 'and leaves sign-in' );
    $test->get_ok('/register')->status_is( $HTTP_OK, 'reads never ask' );
    $store->scope('writes');
    $test->post_ok( '/threads' => $JSON )
      ->status_is( $HTTP_FORBIDDEN, 'every write' );
    $test->post_ok('/logout')->status_is( $HTTP_OK, 'but signing out' );
    my $events = $telemetry->snapshot->{events};
    is( $events->{address_ban_refusal}{count}, 2, 'each refusal is counted' );
    $store->fail(1);
    $test->post_ok('/threads')
      ->status_is( $HTTP_OK, 'a lookup that fails lets the write on' );
};

done_testing();

sub _app ( $store, $telemetry ) {
    my $app = Mojolicious->new;
    $app->log->level('fatal');
    GPForum::Web::ClientAddress->register($app);
    $app->helper( gp_address_bans       => sub { return $store; } );
    $app->helper( gp_security_telemetry => sub { return $telemetry; } );
    my $answer = sub ($c) {
        return $c->render( text => $c->current_route );
    };
    my $routes = $app->routes;
    $routes->get('/register')->to( cb => $answer )->name('register');
    $routes->post('/register')->to( cb => $answer )->name('register_submit');
    $routes->post('/login')->to( cb => $answer )->name('login_submit');
    $routes->post('/logout')->to( cb => $answer )->name('logout');
    $routes->post('/threads')->to( cb => $answer )->name('thread_create');

    return Test::Mojo->new($app);
}

1;
