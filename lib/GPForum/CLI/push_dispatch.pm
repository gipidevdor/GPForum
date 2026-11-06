# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- Mojolicious command names are lowercase
package GPForum::CLI::push_dispatch;
## use critic
use Mojo::Base 'Mojolicious::Command', -signatures;
use v5.40;
use GPForum::Command::PushDispatch;
use GPForum::Command::Usage;
our $VERSION = '0.001';
has description => 'Dispatch encrypted Web Push notifications';
has usage       => sub { return GPForum::Command::PushDispatch->usage_text; };

sub run ( $self, @arguments ) {
    return GPForum::Command::Usage->front_door(
        GPForum::Command::PushDispatch->new( app => $self->app )
          ->run(@arguments) );
}
1;
