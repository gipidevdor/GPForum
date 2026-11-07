# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
# Mojolicious derives the command name from the lower-case basename.
package GPForum::CLI::api_role;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;
use GPForum::Command::ApiRole;

our $VERSION = '0.001';
has description => 'Provision the function-only PostgreSQL application role';

sub command ($self) {
    return GPForum::Command::ApiRole->new;
}

1;
