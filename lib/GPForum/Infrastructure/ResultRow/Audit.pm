# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::Audit;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;
use JSON::MaybeXS qw(decode_json);

our $VERSION = '0.001';

# Audit viewers read the raw column; diagnostics read the inflated metadata.
# Keep both contracts while the fixed function returns PostgreSQL's row.
sub get_inflated_column ( $self, $column ) {
    my $value = $self->get_column($column);
    return decode_json($value) if $column eq 'metadata' && defined $value;
    return $value;
}

1;
