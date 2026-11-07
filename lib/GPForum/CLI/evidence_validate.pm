# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::evidence_validate;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::EvidenceValidate;

our $VERSION = '0.001';

has description => 'Validate an evidence bundle';

sub command ($self) {
    return GPForum::Command::EvidenceValidate->new;
}

1;
