# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReadinessSchema;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

# A schema whose storage hands out a handle that answers readiness's
# SELECT 1. The rest of what readiness reads goes through its call layer
# (GPForum::Test::ReadinessFunctions).
sub storage {
    my ($self) = @_;

    return $self;
}

sub dbh {
    my ($self) = @_;

    return $self;
}

sub selectrow_array {
    return 1;
}

1;
