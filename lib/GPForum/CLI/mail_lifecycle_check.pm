# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::mail_lifecycle_check;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::MailLifecycleCheck;

our $VERSION = '0.001';

has description => 'Exercise the mail lifecycle end to end';

sub command ($self) {
    return GPForum::Command::MailLifecycleCheck->new;
}

1;
