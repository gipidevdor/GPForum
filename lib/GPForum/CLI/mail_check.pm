# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::mail_check;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::MailCheck;

our $VERSION = '0.001';

# `gpforum mail-check` answers in sentences, as every gpforum verb does;
# --json gives the evidence.
has description => 'Send a test message through the configured mailer';

sub command ($self) {
    return GPForum::Command::MailCheck->new( default_format => 'human' );
}

1;
