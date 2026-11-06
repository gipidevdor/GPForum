# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::Asset::Memory;
use Test::More;

use lib 'lib', 't/lib';
use GPForum::Service::Attachment::PostgresAsset;
use GPForum::Service::Attachment::PostgresStorage;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';

const my $CHUNK_BYTES => 1_024 * 1_024;
const my $HTTP_CHUNK  => 131_072;

my $bytes = ( 'a' x $CHUNK_BYTES ) . 'tail';
my @reads;
my $asset = GPForum::Service::Attachment::PostgresAsset->new(
    storage =>
      GPForum::Service::Attachment::PostgresStorage->new( schema => {} ),
    object_key => 'binary',
    byte_size  => length $bytes,
);

with_replaced_subs(
    'GPForum::Service::Attachment::PostgresStorage',
    {
        read_chunk => sub ( $storage, $key, $number ) {
            push @reads, $number;
            return substr $bytes, $number * $CHUNK_BYTES, $CHUNK_BYTES;
        },
    },
    sub {
        is( $asset->get_chunk( 0, 0 ), q{}, 'an empty read returns no bytes' );
        is_deeply( \@reads, [], 'an empty read performs no storage query' );
        is( $asset->get_chunk( length $bytes ),
            q{}, 'reading past EOF returns no bytes' );
        is_deeply( \@reads, [], 'EOF performs no storage query' );

        my $memory = Mojo::Asset::Memory->new->add_chunk($bytes);
        is(
            length $asset->get_chunk( 0, undef ),
            length $memory->get_chunk( 0, undef ),
            'an explicit undef uses the Mojo chunk default'
        );
        is( length $asset->get_chunk(0),
            $HTTP_CHUNK, 'an omitted maximum uses the same default' );
        is_deeply( \@reads, [0], 'sequential reads share one database chunk' );

        is( $asset->get_chunk( $CHUNK_BYTES, 0 ),
            q{}, 'an empty seek returns no bytes' );
        is( $asset->get_chunk( 0, 1 ),
            'a', 'the previous database chunk remains available' );
        is_deeply( \@reads, [0],
            'an empty seek neither queries nor evicts a cached chunk' );
        is( $asset->get_chunk($CHUNK_BYTES),
            'tail', 'a real seek reads the next chunk' );
        is_deeply( \@reads, [ 0, 1 ], 'one database read per visited chunk' );
    }
);

done_testing();

1;
