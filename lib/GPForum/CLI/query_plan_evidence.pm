# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::query_plan_evidence;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::QueryPlanEvidence;

our $VERSION = '0.001';

has description => 'Collect EXPLAIN evidence for the budgeted endpoints';

sub command ($self) {
    return GPForum::Command::QueryPlanEvidence->new;
}

1;
