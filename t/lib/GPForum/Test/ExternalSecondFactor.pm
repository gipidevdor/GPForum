# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ExternalSecondFactor;

use Mojo::Base -base, -signatures;
use v5.40;
our $VERSION = '0.001';

sub open_challenge ( $self, $actor, $credential ) {
    return { status => 'open', token => 'pending-local-second-factor' };
}

1;
