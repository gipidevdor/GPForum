# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Compress::Raw::Zlib qw(WANT_GZIP Z_STREAM_END);
use Const::Fast;
use Mojolicious::Lite -signatures;
use Test::Mojo;
use Test::More;

use lib 'lib';

use GPForum::Bootstrap::Core;

our $VERSION = '0.001';

const my $REPEAT => 200;
const my $FOUR   => 4;

# A page the public cache answers is gzipped once for as long as its bytes
# are the same, and every other response as before: each time, for the
# client that accepts it. Gzipping is counted by wrapping the one function
# that does it, and the hook is the one the application registers.
my $gzipped = 0;
{
    ## no critic (Variables::ProtectPrivateVars, Subroutines::ProtectPrivateSubs) -- the one function that gzips, counted, and the hook that calls it
    my $gzip = \&GPForum::Bootstrap::Core::_gzip;
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- the counted function replaces the real one
    *GPForum::Bootstrap::Core::_gzip = sub {
        ++$gzipped;
        return $gzip->(@_);
    };
    GPForum::Bootstrap::Core::_configure_compression(app);
    ## use critic
}

my %page = ( body => 'a public page ' x $REPEAT, etag => 'W/"one"' );
get '/public' => sub ($c) {
    $c->res->headers->header( 'X-GPForum-Source' => 'public-http-cache' );
    $c->res->headers->etag( $page{etag} );
    return $c->render( data => $page{body}, format => 'html' );
};
get '/private' => sub ($c) {
    return $c->render( data => 'a member page ' x $REPEAT, format => 'html' );
};

my $t = Test::Mojo->new;
$t->ua->transactor->compressed(0);    # the bytes as they are sent
my %gzip = ( 'Accept-Encoding' => 'gzip' );

$t->get_ok( '/public' => \%gzip )->header_is( 'Content-Encoding' => 'gzip' );
my $first = $t->tx->res->body;
$t->get_ok( '/public' => \%gzip );
is( $t->tx->res->body, $first,      'the same page gets the same bytes' );
is( $gzipped,          1,           'gzipped once' );
is( _gunzip($first),   $page{body}, 'and they are its body' );

$page{body} = 'the page changed ' x $REPEAT;
$t->get_ok( '/public' => \%gzip );
is( _gunzip( $t->tx->res->body ),
    $page{body}, 'other bytes under the same ETag are gzipped anew' );
is( $gzipped, 2, 'once more' );

$t->get_ok('/public')->header_isnt( 'Content-Encoding' => 'gzip' );
is( $t->tx->res->body, $page{body}, 'a client that asks for none gets none' );
is( $gzipped,          2,           'and nothing is gzipped for it' );

for ( 1 .. 2 ) {
    $t->get_ok( '/private' => \%gzip );
}
is( $gzipped, $FOUR, 'any other response is gzipped each time' );

done_testing();

sub _gunzip ($bytes) {
    my ($inflate) =
      Compress::Raw::Zlib::Inflate->new( -WindowBits => WANT_GZIP );
    my $plain  = q{};
    my $status = $inflate->inflate( $bytes, $plain );
    cmp_ok( $status, q{==}, Z_STREAM_END, 'a whole gzip stream' );

    return $plain;
}

1;
