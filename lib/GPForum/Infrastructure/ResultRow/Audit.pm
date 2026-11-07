# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::Audit;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;
use JSON::MaybeXS ();

our $VERSION = '0.001';

# The connection hands text back as characters (pg_enable_utf8), so the
# jsonb's text is decoded as characters, not as UTF-8 octets: metadata with
# an accent or a dash in it decodes as it was written.
my $JSON = JSON::MaybeXS->new( utf8 => 0 );

# The metadata, decoded. The call layer decodes it for the functions the
# catalogue marks; a row built from anything else may still hold the text.
sub get_inflated_column ( $self, $column ) {
    my $value = $self->get_column($column);
    return $value if $column ne 'metadata' || !defined $value || ref $value;

    return $JSON->decode($value);
}

1;
