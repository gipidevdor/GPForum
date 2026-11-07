# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SocketRateClock;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Clock', -signatures;
use v5.40;
use GPForum::Service::Operations::RateLimiter::PostgreSQLStore;

our $VERSION = '0.001';

const my $NOW_EPOCH => time;

# Loaded explicitly by the socket test's service process. Only the rate
# store's clock is held still: ten logins must share one five-minute window
# even when the real clock passes a boundary during the request sequence.
sub import ($class) {
    GPForum::Service::Operations::RateLimiter::PostgreSQLStore->attr(
        clock => sub { return $class->new; } );
    return;
}

sub now_epoch ($self) {
    return $NOW_EPOCH;
}

1;
