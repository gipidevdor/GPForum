# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PushResolver;
use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::Promise;
our $VERSION = '0.001';
const my $TTL => 60;
has peer => sub { return { address => '8.8.8.8', expires => time + $TTL }; };

sub resolve_p ( $self, $host ) {
    return Mojo::Promise->resolve( { %{ $self->peer } } );
}
1;
