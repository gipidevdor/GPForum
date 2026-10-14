# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FixedPassword;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A password service whose hash is a function of the password alone, so two
# databases written from the same input hold the same credential and can be
# compared row for row; the real service salts, and no two hashes agree.

sub hash_password ( $, $password ) {
    return 'fixed:' . ( $password // q{} );
}

sub verify_password ( $, $password, $encoded_hash ) {
    return ( $encoded_hash // q{} ) eq 'fixed:' . ( $password // q{} ) ? 1 : 0;
}

sub decoy_hash ($self) {
    return 'fixed:decoy';
}

1;

__END__

=head1 NAME

GPForum::Test::FixedPassword - A password service with one hash per password.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $password = GPForum::Test::FixedPassword->new;
    $password->hash_password('secret');    # 'fixed:secret'

=head1 DESCRIPTION

For differential tests that compare the rows two paths write from the same
input: the real service salts every hash, so two registrations of one
password never agree. This one answers C<fixed:> and the password.

=head1 SUBROUTINES/METHODS

=head2 hash_password

Takes a password and returns its fixed hash.

=head2 verify_password

Takes a password and a hash and answers whether the hash is the password's.

=head2 decoy_hash

The hash a login for an account that does not exist verifies against.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Never for a real account.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
