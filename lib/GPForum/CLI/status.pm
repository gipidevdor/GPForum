# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::status;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Status;

our $VERSION = '0.001';

# `gpforum status`. The work is GPForum::Command::Status's.
has description => 'Ask the running forum how it is';

sub command ($self) {
    return GPForum::Command::Status->new;
}

1;
