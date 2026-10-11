# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
# Mojolicious derives the command name from the lower-case basename.
package GPForum::CLI::api_role;
## use critic

use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use GPForum::Command::ApiRole;
use GPForum::Command::Usage;

our $VERSION = '0.001';
has description => 'Provision the function-only PostgreSQL application role';
has usage       => sub { return GPForum::Command::ApiRole->new->usage_text; };

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->front_door(
        GPForum::Command::ApiRole->new->run(@arguments) );
}

1;
