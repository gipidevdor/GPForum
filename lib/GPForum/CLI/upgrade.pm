# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::upgrade;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Upgrade;

our $VERSION = '0.001';

# `gpforum upgrade`. The work is GPForum::Command::Upgrade's.
has description => 'Print the commands that upgrade this forum';

sub command ($self) {
    return GPForum::Command::Upgrade->new;
}

1;
