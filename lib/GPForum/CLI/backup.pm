# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::backup;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::CLI::FrontDoor::Launcher;
use GPForum::Command::Backup;

our $VERSION = '0.001';

# `gpforum backup [--to DIR]`. The work is GPForum::Command::Backup's; a
# relative --to, and the backup without one, start where the operator typed
# the command, which the front door remembers before it moves to the code
# directory.
has description => 'Back up the database and the uploads';

sub command ($self) {
    my $typed_in = GPForum::CLI::FrontDoor::Launcher->typed_in;

    return GPForum::Command::Backup->new(
        defined $typed_in ? ( directory => $typed_in ) : () );
}

1;
