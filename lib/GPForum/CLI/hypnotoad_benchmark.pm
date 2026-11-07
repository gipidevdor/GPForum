# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

## no critic (NamingConventions::Capitalization)
package GPForum::CLI::hypnotoad_benchmark;
## use critic

use Mojo::Base 'GPForum::CLI::FrontDoor::Command', -signatures;
use v5.40;

use GPForum::Command::HypnotoadBenchmark;

our $VERSION = '0.001';

has description => 'Benchmark Hypnotoad, optionally behind a reverse proxy';

sub command ($self) {
    return GPForum::Command::HypnotoadBenchmark->new;
}

1;
