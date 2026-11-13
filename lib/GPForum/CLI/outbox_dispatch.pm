# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::outbox_dispatch;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::OutboxDispatch;

our $VERSION = '0.001';

has description => 'Dispatch pending outbox messages';
has usage       => sub ($self) {
    return GPForum::Command::OutboxDispatch->usage_text;
};

sub command ($self) {
    return GPForum::Command::OutboxDispatch->new(
        app   => $self->app,
        human => 1
    );
}

1;
