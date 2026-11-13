# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::service;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::CLI::FrontDoor::Launcher;
use GPForum::Command::Service;

our $VERSION = '0.001';

# `gpforum service print [TARGET]`. The work is GPForum::Command::Service's;
# a relative --to starts where the operator typed the command, which the
# front door remembers before it moves to the code directory.
has description => 'Print the service files, written for this host';

sub command ($self) {
    my $typed_in = GPForum::CLI::FrontDoor::Launcher->typed_in;

    return GPForum::Command::Service->new(
        defined $typed_in ? ( directory => $typed_in ) : () );
}

1;
