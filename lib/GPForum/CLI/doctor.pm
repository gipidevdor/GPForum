# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::doctor;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Doctor;

our $VERSION = '0.001';

# `gpforum doctor`. The work is GPForum::Command::Doctor's.
has description =>
  'Check the settings, the host and the services, with the fixes';

sub command ($self) {
    return GPForum::Command::Doctor->new;
}

1;
