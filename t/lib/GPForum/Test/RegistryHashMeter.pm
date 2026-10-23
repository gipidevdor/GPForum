# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::RegistryHashMeter;
use v5.40;
our $VERSION = '0.001';

# A read-only hash instrument for complexity checks; production never ties data.
sub TIEHASH ( $class, $data ) {
    return bless { data => $data, fetches => 0, iterations => 0 }, $class;
}

sub FETCH ( $self, $key ) {
    $self->{fetches}++;
    return $self->{data}{$key};
}

sub FIRSTKEY ($self) {
    $self->{iterations}++;
    keys %{ $self->{data} };
    return each %{ $self->{data} };
}

sub NEXTKEY ( $self, @ ) {
    $self->{iterations}++;
    return each %{ $self->{data} };
}
1;
