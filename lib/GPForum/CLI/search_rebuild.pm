# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::search_rebuild;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::SearchRebuild;

our $VERSION = '0.001';

has description => 'Rebuild the search index, or report its lag';

sub command ($self) {
    return GPForum::Command::SearchRebuild->new;
}

1;
