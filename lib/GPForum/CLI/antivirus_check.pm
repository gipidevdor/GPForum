# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::antivirus_check;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::AntivirusCheck;

our $VERSION = '0.001';

# An adapter, not a reimplementation: the work stays in
# GPForum::Command::AntivirusCheck; this makes it discoverable as
# `gpforum antivirus-check`.
has description => 'Prove the upload antivirus detects a test file';

sub command ($self) {
    return GPForum::Command::AntivirusCheck->new;
}

1;
