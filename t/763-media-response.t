# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use Mojolicious;
use Mojo::Asset::Memory;
use lib 'lib';
use GPForum::Web::MediaResponse;

our $VERSION = '0.001';
const my $ASSET_BYTES        => 10;
const my $HTTP_OK            => 200;
const my $HTTP_PARTIAL       => 206;
const my $HTTP_NOT_MODIFIED  => 304;
const my $HTTP_UNSATISFIABLE => 416;
my $app = Mojolicious->new;
$app->routes->get('/media')->to(
    cb => sub ($c) {
        my $asset = Mojo::Asset::Memory->new->add_chunk('0123456789');
        return GPForum::Web::MediaResponse->new->render( $c, $asset, 'digest' );
    }
);
$app->renderer->paths( ['templates'] );
$app->routes->get('/markup/:kind')->to(
    cb => sub ($c) {
        my %types = (
            image => 'image/png',
            video => 'video/mp4',
            audio => 'audio/mpeg',
        );
        return $c->render(
            template   => 'components/attachment_media',
            attachment => {
                media_type        => $types{ $c->param('kind') },
                original_filename => 'Example episode'
            },
            media_url => '/mount/media?lang=it'
        );
    }
);
my $t = Test::Mojo->new($app);
$t->get_ok('/media')->status_is($HTTP_OK);
$t->content_is('0123456789')
  ->header_is( 'Accept-Ranges'  => 'bytes' )
  ->header_is( 'Content-Length' => $ASSET_BYTES );
$t->head_ok('/media')->status_is($HTTP_OK);
$t->content_is(q{})->header_is( 'Content-Length' => $ASSET_BYTES );
for my $case (
    [ 'bytes=2-5', '2345',       'bytes 2-5/10' ],
    [ 'bytes=7-',  '789',        'bytes 7-9/10' ],
    [ 'bytes=-3',  '789',        'bytes 7-9/10' ],
    [ 'bytes=0-0', '0',          'bytes 0-0/10' ],
    [ 'bytes=-20', '0123456789', 'bytes 0-9/10' ],
  )
{
    $t->get_ok( '/media' => { Range => $case->[0] } )->status_is($HTTP_PARTIAL);
    $t->content_is( $case->[1] )->header_is( 'Content-Range' => $case->[2] );
}
$t->get_ok( '/media' => { Range => 'bytes=10-' } )
  ->status_is($HTTP_UNSATISFIABLE);
$t->content_is(q{})->header_is( 'Content-Range' => 'bytes */10' );
$t->get_ok( '/media' => { Range => 'bytes=5-2' } )
  ->status_is($HTTP_UNSATISFIABLE);
$t->get_ok( '/media' => { Range => 'bytes=-0' } )
  ->status_is($HTTP_UNSATISFIABLE);
$t->get_ok( '/media' => { Range => 'bytes=2-5', 'If-Range' => '"old"' } )
  ->status_is($HTTP_OK);
$t->content_is('0123456789');
$t->get_ok( '/media' => { Range => 'bytes=2-5', 'If-Range' => '"digest"' } )
  ->status_is($HTTP_PARTIAL);
$t->content_is('2345');
$t->get_ok( '/media' => { 'If-None-Match' => '"digest"' } )
  ->status_is($HTTP_NOT_MODIFIED);
$t->content_is(q{});
$t->get_ok( '/media' => { Range => 'bytes=0-1,7-9' } )->status_is($HTTP_OK);
$t->content_is('0123456789');
$t->get_ok('/markup/image')->status_is($HTTP_OK);
$t->element_exists(
'img[loading="lazy"][alt="Example episode"][src="/mount/media?lang=it&preview=1280"]'
);
$t->element_exists(
    'a.attachment-media__image-link[href="/mount/media?lang=it"]');
$t->get_ok('/markup/video')->status_is($HTTP_OK);
$t->element_exists('video[controls][playsinline] source[type="video/mp4"]');
$t->get_ok('/markup/audio')->status_is($HTTP_OK);
$t->element_exists('audio[controls][preload="none"] source[type="audio/mpeg"]');
done_testing();

1;
