# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::os_preflight;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::OsPreflight;

our $VERSION = '0.001';

has description => 'Report whether this host can run GPForum';

sub command ($self) {
    return GPForum::Command::OsPreflight->new;
}

1;
