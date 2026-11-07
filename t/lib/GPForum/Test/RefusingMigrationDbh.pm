# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RefusingMigrationDbh;

use Mojo::Base -base, -signatures;
use v5.40;

use Carp qw(croak);

our $VERSION = '0.001';

# A PostgreSQL handle as the migration runner meets it: lock_timeout set,
# and the statements naming `failing` fail with the SQLSTATE in `fails`.
has failing    => q{};
has state      => q{};
has fails      => undef;
has statements => sub { return []; };

sub selectrow_array ( $self, $sql, @bind ) {
    push @{ $self->statements }, $sql;
    return '3s' if $sql eq 'SHOW lock_timeout';
    $self->_maybe_fail($sql);

    return 1;
}

sub selectall_arrayref ( $self, $sql, @bind ) {
    push @{ $self->statements }, $sql;
    $self->_maybe_fail($sql);

    return [];
}

sub _maybe_fail ( $self, $sql ) {
    return if !length $self->failing || index( $sql, $self->failing ) < 0;
    $self->state( $self->fails );
    croak "ERROR:  failing $sql";
}

1;
