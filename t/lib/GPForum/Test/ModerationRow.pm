# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ModerationRow;

use Mojo::Base 'GPForum::Test::CopyingRow';
use v5.40;

our $VERSION = '0.001';

# The resultset refuses a row whose columns its result class does not have,
# as an INSERT naming an unknown column fails.
sub assert_columns {
    my ( $self, @columns ) = @_;

    for my $column (@columns) {
        $self->_assert_column($column);
    }

    return;
}

1;
