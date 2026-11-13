# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::dead_letter_replay;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::DeadLetterReplay;

our $VERSION = '0.001';

has description => 'Review and replay dead letters';

sub command ($self) {
    return GPForum::Command::DeadLetterReplay->new;
}

1;
