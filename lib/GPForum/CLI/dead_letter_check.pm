# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::dead_letter_check;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::DeadLetterCheck;

our $VERSION = '0.001';

has description => 'Report exhausted outbox messages';

sub command ($self) {
    return GPForum::Command::DeadLetterCheck->new;
}

1;
