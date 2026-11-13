# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Const::Fast;
use GPForum::Test::DiscoveryController;
use GPForum::Web::DiscoveryAccess;
use Mojo::Util qw(decode);
use Test::More;

our $VERSION = '0.001';

const my $HTTP_OK              => 200;
const my $DEFAULT_FEED_LIMIT   => 25;
const my $REQUESTED_FEED_LIMIT => 10;
const my $TEXT =>
  "Caf\N{LATIN SMALL LETTER E WITH ACUTE}\N{HORIZONTAL ELLIPSIS}";
const my $UTF8_OCTETS => 8;

my $access = GPForum::Web::DiscoveryAccess->new;
is( $access->feed_limit(undef),
    $DEFAULT_FEED_LIMIT, 'feed_limit defaults a missing requested limit' );
is( $access->feed_limit($REQUESTED_FEED_LIMIT),
    $REQUESTED_FEED_LIMIT, 'feed_limit keeps an explicit requested limit' );
is( $access->feed_limit(0),
    $DEFAULT_FEED_LIMIT, 'feed_limit defaults a zero requested limit' );

my $controller = GPForum::Test::DiscoveryController->new;
my $document   = {
    content_type => 'text/plain; charset=utf-8',
    data         => 'User-agent: *',
    format       => 'txt',
    status       => $HTTP_OK,
};
$access->render_document( $controller, $document );
is(
    $controller->last_content_type,
    'text/plain; charset=utf-8',
    'render_document sets the document content type'
);
is(
    $controller->last_render->{data},
    'User-agent: *',
    'render_document renders document data'
);
is( $controller->last_render->{format},
    'txt', 'render_document keeps the document format' );
is( $controller->last_render->{status},
    $HTTP_OK, 'render_document keeps an explicit status' );

my $without_status = { %{$document} };
delete $without_status->{status};
$access->render_document( $controller, $without_status );
is( $controller->last_render->{status},
    $HTTP_OK, 'render_document defaults a missing status to HTTP 200' );

$access->render_document( $controller, { %{$document}, data => $TEXT } );
is( length $controller->last_render->{data},
    $UTF8_OCTETS, 'and sends its text as octets' );
is( decode( 'UTF-8', $controller->last_render->{data} ),
    $TEXT, 'the UTF-8 its content type names' );

done_testing();

1;
