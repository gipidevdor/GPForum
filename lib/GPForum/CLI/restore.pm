# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::restore;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::CLI::FrontDoor::Launcher;
use GPForum::Command::Restore;

our $VERSION = '0.001';

# `gpforum restore --check DIR`. The work is GPForum::Command::Restore's; a
# relative DIR starts where the operator typed the command, which the front
# door remembers before it moves to the code directory.
has description => 'Check that a backup can be restored';

sub command ($self) {
    my $typed_in = GPForum::CLI::FrontDoor::Launcher->typed_in;

    return GPForum::Command::Restore->new(
        defined $typed_in ? ( directory => $typed_in ) : () );
}

1;
