# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::evidence_meta;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::EvidenceMeta;

our $VERSION = '0.001';

has description => 'Summarise an evidence bundle';

sub command ($self) {
    return GPForum::Command::EvidenceMeta->new;
}

1;
