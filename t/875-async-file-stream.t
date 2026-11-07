# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use Carp    qw(croak);
use English qw(-no_match_vars);
use Test::Mojo;
use Mojolicious;
use File::Temp;
use lib 'lib', 't/lib';
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Controller::Base;
use GPForum::Infrastructure::FileAsset;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';
const my $REPEAT_BYTES      => 70_000;
const my $HTTP_OK           => 200;
const my $HTTP_PARTIAL      => 206;
const my $HTTP_NOT_MODIFIED => 304;
const my $RANGE_START       => 3;
const my $RANGE_LENGTH      => 17;
my $file = File::Temp->new( UNLINK => 1 );
binmode $file;
my $bytes = pack( 'H*', '00ff3c2625' ) x $REPEAT_BYTES;
print {$file} $bytes or croak 'cannot write stream fixture';
$file->flush;
my $path = $file->filename;
my $app  = Mojolicious->new;
$app->log->level('fatal');
$app->controller_class('GPForum::Controller::Base');
$app->routes->get('/file')
  ->to(
    cb => sub ($c) { return $c->file_p( $path, 'application/octet-stream' ); }
  );
my $test = Test::Mojo->new($app);
{
    my $start  = GPForum::Infrastructure::Subprocess->can('_start');
    my $starts = 0;
    with_replaced_subs(
        'GPForum::Infrastructure::Subprocess',
        {
            _start => sub { ++$starts; return $start->(@_); },
        },
        sub {
            $test->get_ok('/file')->status_is($HTTP_OK)->content_is($bytes);
            is( $starts, 1,
                'metadata and multiple binary chunks use one subprocess' );
        }
    );
}
my $headers = $test->tx->res->headers;
my $etag    = $headers->etag;
$test->get_ok( '/file' => { Range => 'bytes=3-19' } )
  ->status_is($HTTP_PARTIAL)
  ->content_is( substr $bytes, $RANGE_START, $RANGE_LENGTH );
$test->head_ok('/file')->status_is($HTTP_OK)->content_is(q{});
$test->get_ok( '/file' => { 'If-None-Match' => $etag } )
  ->status_is($HTTP_NOT_MODIFIED)
  ->content_is(q{});
my $asset =
  await_result( GPForum::Infrastructure::FileAsset->from_path_p($path) );
open my $changed, '>>:raw', $path or croak $OS_ERROR;
print {$changed} 'changed' or croak 'cannot change stream fixture';
close $changed             or croak 'cannot close changed fixture';
my $error;
$asset->get_chunk_p(0)
  ->catch( sub ($caught) { $error = "$caught"; return; } )
  ->wait;
like(
    $error,
    qr/file[ ]changed[ ]while[ ]streaming/msx,
    'a file replacement cannot silently change a captured response'
);
done_testing();

1;
