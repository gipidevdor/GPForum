# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::IdentityUser;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures;
use v5.40;
use Scalar::Util qw(refaddr);

our $VERSION = '0.001';

# Keep the call layer out of the row's column hash: callers can serialize
# the columns, and get_columns stays the exact user row the database read.
my %FUNCTIONS;

sub from ( $class, $row, $functions ) {
    return undef if ref $row ne 'HASH';
    my $user = $class->SUPER::from($row);
    $FUNCTIONS{ refaddr($user) } = $functions;
    return $user;
}

# AccountStore and PreferenceStore retain their validated input and their
# surrounding transaction while the persistence step becomes a fixed call.
sub update ( $self, $values ) {
    my $functions = $FUNCTIONS{ refaddr($self) };
    my $stored    = $functions->row( 'identity_update_user',
        { user_id => $self->{id}, changes => $values } );
    if ($stored) {
        %{$self} = ( %{$stored}, %{$values}, status => $stored->{status} );
    }
    return $self;
}

sub DESTROY ($self) {
    delete $FUNCTIONS{ refaddr($self) };
    return;
}

1;
