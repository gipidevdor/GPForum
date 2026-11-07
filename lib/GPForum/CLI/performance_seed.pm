# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::performance_seed;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::PerformanceSeed;

our $VERSION = '0.001';

has description => 'Seed representative data for performance work';

sub command ($self) {
    return GPForum::Command::PerformanceSeed->new;
}

1;
