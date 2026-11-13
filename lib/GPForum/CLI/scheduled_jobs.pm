# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::scheduled_jobs;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::ScheduledJobs;

our $VERSION = '0.001';

has description => 'Run the retention and cleanup jobs once';
has usage       => sub ($self) {
    return GPForum::Command::ScheduledJobs->usage_text;
};

sub command ($self) {
    return GPForum::Command::ScheduledJobs->new(
        app   => $self->app,
        human => 1
    );
}

1;
