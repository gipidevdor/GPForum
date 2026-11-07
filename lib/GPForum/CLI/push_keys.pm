# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command names are lowercase
package GPForum::CLI::push_keys;
## use critic
use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;
use GPForum::Command::PushKeys;
our $VERSION = '0.001';
has description => 'Generate or rotate Web Push signing keys';

sub command ($self) {
    return GPForum::Command::PushKeys->new;
}
1;
