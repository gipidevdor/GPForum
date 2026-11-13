# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::DyingRetentionStore;

use Carp qw(croak);
use v5.40;

our $VERSION = '0.001';

# A retention store whose session purge dies, as one does when the database
# restarts under it.
sub new ($class) { return bless {}, $class }

sub purge_sessions ( $self, $input ) {
    croak "database restarted\nat the second line\n";
}

1;
