# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RefusingMigrationSchema;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The schema the migration runner reads its handle from: its own storage,
# whose dbh is a GPForum::Test::RefusingMigrationDbh.
has 'dbh';

sub storage ($self) { return $self; }

1;
