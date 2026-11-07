# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AsyncChunkStorage;
use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::Promise;
use Carp qw(croak);
our $VERSION = '0.001';
const my $CHUNK_BYTES => 1_024 * 1_024;
has bytes => '0123456789';
has reads => sub { return []; };
has fail  => 0;

sub read_chunk { croak 'synchronous chunk reads are forbidden'; }

sub read_chunk_p ( $self, $key, $number, @ ) {
    push @{ $self->reads }, $number;
    return Mojo::Promise->reject('simulated storage failure') if $self->fail;
    return Mojo::Promise->resolve->then(
        sub {
            return substr $self->bytes, $number * $CHUNK_BYTES, $CHUNK_BYTES;
        }
    );
}
1;
