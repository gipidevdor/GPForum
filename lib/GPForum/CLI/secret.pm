# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::secret;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Secret;

our $VERSION = '0.001';

# `gpforum secret rotate session|metrics`. The work is
# GPForum::Command::Secret's.
has description => 'Rotate the session secret or the metrics token';

sub command ($self) {
    return GPForum::Command::Secret->new;
}

1;
