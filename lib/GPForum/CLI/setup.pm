# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::setup;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Setup;

our $VERSION = '0.001';

# `gpforum setup`. The work is GPForum::Command::Setup's.
has description => 'Set this host up: the settings, the database, the schema';

sub command ($self) {
    return GPForum::Command::Setup->new;
}

1;
