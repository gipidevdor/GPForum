# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::Notification;

use JSON::MaybeXS;
use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;

our $VERSION = '0.001';

my $JSON = JSON::MaybeXS->new( utf8 => 0 );

sub get_inflated_column ( $self, $column ) {
    my $value = $self->get_column($column);
    return $JSON->decode($value)
      if $column eq 'payload' && defined $value && !ref $value;

    return $value;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ResultRow::Notification - A notification's raw and decoded payload columns.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $payload = $row->get_inflated_column('payload');

=head1 DESCRIPTION

Preserves DBIx's column contract: get_column and get_columns return the raw
JSON text, while get_inflated_column returns the decoded payload used by the
presenter. Neither operation accesses the database.

=head1 SUBROUTINES/METHODS

=head2 get_inflated_column

Decodes the payload column; returns other columns as they were fetched.

=head1 DIAGNOSTICS

Malformed JSON raises the codec's error.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ResultRow>, L<JSON::MaybeXS>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Decodes only the notification payload column.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
