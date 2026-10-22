# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::CommandIdempotency;
use GPForum::Test::IdentitySecurityAudit;
use GPForum::Test::IdentityStore;
use GPForum::Test::RecordingLimiter;

our $VERSION = '0.001';

const my $HTTP_FOUND        => 302;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_TOO_MANY     => 429;
const my $DEVICE_COOKIE     => 'gpforum_device';
const my $IDENTIFIER        => 'giacomo@example.test';

# The limit on the logins one account receives, from every address
# together, let anyone lock a member out: twenty wrong passwords every five
# minutes, from anywhere, and the member's own right password was refused
# with 429 too. A browser a member has signed in from carries a signed mark
# of the account it signed in to, and that account's limit does not apply
# to it: only the limit of its own address does. Someone guessing from
# anywhere else still meets the account's limit.
my %double = (
    limiter => GPForum::Test::RecordingLimiter->new,
    store   => GPForum::Test::IdentityStore->new,
);
my $test = _client();

_login( $test, ' Giacomo@Example.test ' )
  ->status_is( $HTTP_FOUND, 'the member signs in' );
my ($mark) = grep { $_->name eq $DEVICE_COOKIE } @{ $test->tx->res->cookies };
ok( $mark, 'and the browser is given a mark of the account' );
ok( $mark && $mark->httponly, 'which scripts cannot read' );
unlike( $mark ? $mark->value : q{},
    qr/giacomo/imsx, 'and which does not carry the identifier as typed' );

_lock_account();
_login( $test, $IDENTIFIER )
  ->status_is( $HTTP_FOUND, 'an account under attack still signs in there' );
is_deeply( [ map { $_->{action} } @{ $double{limiter}->checks } ],
    ['identity.login'], 'checked against the limit of its address alone' );

$double{store} = GPForum::Test::IdentityStore->new( invalid_login => 1 );
_login( $test, $IDENTIFIER )
  ->status_is( $HTTP_UNAUTHORIZED,
    'a wrong password there is wrong, not limited' );
$double{store} = GPForum::Test::IdentityStore->new;

_lock_account();
_login( $test, 'someone.else@example.test' )
  ->status_is( $HTTP_TOO_MANY, 'another account from that browser is limited' );

my $stranger = _client();
_lock_account();
_login( $stranger, $IDENTIFIER )
  ->status_is( $HTTP_TOO_MANY, 'a browser with no mark meets the limit' );

my $forger = _client();
my $server = $forger->ua->server->url;
$forger->ua->cookie_jar->add(
    Mojo::Cookie::Response->new(
        domain => $server->host,
        name   => $DEVICE_COOKIE,
        path   => q{/},
        value  => $mark ? $mark->value =~ s/--.*\z//rmsx : 'forged',
    )
);
_lock_account();
_login( $forger, $IDENTIFIER )
  ->status_is( $HTTP_TOO_MANY, 'and so does a mark without its signature' );

done_testing();

sub _lock_account {
    $double{limiter} = GPForum::Test::RecordingLimiter->new(
        denied => { 'identity.login_account' => 1 } );

    return;
}

sub _client {
    my $client = Test::Mojo->new('GPForum');
    $client->app->log->level(q{fatal});
    $client->app->helper( gp_identity_store => sub { return $double{store} } );
    $client->app->helper( gp_identity_security_audit =>
          sub { return GPForum::Test::IdentitySecurityAudit->new; } );
    $client->app->helper( gp_command_idempotency =>
          sub { return GPForum::Test::CommandIdempotency->new; } );
    $client->app->helper( gp_rate_limiter => sub { return $double{limiter} } );

    return $client;
}

sub _login ( $client, $identifier ) {
    $client->get_ok('/login');
    my $body         = $client->tx->res->body;
    my ($token)      = $body =~ /name="csrf_token" [^>]+ value="([^"]+)"/msx;
    my ($command_id) = $body =~ /name="command_id" [^>]+ value="([^"]+)"/msx;

    return $client->post_ok(
        '/login' => form => {
            command_id => $command_id,
            csrf_token => $token,
            identifier => $identifier,
            password   => 'a password value',
        }
    );
}

1;
