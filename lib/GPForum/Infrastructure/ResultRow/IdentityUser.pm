# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow::IdentityUser;

use Mojo::Base 'GPForum::Infrastructure::ResultRow', -signatures, -async_await;
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
    return $self->_updated(
        $functions->row(
            'identity_update_user',
            { user_id => $self->{id}, changes => $values }
        ),
        $values
    );
}

# update on the worker's pooled asynchronous connections, or on $scope: a
# transaction the caller holds.
async sub update_p ( $self, $values, $context = undef, $scope = undef ) {
    $scope //= $FUNCTIONS{ refaddr($self) };
    return $self->_updated(
        await $scope->row_p(
            'identity_update_user',
            { user_id => $self->{id}, changes => $values }, $context
        ),
        $values
    );
}

sub _updated ( $self, $stored, $values ) {
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
