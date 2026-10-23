# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojolicious;
use Test::Mojo;
use Test::More;

use lib 'lib';
use GPForum::Config;
use GPForum::Log;

our $VERSION = '0.001';
const my $HTTP_OK => 200;

my $directory = tempdir;
my $file      = $directory->child('operations.log');
my $app       = Mojolicious->new;
my $config    = GPForum::Config->new(
    environment    => 'production',
    log_level      => 'info',
    log_path       => "$file",
    session_secret => 'operational-log-test-secret',
);
GPForum::Log->configure( $app, $config );
$app->hook(
    before_dispatch => sub ($c) {
        $c->stash( gp_request_id => $c->req->headers->header('X-Request-ID') );
        GPForum::Log->identify_request( $c, $config );
    }
);
my @retained;
$app->routes->get('/log/:actor')->to(
    cb => sub ($c) {
        my $actor = $c->stash('actor');
        $c->session( user_id => $actor eq 'guest' ? undef : $actor );
        GPForum::Log->identify_request( $c, $config );
        $c->log->info(
            "line one\nline two caf\N{LATIN SMALL LETTER E WITH ACUTE}");
        $app->log->info('application entry');
        push @retained, $c->log;
        _warning('a-secret-argument');
        $c->render( text => 'ok' );
    }
);
my $test = Test::Mojo->new($app);
$test->get_ok( '/log/member-1' => { 'X-Request-ID' => 'first' } )
  ->status_is($HTTP_OK);
$test->get_ok( '/log/guest' => { 'X-Request-ID' => 'second' } )
  ->status_is($HTTP_OK);

# Reverse completion order: retained request loggers must never share state.
$retained[1]->info('guest delayed');
$retained[0]->info('member delayed');
$app->log->info('background');
my @records = map { decode_json($_) } grep { length } split /\n/msx,
  $file->slurp;
my @warnings = grep { ( $_->{event} // q{} ) eq 'perl.warning' } @records;
is( scalar @warnings,
    2, 'production warnings became structured operational events' );
is( $warnings[0]{request_id}, 'first', 'the warning has its request id' );
like(
    $warnings[0]{warning},
    qr/operational[ ]warning/msx,
    'the original warning is retained'
);
ok( @{ $warnings[0]{stack} }, 'the warning includes stack locations' );
unlike(
    $file->slurp,
    qr/a-secret-argument|HASH[(]/msx,
    'no stack arguments or stringified context leaked'
);
my ($member) = grep { $_->{message} eq 'member delayed' } @records;
my ($guest)  = grep { $_->{message} eq 'guest delayed' } @records;
is( $member->{request_id}, 'first',
    'the delayed member logger keeps its request' );
is( $guest->{request_id}, 'second',
    'the delayed guest logger keeps its request' );
like( $member->{user_hash}, qr/\A[[:xdigit:]]{64}\z/msx,
    'the member is pseudonymized with an HMAC' );
ok( !defined $guest->{user_hash}, 'a guest has no user identifier' );
unlike( $file->slurp, qr/member-1/msx, 'the raw user id is absent' );
cmp_ok( $member->{duration_ms}, '>=', 0, 'elapsed duration is numeric' );
my ($background) = grep { $_->{message} eq 'background' } @records;
ok(
    !defined $background->{request_id},
    'the background logger has no stale request'
);
my @application = grep { $_->{message} eq 'application entry' } @records;
is_deeply(
    [ map { $_->{request_id} } @application ],
    [ 'first', 'second' ],
    'synchronous app logs inherit the current request'
);
my @multiline = grep { $_->{message} =~ /line[ ]one/msx } @records;
is(
    $multiline[0]{message},
    "line one\nline two caf\N{LATIN SMALL LETTER E WITH ACUTE}",
    'JSON preserves multiline Unicode in one physical line'
);

done_testing();

sub _warning ($secret) {
    warn "operational warning\n";
    return;
}

1;
