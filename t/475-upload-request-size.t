# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Carp       qw(croak);
use Mojo::File qw(path tempfile);
use Test::Mojo;
use Test::More;

use lib 'lib';

use GPForum::Service::Attachment::Validator;

our $VERSION = '0.001';

const my $MEBIBYTE => 1_024 * 1_024;

# The transport accepts 250 MiB media plus its multipart form. Sparse files
# exercise that boundary without allocating several full-size request copies.

my $t       = Test::Mojo->new('GPForum');
my $largest = GPForum::Service::Attachment::Validator->max_bytes;

subtest 'the application takes a request as large as an attachment' => sub {
    cmp_ok( $t->app->max_request_size,
        '>', $largest,
        'more than the largest attachment, for the form around it' );

    for my $nginx (qw(deploy/nginx/gpforum.conf)) {
        my ($megabytes) =
          path($nginx)->slurp =~ /^ \s* client_max_body_size [ ] (\d+)m;/msx;
        is(
            $t->app->max_request_size,
            $megabytes * $MEBIBYTE,
            "and as much as $nginx lets through"
        );
    }
};

subtest 'an upload at the limit reaches the application whole' => sub {
    my $exceeded;
    $t->app->hook(
        before_dispatch => sub ($c) {
            $exceeded = $c->req->is_limit_exceeded ? 1 : 0;
        }
    );

    my $file   = tempfile;
    my $handle = $file->open('>');
    truncate $handle, $largest or croak 'cannot size upload fixture';
    close $handle or croak 'cannot close upload fixture';
    $t->post_ok( '/login' => form =>
          { upload => { file => "$file", filename => 'a.bin' } } );
    is( $exceeded, 0, 'a 250 MiB attachment reaches the application' );

    $handle = $file->open('>');
    truncate $handle, $largest + 2 * $MEBIBYTE
      or croak 'cannot size upload fixture';
    close $handle or croak 'cannot close upload fixture';

    $t->post_ok(
        '/login' => form => {
            upload => {
                file     => "$file",
                filename => 'a.bin'
            }
        }
    );
    is( $exceeded, 1, 'and a larger request is still cut off' );
};

done_testing();

1;
