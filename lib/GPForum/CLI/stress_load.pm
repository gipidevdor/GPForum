# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::stress_load;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::StressLoad;

our $VERSION = '0.001';

has description => 'Generate stress load against a running instance';

sub command ($self) {
    return GPForum::Command::StressLoad->new;
}

1;
