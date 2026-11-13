# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization) -- a front-door command's package is its verb, lower-case
package GPForum::CLI::staging_host_verify;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::StagingHostVerify;

our $VERSION = '0.001';

has description => 'Verify a staging host against the deploy contract';

sub command ($self) {
    return GPForum::Command::StagingHostVerify->new;
}

1;
