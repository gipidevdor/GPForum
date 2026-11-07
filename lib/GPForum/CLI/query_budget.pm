# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::query_budget;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::QueryBudget;

our $VERSION = '0.001';

has description => 'Print, sync or check the query-plan budget catalog';

sub command ($self) {
    return GPForum::Command::QueryBudget->new( human => 1 );
}

1;
