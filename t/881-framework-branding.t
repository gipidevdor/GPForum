# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Log;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::ForumWebServices;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_NOT_FOUND   => 404;
const my $HTTP_ERROR       => 500;
const my $ICO_HEADER_BYTES => 6;
const my $ICO_FRAME_COUNT  => 3;
const my $APPLE_ICON_SIZE  => 180;
const my $SMALL_PNG_SIZE   => 192;
const my $LARGE_PNG_SIZE   => 512;
const my $PNG_DIMENSIONS   => 16;
const my $PNG_SIZE_BYTES   => 8;
const my $PRIVATE_DETAIL   => 'private-branding-probe-never-for-the-browser';
const my $BUILTIN_MARKUP =>
  qr{Mojolicious|mojo/(?:debug|logo|notfound|failraptor)|<pre}imsx;

local $ENV{GPFORUM_SITE_NAME}        = 'Officina <Roma> & amici';
local $ENV{GPFORUM_SITE_DESCRIPTION} = 'Conversazioni, con cura.';

my $test     = Test::Mojo->new('GPForum');
my $app      = $test->app;
my $log_file = path( tempdir( CLEANUP => 1 ) )->child('requests.log');
$app->log( Mojo::Log->new( path => "$log_file", level => 'error' ) );
$app->helper(
    gp_home_page_reader => sub { return GPForum::Test::ForumWebServices->new; }
);
$app->routes->get('/__test/branding-exception')
  ->to( cb => sub ($c) { return $c->reply->exception($PRIVATE_DETAIL); } );
$app->routes->get('/__test/branding-json')->to(
    cb => sub ($c) {
        $c->exception_format('json');
        return $c->reply->exception($PRIVATE_DETAIL);
    }
);
$app->routes->get('/__test/branding-text')->to(
    cb => sub ($c) {
        $c->exception_format('txt');
        return $c->reply->not_found;
    }
);

$test->get_ok('/favicon.ico')->status_is($HTTP_OK);
$test->content_type_like(qr{image/(?:x-icon|vnd[.]microsoft[.]icon)}msx);
is(
    substr( $test->tx->res->body, 0, $ICO_HEADER_BYTES ),
    pack( 'vvv', 0, 1, $ICO_FRAME_COUNT ),
    'the implicit browser URL serves a real three-frame ICO'
);
is(
    $test->tx->res->body,
    path('assets/img/favicon.ico')->slurp,
    'the favicon is our asset, not the framework fallback'
);
$test->header_is( Server => 'GPForum' );
$test->head_ok('/favicon.ico')->status_is($HTTP_OK)->content_is(q{});

for my $export (
    [ 'apple-touch-icon.png', $APPLE_ICON_SIZE ],
    [ 'icon-192.png',         $SMALL_PNG_SIZE ],
    [ 'icon-512.png',         $LARGE_PNG_SIZE ]
  )
{
    my ( $name, $size ) = @{$export};
    $test->get_ok("/$name")->status_is($HTTP_OK);
    $test->content_type_is('image/png');
    my $header = substr $test->tx->res->body, $PNG_DIMENSIONS, $PNG_SIZE_BYTES;
    my @dimensions = unpack 'NN', $header;
    is_deeply(
        \@dimensions,
        [ $size, $size ],
        "$name carries the advertised dimensions"
    );
}

for my $mode (qw(development production)) {
    $app->mode($mode);
    for my $locale (qw(en it)) {
        my $missing = $locale eq 'it' ? 'Non trovato' : 'Not found';
        my $failed =
          $locale eq 'it'
          ? 'Si è verificato un errore'
          : 'Something went wrong';
        my $headers =
          { 'Accept-Language' => $locale, 'X-Request-ID' => 'branding-probe' };
        $test->get_ok( '/missing-branding-page' => $headers )
          ->status_is($HTTP_NOT_FOUND);
        $test->text_is( 'h1'    => $missing );
        $test->text_is( 'title' => $missing . ' - Officina <Roma> & amici' );
        $test->text_is( '.brand__name' => 'Officina <Roma> & amici' );
        $test->element_exists( 'html[lang="' . $locale . '"]' );
        $test->element_exists('link[rel="icon"][href="/icon.svg"]');
        $test->element_exists(
            'link[rel="apple-touch-icon"][href^="/apple-touch-icon.png?v="]');
        $test->element_exists(
            'main[id="content"] section[aria-labelledby="system-error-heading"]'
        );
        $test->element_exists_not('.header-search, .primary-nav, script');
        $test->content_like(qr{branding-probe}msx);
        $test->content_unlike($BUILTIN_MARKUP);
        $test->header_is( 'Cache-Control' => 'no-store' );
        $test->header_is( Server          => 'GPForum' );

        $test->get_ok( '/__test/branding-exception' => $headers )
          ->status_is($HTTP_ERROR);
        $test->text_is( 'h1'    => $failed );
        $test->text_is( 'title' => $failed . ' - Officina <Roma> & amici' );
        $test->content_unlike($BUILTIN_MARKUP);
        unlike( $test->tx->res->body,
            qr/\Q$PRIVATE_DETAIL\E/msx,
            'exception diagnostics stay out of the HTML' );
        $test->header_is( 'Cache-Control' => 'no-store' );
    }
}
like( $log_file->slurp, qr/\Q$PRIVATE_DETAIL\E/msx,
    'the exception remains in operator logs' );

$test->get_ok('/__test/branding-json')
  ->status_is($HTTP_ERROR)
  ->content_type_like(qr{application/json}msx);
$test->json_is( '/error', 'Internal Server Error' );
$test->get_ok('/__test/branding-text')
  ->status_is($HTTP_NOT_FOUND)
  ->content_type_like(qr{text/plain}msx);

$test->get_ok('/site.webmanifest')->status_is($HTTP_OK);
$test->header_is( 'Content-Type' => 'application/manifest+json' );
$test->json_is( '/name',        'Officina <Roma> & amici' );
$test->json_is( '/short_name',  'Officina <Roma> & amici' );
$test->json_is( '/description', 'Conversazioni, con cura.' );
$test->json_is( '/icons/0/src', 'icon.svg' );
$test->json_is( '/icons/1/src', 'icon-192.png' );
$test->json_is( '/icons/2/src', 'icon-512.png' );
$test->json_is( '/theme_color', '#f2f2f7' );

# A broken shared UI must still reach our independent last-resort page.
$app->helper( ui_icon => sub { croak 'broken shared UI for branding probe'; } );
for my $mode (qw(development production)) {
    $app->mode($mode);
    $test->get_ok(
        '/__test/branding-exception' => { 'Accept-Language' => 'it' } )
      ->status_is($HTTP_ERROR);
    $test->text_is( 'h1' => 'Si è verificato un errore' );
    $test->element_exists('html[data-theme="auto"]');
    $test->text_is(
        'title' => 'Si è verificato un errore - Officina <Roma> & amici' );
    $test->content_unlike($BUILTIN_MARKUP);
    $test->element_exists('link[rel="icon"][href="/icon.svg"]');
    $test->header_is( 'Cache-Control' => 'no-store' );
}
for my $asset (
    '/mojo/logo.png',       '/mojo/notfound.png',
    '/mojo/failraptor.png', '/mojo/mojo.css'
  )
{
    $test->get_ok($asset)->status_is($HTTP_NOT_FOUND);
    $test->content_type_like(qr{text/html}msx);
    $test->content_unlike($BUILTIN_MARKUP);
}

done_testing();

1;
