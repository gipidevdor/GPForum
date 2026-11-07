# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PushUserAgent;
use Mojo::Base 'Mojo::UserAgent', -signatures;
use v5.40;
use Const::Fast;
use Mojo::Promise;
our $VERSION = '0.001';
const my $ACCEPTED => 201;
has captured => sub { return []; };

sub start_p ( $self, $transaction ) {
    push @{ $self->captured }, $transaction;
    $transaction->res->code($ACCEPTED);
    return Mojo::Promise->resolve($transaction);
}
1;
