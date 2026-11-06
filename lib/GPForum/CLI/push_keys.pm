# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command names are lowercase
package GPForum::CLI::push_keys;
## use critic
use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use GPForum::Command::PushKeys;
use GPForum::Command::Usage;
our $VERSION = '0.001';
has description => 'Generate or rotate Web Push signing keys';
has usage       => sub { return GPForum::Command::PushKeys->usage_text; };

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->front_door(
        GPForum::Command::PushKeys->new->run(@arguments) );
}
1;
