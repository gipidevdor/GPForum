# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ExternalSecondFactor;

use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::Promise;
our $VERSION = '0.001';

# A member with two-step sign-in on: every sign-in is asked for its code.
sub open_challenge_p ( $self, $actor, $credential, @ ) {
    return Mojo::Promise->resolve(
        { status => 'open', token => 'pending-local-second-factor' } );
}

1;
