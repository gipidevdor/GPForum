# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::admin;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::AdminBootstrap;

our $VERSION = '0.001';

# `gpforum admin create` and `gpforum admin grant`. The work is
# GPForum::Command::AdminBootstrap's.
has description => q{Create the forum's owner, or make a member one};

sub command ($self) {
    return GPForum::Command::AdminBootstrap->new;
}

1;
