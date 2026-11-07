# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::benchmark;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::Benchmark;

our $VERSION = '0.001';

has description =>
  'Benchmark the application against a fixture or a live configuration';

sub command ($self) {
    return GPForum::Command::Benchmark->new;
}

1;
