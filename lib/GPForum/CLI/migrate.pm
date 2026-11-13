# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::migrate;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Migrate;

our $VERSION = '0.001';

# An adapter, not a reimplementation: the work stays in
# GPForum::Command::Migrate. `gpforum migrate` does it -- the migrations, the
# partition window, the query budgets -- without being told --apply.
has description => 'Bring the database up to date';

sub command ($self) {
    return GPForum::Command::Migrate->new( default_mode => 'apply' );
}

1;
