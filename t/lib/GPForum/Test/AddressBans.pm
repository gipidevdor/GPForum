# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AddressBans;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0146: the lookup Web::AddressBans makes, answering the scope a test
# sets, remembering the address it was asked about, and failing when told.
has scope => undef;
has asked => undef;
has fail  => 0;

sub covering ( $self, $address ) {
    if ( $self->fail ) {
        GPForum::X::Unavailable->throw( message => 'lookup failed' );
    }
    $self->asked($address);

    return $self->scope ? { scope => $self->scope } : undef;
}

1;

__END__

=head1 NAME

GPForum::Test::AddressBans - A ban lookup for the enforcement tests.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $bans = GPForum::Test::AddressBans->new( scope => 'writes' );
    $app->helper( gp_address_bans => sub { return $bans; } );

=head1 DESCRIPTION

Stands in for L<GPForum::Service::Admin::AddressBans/covering>.

=head1 SUBROUTINES/METHODS

=head2 covering

Answers C<{ scope }> when a scope is set, undef otherwise; throws
L<GPForum::X::Unavailable> when C<fail> is set.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
