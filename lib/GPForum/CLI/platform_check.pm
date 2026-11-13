# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::platform_check;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::PlatformCheck;

our $VERSION = '0.001';

has description =>
  'Check the platform prerequisites, with or without a database';

sub command ($self) {
    return GPForum::Command::PlatformCheck->new;
}

1;
