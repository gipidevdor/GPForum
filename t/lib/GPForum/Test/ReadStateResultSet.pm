# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ReadStateResultSet;

use Mojo::Base 'GPForum::Test::TransactionalResultSet';
use v5.40;

use GPForum::Infrastructure::UniqueConflict;
use GPForum::Test::ReadStateRow;

our $VERSION = '0.001';

has created     => sub { return []; };
has find_misses => 0;
has rows        => sub { return {}; };
has schema      => undef;    # optional: without it no transaction is checked
has unique_name => sub { return 'thread_read_state_pkey'; };

sub create {
    my ( $self, $row ) = @_;

    $self->assert_usable;
    $self->assert_unique_constraints($row);
    my $object = GPForum::Test::ReadStateRow->new( data => { %{$row} } );
    $self->rows->{ _key($row) } = $object;
    push @{ $self->created }, { %{$row} };

    return $object;
}

sub update_or_create {
    my ( $self, $row ) = @_;

    $self->assert_usable;
    my $existing = $self->rows->{ _key($row) };
    if ($existing) {
        return $existing->update($row);
    }

    return $self->create($row);
}

sub find {
    my ( $self, $query ) = @_;

    $self->assert_usable;
    if ( $self->find_misses ) {
        $self->find_misses( $self->find_misses - 1 );
        return;
    }

    return $self->rows->{ _key($query) };
}

sub check_unique_constraints {
    my ( $self, $row ) = @_;

    my $key = _key($row);
    if ( $key && $self->rows->{$key} ) {
        GPForum::Infrastructure::UniqueConflict->throw( $self->unique_name );
    }

    return;
}

sub _key {
    my ($row) = @_;

    return join q{:}, @{$row}{qw(user_id thread_id)};
}

1;
