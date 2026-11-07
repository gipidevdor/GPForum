# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::DenyLimiter;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

sub check {
    return { ok => 0 };
}

1;
