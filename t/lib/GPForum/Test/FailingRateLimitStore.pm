# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FailingRateLimitStore;

use Carp qw(croak);
use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

sub check {
    croak 'rate limit primary store unavailable';
}

sub snapshot {
    croak 'rate limit primary store unavailable';
}

1;
