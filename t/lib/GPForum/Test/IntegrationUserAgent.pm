# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::IntegrationUserAgent;
use Mojo::Base 'Mojo::UserAgent', -signatures;
use v5.40;
use Const::Fast;
our $VERSION = '0.001';
const my $HTTP_OK => 200;
has captured => undef;

sub start ( $self, $transaction ) {
    $self->proxy->prepare($transaction);
    $self->captured($transaction);
    $transaction->res->code($HTTP_OK)->body('{}');
    $transaction->res->headers->content_type('application/json');
    return $transaction;
}
1;
