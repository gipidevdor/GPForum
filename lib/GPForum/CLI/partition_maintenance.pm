# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::partition_maintenance;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::PartitionMaintenance;

our $VERSION = '0.001';

has description => 'Create the next log partitions before rows reach DEFAULT';

sub command ($self) {
    return GPForum::Command::PartitionMaintenance->new( human => 1 );
}

1;
